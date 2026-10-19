// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIBase, T} from "./SAIBase.t.sol";
import "../assets/erc-8447/contracts/SAIErrors.sol";
import {IEligibility} from "../assets/erc-8447/contracts/interfaces/IEligibility.sol";
import {AllowlistEligibility} from "../assets/erc-8447/contracts/modules/AllowlistEligibility.sol";
import {CompositeEligibility} from "../assets/erc-8447/contracts/modules/CompositeEligibility.sol";
import {ERC8004Eligibility} from "../assets/erc-8447/contracts/modules/ERC8004Eligibility.sol";
import {AssertionLevelEligibility} from "../assets/erc-8447/contracts/modules/AssertionLevelEligibility.sol";
import {IdentityStateEligibility} from "../assets/erc-8447/contracts/modules/IdentityStateEligibility.sol";
import {IERC8004Identity} from "../assets/erc-8447/contracts/modules/interfaces/IERC8004Identity.sol";
import {ITrustAssertionRegistry} from "../assets/erc-8447/contracts/modules/interfaces/ITrustAssertionRegistry.sol";
import {IAddressAnchoredIdentity} from "../assets/erc-8447/contracts/modules/interfaces/IAddressAnchoredIdentity.sol";

/// Minimal identity registry: owner and wallet per agent id.
contract IdentityMock is IERC8004Identity {
    mapping(uint256 => address) public owners;
    mapping(uint256 => address) public wallets;
    function set(uint256 id, address owner, address wallet) external { owners[id] = owner; wallets[id] = wallet; }
    function ownerOf(uint256 id) external view returns (address) { require(owners[id] != address(0), "none"); return owners[id]; }
    function getAgentWallet(uint256 id) external view returns (address) { return wallets[id]; }
}

/// Minimal trust-assertion registry: a level per (account, scheme).
contract AssertionsMock is ITrustAssertionRegistry {
    mapping(bytes32 => mapping(address => uint8)) public level;
    function set(bytes32 scheme, address a, uint8 l) external { level[scheme][a] = l; }
    function check(Subject calldata subject, bytes32 schemeId, uint8 minLevel, address[] calldata) external view returns (bool) {
        (uint256 chainId, address account) = abi.decode(subject.subjectData, (uint256, address));
        require(subject.subjectType == keccak256("account") && chainId == block.chainid, "subject");
        return level[schemeId][account] >= minLevel;
    }
}

contract IdentityStateMock is IAddressAnchoredIdentity {
    mapping(address => uint8) public states;
    function set(address a, uint8 s) external { states[a] = s; }
    function state(address a) external view returns (uint8) { return states[a]; }
}

contract SAIModulesTest is SAIBase {
    function specWithWorkerModule(address module) internal view returns (T.SwarmSpec memory spec) {
        spec = defaultSpec();
        spec.roles[1].eligibility = module;
    }

    function test_erc8004Eligibility() public {
        IdentityMock ids = new IdentityMock();
        ERC8004Eligibility mod = new ERC8004Eligibility(ids);
        ids.set(7, stranger, w1); // w1 is the agent wallet of agent 7
        vm.prank(w2);
        vm.expectRevert("ERC8004Eligibility: not the agent's owner or wallet");
        mod.declareAgent(7);
        vm.prank(w1);
        mod.declareAgent(7);
        assertTrue(mod.isEligible(bytes32(0), bytes32(0), w1));
        assertFalse(mod.isEligible(bytes32(0), bytes32(0), w2));
        // in a swarm
        bytes32 id = formWith(specWithWorkerModule(address(mod)), defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        // the wallet moves to another account: the live predicate fails and a challenge suspends
        ids.set(7, stranger, w3);
        (bool ev, bool ok) = reg.challenge(id, w1);
        assertTrue(ev); assertFalse(ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        // the agent comes back to w1: reinstatement passes again
        ids.set(7, w1, address(0));
        vm.prank(coord);
        reg.reinstate(id, w1);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
    }

    function test_assertionLevelEligibility() public {
        AssertionsMock kya = new AssertionsMock();
        bytes32 scheme = keccak256("scheme");
        address[] memory issuers = new address[](1); issuers[0] = judge;
        AssertionLevelEligibility mod = new AssertionLevelEligibility(kya, scheme, 2, issuers);
        assertEq(mod.issuers().length, 1);
        kya.set(scheme, w1, 1);
        assertFalse(mod.isEligible(bytes32(0), bytes32(0), w1));
        kya.set(scheme, w1, 3);
        assertTrue(mod.isEligible(bytes32(0), bytes32(0), w1));
        bytes32 id = formWith(specWithWorkerModule(address(mod)), defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        kya.set(scheme, w1, 0); // revoked
        (, bool ok) = reg.challenge(id, w1);
        assertFalse(ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
    }

    function test_identityStateEligibility() public {
        IdentityStateMock aid = new IdentityStateMock();
        IdentityStateEligibility mod = new IdentityStateEligibility(aid);
        aid.set(w1, 1); // ACTIVE
        assertTrue(mod.isEligible(bytes32(0), bytes32(0), w1));
        bytes32 id = formWith(specWithWorkerModule(address(mod)), defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        aid.set(w1, 2); // STALE
        (, bool ok) = reg.challenge(id, w1);
        assertFalse(ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        aid.set(w1, 3); // RETIRED: expulsion after the grace period
        vm.warp(block.timestamp + DAY + 1);
        reg.expel(id, w1);
        assertEq(uint8(exitReason(id, w1)), uint8(T.ExitReason.INELIGIBLE));
    }

    function test_compositeEligibility() public {
        AllowlistEligibility a = new AllowlistEligibility(address(this));
        AllowlistEligibility b = new AllowlistEligibility(address(this));
        IEligibility[] memory mods = new IEligibility[](2);
        mods[0] = a; mods[1] = b;
        CompositeEligibility all = new CompositeEligibility(mods, true);
        CompositeEligibility any = new CompositeEligibility(mods, false);
        assertEq(all.moduleCount(), 2);
        a.setAllowed(w1, true);
        assertFalse(all.isEligible(bytes32(0), bytes32(0), w1));
        assertTrue(any.isEligible(bytes32(0), bytes32(0), w1));
        b.setAllowed(w1, true);
        assertTrue(all.isEligible(bytes32(0), bytes32(0), w1));
        assertFalse(any.isEligible(bytes32(0), bytes32(0), w2));
        vm.expectRevert("Composite: no modules");
        new CompositeEligibility(new IEligibility[](0), true);
    }

    function test_allowlistOwnership() public {
        AllowlistEligibility a = new AllowlistEligibility(coord);
        vm.expectRevert("Allowlist: not owner");
        a.setAllowed(w1, true);
        vm.prank(coord);
        a.setOwner(w2);
        vm.prank(w2);
        a.setAllowed(w1, true);
        assertTrue(a.allowed(w1));
    }
}
