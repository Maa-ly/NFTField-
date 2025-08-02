//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC721Upgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";

import "./DisputeStorage.sol";
import "./Dispute_Error.sol";

/**
 * @title DisputeMarket
 * @dev Upgradeable contract
 * @author Lee
 */
contract DisputeMarket is 
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    DisputeStorage,
    DisputeErrors
{
    // ============ CONSTANTS ============
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    uint40 public constant DISPUTE_COOL_DOWN_PERIOD = 7 days;
    uint40 public constant RESOLUTION_PERIOD = 14 days;
    uint40 public constant DISPUTE_ACTIVATION_PERIOD = 1 days;
    uint40 public constant DISPUTE_PERIOD = 30 days;
    uint40 public constant VOTING_PERIOD = 7 days;
    uint40 public constant MIN_DISPUTE_PERIOD = 1 days;
    uint40 public constant MAX_DISPUTE_PERIOD = 90 days;
    uint256 public constant MIN_VOTE_REASON_LENGTH = 5;
    uint256 public constant MAX_VOTE_REASON_LENGTH = 500;
    
    uint256 public constant MIN_DESCRIPTION_LENGTH = 10;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;
    uint256 public constant MIN_EVIDENCE_COUNT = 1;
    uint256 public constant MAX_EVIDENCE_COUNT = 50;

    // Note: All storage variables, enums, and structs are now inherited from DisputeStorage

    // ============ MODIFIERS ============
    
    modifier onlyValidDispute(uint256 _disputeId) {
        if (_disputeId >= disputeCounter || _disputeId == 0) revert DisputeNotFound();
        _;
    }
    
    modifier notBlacklisted() {
        if (isBlacklisted[msg.sender]) revert UserBlacklisted();
        _;
    }
    
    modifier respectsCooldown() {
        if (lastDisputeTime[msg.sender] > 0) {
            uint40 timeSinceLastDispute = uint40(block.timestamp) - lastDisputeTime[msg.sender];
            if (timeSinceLastDispute < DISPUTE_COOL_DOWN_PERIOD) {
                revert DisputeCooldownActive(DISPUTE_COOL_DOWN_PERIOD - timeSinceLastDispute);
            }
        }
        _;
    }

    // ============ INITIALIZATION ============
    
    function initialize(address _admin) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __ERC721_init("DisputeResolutionNFT", "DISPUTE");
        __ERC721URIStorage_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        
        disputeCounter = 1;
        _nftTokenIdCounter = 0;
    }

    // ============ MAIN FUNCTIONS ============
    
    function createDispute(CreateDisputeParams calldata params) 
        external 
        payable 
        whenNotPaused
        nonReentrant
        notBlacklisted
        respectsCooldown
        returns (uint256 disputeId)
    {
        _validateDisputeParams(params);
        
        disputeId = disputeCounter++;
        _createDisputeInternal(disputeId, params);
        _handleEvidenceSubmission(disputeId, params);
        _updateUserTracking(disputeId, params.category);
        _handleEscrowAndRefund(params);
        
        emit DisputeCreated(
            disputeId,
            msg.sender,
            params.respondent,
            params.title,
            params.category,
            params.escrowAmount
        );
        
        return disputeId;
    }

    function submitEvidence(
        uint256 _disputeId,
        string calldata _description,
        string calldata _documentHash,
        bool _supportsCreator
    ) external whenNotPaused onlyValidDispute(_disputeId) notBlacklisted {
        _validateEvidenceSubmission(_disputeId, _description);
        _addEvidence(_disputeId, _description, _documentHash, _supportsCreator);
    }

    function startVoting(uint256 _disputeId) external whenNotPaused onlyValidDispute(_disputeId) {
        DisputeInfo storage dispute = disputes[_disputeId];
        
        // Auto-activate dispute if enough time has passed
        if (dispute.status == DisputeStatus.Pending && block.timestamp >= dispute.activationTime) {
            dispute.status = DisputeStatus.Active;
        }
        
        require(dispute.status == DisputeStatus.Active, "Dispute not in active status");
        require(block.timestamp >= dispute.votingStartTime, "Voting time not reached");
        require(evidenceSubmitters[_disputeId].length > 0, "No evidence submitters to vote");
        
        DisputeStatus oldStatus = dispute.status;
        dispute.status = DisputeStatus.Voting;
        
        emit DisputeStatusChanged(_disputeId, oldStatus, DisputeStatus.Voting, msg.sender);
        emit VotingStarted(_disputeId, dispute.votingEndTime);
    }

    function castVote(
        uint256 _disputeId,
        bool _supportsCreator,
        string calldata _reason
    ) external whenNotPaused onlyValidDispute(_disputeId) notBlacklisted {
        _validateVote(_disputeId, _reason);
        _recordVote(_disputeId, _supportsCreator, _reason);
    }

    function resolveDispute(uint256 _disputeId) external whenNotPaused onlyValidDispute(_disputeId) nonReentrant {
        _validateResolution(_disputeId);
        _processResolution(_disputeId);
    }

    // ============ INTERNAL FUNCTIONS ============

    function _validateDisputeParams(CreateDisputeParams calldata params) internal view {
        if (params.respondent == address(0) || params.respondent == msg.sender) {
            revert InvalidDisputeParameters();
        }
        
        if (bytes(params.description).length < MIN_DESCRIPTION_LENGTH || 
            bytes(params.description).length > MAX_DESCRIPTION_LENGTH) {
            revert InvalidDescriptionLength();
        }
        
        if (params.evidenceDescriptions.length != params.evidenceHashes.length ||
            params.evidenceDescriptions.length != params.evidenceSupportsCreator.length ||
            params.evidenceDescriptions.length < MIN_EVIDENCE_COUNT || 
            params.evidenceDescriptions.length > MAX_EVIDENCE_COUNT) {
            revert InvalidEvidenceCount();
        }
        
        uint40 disputePeriod = params.customPeriod > 0 ? params.customPeriod : DISPUTE_PERIOD;
        if (disputePeriod < MIN_DISPUTE_PERIOD || disputePeriod > MAX_DISPUTE_PERIOD) {
            revert InvalidDisputeParameters();
        }
        
        if (params.requiresEscrow) {
            if (params.escrowAmount == 0 || msg.value < params.escrowAmount) {
                revert InvalidEscrowAmount();
            }
        }
    }

    function _createDisputeInternal(uint256 disputeId, CreateDisputeParams calldata params) internal {
        DisputeInfo storage newDispute = disputes[disputeId];
        
        newDispute.disputeCreatorAddress = msg.sender;
        newDispute.respondentAddress = params.respondent;
        newDispute.title = params.title;
        newDispute.description = params.description;
        newDispute.category = params.category;
        newDispute.priority = params.priority;
        newDispute.escrowAmount = params.escrowAmount;
        newDispute.requiresEscrow = params.requiresEscrow;
        
        uint40 disputePeriod = params.customPeriod > 0 ? params.customPeriod : DISPUTE_PERIOD;
        newDispute.creationTime = uint40(block.timestamp);
        newDispute.activationTime = uint40(block.timestamp) + DISPUTE_ACTIVATION_PERIOD;
        newDispute.endTime = newDispute.activationTime + disputePeriod;
        newDispute.votingStartTime = newDispute.endTime;
        newDispute.votingEndTime = newDispute.votingStartTime + VOTING_PERIOD;
        newDispute.resolutionDeadline = newDispute.votingEndTime + RESOLUTION_PERIOD;
        newDispute.status = DisputeStatus.Pending;
    }

    function _handleEvidenceSubmission(uint256 disputeId, CreateDisputeParams calldata params) internal {
        if (!hasSubmittedEvidence[disputeId][msg.sender]) {
            hasSubmittedEvidence[disputeId][msg.sender] = true;
            evidenceSubmitters[disputeId].push(msg.sender);
        }
        
        for (uint256 i = 0; i < params.evidenceDescriptions.length; i++) {
            Evidence memory evidence = Evidence({
                description: params.evidenceDescriptions[i],
                documentHash: params.evidenceHashes[i],
                submittedBy: msg.sender,
                timestamp: uint40(block.timestamp),
                verified: false,
                supportsCreator: params.evidenceSupportsCreator[i]
            });
            disputeEvidences[disputeId].push(evidence);
            
            emit EvidenceSubmitted(
                disputeId,
                msg.sender,
                evidence.description,
                evidence.documentHash,
                evidence.supportsCreator
            );
        }
    }

    function _updateUserTracking(uint256 disputeId, DisputeCategory category) internal {
        userDisputes[msg.sender].push(disputeId);
        userDisputeCount[msg.sender]++;
        lastDisputeTime[msg.sender] = uint40(block.timestamp);
        categoryCount[category]++;
    }

    function _handleEscrowAndRefund(CreateDisputeParams calldata params) internal {
        uint256 excess = 0;
        if (params.requiresEscrow) {
            excess = msg.value - params.escrowAmount;
        } else {
            excess = msg.value;
        }
        
        if (excess > 0) {
            (bool success, ) = msg.sender.call{value: excess}("");
            require(success, "Excess refund failed");
        }
    }

    function _validateEvidenceSubmission(uint256 _disputeId, string calldata _description) internal view {
        DisputeInfo storage dispute = disputes[_disputeId];
        
        require(
            dispute.status == DisputeStatus.Pending ||
            dispute.status == DisputeStatus.Active ||
            dispute.status == DisputeStatus.UnderReview,
            "Cannot submit evidence at this time"
        );
        
        require(disputeEvidences[_disputeId].length < MAX_EVIDENCE_COUNT, "Evidence limit reached");
        require(bytes(_description).length >= MIN_DESCRIPTION_LENGTH, "Description too short");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
    }

    function _addEvidence(
        uint256 _disputeId,
        string calldata _description,
        string calldata _documentHash,
        bool _supportsCreator
    ) internal {
        if (!hasSubmittedEvidence[_disputeId][msg.sender]) {
            hasSubmittedEvidence[_disputeId][msg.sender] = true;
            evidenceSubmitters[_disputeId].push(msg.sender);
        }
        
        Evidence memory evidence = Evidence({
            description: _description,
            documentHash: _documentHash,
            submittedBy: msg.sender,
            timestamp: uint40(block.timestamp),
            verified: false,
            supportsCreator: _supportsCreator
        });
        
        disputeEvidences[_disputeId].push(evidence);
        emit EvidenceSubmitted(_disputeId, msg.sender, _description, _documentHash, _supportsCreator);
    }

    function _validateVote(uint256 _disputeId, string calldata _reason) internal view {
        DisputeInfo storage dispute = disputes[_disputeId];
        
        require(dispute.status == DisputeStatus.Voting, "Dispute not in voting phase");
        require(block.timestamp <= dispute.votingEndTime, "Voting period ended");
        require(!hasVoted[_disputeId][msg.sender], "Already voted");
        require(hasSubmittedEvidence[_disputeId][msg.sender], "Must have submitted evidence to vote");
        require(bytes(_reason).length >= MIN_VOTE_REASON_LENGTH, "Reason too short");
        require(bytes(_reason).length <= MAX_VOTE_REASON_LENGTH, "Reason too long");
    }

    function _recordVote(uint256 _disputeId, bool _supportsCreator, string calldata _reason) internal {
        hasVoted[_disputeId][msg.sender] = true;
        
        Vote memory vote = Vote({
            voter: msg.sender,
            supportsCreator: _supportsCreator,
            reason: _reason,
            timestamp: uint40(block.timestamp),
            verified: false
        });
        
        disputeVotes[_disputeId].push(vote);
        
        if (_supportsCreator) {
            disputes[_disputeId].creatorVotes++;
        } else {
            disputes[_disputeId].respondentVotes++;
        }
        
        emit VoteCast(_disputeId, msg.sender, _supportsCreator, _reason);
    }

    function _validateResolution(uint256 _disputeId) internal view {
        DisputeInfo storage dispute = disputes[_disputeId];
        
        require(dispute.status == DisputeStatus.Voting, "Dispute not in voting phase");
        require(block.timestamp > dispute.votingEndTime, "Voting period not ended");
        require(dispute.winner == address(0), "Dispute already resolved");
    }

    function _processResolution(uint256 _disputeId) internal {
        DisputeInfo storage dispute = disputes[_disputeId];
        
        (address winner, bool isTie) = _determineWinner(dispute);
        dispute.winner = winner;
        dispute.status = DisputeStatus.Resolved;
        
        _createResolutionSummary(_disputeId, isTie);
        uint256 tokenId = _mintDisputeNFT(_disputeId, winner);
        dispute.winnerNftTokenId = tokenId;
        
        _handleEscrowDistribution(_disputeId, winner, isTie);
        
        emit DisputeResolved(
            _disputeId,
            winner,
            dispute.creatorVotes,
            dispute.respondentVotes,
            tokenId
        );
    }

    function _determineWinner(DisputeInfo storage dispute) internal view returns (address winner, bool isTie) {
        if (dispute.creatorVotes > dispute.respondentVotes) {
            return (dispute.disputeCreatorAddress, false);
        } else if (dispute.respondentVotes > dispute.creatorVotes) {
            return (dispute.respondentAddress, false);
        } else {
            return (address(this), true);
        }
    }

    function _createResolutionSummary(uint256 _disputeId, bool isTie) internal {
        DisputeInfo storage dispute = disputes[_disputeId];
        
        if (isTie) {
            dispute.resolutionSummary = string(abi.encodePacked(
                "Resolved by community vote - TIE. Creator votes: ",
                _toString(dispute.creatorVotes),
                ", Respondent votes: ",
                _toString(dispute.respondentVotes),
                ". NFT minted to contract."
            ));
        } else {
            dispute.resolutionSummary = string(abi.encodePacked(
                "Resolved by community vote. Creator votes: ",
                _toString(dispute.creatorVotes),
                ", Respondent votes: ",
                _toString(dispute.respondentVotes)
            ));
        }
    }

    function _handleEscrowDistribution(uint256 _disputeId, address winner, bool isTie) internal {
        DisputeInfo storage dispute = disputes[_disputeId];
        
        if (dispute.requiresEscrow && dispute.escrowAmount > 0) {
            if (isTie) {
                uint256 halfAmount = dispute.escrowAmount / 2;
                uint256 remainder = dispute.escrowAmount - (halfAmount * 2);
                
                (bool success1, ) = dispute.disputeCreatorAddress.call{value: halfAmount}("");
                require(success1, "Escrow transfer to creator failed");
                
                (bool success2, ) = dispute.respondentAddress.call{value: halfAmount + remainder}("");
                require(success2, "Escrow transfer to respondent failed");
            } else {
                (bool success, ) = winner.call{value: dispute.escrowAmount}("");
                require(success, "Escrow transfer failed");
            }
        }
    }

    function _mintDisputeNFT(uint256 _disputeId, address _winner) internal returns (uint256 tokenId) {
        _nftTokenIdCounter++;
        tokenId = _nftTokenIdCounter;
        
        _mint(_winner, tokenId);
        
        string memory uri = _generateTokenURI(_disputeId, tokenId);
        _setTokenURI(tokenId, uri);
        
        disputeToNftToken[_disputeId] = tokenId;
        nftTokenToDispute[tokenId] = _disputeId;
        
        emit DisputeNFTMinted(_disputeId, _winner, tokenId, uri);
        
        return tokenId;
    }

    function _generateTokenURI(uint256 _disputeId, uint256 /* _tokenId */) internal view returns (string memory) {
        return _buildTokenURI(_disputeId, _getResultType(_disputeId), _getDescription(_disputeId));
    }
    
    function _getResultType(uint256 _disputeId) internal view returns (string memory) {
        DisputeInfo storage dispute = disputes[_disputeId];
        bool isTie = dispute.creatorVotes == dispute.respondentVotes;
        
        if (isTie) {
            return "Tie";
        } else {
            return dispute.winner == dispute.disputeCreatorAddress ? "Creator Won" : "Respondent Won";
        }
    }
    
    function _getDescription(uint256 _disputeId) internal view returns (string memory) {
        DisputeInfo storage dispute = disputes[_disputeId];
        bool isTie = dispute.creatorVotes == dispute.respondentVotes;
        
        if (isTie) {
            return string(abi.encodePacked("Tie result in dispute resolution: ", dispute.title));
        } else {
            return string(abi.encodePacked("Winner of dispute resolution: ", dispute.title));
        }
    }
    
    function _buildTokenURI(uint256 _disputeId, string memory resultType, string memory description) internal pure returns (string memory) {
        string memory json = string(abi.encodePacked(
            '{"name": "Dispute Resolution #',
            _toString(_disputeId),
            '","description": "',
            description,
            '","attributes": [',
            '{"trait_type": "Dispute ID", "value": "',
            _toString(_disputeId),
            '"},',
            '{"trait_type": "Result", "value": "',
            resultType,
            '"}]}'
        ));
        
        return string(abi.encodePacked("data:application/json;base64,", _base64Encode(bytes(json))));
    }

    // ============ VIEW FUNCTIONS ============

    function getDisputeBasicInfo(uint256 _disputeId) external view onlyValidDispute(_disputeId) returns (
        address creator, address respondent, string memory title, string memory description,
        DisputeCategory category, Priority priority, DisputeStatus status
    ) {
        DisputeInfo storage dispute = disputes[_disputeId];
        return (
            dispute.disputeCreatorAddress, dispute.respondentAddress, dispute.title,
            dispute.description, dispute.category, dispute.priority, dispute.status
        );
    }
    
    function getDisputeTimestamps(uint256 _disputeId) external view onlyValidDispute(_disputeId) returns (
        uint40 creationTime, uint40 endTime, uint40 votingEndTime
    ) {
        DisputeInfo storage dispute = disputes[_disputeId];
        return (dispute.creationTime, dispute.endTime, dispute.votingEndTime);
    }
    
    function getDisputeResults(uint256 _disputeId) external view onlyValidDispute(_disputeId) returns (
        uint256 creatorVotes, uint256 respondentVotes, address winner
    ) {
        DisputeInfo storage dispute = disputes[_disputeId];
        return (dispute.creatorVotes, dispute.respondentVotes, dispute.winner);
    }

    function getDisputeVotes(uint256 _disputeId) external view onlyValidDispute(_disputeId) returns (Vote[] memory) {
        return disputeVotes[_disputeId];
    }

    function getDisputeEvidence(uint256 _disputeId) external view onlyValidDispute(_disputeId) returns (Evidence[] memory) {
        return disputeEvidences[_disputeId];
    }

    function getEvidenceSubmitters(uint256 _disputeId) external view onlyValidDispute(_disputeId) returns (address[] memory) {
        return evidenceSubmitters[_disputeId];
    }

    function getUserDisputes(address _user) external view returns (uint256[] memory) {
        return userDisputes[_user];
    }

    function getCurrentTokenId() external view returns (uint256) {
        return _nftTokenIdCounter;
    }

    function canCreateDispute(address _user) external view returns (bool canCreate, uint40 remainingCooldown) {
        if (isBlacklisted[_user]) {
            return (false, type(uint40).max);
        }
        
        if (lastDisputeTime[_user] == 0) {
            return (true, 0);
        }
        
        uint40 timeSinceLastDispute = uint40(block.timestamp) - lastDisputeTime[_user];
        if (timeSinceLastDispute >= DISPUTE_COOL_DOWN_PERIOD) {
            return (true, 0);
        } else {
            return (false, DISPUTE_COOL_DOWN_PERIOD - timeSinceLastDispute);
        }
    }

    // ============ ADMIN FUNCTIONS ============

    function setUserBlacklist(address _user, bool _blacklisted) external onlyRole(ADMIN_ROLE) {
        isBlacklisted[_user] = _blacklisted;
    }

    function transferTieNFT(uint256 _tokenId, address _to) external onlyRole(ADMIN_ROLE) {
        require(_to != address(0), "Invalid recipient address");
        require(ownerOf(_tokenId) == address(this), "NFT not owned by contract");
        
        uint256 disputeId = nftTokenToDispute[_tokenId];
        DisputeInfo storage dispute = disputes[disputeId];
        require(dispute.creatorVotes == dispute.respondentVotes, "Not a tie dispute NFT");
        
        _transfer(address(this), _to, _tokenId);
        emit TieNFTTransferred(_tokenId, disputeId, _to);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============ UTILITY FUNCTIONS ============

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _base64Encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        
        string memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);
        
        /// @solidity memory-safe-assembly
        assembly {
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 32)
            
            for {} lt(dataPtr, endPtr) {}
            {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr( 6, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(        input,  0x3F))))
                resultPtr := add(resultPtr, 1)
            }
            
            switch mod(mload(data), 3)
            case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
            case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
            
            mstore(result, encodedLen)
        }
        
        return result;
    }

    // ============ OVERRIDES ============

    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, AccessControlUpgradeable, ERC721URIStorageUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}