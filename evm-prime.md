EVM Prime
=========

In `EVMPRIME` mode, certain opcodes can be used which compile down to standard EVM but provide better-behaved high-level language constructs.

```{.k .uiuck .rvk}
requires "evm.k"

module EVM-PRIME
    imports EVM
```

```{.k .rvk}
    imports K-REFLECTION
```

```{.k .uiuck .rvk}
    syntax OpCode ::= PrimeOp
 // -------------------------

    syntax Bool ::= isCompiled ( OpCodes ) [function]
 // -------------------------------------------------
    rule isCompiled ( .OpCodes ) => true
    rule isCompiled ( OP ; OPS ) => (notBool isPrimeOp(OP)) andBool isCompiled(OPS)
```

-   `Vars` are lists of `Id` (builtin to K), separated by `:`.
-   `#env` is used to calculate the correct memory locations to access for variables given the list of currently scoped variables.

```{.k .uiuck .rvk}
    syntax Vars ::= List{Id, ":"}
 // -----------------------------

    syntax Int ::= #env ( Vars , Id ) [function]
 // --------------------------------------------
    rule #env( (V : _)  , V ) => 0
    rule #env( (V : VS) , X ) => 32 +Int #env( VS , X ) requires X =/=K V
```

-   `#resolvePrimeOp` and `#resolvePrimeOps` operate in the monad from `(ENV, OpCode) -> OpCodes`.

```{.k .uiuck .rvk}
    syntax OpCodes ::= #resolvePrimeOp  ( Vars , OpCode  ) [function]
                     | #resolvePrimeOps ( Vars , OpCodes ) [function]
 // -----------------------------------------------------------------
    rule #resolvePrimeOp( IDS, OP ) => OP ; .OpCodes requires notBool isPrimeOp(OP)

    rule #resolvePrimeOps( _,   .OpCodes ) => .OpCodes
    rule #resolvePrimeOps( IDS, OP ; OPS ) => #resolvePrimeOp(IDS, OP) ++OpCodes #resolvePrimeOps(IDS, OPS)

    syntax OpCodes ::= OpCodes "++OpCodes" OpCodes [function]
 // ---------------------------------------------------------
    rule .OpCodes    ++OpCodes OPS  => OPS
    rule (OP ; OPS1) ++OpCodes OPS2 => OP ; (OPS1 ++OpCodes OPS2)
```

-   `#compile` will desugar `PrimeOp`s with `#resolvePrimeOps` and then resolve the jump destinations with `#resolveJumps`.

```{.k .uiuck .rvk}
    syntax OpCodes ::= #compile ( OpCodes ) [function]
 // --------------------------------------------------
    rule #compile(OPS) => #resolveJumps(#resolvePrimeOps(.Vars, OPS))
```

### Example

This is psuedo-code for the running example we have throughout this document.

```
s = 0 ;
n = 10 ;
while ( n > 0 ) {
    s = s + n ;
    n = n - 1 ;
}
sstore(0, s) ;
```

Structured Jumps
----------------

Because jump destinations are not well-defined until the entire program has been represented as bytecode, desugaring the `jump*` opcodes *must* be done *last*.

-   `jumpdest` allows marking a jump destination with a string (instead up relying on the program counter).
-   `jump` and `jumpi` allow supplying the string-labeled jump destination for jumping (instead of `PUSH`ing the destination).

```{.k .uiuck .rvk}
    syntax OpCode ::= JumpPrimeOp
    syntax JumpPrimeOp ::= jumpdest ( String ) | jump ( String ) | jumpi ( String )
 // -------------------------------------------------------------------------------
```

-   `#resolveJumps` will replace the labeled jump destinations/jumps with their corresponding EVM code.
-   `#calcJumpTable` is a helper for resolving the jump table.

