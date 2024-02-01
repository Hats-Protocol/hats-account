// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, StdUtils } from "forge-std/Test.sol";
import { WithForkTest } from "./Base.t.sol";
import { HatsAccountBase, HatsAccount1ofN } from "../src/HatsAccount1ofN.sol";
import "../src/lib/HatsAccountErrors.sol";
import { DeployImplementation, DeployWallet } from "../script/HatsAccount1ofN.s.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import { IERC6551Account } from "tokenbound/abstract/ERC6551Account.sol";
import { ERC721, ERC1155, MockERC721, MockERC1155 } from "./utils/TestContracts.sol";

contract HatsAccountBaseTest is DeployImplementation, WithForkTest {
  // variables inhereted from DeployImplementation
  // bytes32 public constant SALT;
  // HatsAccount1ofN public implementation;

  HatsAccount1ofN public instance;
  DeployWallet public deployWallet;

  address public benefactor = makeAddr("benefactor");

  ERC721 public mock721;
  ERC1155 public mock1155;

  function setUp() public virtual override {
    super.setUp();

    // deploy implementation
    DeployImplementation.prepare(false, version);
    DeployImplementation.run();

    // deploy wallet instance
    deployWallet = new DeployWallet();
    deployWallet.prepare(false, address(implementation), hatWithWallet, SALT);
    // deploy wallet instance
    instance = HatsAccount1ofN(payable(deployWallet.run()));
  }
}

contract Constants is HatsAccountBaseTest {
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

contract IsValidSigner is HatsAccountBaseTest {
  function test_true_wearer() public {
    assertEq(instance.isValidSigner(wearer1, EMPTY_BYTES), ERC6551_MAGIC_NUMBER);
  }

  function test_false_nonWearer() public {
    assertEq(instance.isValidSigner(nonWearer, EMPTY_BYTES), bytes4(0));
  }
}

contract Receive is HatsAccountBaseTest {
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
    // deploy new MockERC721, with benefactor as recipient
    mock721 = new MockERC721("mock721", "TST", benefactor);
    assertEq(mock721.ownerOf(1), benefactor);

    // send ERC721 to wallet
    vm.prank(benefactor);
    mock721.safeTransferFrom(benefactor, address(instance), 1);

    assertEq(mock721.ownerOf(1), address(instance));
  }

  function test_receive_ERC1155_single() public {
    // deploy new MockERC1155, with benefactor as recipient
    mock1155 = new MockERC1155(benefactor);

    // send a single ERC1155 to wallet
    vm.prank(benefactor);
    mock1155.safeTransferFrom(benefactor, address(instance), 1, 1, "");

    assertEq(mock1155.balanceOf(benefactor, 1), 99);
    assertEq(mock1155.balanceOf(address(instance), 1), 1);
  }

  function test_receive_ERC1155_batch() public {
    // deploy new MockERC1155, with benefactor as recipient
    mock1155 = new MockERC1155(benefactor);

    // prepare batch arrays
    uint256[] memory ids = new uint256[](2);
    ids[0] = 1;
    ids[1] = 2;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 10;
    amounts[1] = 20;

    // send batch ERC1155 to wallet
    vm.prank(benefactor);
    mock1155.safeBatchTransferFrom(benefactor, address(instance), ids, amounts, "");

    assertEq(mock1155.balanceOf(benefactor, 1), 90);
    assertEq(mock1155.balanceOf(benefactor, 2), 180);
    assertEq(mock1155.balanceOf(address(instance), 1), 10);
    assertEq(mock1155.balanceOf(address(instance), 2), 20);
  }
}

contract ERC165 is HatsAccountBaseTest {
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

/*
  See HatsAccount1ofN.t.sol for coverage of the following HatsAccountBase internal functions:
    - _beforeExecute
    - _updateState

  See HatsAccount1ofN.t.sol for coverage of the following HatsAccountBase functions:
    - getMessageHash
 */
