// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BinaryOptions is ReentrancyGuard(), Ownable(msg.sender) {
    struct Option {
        uint256 strikePrice;
        uint256 expirationTime;
        uint256 totalYes;
        uint256 totalNo;
        mapping(address => uint256) yesBets;
        mapping(address => uint256) noBets;
        bool resolved;
        bool outcome; // true for Yes, false for No
    }

    Option[] public options;

    uint256 public housePercentage; // Percentage of the reward that goes to the house
    address payable public housePayoutAddress; // Address to which the house's share is sent

    event OptionCreated(uint256 indexed optionId, uint256 strikePrice, uint256 expirationTime);
    event BetPlaced(uint256 indexed optionId, address indexed bettor, bool betOnYes, uint256 amount);
    event OptionResolved(uint256 indexed optionId, bool outcome);
    event RewardClaimed(uint256 indexed optionId, address indexed claimant, uint256 reward);

    constructor(uint256 _housePercentage, address payable _housePayoutAddress) {
        require(_housePercentage <= 100, "House percentage cannot be more than 100");
        housePercentage = _housePercentage;
        housePayoutAddress = _housePayoutAddress;
        transferOwnership(msg.sender);
    }

    function createOption(uint256 _strikePrice, uint256 _expirationTime) external onlyOwner returns (uint256) {
        require(_expirationTime > block.timestamp, "Invalid expiration time");
        Option storage newOption = options.push();
        newOption.strikePrice = _strikePrice;
        newOption.expirationTime = _expirationTime;
        emit OptionCreated(options.length - 1, _strikePrice, _expirationTime);
        
        // Return the index of the new option
        return options.length - 1;
    }

    function placeBet(uint256 _optionId, bool _betOnYes) external payable nonReentrant {
        require(_optionId < options.length, "Option does not exist");
        Option storage option = options[_optionId];
        require(block.timestamp < option.expirationTime, "Betting closed");
        require(msg.value > 0, "Must place a bet");

        if (_betOnYes) {
            option.yesBets[msg.sender] += msg.value;
            option.totalYes += msg.value;
        } else {
            option.noBets[msg.sender] += msg.value;
            option.totalNo += msg.value;
        }

        emit BetPlaced(_optionId, msg.sender, _betOnYes, msg.value);
    }

    function resolveOption(uint256 _optionId, bool _outcome) external onlyOwner {
        require(_optionId < options.length, "Option does not exist");
        Option storage option = options[_optionId];
        require(block.timestamp >= option.expirationTime, "Option not expired");
        require(!option.resolved, "Already resolved");

        option.resolved = true;
        option.outcome = _outcome;

        emit OptionResolved(_optionId, _outcome);
    }

    function claimReward() external nonReentrant {
        uint256 totalReward = 0;

        for (uint256 i = 0; i < options.length; i++) {
            Option storage option = options[i];
            if (option.resolved) {
                uint256 reward = 0;
                if (option.outcome && option.yesBets[msg.sender] > 0) {
                    require(option.totalYes > 0, "No totalYes bets");
                    reward = (option.yesBets[msg.sender] * address(this).balance) / option.totalYes;
                    option.yesBets[msg.sender] = 0;
                } else if (!option.outcome && option.noBets[msg.sender] > 0) {
                    require(option.totalNo > 0, "No totalNo bets");
                    reward = (option.noBets[msg.sender] * address(this).balance) / option.totalNo;
                    option.noBets[msg.sender] = 0;
                }

                if (reward > 0) {
                    totalReward += reward;
                    emit RewardClaimed(i, msg.sender, reward);
                }
            }
        }

        require(totalReward > 0, "No reward to claim");

        // Calculate house's share and user's share
        uint256 houseShare = (totalReward * housePercentage) / 100;
        uint256 userShare = totalReward - houseShare;

        // Transfer the respective amounts
        (bool houseSuccess, ) = housePayoutAddress.call{value: houseShare}("");
        require(houseSuccess, "House transfer failed");

        (bool userSuccess, ) = payable(msg.sender).call{value: userShare}("");
        require(userSuccess, "User transfer failed");
    }

    function checkRewards() external view returns (uint256 userShare, uint256 houseShare) {
        uint256 totalReward = 0;

        for (uint256 i = 0; i < options.length; i++) {
            Option storage option = options[i];
            if (option.resolved) {
                uint256 reward = 0;
                if (option.outcome && option.yesBets[msg.sender] > 0) {
                    require(option.totalYes > 0, "No totalYes bets");
                    reward = (option.yesBets[msg.sender] * address(this).balance) / option.totalYes;
                } else if (!option.outcome && option.noBets[msg.sender] > 0) {
                    require(option.totalNo > 0, "No totalNo bets");
                    reward = (option.noBets[msg.sender] * address(this).balance) / option.totalNo;
                }

                if (reward > 0) {
                    totalReward += reward;
                }
            }
        }

        // Calculate house's share and user's share
        houseShare = (totalReward * housePercentage) / 100;
        userShare = totalReward - houseShare;

        return (userShare, houseShare);
    }


    function findOptions(uint256 optionId) external view returns (uint256 strikePrice, uint256 expirationTime, uint256 totalYes, uint256 totalNo, bool resolved, bool outcome, uint256 id) {
        require(optionId < options.length, "Option does not exist");
        Option storage option = options[optionId];
        return (option.strikePrice, option.expirationTime, option.totalYes, option.totalNo, option.resolved, option.outcome, optionId);
    }
}