```{.k .uiuck .rvk}
    syntax OpCodes ::= #resolveJumps ( OpCodes )             [function]
                     | #resolveJumps ( OpCodes , Int , Map ) [function, klabel(#resolveJumpsAux)]
 // ---------------------------------------------------------------------------------------------
    rule #resolveJumps( OPS ) => #resolveJumps( OPS , #maxJumpPushWidth(OPS), #calcJumpTable( OPS , 0 , #maxJumpPushWidth(OPS) , .Map ) )

    rule #resolveJumps( .OpCodes              , W , JT ) => .OpCodes
    rule #resolveJumps( OP              ; OPS , W , JT ) => OP       ; #resolveJumps(OPS, W, JT) requires notBool isJumpPrimeOp(OP)
    rule #resolveJumps( jumpdest(LABEL) ; OPS , W , JT ) => JUMPDEST ; #resolveJumps(OPS, W, JT)
    rule #resolveJumps( jump(LABEL)     ; OPS , W , LABEL |-> PCOUNT JT ) => PUSH(W, PCOUNT) ; JUMP  ; #resolveJumps(OPS, W, LABEL |-> PCOUNT JT)
    rule #resolveJumps( jumpi(LABEL)    ; OPS , W , LABEL |-> PCOUNT JT ) => PUSH(W, PCOUNT) ; JUMPI ; #resolveJumps(OPS, W, LABEL |-> PCOUNT JT)

    syntax Map ::= #calcJumpTable ( OpCodes , Int , Int , Map ) [function]
 // ----------------------------------------------------------------------
    rule #calcJumpTable( .OpCodes              , _      , MW , JT ) => JT
    rule #calcJumpTable( jumpdest(LABEL) ; OPS , PCOUNT , MW , JT ) => #calcJumpTable(OPS, PCOUNT +Int 1,        MW, JT [ LABEL <- PCOUNT ])
    rule #calcJumpTable( jump(LABEL)     ; OPS , PCOUNT , MW , JT ) => #calcJumpTable(PUSH(MW, 0) ; JUMP  ; OPS, PCOUNT, MW, JT)
    rule #calcJumpTable( jumpi(LABEL)    ; OPS , PCOUNT , MW , JT ) => #calcJumpTable(PUSH(MW, 0) ; JUMPI ; OPS, PCOUNT, MW, JT)
    rule #calcJumpTable( PUSH(W, _)      ; OPS , PCOUNT , MW , JT ) => #calcJumpTable(OPS, PCOUNT +Int W +Int 1, MW, JT)
    rule #calcJumpTable( _               ; OPS , PCOUNT , MW , JT ) => #calcJumpTable(OPS, PCOUNT +Int 1,        MW, JT) [owise]
```

-   `#maxJumpPushWidth` will calculate the maximum jump address that can be used in a chunk of EVM.
-   `#maxOpCodesWidth` will calculate the maximum width that an EVM `OpCodes` could have after resolving jump destinations.

```{.k .uiuck .rvk}
    syntax Int ::= #maxJumpPushWidth ( OpCodes ) [function]
                 | #maxOpCodesWidth  ( OpCodes ) [function]
 // -------------------------------------------------------
    rule #maxJumpPushWidth ( OPS ) => #sizeWordStack(#asByteStack(#maxOpCodesWidth(OPS)))

    rule #maxOpCodesWidth( .OpCodes )          => 0
    rule #maxOpCodesWidth( PUSH(W, _)  ; OPS ) => W +Int 1 +Int #maxOpCodesWidth(OPS)
    rule #maxOpCodesWidth( jumpdest(_) ; OPS ) => 1        +Int #maxOpCodesWidth(OPS)
    rule #maxOpCodesWidth( jump(_)     ; OPS ) => 34       +Int #maxOpCodesWidth(OPS)
    rule #maxOpCodesWidth( jumpi(_)    ; OPS ) => 34       +Int #maxOpCodesWidth(OPS)
    rule #maxOpCodesWidth( OP          ; OPS ) => 1        +Int #maxOpCodesWidth(OPS) [owise]
```

### Example

In this example, we check that using the structured jumps desugars to the correct original program.

