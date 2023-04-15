// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { DeployFactory } from "script/HatsWallet.s.sol";
import { HatsWallet } from "src/HatsWallet.sol";
import { HatsWalletFactory } from "src/HatsWalletFactory.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract HatsWalletFactoryTest is Test, DeployFactory {
  // variables inhereted from DeployFactory script
  // address public implementation;
  // address public factory;
  // address public hats;

  uint256 public topHat1 = 0x0000000100000000000000000000000000000000000000000000000000000000;
  uint256 public hat1 = 0x0000000100010000000000000000000000000000000000000000000000000000;
  bytes32 maxBytes32 = bytes32(type(uint256).max);
  bytes largeBytes = abi.encodePacked("this is a fairly large bytes object");

  event HatsWalletDeployed(uint256 hatId, address instance);

  error HatsWalletFactory_AlreadyDeployed(uint256 hatId);

  function setUp() virtual public {
    // deploy the clone factory and the implementation contract
    DeployFactory.run();
  }
}

contract Deploy is HatsWalletFactoryTest {
  function test_deploy() public {
    assertEq(address(factory.HATS()), address(hats), "hats");
    assertEq(address(factory.IMPLEMENTATION()), address(implementation), "implementation");
  }
}

/// @notice Harness contract to test HatsWalletFactory's internal functions
contract FactoryHarness is HatsWalletFactory {
  constructor(HatsWallet _implementation, IHats _hats, string memory _version)
    HatsWalletFactory(_implementation, _hats)
  { }

  function calculateSalt(uint256 _hatId) public view returns (bytes32) {
    return _calculateSalt(_hatId);
  }

  function getHatsWalletAddress(bytes32 _salt) public view returns (address) {
    return _getHatsWalletAddress(_salt);
  }

  function createWallet(uint256 _hatId) public returns (HatsWallet) {
    return _createHatsWallet(_hatId);
  }
}

contract InternalTest is HatsWalletFactoryTest {
  FactoryHarness harness;

  function setUp() public virtual override {
    super.setUp();
    // deploy harness
    harness = new FactoryHarness(implementation, hats, "this is a test harness");
  }
}

contract Internal_calculateSalt is InternalTest {
  function test_fuzz_calculateSalt(uint256 _hatId) public {
    assertEq(
      harness.calculateSalt(_hatId), keccak256(abi.encodePacked(harness, _hatId, block.chainid)), "calculateSalt"
    );
  }

  function test_calculateSalt_0() public {
    test_fuzz_calculateSalt(0);
  }

  function test_calculateSalt_large() public {
    test_fuzz_calculateSalt(type(uint256).max);
  }

  function test_calculateSalt_validHat() public {
    test_fuzz_calculateSalt(hat1);
  }
}

contract Internal_getHatsWalletAddress is InternalTest {
  function test_fuzz_getHatsWalletAddress(bytes32 _salt) public {
    assertEq(
      harness.getHatsWalletAddress(_salt),
      LibClone.predictDeterministicAddress(address(implementation), hex"00", _salt, address(harness))
    );
  }

  function test_getHatsWalletAddress_0() public {
    test_fuzz_getHatsWalletAddress(hex"00");
  }

  function test_getHatsWalletAddress_large() public {
    test_fuzz_getHatsWalletAddress(maxBytes32);
  }

  function test_getHatsWalletAddress_validHat() public {
    test_fuzz_getHatsWalletAddress(harness.calculateSalt(hat1));
  }
}

contract Internal_createHatsWallet is InternalTest {
  function test_fuzz_createHatsWallet(uint256 _hatId) public {
    HatsWallet wallet = harness.createWallet(_hatId);
    assertEq(address(wallet), harness.getHatsWalletAddress(harness.calculateSalt(_hatId)));
  }

  function test_createHatsWallet_0() public {
    test_fuzz_createHatsWallet(0);
  }
}

contract Deployed is InternalTest {
  // uses the FactoryHarness version for easy access to the internal _createHatsWallet function
  function test_fuzz_deployed_true(uint256 _hatId) public {
    harness.createWallet(_hatId);
    assertTrue(harness.deployed(_hatId));
  }

  function test_fuzz_deployed_false(uint256 _hatId) public {
    assertFalse(harness.deployed(_hatId));
  }
}

contract CreateHatsWallet is HatsWalletFactoryTest {
  function test_fuzz_createHatsWallet(uint256 _hatId) public {
    vm.assume(_hatId > 0); // hatId must be > 0

    vm.expectEmit(true, true, true, true);
    emit HatsWalletDeployed(_hatId, factory.getHatsWalletAddress(_hatId));
    HatsWallet wallet = factory.createHatsWallet(_hatId);
    assertEq(wallet.hat(), _hatId, "hat");
    assertEq(address(wallet.HATS()), address(hats), "HATS");
  }

  function test_createHatsWallet_validHat() public {
    test_fuzz_createHatsWallet(hat1);
  }

  function test_fuzz_createHatsWallet_alreadyDeployed_reverts(uint256 _hatId) public {
    factory.createHatsWallet(_hatId);
    vm.expectRevert(abi.encodeWithSelector(HatsWalletFactory_AlreadyDeployed.selector, _hatId));
    factory.createHatsWallet(_hatId);
  }
}

contract GetHatsWalletAddress is HatsWalletFactoryTest {
  function test_fuzz_getHatsWalletAddress(uint256 _hatId) public {
    address expected = LibClone.predictDeterministicAddress(
      address(implementation),
      hex"00",
      keccak256(abi.encodePacked(address(factory), _hatId, block.chainid)),
      address(factory)
    );
    assertEq(factory.getHatsWalletAddress(_hatId), expected);
  }

  function test_getHatsWalletAddress_validHat() public {
    test_fuzz_getHatsWalletAddress(hat1);
  }
}
