// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

interface IStaker {
    function deposit(uint _amount, uint _stakingLevel) external returns (bool);
    function withdraw(uint256 _amount) external returns (bool);
    function getUserStakingLevel(address _user) external view returns (uint);
}

contract GRBStaker is IStaker, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public stakingToken;

    struct stakingInfo {
        uint amount;
        uint releaseDate;
        uint stakingLevel;
        uint requiredAmount;
    }

    struct stakingType {
        uint duration;
        uint requiredAmount;
    }

    mapping(address => stakingInfo) public userStakeInfo; 
    mapping(uint => stakingType) public stakingLevels;
    uint public maxStakingLevel;
    uint public stakingDuration = 7776000; //90 days

    event SetLevel(uint levelNo, uint requiredAmount);
    event Deposit(address indexed user, uint256 amount, uint256 stakingLevel, uint256 releaseDate);
    event Withdraw(address indexed user, uint256 amount, uint256 stakingLevel);

    constructor(address _grb) {
        stakingToken = IERC20(_grb);
        stakingLevels[1].requiredAmount = 10 ether;
        stakingLevels[2].requiredAmount = 100 ether;
        stakingLevels[3].requiredAmount = 1000 ether;
        maxStakingLevel = 3;
    }

    function setStakingDuration(uint _duration) external onlyOwner {
        stakingDuration = _duration;
    }

    function setStakingLevel(uint _levelNo, uint _requiredAmount) external onlyOwner {
        require(_levelNo > 0, "level 0 should be empty");

        stakingLevels[_levelNo].requiredAmount = _requiredAmount;
        if(_levelNo>maxStakingLevel)
        {
            maxStakingLevel = _levelNo;
        }
        emit SetLevel(_levelNo, _requiredAmount);
    }

    function getStakingLevel(uint _levelNo) external view returns (uint requiredAmount) {
        require(_levelNo <= maxStakingLevel, "Given staking level does not exist.");
        require(_levelNo > 0, "level 0 is not available");
        return stakingLevels[_levelNo].requiredAmount;
    }

    function deposit(uint _amount, uint _stakingLevel) override external returns (bool){
        require(_stakingLevel > 0, "level 0 is not available");
        require(_amount > 0, "amount is 0");
        require(maxStakingLevel >= _stakingLevel, "Given staking level does not exist.");
        require(userStakeInfo[msg.sender].stakingLevel < _stakingLevel, "User already has a higher or same stake");
        require(userStakeInfo[msg.sender].amount + _amount == stakingLevels[_stakingLevel].requiredAmount, "You need to stake required amount.");
        
        userStakeInfo[msg.sender].amount = userStakeInfo[msg.sender].amount + _amount;

        userStakeInfo[msg.sender].stakingLevel = _stakingLevel;
        userStakeInfo[msg.sender].requiredAmount = stakingLevels[_stakingLevel].requiredAmount;
        userStakeInfo[msg.sender].releaseDate = block.timestamp + stakingDuration;

        emit Deposit(msg.sender, _amount, _stakingLevel, userStakeInfo[msg.sender].releaseDate);

        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        return true;
    }

    function withdraw(uint256 _amount) override external nonReentrant returns (bool) {
        require(userStakeInfo[msg.sender].amount >= _amount, "You do not have the entered amount.");
        require(userStakeInfo[msg.sender].releaseDate <= block.timestamp ||
                userStakeInfo[msg.sender].amount - _amount >= stakingLevels[userStakeInfo[msg.sender].stakingLevel].requiredAmount, 
                "You can't withdraw until your staking period is complete.");
        userStakeInfo[msg.sender].amount = userStakeInfo[msg.sender].amount - _amount;
        if(userStakeInfo[msg.sender].amount < stakingLevels[userStakeInfo[msg.sender].stakingLevel].requiredAmount)
        {
            userStakeInfo[msg.sender].stakingLevel = 0;
        }
        stakingToken.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount, userStakeInfo[msg.sender].stakingLevel);

        return true;
    }

    function getUserStakingLevel(address _user) override external view returns (uint) {
        return userStakeInfo[_user].stakingLevel;
    }

    function getUserBalance(address _user) external view returns (uint) {
        return userStakeInfo[_user].amount;
    }
}