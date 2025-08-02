//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Dispute_Market.sol";
import "../src/DisputeStorage.sol";
import "../src/Dispute_Event.sol";
import "../src/Dispute_Error.sol";

/**
 * @title BaseTest
 * @dev Base test contract with common setup and utilities for all test files
 */
contract BaseTest is Test, DisputeEvents, DisputeErrors {
    DisputeMarket public disputeMarket;
    DisputeMarket public implementation;
    ERC1967Proxy public proxy;
    
    address public admin = makeAddr("admin");
    address public moderator = makeAddr("moderator");
    address public resolver = makeAddr("resolver");
    address public creator = makeAddr("creator");
    address public respondent = makeAddr("respondent");
    address public voter1 = makeAddr("voter1");
    address public voter2 = makeAddr("voter2");
    address public voter3 = makeAddr("voter3");
    
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant ESCROW_AMOUNT = 1 ether;
    
    // Test dispute parameters
    DisputeStorage.CreateDisputeParams public defaultParams;
    
    function setUp() public virtual {
        // Deploy implementation
        implementation = new DisputeMarket();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            DisputeMarket.initialize.selector,
            admin
        );
        proxy = new ERC1967Proxy(address(implementation), initData);
        disputeMarket = DisputeMarket(address(proxy));
        
        // Setup roles
        vm.startPrank(admin);
        disputeMarket.grantRole(disputeMarket.MODERATOR_ROLE(), moderator);
        disputeMarket.grantRole(disputeMarket.RESOLVER_ROLE(), resolver);
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(admin, INITIAL_BALANCE);
        vm.deal(creator, INITIAL_BALANCE);
        vm.deal(respondent, INITIAL_BALANCE);
        vm.deal(voter1, INITIAL_BALANCE);
        vm.deal(voter2, INITIAL_BALANCE);
        vm.deal(voter3, INITIAL_BALANCE);
        
        // Setup default dispute parameters
        string[] memory evidenceDescriptions = new string[](2);
        evidenceDescriptions[0] = "Evidence description 1";
        evidenceDescriptions[1] = "Evidence description 2";
        
        string[] memory evidenceHashes = new string[](2);
        evidenceHashes[0] = "hash1";
        evidenceHashes[1] = "hash2";
        
        bool[] memory evidenceSupportsCreator = new bool[](2);
        evidenceSupportsCreator[0] = true;
        evidenceSupportsCreator[1] = true;
        
        defaultParams = DisputeStorage.CreateDisputeParams({
            respondent: respondent,
            title: "Test Dispute",
            description: "This is a test dispute for unit testing",
            category: DisputeEvents.DisputeCategory.General,
            priority: DisputeStorage.Priority.Medium,
            requiresEscrow: true,
            escrowAmount: ESCROW_AMOUNT,
            customPeriod: 0,
            evidenceDescriptions: evidenceDescriptions,
            evidenceHashes: evidenceHashes,
            evidenceSupportsCreator: evidenceSupportsCreator
        });
    }
    
    // ============ HELPER FUNCTIONS ============
    
    function createBasicDispute() public returns (uint256 disputeId) {
        vm.prank(creator);
        disputeId = disputeMarket.createDispute{value: ESCROW_AMOUNT}(defaultParams);
    }
    
    function createDisputeAndActivate() public returns (uint256 disputeId) {
        disputeId = createBasicDispute();
        
        // Fast forward past activation period
        vm.warp(block.timestamp + disputeMarket.DISPUTE_ACTIVATION_PERIOD() + 1);
    }
    
    function createDisputeAndStartVoting() public returns (uint256 disputeId) {
        disputeId = createDisputeAndActivate();
        
        // Fast forward to voting time
        vm.warp(block.timestamp + disputeMarket.DISPUTE_PERIOD() + 1);
        
        // Start voting
        disputeMarket.startVoting(disputeId);
    }
    
    function addEvidence(uint256 disputeId, address submitter, bool supportsCreator) public {
        vm.prank(submitter);
        disputeMarket.submitEvidence(
            disputeId,
            "Additional evidence",
            "additional_hash",
            supportsCreator
        );
    }
    
    function castVote(uint256 disputeId, address voter, bool supportsCreator) public {
        // Check if voter already has evidence, if not, this should be called before voting starts
        if (!disputeMarket.hasSubmittedEvidence(disputeId, voter)) {
            revert("Voter must submit evidence before voting starts");
        }
        
        vm.prank(voter);
        disputeMarket.castVote(disputeId, supportsCreator, "Vote reason");
    }
    
    function addEvidenceAndPrepareVote(uint256 disputeId, address voter, bool supportsCreator) public {
        // Add evidence before voting starts
        addEvidence(disputeId, voter, supportsCreator);
    }
    
    function expectDispute(
        uint256 disputeId,
        address expectedCreator,
        address expectedRespondent,
        DisputeEvents.DisputeStatus expectedStatus
    ) public {
        (
            address creator_,
            address respondent_,
            ,
            ,
            ,
            ,
            DisputeEvents.DisputeStatus status_
        ) = disputeMarket.getDisputeBasicInfo(disputeId);
        
        assertEq(creator_, expectedCreator, "Creator mismatch");
        assertEq(respondent_, expectedRespondent, "Respondent mismatch");
        assertEq(uint256(status_), uint256(expectedStatus), "Status mismatch");
    }
    
    function skipCooldown(address user) public {
        vm.warp(block.timestamp + disputeMarket.DISPUTE_COOL_DOWN_PERIOD() + 1);
    }
    
    // ============ ASSERTION HELPERS ============
    
    function assertDisputeCreated(uint256 disputeId, address creator_, address respondent_) public {
        expectDispute(disputeId, creator_, respondent_, DisputeEvents.DisputeStatus.Pending);
        assertEq(disputeMarket.disputeCounter() - 1, disputeId, "Dispute counter should increment");
    }
    
    function assertVoteRecorded(uint256 disputeId, address voter, bool supportsCreator) public {
        assertTrue(disputeMarket.hasVoted(disputeId, voter), "Vote should be recorded");
        
        (uint256 creatorVotes, uint256 respondentVotes, ) = disputeMarket.getDisputeResults(disputeId);
        if (supportsCreator) {
            assertGt(creatorVotes, 0, "Creator should have votes");
        } else {
            assertGt(respondentVotes, 0, "Respondent should have votes");
        }
    }
    
    function assertEvidenceSubmitted(uint256 disputeId, address submitter) public {
        assertTrue(disputeMarket.hasSubmittedEvidence(disputeId, submitter), "Evidence should be recorded");
        
        address[] memory submitters = disputeMarket.getEvidenceSubmitters(disputeId);
        bool found = false;
        for (uint256 i = 0; i < submitters.length; i++) {
            if (submitters[i] == submitter) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Submitter should be in evidence submitters list");
    }
    
    // ============ MOCK DATA GENERATORS ============
    
    function generateRandomDispute(uint256 seed) public view returns (DisputeStorage.CreateDisputeParams memory) {
        string[] memory evidenceDescriptions = new string[](1);
        evidenceDescriptions[0] = string(abi.encodePacked("Evidence ", vm.toString(seed)));
        
        string[] memory evidenceHashes = new string[](1);
        evidenceHashes[0] = string(abi.encodePacked("hash", vm.toString(seed)));
        
        bool[] memory evidenceSupportsCreator = new bool[](1);
        evidenceSupportsCreator[0] = seed % 2 == 0;
        
        return DisputeStorage.CreateDisputeParams({
            respondent: address(uint160(seed + 1000)),
            title: string(abi.encodePacked("Dispute ", vm.toString(seed))),
            description: string(abi.encodePacked("Description for dispute ", vm.toString(seed))),
            category: DisputeEvents.DisputeCategory(seed % 7),
            priority: DisputeStorage.Priority(seed % 4),
            requiresEscrow: seed % 3 == 0,
            escrowAmount: seed % 3 == 0 ? ESCROW_AMOUNT : 0,
            customPeriod: 0,
            evidenceDescriptions: evidenceDescriptions,
            evidenceHashes: evidenceHashes,
            evidenceSupportsCreator: evidenceSupportsCreator
        });
    }
}