```{.k .example}
load "exec" : { "code" : PUSH(1, 0)  ; PUSH(1, 0)  ; MSTORE
                       ; PUSH(1, 10) ; PUSH(1, 32) ; MSTORE
                       ; jumpdest("loop-begin")
                       ; PUSH(1, 0) ; PUSH(1, 32) ; MLOAD ; GT
                       ; ISZERO ; jumpi("end")
                       ; PUSH(1, 32) ; MLOAD ; PUSH(1, 0)  ; MLOAD ; ADD ; PUSH(1, 0)  ; MSTORE
                       ; PUSH(1, 1)          ; PUSH(1, 32) ; MLOAD ; SUB ; PUSH(1, 32) ; MSTORE
                       ; jump("loop-begin")
                       ; jumpdest("end")
                       ; PUSH(1, 0) ; MLOAD ; PUSH(1, 0) ; SSTORE
                       ; .OpCodes
              }

compile

check "program" : PUSH(1, 0)  ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 10) ; PUSH(1, 32) ; MSTORE
                ; JUMPDEST
                ; PUSH(1, 0) ; PUSH(1, 32) ; MLOAD ; GT
                ; ISZERO ; PUSH(1, 43) ; JUMPI
                ; PUSH(1, 32) ; MLOAD ; PUSH(1, 0)  ; MLOAD ; ADD ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 1)          ; PUSH(1, 32) ; MLOAD ; SUB ; PUSH(1, 32) ; MSTORE
                ; PUSH(1, 10) ; JUMP
                ; JUMPDEST
                ; PUSH(1, 0) ; MLOAD ; PUSH(1, 0) ; SSTORE
                ; .OpCodes

failure "DESUGAR EVMPRIME JUMPS"

clear
```

PUSH Simplification
-------------------

-   `push` allows not specifying the width of the constant being pushed (it will be calculated for you).

```{.k .uiuck .rvk}
    syntax PrimeOp ::= push ( Int ) [function]
 // ------------------------------------------
    rule push(N) => PUSH(#sizeWordStack(#padToWidth(1, #asByteStack(N))), N) requires N <Int pow256
```

### Example

In this example, we use our simpler `push` notation for avoiding specifying the width of a `PUSH`.

```{.k .example}
load "exec" : { "code" : push(0)  ; push(0)  ; MSTORE
                       ; push(10) ; push(32) ; MSTORE
                       ; jumpdest("loop-begin")
                       ; push(0) ; push(32) ; MLOAD ; GT
                       ; ISZERO ; jumpi("end")
                       ; push(32) ; MLOAD ; push(0)  ; MLOAD ; ADD ; push(0)  ; MSTORE
                       ; push(1)          ; push(32) ; MLOAD ; SUB ; push(32) ; MSTORE
                       ; jump("loop-begin")
                       ; jumpdest("end")
                       ; push(0) ; MLOAD ; push(0) ; SSTORE
                       ; .OpCodes
              }

compile

check "program" : PUSH(1, 0)  ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 10) ; PUSH(1, 32) ; MSTORE
                ; JUMPDEST
                ; PUSH(1, 0) ; PUSH(1, 32) ; MLOAD ; GT
                ; ISZERO ; PUSH(1, 43) ; JUMPI
                ; PUSH(1, 32) ; MLOAD ; PUSH(1, 0)  ; MLOAD ; ADD ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 1)          ; PUSH(1, 32) ; MLOAD ; SUB ; PUSH(1, 32) ; MSTORE
                ; PUSH(1, 10) ; JUMP
                ; JUMPDEST
                ; PUSH(1, 0) ; MLOAD ; PUSH(1, 0) ; SSTORE
                ; .OpCodes

failure "DESUGAR EVMPRIME PUSH"

clear
```

Variables: Assignment and Lookup
--------------------------------

-   `procedure (_) {_}` declares new variables in scope for the environment (note that new variables shadow existing ones).

```{.k .uiuck .rvk}
    syntax PrimeOp ::= "procedure" "(" Vars ")" "{" OpCodes "}"
 // -----------------------------------------------------------
    rule #resolvePrimeOp( .Vars , procedure ( IDS  ) { OPS } ) => #resolvePrimeOps( IDS , OPS )
    rule #resolvePrimeOp( IDS1  , procedure ( IDS2 ) { OPS } ) => #resolvePrimeOps( (IDS2 : IDS1), OPS )
```

-   `mload` loads variables from the `localMem` onto the `wordStack` (using the environment to determine where they are).
-   `mstore` stores an element from the `wordStack` from the location specified in the `localMem`.

