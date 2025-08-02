//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title DisputeErrors
 * @dev Custom errors for the Dispute Market contract
 */
contract DisputeErrors {
    // ============ ERRORS ============
    
    error InvalidDisputeParameters();
    error DisputeCooldownActive(uint40 remainingTime);
    error UserBlacklisted();
    error InvalidEvidenceCount();
    error InvalidDescriptionLength();
    error DisputeNotFound();
    error UnauthorizedAction();
    error DisputeNotActive();
    error DisputeNotInVotingPhase();
    error AlreadyVoted();
    error NotEvidenceSubmitter();
    error InvalidEscrowAmount();
    error DisputeExpired();
    error VotingNotStarted();
    error VotingEnded();
    error DisputeAlreadyResolved();
}