// HKG Token - Full Proof Claims
// =============================

// We now present reachability claims used for verification, one for each function
// in the ERC20 specification. Since the HKG token contract contains only
// sequential code (no loops), we only need one reachability claim per branch per
// function. In the following claims, any symbol starting with a `%` indicates a
// constant which has been replaced by a symbol for clarity. In particular:

// -   `%HKG_Program` is the EVM bytecode for the Hacker Gold token program;
// -   `TRANSFER` represents the symbolic amount to transfer;
// -   `B1` and `B2` are the starting balances of accounts 1 and 2, respectively;
// -   `A1` is the allowance of account 1 (strictly smaller than the balance).

// BalanceOf Function
// ------------------

// Here we provide a specification file containing a reachability rule for the
// verifying the correctness of the HKG Token's BalanceOf Function.


module BALANCE-OF-SPEC
    imports ETHEREUM-SIMULATION

    rule <k> #execute ... </k>
         <exit-code> 1       </exit-code>
         <mode>      NORMAL  </mode>
         <schedule>  DEFAULT </schedule>

         <output>        .WordStack </output>
         <memoryUsed>    4          </memoryUsed>
         <callDepth>     0          </callDepth>
         <callStack>     .List      </callStack>
         <interimStates> .List      </interimStates>
         <substateStack> .List      </substateStack>
         <callLog>       .Set       </callLog>

         <program>      %HKG_Program      </program>
         <programBytes> %HKG_ProgramBytes </programBytes>
         <id>           %ACCT_ID          </id>
         <caller>       %CALLER_ID        </caller>
         <callData>     .WordStack        </callData>
         <callValue>    0                 </callValue>

         <wordStack>    WS    => ?A:WordStack </wordStack>
         <localMem>     .Map  => ?B:Map       </localMem>
         <pc>           316   => 381          </pc>
         <gas>          G     => G -Int 274   </gas>
         <previousGas>  _     => _            </previousGas>

         <selfDestruct> .Set    </selfDestruct>
         <log>          .List    </log>
         <refund>       0  => _ </refund>

         <gasPrice>     _               </gasPrice>
         <origin>       %ORIGIN_ID      </origin>
         <gasLimit>     _               </gasLimit>
         <coinbase>     %COINBASE_VALUE </coinbase>
         <timestamp>    1               </timestamp>
         <number>       0               </number>
         <previousHash> 0               </previousHash>
         <difficulty>   256             </difficulty>

         <activeAccounts> %ACCT_ID |-> false </activeAccounts>
         <accounts>
           <account>
             <acctID>  %ACCT_ID          </acctID>
             <balance> BAL               </balance>
             <code>    %HKG_ProgramBytes </code>
             <nonce>   0                 </nonce>
             <storage> %ACCT_1_BALANCE |-> B1:Int
                       %ACCT_1_ALLOWED |-> A1:Int
                       %ACCT_2_BALANCE |-> B2:Int
                       %ACCT_2_ALLOWED |-> A2:Int
                       3 |-> %ORIGIN_ID
                       4 |-> %CALLER_ID
             </storage>
           </account>
         </accounts>

      requires #sizeWordStack(WS) <Int 1018 andBool G >=Int 274
endmodule