```{.k .uiuck .rvk}
    syntax PrimeOp ::= mload ( Id ) | mstore ( Id )
 // -----------------------------------------------
    rule #resolvePrimeOp(VS, mload(V))  => push(#env(VS, V)) ; MLOAD  ; .OpCodes
    rule #resolvePrimeOp(VS, mstore(V)) => push(#env(VS, V)) ; MSTORE ; .OpCodes
```

-   Syntax `_:=_` is sugar for storing the result of an exprssion to the `localMem`.

```{.k .uiuck .rvk}
    syntax PrimeOp ::= Id ":=" ExpOp
 // --------------------------------
    rule #resolvePrimeOp(VS, V := WEXP) => #resolvePrimeOps(VS, WEXP ; mstore(V) ; .OpCodes)
```

### Example

In this example, we use `procedure` to declare some variables and use them with `mload` and `mstore`.

```{.k .example}
load "exec" : { "code" : procedure(s : n)
                            { push(0)  ; mstore(s)
                            ; push(10) ; mstore(n)
                            ; jumpdest("loop-begin")
                            ; push(0) ; mload(n) ; GT
                            ; ISZERO ; jumpi("end")
                            ; mload(n) ; mload(s) ; ADD ; mstore(s)
                            ; push(1)  ; mload(n) ; SUB ; mstore(n)
                            ; jump("loop-begin")
                            ; jumpdest("end")
                            ; mload(s) ; push(0) ; SSTORE
                            ; .OpCodes
                            }
                       ; .OpCodes
              }

compile

check "program" : PUSH(1, 0)  ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 10) ; PUSH(1, 32) ; MSTORE
                ; JUMPDEST
                ; PUSH(1, 0) ; PUSH(1, 32) ; MLOAD ; GT
                ; ISZERO ; PUSH(1, 43) ; JUMPI
                ; PUSH(1, 32) ; MLOAD ; PUSH(1, 0)  ; MLOAD ; ADD ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 1)          ; PUSH(1, 32) ; MLOAD ; SUB ; PUSH(1, 32) ; MSTORE
                ; PUSH(1, 10) ; JUMP
                ; JUMPDEST
                ; PUSH(1, 0) ; MLOAD ; PUSH(1, 0) ; SSTORE
                ; .OpCodes

failure "DESUGAR EVMPRIME MLOAD/MSTORE"

clear
```

Expressions
-----------

-   `Id` is subsorted into `PrimeOp` so and is interpereted as a variable lookup.
-   `Int` is subsorted into `PrimeOp` and means pushing a constant.

```{.k .uiuck .rvk}
    syntax PrimeOp ::= ExpOp
    syntax ExpOp   ::= Id | Int
 // ---------------------------
    rule #resolvePrimeOp(VS, V:Id)  => #resolvePrimeOp(VS, mload(V))
    rule #resolvePrimeOp(VS, C:Int) => push(C) ; .OpCodes
```

-   `_+_`, `_*_`, `_-_`, and `_/_` provide integer arithmetic expressions.

```{.k .uiuck .rvk}
    syntax ExpOp ::= ExpOp "+" ExpOp
                   | ExpOp "*" ExpOp
                   | ExpOp "-" ExpOp
                   | ExpOp "/" ExpOp
 // --------------------------------
    rule #resolvePrimeOp(VS, W0 + W1) => #resolvePrimeOps(VS, W1 ; W0 ; ADD ; .OpCodes)
    rule #resolvePrimeOp(VS, W0 - W1) => #resolvePrimeOps(VS, W1 ; W0 ; SUB ; .OpCodes)
    rule #resolvePrimeOp(VS, W0 * W1) => #resolvePrimeOps(VS, W1 ; W0 ; MUL ; .OpCodes)
    rule #resolvePrimeOp(VS, W0 / W1) => #resolvePrimeOps(VS, W1 ; W0 ; DIV ; .OpCodes)
```

-   `_==_`, `_=/=_`, `_<_`, `_<=_`, `_>_`, and `_>=_` provide boolean expressions.

