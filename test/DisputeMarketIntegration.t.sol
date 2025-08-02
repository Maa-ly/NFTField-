//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BaseTest.sol";

/**
 * @title DisputeMarketIntegrationTest
 * @dev Integration tests for complete workflows and multi-step processes
 */
contract DisputeMarketIntegrationTest is BaseTest {
    
    function test_CompleteDisputeWorkflow_CreatorWins() public {
        // Step 1: Create dispute
        uint256 disputeId = createBasicDispute();
        assertDisputeCreated(disputeId, creator, respondent);
        
        // Step 2: Wait for activation
        vm.warp(block.timestamp + disputeMarket.DISPUTE_ACTIVATION_PERIOD() + 1);
        
        // Step 3: Add additional evidence from both sides
        addEvidence(disputeId, respondent, false);
        addEvidence(disputeId, voter1, true);
        addEvidence(disputeId, voter2, false);
        
        // Step 4: Wait for dispute period to end and start voting
        vm.warp(block.timestamp + disputeMarket.DISPUTE_PERIOD() + 1);
        disputeMarket.startVoting(disputeId);
        expectDispute(disputeId, creator, respondent, DisputeEvents.DisputeStatus.Voting);
        
        // Step 5: Cast votes (creator wins 3-1)
        castVote(disputeId, creator, true); // Creator votes for themselves (evidence already submitted)
        castVote(disputeId, respondent, false); // Respondent votes for themselves
        castVote(disputeId, voter1, true); // Voter1 supports creator
        castVote(disputeId, voter2, false); // Voter2 supports respondent
        
        // Add one more voter to break the tie
        addEvidence(disputeId, voter3, true);
        castVote(disputeId, voter3, true); // Voter3 supports creator
        
        // Step 6: Wait for voting period to end and resolve
        vm.warp(block.timestamp + disputeMarket.VOTING_PERIOD() + 1);
        
        uint256 creatorBalanceBefore = creator.balance;
        disputeMarket.resolveDispute(disputeId);
        
        // Step 7: Verify resolution
        expectDispute(disputeId, creator, respondent, DisputeEvents.DisputeStatus.Resolved);
        
        (uint256 creatorVotes, uint256 respondentVotes, address winner) = disputeMarket.getDisputeResults(disputeId);
        assertEq(creatorVotes, 3);
        assertEq(respondentVotes, 2);
        assertEq(winner, creator);
        
        // Step 8: Verify escrow distribution
        assertEq(creator.balance, creatorBalanceBefore + ESCROW_AMOUNT);
        
        // Step 9: Verify NFT minting
        uint256 tokenId = disputeMarket.getCurrentTokenId();
        assertEq(tokenId, 1);
        assertEq(disputeMarket.ownerOf(tokenId), creator);
        assertEq(disputeMarket.nftTokenToDispute(tokenId), disputeId);
    }
    
    function test_CompleteDisputeWorkflow_RespondentWins() public {
        uint256 disputeId = createBasicDispute();
        
        // Fast forward to voting
        vm.warp(block.timestamp + disputeMarket.DISPUTE_ACTIVATION_PERIOD() + disputeMarket.DISPUTE_PERIOD() + 1);
        disputeMarket.startVoting(disputeId);
        
        // Add evidence and vote (respondent wins 2-1)
        addEvidence(disputeId, respondent, false);
        addEvidence(disputeId, voter1, false);
        
        castVote(disputeId, creator, true); // Creator votes for themselves
        castVote(disputeId, respondent, false); // Respondent votes for themselves
        castVote(disputeId, voter1, false); // Voter1 supports respondent
        
        vm.warp(block.timestamp + disputeMarket.VOTING_PERIOD() + 1);
        
        uint256 respondentBalanceBefore = respondent.balance;
        disputeMarket.resolveDispute(disputeId);
        
        (, , address winner) = disputeMarket.getDisputeResults(disputeId);
        assertEq(winner, respondent);
        assertEq(respondent.balance, respondentBalanceBefore + ESCROW_AMOUNT);
        assertEq(disputeMarket.ownerOf(1), respondent);
    }
    
    function test_CompleteDisputeWorkflow_TieResult() public {
        uint256 disputeId = createBasicDispute();
        
        // Fast forward to voting
        vm.warp(block.timestamp + disputeMarket.DISPUTE_ACTIVATION_PERIOD() + disputeMarket.DISPUTE_PERIOD() + 1);
        disputeMarket.startVoting(disputeId);
        
        // Add evidence and vote (tie 2-2)
        addEvidence(disputeId, respondent, false);
        addEvidence(disputeId, voter1, true);
        addEvidence(disputeId, voter2, false);
        
        castVote(disputeId, creator, true);
        castVote(disputeId, respondent, false);
        castVote(disputeId, voter1, true);
        castVote(disputeId, voter2, false);
        
        vm.warp(block.timestamp + disputeMarket.VOTING_PERIOD() + 1);
        
        uint256 creatorBalanceBefore = creator.balance;
        uint256 respondentBalanceBefore = respondent.balance;
        
        disputeMarket.resolveDispute(disputeId);
        
        // Verify tie resolution
        (uint256 creatorVotes, uint256 respondentVotes, address winner) = disputeMarket.getDisputeResults(disputeId);
        assertEq(creatorVotes, 2);
        assertEq(respondentVotes, 2);
        assertEq(winner, address(disputeMarket)); // Contract address for tie
        
        // Verify escrow split
        uint256 halfAmount = ESCROW_AMOUNT / 2;
        assertEq(creator.balance, creatorBalanceBefore + halfAmount);
        assertEq(respondent.balance, respondentBalanceBefore + halfAmount);
        
        // Verify NFT minted to contract
        assertEq(disputeMarket.ownerOf(1), address(disputeMarket));
    }
    
    function test_MultipleDisputesWorkflow() public {
        // Create multiple disputes from different users
        uint256 dispute1 = createBasicDispute();
        
        // Create second dispute from different creator
        address creator2 = makeAddr("creator2");
        vm.deal(creator2, INITIAL_BALANCE);
        
        defaultParams.respondent = makeAddr("respondent2");
        vm.prank(creator2);
        uint256 dispute2 = disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
        
        // Verify both disputes exist
        assertEq(disputeMarket.disputeCounter() - 1, dispute2);
        assertEq(dispute2, dispute1 + 1);
        
        // Check user dispute tracking
        uint256[] memory user1Disputes = disputeMarket.getUserDisputes(creator);
        uint256[] memory user2Disputes = disputeMarket.getUserDisputes(creator2);
        
        assertEq(user1Disputes.length, 1);
        assertEq(user2Disputes.length, 1);
        assertEq(user1Disputes[0], dispute1);
        assertEq(user2Disputes[0], dispute2);
        
        // Process both disputes to completion
        _processDisputeToCompletion(dispute1, creator, true);
        _processDisputeToCompletion(dispute2, creator2, false);
        
        // Verify final states
        expectDispute(dispute1, creator, respondent, DisputeEvents.DisputeStatus.Resolved);
        expectDispute(dispute2, creator2, defaultParams.respondent, DisputeEvents.DisputeStatus.Resolved);
        
        assertEq(disputeMarket.getCurrentTokenId(), 2);
    }
    
    function test_EscrowHandling_NoEscrowRequired() public {
        defaultParams.requiresEscrow = false;
        defaultParams.escrowAmount = 0;
        
        uint256 creatorBalanceBefore = creator.balance;
        
        vm.prank(creator);
        uint256 disputeId = disputeMarket.createDispute(defaultParams);
        
        // No escrow should be held
        assertEq(address(disputeMarket).balance, 0);
        assertEq(creator.balance, creatorBalanceBefore); // No change in balance
        
        // Process to completion
        _processDisputeToCompletion(disputeId, creator, true);
        
        // Still no escrow changes
        assertEq(creator.balance, creatorBalanceBefore);
    }
    
    function test_EscrowHandling_ExcessRefund() public {
        uint256 excessAmount = 0.5 ether;
        uint256 totalSent = ESCROW_AMOUNT + excessAmount;
        
        uint256 creatorBalanceBefore = creator.balance;
        
        vm.prank(creator);
        uint256 disputeId = disputeMarket.createDispute{value: totalSent}(defaultParams);
        
        // Only escrow amount should be held, excess refunded
        assertEq(address(disputeMarket).balance, ESCROW_AMOUNT);
        assertEq(creator.balance, creatorBalanceBefore - totalSent + excessAmount);
    }
    
    function test_CooldownMechanism_MultipleUsers() public {
        // User 1 creates dispute
        createBasicDispute();
        
        // User 2 can create immediately (different user)
        address creator2 = makeAddr("creator2");
        vm.deal(creator2, INITIAL_BALANCE);
        
        defaultParams.respondent = makeAddr("respondent2");
        vm.prank(creator2);
        disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
        
        // User 1 cannot create another immediately
        vm.prank(creator);
        vm.expectRevert();
        disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
        
        // After cooldown, user 1 can create again
        skipCooldown(creator);
        uint256 dispute3 = createBasicDispute();
        assertEq(dispute3, 3);
    }
    
    function test_EvidenceAndVotingIntegration() public {
        uint256 disputeId = createBasicDispute();
        
        // Multiple users submit evidence
        address[] memory evidenceSubmitters = new address[](5);
        evidenceSubmitters[0] = creator; // Already submitted during creation
        evidenceSubmitters[1] = respondent;
        evidenceSubmitters[2] = voter1;
        evidenceSubmitters[3] = voter2;
        evidenceSubmitters[4] = voter3;
        
        // Add evidence from multiple users
        for (uint256 i = 1; i < evidenceSubmitters.length; i++) {
            addEvidence(disputeId, evidenceSubmitters[i], i % 2 == 0);
        }
        
        // Verify all evidence submitters are tracked
        address[] memory submitters = disputeMarket.getEvidenceSubmitters(disputeId);
        assertEq(submitters.length, evidenceSubmitters.length);
        
        // Start voting phase
        vm.warp(block.timestamp + disputeMarket.DISPUTE_ACTIVATION_PERIOD() + disputeMarket.DISPUTE_PERIOD() + 1);
        disputeMarket.startVoting(disputeId);
        
        // All evidence submitters can vote
        for (uint256 i = 0; i < evidenceSubmitters.length; i++) {
            vm.prank(evidenceSubmitters[i]);
            disputeMarket.castVote(disputeId, i % 2 == 0, string(abi.encodePacked("Vote reason ", vm.toString(i))));
        }
        
        // Verify all votes recorded
        DisputeStorage.Vote[] memory votes = disputeMarket.getDisputeVotes(disputeId);
        assertEq(votes.length, evidenceSubmitters.length);
        
        (uint256 creatorVotes, uint256 respondentVotes, ) = disputeMarket.getDisputeResults(disputeId);
        assertEq(creatorVotes + respondentVotes, evidenceSubmitters.length);
    }
    
    function test_AdminFunctions_Integration() public {
        uint256 disputeId = createBasicDispute();
        
        // Admin blacklists creator
        vm.prank(admin);
        disputeMarket.setUserBlacklist(creator, true);
        
        // Creator cannot create new disputes
        skipCooldown(creator);
        vm.prank(creator);
        vm.expectRevert(UserBlacklisted.selector);
        disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
        
        // Creator cannot submit evidence
        vm.prank(creator);
        vm.expectRevert(UserBlacklisted.selector);
        disputeMarket.submitEvidence(disputeId, "Evidence", "hash", true);
        
        // Admin pauses contract
        vm.prank(admin);
        disputeMarket.pause();
        
        // No one can interact while paused
        vm.prank(respondent);
        vm.expectRevert(); // OpenZeppelin 5.x uses custom errors instead of string messages
        disputeMarket.submitEvidence(disputeId, "Evidence", "hash", false);
        
        // Admin unpauses and unblacklists
        vm.prank(admin);
        disputeMarket.unpause();
        
        vm.prank(admin);
        disputeMarket.setUserBlacklist(creator, false);
        
        // Normal operations resume
        vm.prank(respondent);
        disputeMarket.submitEvidence(disputeId, "Evidence after unpause", "hash2", false);
    }
    
    // Helper function to process a dispute to completion
    function _processDisputeToCompletion(uint256 disputeId, address expectedWinner, bool creatorWins) internal {
        // Add evidence before voting starts
        if (creatorWins) {
            addEvidenceAndPrepareVote(disputeId, voter1, true);
            addEvidenceAndPrepareVote(disputeId, voter2, true);
        } else {
            addEvidenceAndPrepareVote(disputeId, voter1, false);
            addEvidenceAndPrepareVote(disputeId, voter2, false);
        }
        
        // Fast forward to voting
        vm.warp(block.timestamp + disputeMarket.DISPUTE_ACTIVATION_PERIOD() + disputeMarket.DISPUTE_PERIOD() + 1);
        disputeMarket.startVoting(disputeId);
        
        // Cast votes to ensure expected winner
        if (creatorWins) {
            castVote(disputeId, expectedWinner, true); // Creator votes for themselves (has evidence from creation)
            castVote(disputeId, voter1, true);
            castVote(disputeId, voter2, true);
        } else {
            castVote(disputeId, expectedWinner, true); // Creator votes for themselves (has evidence from creation) 
            castVote(disputeId, voter1, false);
            castVote(disputeId, voter2, false);
        }
        
        // Resolve
        vm.warp(block.timestamp + disputeMarket.VOTING_PERIOD() + 1);
        disputeMarket.resolveDispute(disputeId);
    }
}