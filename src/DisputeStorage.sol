//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Dispute_Event.sol";

/**
 * @title DisputeStorage
 * @dev Storage contract
 * @author Lee
 */
contract DisputeStorage is DisputeEvents {
    // ============ ENUMS ============
    
    enum Priority {
        Low,
        Medium,
        High,
        Critical
    }

    // ============ STRUCTS ============
    
    struct Evidence {
        string description;
        string documentHash;
        address submittedBy;
        uint40 timestamp;
        bool verified;
        bool supportsCreator;
    }
    
    struct Vote {
        address voter;
        bool supportsCreator;
        string reason;
        uint40 timestamp;
        bool verified;
    }
    
    struct DisputeInfo {
        address disputeCreatorAddress;
        address respondentAddress;
        string title;
        string description;
        DisputeCategory category;
        Priority priority;
        uint256 escrowAmount;
        uint40 creationTime;
        uint40 activationTime;
        uint40 endTime;
        uint40 votingEndTime;
        uint40 resolutionDeadline;
        DisputeStatus status;
        uint256 creatorVotes;
        uint256 respondentVotes;
        address winner;
        uint256 winnerNftTokenId;
        string resolutionSummary;
        bool requiresEscrow;
        uint40 votingStartTime;
    }

    struct CreateDisputeParams {
        address respondent;
        string title;
        string description;
        DisputeCategory category;
        Priority priority;
        bool requiresEscrow;
        uint256 escrowAmount;
        uint40 customPeriod;
        string[] evidenceDescriptions;
        string[] evidenceHashes;
        bool[] evidenceSupportsCreator;
    }

    // ============ STATE VARIABLES ============
    
    uint256 public disputeCounter;
    uint256 internal _nftTokenIdCounter;
    
    mapping(uint256 => DisputeInfo) public disputes;
    mapping(uint256 => Evidence[]) public disputeEvidences;
    mapping(uint256 => Vote[]) public disputeVotes;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => bool)) public hasSubmittedEvidence;
    mapping(uint256 => address[]) public evidenceSubmitters;
    mapping(address => uint256[]) public userDisputes;
    mapping(address => uint256) public userDisputeCount;
    mapping(address => uint40) public lastDisputeTime;
    mapping(address => bool) public isBlacklisted;
    mapping(DisputeCategory => uint256) public categoryCount;
    mapping(uint256 => uint256) public disputeToNftToken;
    mapping(uint256 => uint256) public nftTokenToDispute;
}