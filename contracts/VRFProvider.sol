// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

interface ISNFT {
    function fulfillRandomness(bytes32 requestId, uint256 randomNumber) external;
}

contract VRFProvider is Ownable, VRFConsumerBase {

    ISNFT public snft;
    bytes32 internal keyHash;
    uint256 internal fee;

    uint256 nonce;
    mapping(bytes32 => address) public requestToAddress;

    modifier onlyGameContract() {
        require(msg.sender == address(snft), "not the game contract");
        _;
    }

    //placeholder vrf data until Chainlink VRF comes out on Avalanche
    constructor() VRFConsumerBase(address(0),address(0))
    {
        keyHash = 0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da;
        fee = 0.0001 * 10 ** 18; 
    }

    function setSNFT(address _snft) external onlyOwner {
        snft = ISNFT(_snft);
    }

    //onchain random until Chainlink VRF comes out on Avalanche
    function getRandom() external onlyGameContract returns (uint256 random) {
        nonce++;
        random = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce)));
    } 

    function requestRandom() external onlyGameContract returns (bytes32) {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );
        bytes32 requestId = requestRandomness(keyHash, fee);
        requestToAddress[requestId] = msg.sender;
        return requestId;
    } 

    function fulfillRandomness(bytes32 requestId, uint256 randomNumber) internal override {
        snft.fulfillRandomness(requestId, randomNumber);
    }

    function recoverLink(uint256 _amount) external onlyOwner {
        require(
            LINK.balanceOf(address(this)) >= _amount,
            "Not enough LINK - fill contract with faucet"
        );

        LINK.transfer(msg.sender, _amount);
    }
}