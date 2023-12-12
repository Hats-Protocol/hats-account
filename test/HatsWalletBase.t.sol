// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, StdUtils } from "forge-std/Test.sol";
import { BaseTest, WithForkTest } from "./Base.t.sol";
import { HatsWalletBase, HatsWallet1ofN } from "../src/HatsWallet1ofN.sol";
import "../src/lib/HatsWalletErrors.sol";
import { DeployImplementation, DeployWallet } from "../script/HatsWallet1ofN.s.sol";
import { IERC6551Registry } from "erc6551/interfaces/IERC6551Registry.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import { IERC6551Account } from "tokenbound/abstract/ERC6551Account.sol";
import {
  ERC721, ERC1155, TestERC721, TestERC1155, ECDSA, SignerMock, MaliciousStateChanger
} from "./utils/TestContracts.sol";

contract HatsWalletBaseTest is DeployImplementation, WithForkTest {
  // variables inhereted from DeployImplementation
  // bytes32 public constant SALT;
  // HatsWallet1ofN public implementation;

  HatsWallet1ofN public instance;
  DeployWallet public deployWallet;

  address public benefactor = makeAddr("benefactor");

  ERC721 public test721;
  ERC1155 public test1155;

  function setUp() public virtual override {
    super.setUp();

    // deploy implementation
    DeployImplementation.prepare(false, version);
    DeployImplementation.run();

    // deploy wallet instance
    deployWallet = new DeployWallet();
    deployWallet.prepare(false, address(implementation), hatWithWallet, SALT);
    // deploy wallet instance
    instance = HatsWallet1ofN(payable(deployWallet.run()));
  }
}

contract Constants is HatsWalletBaseTest {
  function test_hat() public {
    // console2.log("hat()", instance.hat());
    assertEq(instance.hat(), hatWithWallet);
  }

  function test_salt() public {
    // console2.log("salt()", instance.salt());
    assertEq(instance.salt(), SALT);
  }

  function test_hats() public {
    // console2.log("HATS()", instance.HATS());
    assertEq(address(instance.HATS()), address(HATS));
  }

  function test_implementation() public {
    // console2.log("IMPLEMENTATION()", instance.IMPLEMENTATION());
    assertEq(address(instance.IMPLEMENTATION()), address(implementation));
  }

  function test_version() public {
    assertEq(implementation.version_(), version, "wrong implementation version");
    assertEq(instance.version(), version, "wrong instance version");
  }
}

contract IsValidSigner is HatsWalletBaseTest {
  function test_true_wearer() public {
    assertEq(instance.isValidSigner(wearer1, EMPTY_BYTES), ERC6551_MAGIC_NUMBER);
  }

  function test_false_nonWearer() public {
    assertEq(instance.isValidSigner(nonWearer, EMPTY_BYTES), bytes4(0));
  }
}

contract Receive is HatsWalletBaseTest {
  function test_receive_eth() public {
    // bankroll benefactor
    vm.deal(benefactor, 100 ether);

    // send eth to wallet
    vm.prank(benefactor);
    (bool success,) = payable(address(instance)).call{ value: 1 ether }("");

    assertTrue(success);
    assertEq(address(instance).balance, 1 ether);
    assertEq(benefactor.balance, 99 ether);
  }

  function test_receive_ERC721() public {
    // deploy new TestERC721, with benefactor as recipient
    test721 = new TestERC721("Test721", "TST", benefactor);
    assertEq(test721.ownerOf(1), benefactor);

    // send ERC721 to wallet
    vm.prank(benefactor);
    test721.safeTransferFrom(benefactor, address(instance), 1);

    assertEq(test721.ownerOf(1), address(instance));
  }

  function test_receive_ERC1155_single() public {
    // deploy new TestERC1155, with benefactor as recipient
    test1155 = new TestERC1155(benefactor);

    // send a single ERC1155 to wallet
    vm.prank(benefactor);
    test1155.safeTransferFrom(benefactor, address(instance), 1, 1, "");

    assertEq(test1155.balanceOf(benefactor, 1), 99);
    assertEq(test1155.balanceOf(address(instance), 1), 1);
  }

  function test_receive_ERC1155_batch() public {
    // deploy new TestERC1155, with benefactor as recipient
    test1155 = new TestERC1155(benefactor);

    // prepare batch arrays
    uint256[] memory ids = new uint256[](2);
    ids[0] = 1;
    ids[1] = 2;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 10;
    amounts[1] = 20;

    // send batch ERC1155 to wallet
    vm.prank(benefactor);
    test1155.safeBatchTransferFrom(benefactor, address(instance), ids, amounts, "");

    assertEq(test1155.balanceOf(benefactor, 1), 90);
    assertEq(test1155.balanceOf(benefactor, 2), 180);
    assertEq(test1155.balanceOf(address(instance), 1), 10);
    assertEq(test1155.balanceOf(address(instance), 2), 20);
  }
}

contract ERC165 is HatsWalletBaseTest {
  function test_true_ERC721Receiver() public {
    assertTrue(instance.supportsInterface(type(IERC721Receiver).interfaceId));
  }

  function test_true_ERC1155Receiver() public {
    assertTrue(instance.supportsInterface(type(IERC1155Receiver).interfaceId));
  }

  function test_true_IERC6551Account() public {
    assertTrue(instance.supportsInterface(type(IERC6551Account).interfaceId));
    assertTrue(instance.supportsInterface(0x6faff5f1));
  }
}