```{.k .uiuck .rvk}
    syntax ExpOp ::= ExpOp "=="  ExpOp
                   | ExpOp "=/=" ExpOp
                   | ExpOp "<"   ExpOp
                   | ExpOp "<="  ExpOp
                   | ExpOp ">"   ExpOp
                   | ExpOp ">="  ExpOp
 // ----------------------------------
    rule #resolvePrimeOp(VS, W0 ==  W1) => #resolvePrimeOps(VS, W1 ; W0 ; EQ           ; .OpCodes)
    rule #resolvePrimeOp(VS, W0 =/= W1) => #resolvePrimeOps(VS, W1 ; W0 ; EQ ; ISZERO  ; .OpCodes)
    rule #resolvePrimeOp(VS, W0 <   W1) => #resolvePrimeOps(VS, W1 ; W0 ; LT           ; .OpCodes)
    rule #resolvePrimeOp(VS, W0 <=  W1) => #resolvePrimeOps(VS, W1 ; W0 ; GT ; ISZERO  ; .OpCodes)
    rule #resolvePrimeOp(VS, W0 >   W1) => #resolvePrimeOps(VS, W1 ; W0 ; GT           ; .OpCodes)
    rule #resolvePrimeOp(VS, W0 >=  W1) => #resolvePrimeOps(VS, W1 ; W0 ; LT ; ISZERO  ; .OpCodes)
```

### Example

In this example, we use the above expression language and assignment (`_:=_`) to simplify many parts of the code.

```{.k .example}
load "exec" : { "code" : procedure(s : n)
                            { s := 0
                            ; n := 10
                            ; jumpdest("loop-begin")
                            ; n > 0
                            ; ISZERO ; jumpi("end")
                            ; s := s + n
                            ; n := n - 1
                            ; jump("loop-begin")
                            ; jumpdest("end")
                            ; mload(s) ; push(0) ; SSTORE
                            ; .OpCodes
                            }
                       ; .OpCodes
              }

compile

check "program" : PUSH(1, 0)  ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 10) ; PUSH(1, 32) ; MSTORE
                ; JUMPDEST
                ; PUSH(1, 0) ; PUSH(1, 32) ; MLOAD ; GT
                ; ISZERO ; PUSH(1, 43) ; JUMPI
                ; PUSH(1, 32) ; MLOAD ; PUSH(1, 0)  ; MLOAD ; ADD ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 1)          ; PUSH(1, 32) ; MLOAD ; SUB ; PUSH(1, 32) ; MSTORE
                ; PUSH(1, 10) ; JUMP
                ; JUMPDEST
                ; PUSH(1, 0) ; MLOAD ; PUSH(1, 0) ; SSTORE
                ; .OpCodes

failure "DESUGAR EVMPRIME EXPRESSIONS"

clear
```

Conditionals
------------

-   `if (_) {_}` allows for conditionally executing a piece of code.
-   `if (_) {_} else {_}` allows for a nicer looking branching structure than writing bare EVM.

```{.k .uiuck .rvk}
    syntax PrimeOp ::= "if" "(" ExpOp ")" "{" OpCodes "}"
 // -----------------------------------------------------
    rule #resolvePrimeOp( IDS , if ( COND ) { THEN } )
      =>             #resolvePrimeOp(IDS, COND)
         ++OpCodes ( ISZERO
                 ;   jumpi( #ifThenLabel(!LABEL:Int) +String "_end" )
                 ; ( #resolvePrimeOps(IDS, THEN)
         ++OpCodes ( jumpdest( #ifThenLabel(!LABEL) +String "_end" )
                 ;   .OpCodes
               )))

    syntax PrimeOp ::= "if" "(" ExpOp ")" "then" "{" OpCodes "}" "else" "{" OpCodes "}"
 // -----------------------------------------------------------------------------------
    rule #resolvePrimeOp( IDS, if ( COND ) then { THEN } else { ELSE } )
      =>             #resolvePrimeOp(IDS, COND)
         ++OpCodes ( jumpi(#ifThenElseLabel(!LABEL:Int) +String "_true")
                 ; ( #resolvePrimeOps(IDS, ELSE)
         ++OpCodes ( jump(#ifThenElseLabel(!LABEL) +String "_end")
                 ;   jumpdest(#ifThenElseLabel(!LABEL) +String "_true")
                 ; ( #resolvePrimeOps(IDS, THEN)
         ++OpCodes ( jumpdest(#ifThenElseLabel(!LABEL) +String "_end")
                 ;   .OpCodes
             )))))

    syntax String ::= #ifThenLabel     ( Int ) [function]
                    | #ifThenElseLabel ( Int ) [function]
 // -----------------------------------------------------
    rule #ifThenLabel( N )     => "if_then_-" +String Int2String(N)
    rule #ifThenElseLabel( N ) => "if_then_else_-" +String Int2String(N)
```

