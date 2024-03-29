// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, StdUtils } from "forge-std/Test.sol";
import { ERC6551Account } from "tokenbound/abstract/ERC6551Account.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISandboxExecutor } from "tokenbound/interfaces/ISandboxExecutor.sol";

contract BaseTest is Test {
  IHats public HATS;
  string public version = "test";

  address public org = makeAddr("org");
  address public wearer1;
  uint256 public wearer1Key;
  address public nonWearer;
  uint256 public nonWearerKey;
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  uint256 public tophat;
  uint256 public hatWithAccount;
  IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // mainnet DAI
  bytes4 public constant ERC6551_MAGIC_NUMBER = ERC6551Account.isValidSigner.selector;
  bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
  bytes public constant EMPTY_BYTES = hex"00";

  address payable public target = payable(makeAddr("target"));

  function setUp() public virtual {
    // set up accounts
    (wearer1, wearer1Key) = makeAddrAndKey("wearer");
    (nonWearer, nonWearerKey) = makeAddrAndKey("nonWearer");
  }
}

contract WithForkTest is BaseTest {
  uint256 public fork;
  uint256 public BLOCK_NUMBER = 18_429_101; // mainnet deployment block for ERC6551Registry v0.3.1

  function calculateNewState(uint256 initialState, bytes memory msgData) public pure returns (uint256) {
    return uint256(keccak256(abi.encode(initialState, msgData)));
  }

  function _encodeSandboxCall(address to, uint256 value, bytes memory _data) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(ISandboxExecutor.extcall.selector, to, value, _data);
  }

  function setUp() public virtual override {
    super.setUp();
    HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // set up initial test hats
    tophat = HATS.mintTopHat(org, "tophat", "org.eth/tophat.png");
    vm.startPrank(org);
    hatWithAccount =
      HATS.createHat(tophat, "hatWithAccount", 15, eligibility, toggle, true, "org.eth/hatWithAccount.png");
    HATS.mintHat(hatWithAccount, wearer1);
    vm.stopPrank();
  }
}
