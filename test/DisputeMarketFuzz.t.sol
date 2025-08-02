//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BaseTest.sol";

/**
 * @title DisputeMarketFuzzTest
 * @dev Fuzz tests for property-based testing and edge case discovery
 */
contract DisputeMarketFuzzTest is BaseTest {
    
    // ============ DISPUTE CREATION FUZZ TESTS ============
    
    function testFuzz_CreateDispute_ValidInputs(
        address respondent,
        uint256 escrowAmount,
        uint8 categoryIndex,
        uint8 priorityIndex,
        bool requiresEscrow,
        uint32 customPeriod
    ) public {
        // Bound inputs to valid ranges
        vm.assume(respondent != address(0) && respondent != creator);
        escrowAmount = bound(escrowAmount, 0, 100 ether);
        categoryIndex = uint8(bound(categoryIndex, 0, 6)); // 7 categories (0-6)
        priorityIndex = uint8(bound(priorityIndex, 0, 3)); // 4 priorities (0-3)
        customPeriod = uint32(bound(customPeriod, 0, disputeMarket.MAX_DISPUTE_PERIOD()));
        
        // Skip if custom period is non-zero but invalid
        if (customPeriod > 0) {
            vm.assume(customPeriod >= disputeMarket.MIN_DISPUTE_PERIOD() && customPeriod <= disputeMarket.MAX_DISPUTE_PERIOD());
        }
        
        // Setup valid evidence arrays
        string[] memory evidenceDescriptions = new string[](1);
        evidenceDescriptions[0] = "Valid evidence description for fuzz testing";
        
        string[] memory evidenceHashes = new string[](1);
        evidenceHashes[0] = "valid_hash";
        
        bool[] memory evidenceSupportsCreator = new bool[](1);
        evidenceSupportsCreator[0] = true;
        
        DisputeStorage.CreateDisputeParams memory params = DisputeStorage.CreateDisputeParams({
            respondent: respondent,
            title: "Fuzz Test Dispute",
            description: "This is a valid description for fuzz testing purposes",
            category: DisputeEvents.DisputeCategory(categoryIndex),
            priority: DisputeStorage.Priority(priorityIndex),
            requiresEscrow: requiresEscrow,
            escrowAmount: requiresEscrow ? escrowAmount : 0,
            customPeriod: customPeriod,
            evidenceDescriptions: evidenceDescriptions,
            evidenceHashes: evidenceHashes,
            evidenceSupportsCreator: evidenceSupportsCreator
        });
        
        uint256 valueSent = requiresEscrow ? escrowAmount : 0;
        
        vm.prank(creator);
        uint256 disputeId = disputeMarket.createDispute{value: valueSent}(params);
        
        // Verify dispute was created successfully
        assertGt(disputeId, 0);
        expectDispute(disputeId, creator, respondent, DisputeEvents.DisputeStatus.Pending);
        
        // Verify escrow handling
        if (requiresEscrow) {
            assertEq(address(disputeMarket).balance, escrowAmount);
        } else {
            assertEq(address(disputeMarket).balance, 0);
        }
    }
    
    function testFuzz_CreateDispute_InvalidEscrow(uint256 escrowAmount, uint256 valueSent) public {
        escrowAmount = bound(escrowAmount, 1, 100 ether);
        valueSent = bound(valueSent, 0, escrowAmount - 1);
        
        defaultParams.requiresEscrow = true;
        defaultParams.escrowAmount = escrowAmount;
        
        vm.prank(creator);
        vm.expectRevert(InvalidEscrowAmount.selector);
        disputeMarket.createDispute{value: valueSent}(defaultParams);
    }
    
    function testFuzz_CreateDispute_ExcessRefund(uint256 escrowAmount, uint256 excess) public {
        escrowAmount = bound(escrowAmount, 1 ether, 10 ether);
        excess = bound(excess, 1, 10 ether);
        
        defaultParams.requiresEscrow = true;
        defaultParams.escrowAmount = escrowAmount;
        
        uint256 totalSent = escrowAmount + excess;
        uint256 creatorBalanceBefore = creator.balance;
        
        vm.prank(creator);
        disputeMarket.createDispute{value: totalSent}(defaultParams);
        
        // Verify correct escrow amount held and excess refunded
        assertEq(address(disputeMarket).balance, escrowAmount);
        assertEq(creator.balance, creatorBalanceBefore - escrowAmount);
    }
    
    // ============ EVIDENCE SUBMISSION FUZZ TESTS ============
    
    function testFuzz_SubmitEvidence_ValidInputs(
        uint8 submitterIndex,
        bool supportsCreator,
        string memory description,
        string memory documentHash
    ) public {
        // Create valid test addresses
        address[5] memory testAddresses = [creator, respondent, voter1, voter2, voter3];
        submitterIndex = uint8(bound(submitterIndex, 0, 4));
        address submitter = testAddresses[submitterIndex];
        
        // Ensure description is valid length
        bytes memory descBytes = bytes(description);
        vm.assume(descBytes.length >= disputeMarket.MIN_DESCRIPTION_LENGTH() && 
                  descBytes.length <= disputeMarket.MAX_DESCRIPTION_LENGTH());
        
        uint256 disputeId = createBasicDispute();
        
        vm.prank(submitter);
        disputeMarket.submitEvidence(disputeId, description, documentHash, supportsCreator);
        
        assertEvidenceSubmitted(disputeId, submitter);
        
        DisputeStorage.Evidence[] memory evidences = disputeMarket.getDisputeEvidence(disputeId);
        bool found = false;
        for (uint256 i = 0; i < evidences.length; i++) {
            if (evidences[i].submittedBy == submitter && 
                keccak256(bytes(evidences[i].description)) == keccak256(descBytes) &&
                evidences[i].supportsCreator == supportsCreator) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Evidence should be found with correct properties");
    }
    
    // ============ VOTING FUZZ TESTS ============
    
    function testFuzz_CastVote_ValidInputs(
        bool supportsCreator,
        string memory reason,
        uint8 voterCount
    ) public {
        // Bound voter count to reasonable range
        voterCount = uint8(bound(voterCount, 1, 10));
        
        // Ensure reason is valid length
        bytes memory reasonBytes = bytes(reason);
        vm.assume(reasonBytes.length >= disputeMarket.MIN_VOTE_REASON_LENGTH() && 
                  reasonBytes.length <= disputeMarket.MAX_VOTE_REASON_LENGTH());
        
        uint256 disputeId = createDisputeAndStartVoting();
        
        // Create multiple voters and have them vote
        address[] memory voters = new address[](voterCount);
        for (uint256 i = 0; i < voterCount; i++) {
            voters[i] = makeAddr(string(abi.encodePacked("voter", vm.toString(i))));
            vm.deal(voters[i], INITIAL_BALANCE);
            
            // Add evidence so they can vote
            addEvidence(disputeId, voters[i], supportsCreator);
            
            vm.prank(voters[i]);
            disputeMarket.castVote(disputeId, supportsCreator, reason);
            
            assertVoteRecorded(disputeId, voters[i], supportsCreator);
        }
        
        // Verify vote counts
        (uint256 creatorVotes, uint256 respondentVotes, ) = disputeMarket.getDisputeResults(disputeId);
        if (supportsCreator) {
            assertEq(creatorVotes, voterCount + 1); // +1 for creator's initial evidence/vote capability
        } else {
            assertEq(respondentVotes, voterCount);
        }
    }
    
    // ============ RESOLUTION FUZZ TESTS ============
    
    function testFuzz_ResolveDispute_VariableVoteCounts(
        uint8 creatorVoteCount,
        uint8 respondentVoteCount
    ) public {
        creatorVoteCount = uint8(bound(creatorVoteCount, 1, 20));
        respondentVoteCount = uint8(bound(respondentVoteCount, 1, 20));
        
        uint256 disputeId = createDisputeAndStartVoting();
        
        // Create voters for creator
        for (uint256 i = 0; i < creatorVoteCount; i++) {
            address voter = makeAddr(string(abi.encodePacked("creatorVoter", vm.toString(i))));
            vm.deal(voter, INITIAL_BALANCE);
            castVote(disputeId, voter, true);
        }
        
        // Create voters for respondent  
        for (uint256 i = 0; i < respondentVoteCount; i++) {
            address voter = makeAddr(string(abi.encodePacked("respondentVoter", vm.toString(i))));
            vm.deal(voter, INITIAL_BALANCE);
            castVote(disputeId, voter, false);
        }
        
        // Fast forward and resolve
        vm.warp(block.timestamp + disputeMarket.VOTING_PERIOD() + 1);
        disputeMarket.resolveDispute(disputeId);
        
        // Verify correct winner determination
        (uint256 finalCreatorVotes, uint256 finalRespondentVotes, address winner) = disputeMarket.getDisputeResults(disputeId);
        
        assertEq(finalCreatorVotes, creatorVoteCount + 1); // +1 for creator's implicit vote
        assertEq(finalRespondentVotes, respondentVoteCount);
        
        if (finalCreatorVotes > finalRespondentVotes) {
            assertEq(winner, creator);
        } else if (finalRespondentVotes > finalCreatorVotes) {
            assertEq(winner, respondent);
        } else {
            assertEq(winner, address(disputeMarket)); // Tie
        }
    }
    
    // ============ TIME-BASED FUZZ TESTS ============
    
    function testFuzz_TimeBasedTransitions(
        uint32 activationDelay,
        uint32 disputePeriod,
        uint32 votingDelay
    ) public {
        // Bound to reasonable time ranges
        activationDelay = uint32(bound(activationDelay, 0, disputeMarket.DISPUTE_ACTIVATION_PERIOD() * 2));
        disputePeriod = uint32(bound(disputePeriod, 0, disputeMarket.DISPUTE_PERIOD() * 2));
        votingDelay = uint32(bound(votingDelay, 0, disputeMarket.VOTING_PERIOD() * 2));
        
        uint256 disputeId = createBasicDispute();
        uint256 startTime = block.timestamp;
        
        // Test activation timing
        vm.warp(startTime + activationDelay);
        
        if (activationDelay >= disputeMarket.DISPUTE_ACTIVATION_PERIOD()) {
            // Should be able to add evidence after activation
            vm.prank(voter1);
            disputeMarket.submitEvidence(disputeId, "Evidence after activation", "hash", true);
        }
        
        // Test dispute period timing
        vm.warp(startTime + disputeMarket.DISPUTE_ACTIVATION_PERIOD() + disputePeriod);
        
        if (disputePeriod >= disputeMarket.DISPUTE_PERIOD()) {
            // Should be able to start voting after dispute period
            disputeMarket.startVoting(disputeId);
            expectDispute(disputeId, creator, respondent, DisputeEvents.DisputeStatus.Voting);
            
            // Test voting period timing
            vm.warp(block.timestamp + votingDelay);
            
            if (votingDelay >= disputeMarket.VOTING_PERIOD()) {
                // Should be able to resolve after voting period
                disputeMarket.resolveDispute(disputeId);
                expectDispute(disputeId, creator, respondent, DisputeEvents.DisputeStatus.Resolved);
            } else {
                // Should not be able to resolve during voting period
                vm.expectRevert("Voting period not ended");
                disputeMarket.resolveDispute(disputeId);
            }
        }
    }
    
    // ============ EDGE CASE FUZZ TESTS ============
    
    function testFuzz_MaxEvidenceCount(uint8 evidenceCount) public {
        evidenceCount = uint8(bound(evidenceCount, 1, disputeMarket.MAX_EVIDENCE_COUNT() + 5));
        
        uint256 disputeId = createBasicDispute();
        
        // Try to submit evidence up to the limit
        for (uint256 i = 1; i < evidenceCount; i++) { // Start from 1 since creator already submitted
            address evidenceSubmitter = makeAddr(string(abi.encodePacked("evidenceSubmitter", vm.toString(i))));
            
            if (i < disputeMarket.MAX_EVIDENCE_COUNT()) {
                // Should succeed
                vm.prank(evidenceSubmitter);
                disputeMarket.submitEvidence(
                    disputeId,
                    string(abi.encodePacked("Evidence ", vm.toString(i))),
                    string(abi.encodePacked("hash", vm.toString(i))),
                    i % 2 == 0
                );
            } else {
                // Should fail at limit
                vm.prank(evidenceSubmitter);
                vm.expectRevert("Evidence limit reached");
                disputeMarket.submitEvidence(
                    disputeId,
                    string(abi.encodePacked("Evidence ", vm.toString(i))),
                    string(abi.encodePacked("hash", vm.toString(i))),
                    i % 2 == 0
                );
            }
        }
        
        DisputeStorage.Evidence[] memory evidences = disputeMarket.getDisputeEvidence(disputeId);
        assertLe(evidences.length, disputeMarket.MAX_EVIDENCE_COUNT());
    }
    
    function testFuzz_CooldownPeriod(uint32 timeBetweenDisputes) public {
        timeBetweenDisputes = uint32(bound(timeBetweenDisputes, 0, disputeMarket.DISPUTE_COOL_DOWN_PERIOD() * 2));
        
        createBasicDispute();
        uint256 firstDisputeTime = block.timestamp;
        
        vm.warp(firstDisputeTime + timeBetweenDisputes);
        
        if (timeBetweenDisputes >= disputeMarket.DISPUTE_COOL_DOWN_PERIOD()) {
            // Should be able to create another dispute
            uint256 secondDisputeId = createBasicDispute();
            assertEq(secondDisputeId, 2);
        } else {
            // Should fail due to cooldown
            vm.prank(creator);
            vm.expectRevert();
            disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
        }
    }
    
    // ============ INVARIANT TESTS ============
    
    function testFuzz_Invariant_DisputeCounterIncreases(uint8 disputeCount) public {
        disputeCount = uint8(bound(disputeCount, 1, 10));
        
        uint256 initialCounter = disputeMarket.disputeCounter();
        
        for (uint256 i = 0; i < disputeCount; i++) {
            address disputeCreator = makeAddr(string(abi.encodePacked("creator", vm.toString(i))));
            vm.deal(disputeCreator, INITIAL_BALANCE);
            
            defaultParams.respondent = makeAddr(string(abi.encodePacked("respondent", vm.toString(i))));
            
            vm.prank(disputeCreator);
            disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
        }
        
        assertEq(disputeMarket.disputeCounter(), initialCounter + disputeCount);
    }
    
    function testFuzz_Invariant_EscrowConservation(uint8 disputeCount, bool[] memory requiresEscrow) public {
        disputeCount = uint8(bound(disputeCount, 1, 5));
        vm.assume(requiresEscrow.length == disputeCount);
        
        uint256 totalEscrowExpected = 0;
        
        for (uint256 i = 0; i < disputeCount; i++) {
            address disputeCreator = makeAddr(string(abi.encodePacked("escrowCreator", vm.toString(i))));
            vm.deal(disputeCreator, INITIAL_BALANCE);
            
            defaultParams.respondent = makeAddr(string(abi.encodePacked("escrowRespondent", vm.toString(i))));
            defaultParams.requiresEscrow = requiresEscrow[i];
            defaultParams.escrowAmount = requiresEscrow[i] ? ESCROW_AMOUNT : 0;
            
            if (requiresEscrow[i]) {
                totalEscrowExpected += ESCROW_AMOUNT;
            }
            
            vm.prank(disputeCreator);
            disputeMarket.createDispute{value: requiresEscrow[i] ? ESCROW_AMOUNT : 0}(defaultParams);
        }
        
        assertEq(address(disputeMarket).balance, totalEscrowExpected);
    }
}