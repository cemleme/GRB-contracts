// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GRB is ERC20 {
  constructor() ERC20("GRB Token", "GRB") {
    _mint(msg.sender, 5000000 * 1 ether);
  }
}
