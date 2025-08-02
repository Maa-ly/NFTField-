//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title DisputeEvents
 * @dev Events for the Dispute Market contract
 */
contract DisputeEvents {
    // ============ ENUMS FOR EVENTS ============
    
    enum DisputeStatus {
        Pending,        
        Active,         
        Voting,         
        UnderReview,    
        Resolved,       
        Cancelled,      
        Expired         
    }
    
    enum DisputeCategory {
        General,
        Financial,
        Technical,
        Legal,
        Service,
        Product,
        Intellectual
    }

    // ============ EVENTS ============
    
    event DisputeCreated(
        uint256 indexed disputeId,
        address indexed creator,
        address indexed respondent,
        string title,
        DisputeCategory category,
        uint256 escrowAmount
    );
    
    event EvidenceSubmitted(
        uint256 indexed disputeId,
        address indexed submitter,
        string description,
        string documentHash,
        bool supportsCreator
    );
    
    event DisputeStatusChanged(
        uint256 indexed disputeId,
        DisputeStatus oldStatus,
        DisputeStatus newStatus,
        address changedBy
    );
    
    event VoteCast(
        uint256 indexed disputeId,
        address indexed voter,
        bool supportsCreator,
        string reason
    );
    
    event VotingStarted(
        uint256 indexed disputeId,
        uint40 votingEndTime
    );
    
    event DisputeResolved(
        uint256 indexed disputeId,
        address indexed winner,
        uint256 creatorVotes,
        uint256 respondentVotes,
        uint256 nftTokenId
    );
    
    event DisputeNFTMinted(
        uint256 indexed disputeId,
        address indexed winner,
        uint256 indexed tokenId,
        string tokenURI
    );
    
    event TieNFTTransferred(
        uint256 indexed tokenId,
        uint256 indexed disputeId,
        address indexed to
    );
}