// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC6551Account } from "erc6551/interfaces/IERC6551Account.sol";
import { IERC6551Executable } from "erc6551/interfaces/IERC6551Executable.sol";

contract HatsWallet is IERC6551Account, IERC6551Executable { }
