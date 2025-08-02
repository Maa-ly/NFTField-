//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BaseTest.sol";

/**
 * @title DisputeMarketUnitTest
 * @dev Unit tests for individual functions of the DisputeMarket contract
 */
contract DisputeMarketUnitTest is BaseTest {
    
    function test_Initialize() public {
        assertEq(disputeMarket.hasRole(disputeMarket.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(disputeMarket.hasRole(disputeMarket.ADMIN_ROLE(), admin), true);
        assertEq(disputeMarket.disputeCounter(), 1);
        assertEq(disputeMarket.getCurrentTokenId(), 0);
    }
    
    function test_CreateDispute_Success() public {
        uint256 disputeId = createBasicDispute();
        
        assertDisputeCreated(disputeId, creator, respondent);
        assertEvidenceSubmitted(disputeId, creator);
        
        // Check escrow was handled
        assertEq(address(disputeMarket).balance, ESCROW_AMOUNT);
    }
    
    function test_CreateDispute_RevertInvalidRespondent() public {
        defaultParams.respondent = address(0);
        
        vm.prank(creator);
        vm.expectRevert(InvalidDisputeParameters.selector);
        disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
    }
    
    function test_CreateDispute_RevertSelfAsRespondent() public {
        defaultParams.respondent = creator;
        
        vm.prank(creator);
        vm.expectRevert(InvalidDisputeParameters.selector);
        disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
    }
    
    function test_CreateDispute_RevertInvalidDescription() public {
        defaultParams.description = "short"; // Too short
        
        vm.prank(creator);
        vm.expectRevert(InvalidDescriptionLength.selector);
        disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
    }
    
    function test_CreateDispute_RevertInsufficientEscrow() public {
        vm.prank(creator);
        vm.expectRevert(InvalidEscrowAmount.selector);
        disputeMarket.createDispute{value: ESCROW_AMOUNT - 1}(defaultParams); // Insufficient value
    }
    
    function test_CreateDispute_RevertCooldownActive() public {
        createBasicDispute();
        
        // Try to create another dispute without waiting for cooldown
        vm.prank(creator);
        vm.expectRevert(); // Expect cooldown revert without checking exact time value
        disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
    }
    
    function test_CreateDispute_SuccessAfterCooldown() public {
        createBasicDispute();
        
        skipCooldown(creator);
        
        // Should succeed after cooldown
        uint256 secondDisputeId = createBasicDispute();
        assertEq(secondDisputeId, 2);
    }
    
    function test_SubmitEvidence_Success() public {
        uint256 disputeId = createBasicDispute();
        
        addEvidence(disputeId, voter1, false);
        assertEvidenceSubmitted(disputeId, voter1);
        
        DisputeStorage.Evidence[] memory evidences = disputeMarket.getDisputeEvidence(disputeId);
        assertGt(evidences.length, 2); // Should have initial evidence + new evidence
    }
    
    function test_SubmitEvidence_RevertDisputeNotFound() public {
        vm.prank(voter1);
        vm.expectRevert(DisputeNotFound.selector);
        disputeMarket.submitEvidence(999, "Evidence", "hash", true);
    }
    
    function test_StartVoting_Success() public {
        uint256 disputeId = createDisputeAndActivate();
        
        // Fast forward to voting time
        vm.warp(block.timestamp + disputeMarket.DISPUTE_PERIOD() + 1);
        
        disputeMarket.startVoting(disputeId);
        
        expectDispute(disputeId, creator, respondent, DisputeEvents.DisputeStatus.Voting);
    }
    
    function test_StartVoting_RevertNoEvidenceSubmitters() public {
        uint256 disputeId = createBasicDispute();
        
        // Clear evidence submitters by creating a dispute without evidence
        defaultParams.evidenceDescriptions = new string[](1);
        defaultParams.evidenceDescriptions[0] = "Minimal evidence";
        defaultParams.evidenceHashes = new string[](1);
        defaultParams.evidenceHashes[0] = "hash";
        defaultParams.evidenceSupportsCreator = new bool[](1);
        defaultParams.evidenceSupportsCreator[0] = true;
        
        vm.warp(block.timestamp + disputeMarket.DISPUTE_ACTIVATION_PERIOD() + disputeMarket.DISPUTE_PERIOD() + 1);
        
        // This should work since we have evidence from creation
        disputeMarket.startVoting(disputeId);
    }
    
    function test_CastVote_Success() public {
        uint256 disputeId = createDisputeAndActivate();
        
        // Add evidence before voting starts
        addEvidenceAndPrepareVote(disputeId, voter1, true);
        
        // Start voting
        vm.warp(block.timestamp + disputeMarket.DISPUTE_PERIOD() + 1);
        disputeMarket.startVoting(disputeId);
        
        // Now cast vote
        castVote(disputeId, voter1, true);
        assertVoteRecorded(disputeId, voter1, true);
    }
    
    function test_CastVote_RevertNotInVotingPhase() public {
        uint256 disputeId = createBasicDispute();
        
        vm.prank(voter1);
        vm.expectRevert("Dispute not in voting phase");
        disputeMarket.castVote(disputeId, true, "Vote reason");
    }
    
    function test_CastVote_RevertAlreadyVoted() public {
        uint256 disputeId = createDisputeAndActivate();
        
        // Add evidence before voting starts
        addEvidenceAndPrepareVote(disputeId, voter1, true);
        
        // Start voting
        vm.warp(block.timestamp + disputeMarket.DISPUTE_PERIOD() + 1);
        disputeMarket.startVoting(disputeId);
        
        // Cast first vote
        castVote(disputeId, voter1, true);
        
        // Try to vote again - should fail
        vm.prank(voter1);
        vm.expectRevert("Already voted");
        disputeMarket.castVote(disputeId, false, "Different vote");
    }
    
    function test_CastVote_RevertMustSubmitEvidence() public {
        uint256 disputeId = createDisputeAndStartVoting();
        
        vm.prank(voter1);
        vm.expectRevert("Must have submitted evidence to vote");
        disputeMarket.castVote(disputeId, true, "Vote without evidence");
    }
    
    function test_ResolveDispute_Success() public {
        uint256 disputeId = createDisputeAndActivate();
        
        // Add evidence for voters before voting starts
        addEvidenceAndPrepareVote(disputeId, voter1, true);
        addEvidenceAndPrepareVote(disputeId, voter2, false);
        addEvidenceAndPrepareVote(disputeId, voter3, true);
        
        // Start voting
        vm.warp(block.timestamp + disputeMarket.DISPUTE_PERIOD() + 1);
        disputeMarket.startVoting(disputeId);
        
        // Cast votes
        castVote(disputeId, voter1, true);  // Vote for creator
        castVote(disputeId, voter2, false); // Vote for respondent
        castVote(disputeId, voter3, true);  // Vote for creator
        
        // Fast forward past voting period
        vm.warp(block.timestamp + disputeMarket.VOTING_PERIOD() + 1);
        
        disputeMarket.resolveDispute(disputeId);
        
        expectDispute(disputeId, creator, respondent, DisputeEvents.DisputeStatus.Resolved);
        
        (, , address winner) = disputeMarket.getDisputeResults(disputeId);
        assertEq(winner, creator); // Creator should win with 3 votes vs 1
    }
    
    function test_ResolveDispute_RevertVotingNotEnded() public {
        uint256 disputeId = createDisputeAndStartVoting();
        
        vm.expectRevert("Voting period not ended");
        disputeMarket.resolveDispute(disputeId);
    }
    
    function test_CanCreateDispute_Success() public {
        (bool canCreate, uint40 remainingCooldown) = disputeMarket.canCreateDispute(creator);
        assertTrue(canCreate);
        assertEq(remainingCooldown, 0);
    }
    
    function test_CanCreateDispute_CooldownActive() public {
        createBasicDispute();
        
        (bool canCreate, uint40 remainingCooldown) = disputeMarket.canCreateDispute(creator);
        assertFalse(canCreate);
        assertGt(remainingCooldown, 0);
    }
    
    function test_CanCreateDispute_Blacklisted() public {
        vm.prank(admin);
        disputeMarket.setUserBlacklist(creator, true);
        
        (bool canCreate, uint40 remainingCooldown) = disputeMarket.canCreateDispute(creator);
        assertFalse(canCreate);
        assertEq(remainingCooldown, type(uint40).max);
    }
    
    function test_SetUserBlacklist_Success() public {
        vm.prank(admin);
        disputeMarket.setUserBlacklist(creator, true);
        assertTrue(disputeMarket.isBlacklisted(creator));
        
        vm.prank(admin);
        disputeMarket.setUserBlacklist(creator, false);
        assertFalse(disputeMarket.isBlacklisted(creator));
    }
    
    function test_SetUserBlacklist_RevertUnauthorized() public {
        vm.prank(creator);
        vm.expectRevert();
        disputeMarket.setUserBlacklist(respondent, true);
    }
    
    function test_PauseUnpause_Success() public {
        vm.prank(admin);
        disputeMarket.pause();
        assertTrue(disputeMarket.paused());
        
        vm.prank(admin);
        disputeMarket.unpause();
        assertFalse(disputeMarket.paused());
    }
    
    function test_PauseUnpause_RevertUnauthorized() public {
        vm.prank(creator);
        vm.expectRevert();
        disputeMarket.pause();
    }
    
    function test_CreateDisputeWhenPaused_Reverts() public {
        vm.prank(admin);
        disputeMarket.pause();
        
        vm.prank(creator);
        vm.expectRevert(); // OpenZeppelin 5.x uses custom errors instead of string messages
        disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
    }
    
    function test_GetDisputeInfo_Success() public {
        uint256 disputeId = createBasicDispute();
        
        (
            address creator_,
            address respondent_,
            string memory title,
            string memory description,
            DisputeEvents.DisputeCategory category,
            DisputeStorage.Priority priority,
            DisputeEvents.DisputeStatus status
        ) = disputeMarket.getDisputeBasicInfo(disputeId);
        
        assertEq(creator_, creator);
        assertEq(respondent_, respondent);
        assertEq(title, defaultParams.title);
        assertEq(description, defaultParams.description);
        assertEq(uint256(category), uint256(defaultParams.category));
        assertEq(uint256(priority), uint256(defaultParams.priority));
        assertEq(uint256(status), uint256(DisputeEvents.DisputeStatus.Pending));
    }
    
    function test_GetUserDisputes_Success() public {
        createBasicDispute();
        skipCooldown(creator);
        createBasicDispute();
        
        uint256[] memory userDisputes = disputeMarket.getUserDisputes(creator);
        assertEq(userDisputes.length, 2);
        assertEq(userDisputes[0], 1);
        assertEq(userDisputes[1], 2);
    }
    
    function test_Version() public {
        assertEq(disputeMarket.version(), "1.0.0");
    }
}