### Example

In this example, we use a conditional to help with jumping back to the loop head.

```{.k .example}
load "exec" : { "code" : procedure(s : n)
                            { s := 0
                            ; n := 10
                            ; jumpdest("loop-begin")
                            ; if ( n > 0 )
                                { s := s + n
                                ; n := n - 1
                                ; jump("loop-begin")
                                ; .OpCodes
                                }
                            ; mload(s) ; push(0) ; SSTORE
                            ; .OpCodes
                            }
                       ; .OpCodes
              }

compile

check "program" : PUSH(1, 0)  ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 10) ; PUSH(1, 32) ; MSTORE
                ; JUMPDEST
                ; PUSH(1, 0) ; PUSH(1, 32) ; MLOAD ; GT
                ; ISZERO ; PUSH(1, 43) ; JUMPI
                ; PUSH(1, 32) ; MLOAD ; PUSH(1, 0)  ; MLOAD ; ADD ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 1)          ; PUSH(1, 32) ; MLOAD ; SUB ; PUSH(1, 32) ; MSTORE
                ; PUSH(1, 10) ; JUMP
                ; JUMPDEST
                ; PUSH(1, 0) ; MLOAD ; PUSH(1, 0) ; SSTORE
                ; .OpCodes

failure "DESUGAR EVMPRIME IFTHEN"

clear
```

While Loops
-----------

-   `while (_) {_}` allows for simpler construction of loops.

```{.k .uiuck .rvk}
    syntax PrimeOp ::= "while" "(" ExpOp ")" "{" OpCodes "}"
 // --------------------------------------------------------
    rule #resolvePrimeOp( IDS, while ( COND ) { BODY } )
      =>   jumpdest( #whileLabel(!LABEL:Int) +String "_begin" )
         ; #resolvePrimeOp( IDS
                          , if ( COND ) {             BODY
                                          ++OpCodes ( jump( #whileLabel(!LABEL) +String "_begin" )
                                                    ; .OpCodes
                                                    )
                                        }
                          )

    syntax String ::= #whileLabel ( Int ) [function]
 // ------------------------------------------------
    rule #whileLabel( N ) => "while__-" +String Int2String(N)
endmodule
```

### Example

In this example, we use a while loop instead for the entire loop (becoming a highly readable program).

```{.k .example}
load "exec" : { "code" : procedure(s : n)
                            { s := 0
                            ; n := 10
                            ; while ( n > 0 )
                                { s := s + n
                                ; n := n - 1
                                ; .OpCodes
                                }
                            ; mload(s) ; push(0) ; SSTORE
                            ; .OpCodes
                            }
                       ; .OpCodes
              }

compile

check "program" : PUSH(1, 0)  ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 10) ; PUSH(1, 32) ; MSTORE
                ; JUMPDEST
                ; PUSH(1, 0) ; PUSH(1, 32) ; MLOAD ; GT
                ; ISZERO ; PUSH(1, 43) ; JUMPI
                ; PUSH(1, 32) ; MLOAD ; PUSH(1, 0)  ; MLOAD ; ADD ; PUSH(1, 0)  ; MSTORE
                ; PUSH(1, 1)          ; PUSH(1, 32) ; MLOAD ; SUB ; PUSH(1, 32) ; MSTORE
                ; PUSH(1, 10) ; JUMP
                ; JUMPDEST
                ; PUSH(1, 0) ; MLOAD ; PUSH(1, 0) ; SSTORE
                ; .OpCodes

failure "DESUGAR EVMPRIME WHILE"

clear

success

.EthereumSimulation
```
