```diff
diff --git a/summer-earn-protocol/packages/gov-contracts/test/governorV2/SummerGovernorV2.crosschain.t.sol b/summer-earn-protocol/packages/gov-contracts/test/governorV2/SummerGovernorV2.crosschain.t.sol
index c5ab707..338dcf4 100644
--- a/summer-earn-protocol/packages/gov-contracts/test/governorV2/SummerGovernorV2.crosschain.t.sol
+++ b/summer-earn-protocol/packages/gov-contracts/test/governorV2/SummerGovernorV2.crosschain.t.sol
@@ -115,7 +115,7 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
         advanceTimeAndBlock();
     }
 
-    function test_CrossChainGovernanceFullCycle2() public {
+    function test_receivedMsgValueCanBeDiffer() public {
         // Start recording logs
         vm.recordLogs();
 
@@ -138,7 +138,7 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
             uint256[] memory dstValues,
             bytes[] memory dstCalldatas,
             bytes32 dstDescriptionHash
-        ) = _createCrossChainProposal(bEid, governorA);
+        ) = _createCrossChainProposalWithNativeToken(bEid, governorA);
 
         // Submit proposal on chain A
         vm.prank(alice);
@@ -167,6 +167,7 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
 
         vm.expectEmit(true, true, true, true);
         emit ISummerGovernorV2.ProposalSentCrossChain(dstProposalId, bEid);
+        vm.prank(alice);
         governorA.execute(
             srcTargets,
             srcValues,
@@ -177,9 +178,25 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
         useNetworkB();
 
         // Verify cross-chain message
-        verifyPackets(bEid, addressToBytes32(address(governorB)));
+        (
+            bytes32[] memory guids,
+            bytes[] memory packetsBytes,
+            bytes[] memory options
+        ) = verifyPacketsWithoutExecute(
+                bEid,
+                addressToBytes32(address(governorB)),
+                0
+            );
+        this.executePackets{value: 100}(
+            bEid,
+            addressToBytes32(address(governorB)),
+            guids,
+            packetsBytes,
+            options,
+            address(0)
+        );
 
-        // Get the logs and verify events
+        //Get the logs and verify events
         (
             bool foundReceivedEvent,
             bool foundQueuedEvent,
@@ -208,8 +225,9 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
 
         // Execute on chain B after timelock delay
         vm.warp(queuedEta + 1);
-        vm.deal(address(timelockB), 100 ether);
+        vm.deal(address(timelockB), 100);
         deal(address(bSummerToken), address(timelockB), 1000);
+        assertEq(address(timelockB).balance, 100);
         timelockB.executeBatch(
             dstTargets,
             dstValues,
@@ -218,10 +236,7 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
             salt
         );
 
-        assertTrue(
-            timelockB.isOperationDone(timelockId),
-            "Operation should be done in timelock"
-        );
+        assertEq(address(timelockB).balance, 0);
     }
 
     function test_CrossChainProposalFailsWithInsufficientFee() public {
@@ -287,6 +302,16 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
     // chain. This test verifies that the proposal is automatically queued upon
     // receipt, with proper events emitted and state transitions occurring.
     function test_CrossChainProposalAutomaticallyQueued() public {
+        address guardian = address(0x1234);
+
+        // Setup guardian in AccessManager
+        vm.startPrank(address(timelockA));
+        accessManagerA.grantGuardianRole(guardian);
+        accessManagerA.setGuardianExpiration(
+            guardian,
+            block.timestamp + 1000000
+        );
+        vm.stopPrank();
         // Setup initial state
         vm.deal(address(governorA), 100 ether); // For cross-chain fees
 
@@ -313,7 +338,7 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
             uint256[] memory dstValues,
             bytes[] memory dstCalldatas,
             bytes32 dstDescriptionHash
-        ) = _createCrossChainProposal(bEid, governorA);
+        ) = _createCrossChainProposalWithNativeToken(bEid, governorA);
 
         useNetworkA();
 
@@ -343,6 +368,10 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
             hashDescription(srcDescription)
         );
 
+        vm.startPrank(guardian);
+        governorA.cancel(srcTargets, srcValues, srcCalldatas, hashDescription(srcDescription));
+        vm.stopPrank();
+
         advanceTimeForTimelockMinDelay();
 
         // Start recording logs for verification
@@ -568,7 +597,90 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
             uint256[] memory dstValues,
             bytes[] memory dstCalldatas,
             string memory dstDescription
-        ) = createProposalParams(address(bSummerToken));
+        ) = createProposalParams(address(aSummerToken));
+
+        bytes[] memory srcCalldatas = new bytes[](1);
+
+        string memory srcDescription = string(
+            abi.encodePacked("Cross-chain proposal: ", dstDescription)
+        );
+        bytes memory options = OptionsBuilder
+            .newOptions()
+            .addExecutorLzReceiveOption(200000, 100);
+
+        srcCalldatas[0] = abi.encodeWithSelector(
+            SummerGovernorV2.sendProposalToTargetChain.selector,
+            dstEid,
+            dstTargets,
+            dstValues,
+            dstCalldatas,
+            hashDescription(dstDescription),
+            options
+        );
+
+        address[] memory srcTargets = new address[](1);
+        srcTargets[0] = address(srcGovernor);
+
+        uint256[] memory srcValues = new uint256[](1);
+        srcValues[0] = 0;
+
+        uint256 dstProposalId = srcGovernor.hashProposal(
+            dstTargets,
+            dstValues,
+            dstCalldatas,
+            hashDescription(dstDescription)
+        );
+
+        console.log(
+            "Description Hash:",
+            uint256(hashDescription(dstDescription))
+        );
+        console.log("Expected Proposal ID:", dstProposalId);
+
+        console.log("Target count:", dstTargets.length);
+        for (uint i = 0; i < dstTargets.length; i++) {
+            console.log("Target", i, ":", dstTargets[i]);
+            console.log("Value", i, ":", dstValues[i]);
+            console.log("Calldata", i, ":", _toHexString(dstCalldatas[i]));
+        }
+
+        return (
+            srcTargets,
+            srcValues,
+            srcCalldatas,
+            srcDescription,
+            dstProposalId,
+            dstTargets,
+            dstValues,
+            dstCalldatas,
+            hashDescription(dstDescription)
+        );
+    }
+
+    function _createCrossChainProposalWithNativeToken(
+        uint32 dstEid,
+        SummerGovernorV2 srcGovernor
+    )
+        internal
+        view
+        returns (
+            address[] memory,
+            uint256[] memory,
+            bytes[] memory,
+            string memory,
+            uint256,
+            address[] memory,
+            uint256[] memory,
+            bytes[] memory,
+            bytes32
+        )
+    {
+        (
+            address[] memory dstTargets,
+            uint256[] memory dstValues,
+            bytes[] memory dstCalldatas,
+            string memory dstDescription
+        ) = createProposalParamsWithNativeTransfer(address(123));
 
         bytes[] memory srcCalldatas = new bytes[](1);
 
@@ -577,7 +689,7 @@ contract SummerGovernorCrossChainTest2 is SummerGovernorV2TestBase {
         );
         bytes memory options = OptionsBuilder
             .newOptions()
-            .addExecutorLzReceiveOption(200000, 0);
+            .addExecutorLzReceiveOption(200000, 100);
 
         srcCalldatas[0] = abi.encodeWithSelector(
             SummerGovernorV2.sendProposalToTargetChain.selector,

```
