// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SAITypes as T} from "../assets/erc-8447/contracts/SAITypes.sol";
import "../assets/erc-8447/contracts/SAIErrors.sol";
import {SwarmRegistry} from "../assets/erc-8447/contracts/SwarmRegistry.sol";
import {ISwarmRegistry} from "../assets/erc-8447/contracts/interfaces/ISwarmRegistry.sol";

/// Shared fixtures: a registry, a default single-phase gated spec with a coordinator and a worker
/// role, every decision point held by `coord` (REPRESENT by the coordinator role), a judge as the
/// objective's acceptance authority.
abstract contract SAIBase is Test {
    SwarmRegistry reg;

    address initiator = makeAddr("initiator");
    address coord = makeAddr("coord");
    address judge = makeAddr("judge");
    address w1 = makeAddr("w1");
    address w2 = makeAddr("w2");
    address w3 = makeAddr("w3");
    address stranger = makeAddr("stranger");

    bytes32 constant ROLE_INITIATOR = keccak256("sai.role.initiator");
    bytes32 constant ROLE_COORD = keccak256("sai.role.coordinator");
    bytes32 constant ROLE_WORKER = keccak256("sai.role.worker");
    bytes32 constant ROLE_VERIFIER = keccak256("sai.role.verifier");
    bytes32 constant ROLE_BIDDER = keccak256("sai.role.bidder");

    bytes32 constant P_SHARED = keccak256("sai.payoff.shared");
    bytes32 constant P_EXCLUSIVE = keccak256("sai.payoff.exclusive");
    bytes32 constant T_PARTITIONED = keccak256("sai.topology.partitioned");
    bytes32 constant T_REDUNDANT = keccak256("sai.topology.redundant");
    bytes32 constant C_LEADER = keccak256("sai.coordination.leader");
    bytes32 constant C_COLLECTIVE = keccak256("sai.coordination.collective");
    bytes32 constant C_AUTOMATED = keccak256("sai.coordination.automated");

    bytes32 constant ORIGIN_INITIATOR = keccak256("sai.origin.initiator");
    bytes32 constant CHARTER1 = keccak256("charter v1");
    bytes32 constant CHARTER2 = keccak256("charter v2");
    bytes32 constant COMMIT1 = keccak256("commitment v1");
    bytes32 constant COMMIT2 = keccak256("commitment v2");
    bytes32 constant OBJECTIVE1 = keccak256("objective v1");

    uint64 constant DAY = 86400;

    function setUp() public virtual {
        reg = new SwarmRegistry(new bytes32[](0), new address[](0));
        vm.warp(1_800_000_000);
    }

    // ------------------------------------------------------------------ spec builders

    function allAddress(address a) internal pure returns (T.Authority[] memory auths) {
        auths = new T.Authority[](T.DECISION_POINTS);
        for (uint256 i = 0; i < T.DECISION_POINTS; i++) {
            auths[i] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: a, roleId: bytes32(0)});
        }
        auths[uint256(T.DecisionPoint.REPRESENT)] = T.Authority({kind: T.AuthorityKind.ROLE, target: address(0), roleId: ROLE_COORD});
    }

    function role(bytes32 id, uint32 min, uint32 max, address module, bool selfJoin) internal pure returns (T.RoleSpec memory) {
        return T.RoleSpec({roleId: id, min: min, max: max, eligibility: module, selfJoin: selfJoin});
    }

    function phase(bytes32 payoff, bytes32 topology, bytes32 coordination, T.Boundary boundary, T.Admission admission, uint64 inputWindow)
        internal pure returns (T.PhaseSpec memory)
    {
        return T.PhaseSpec({
            name: bytes32("phase"), payoff: payoff, topology: topology, coordination: coordination,
            boundary: boundary, admission: admission, inputWindow: inputWindow, descriptorHash: bytes32(0)
        });
    }

    function defaultSpec() internal view returns (T.SwarmSpec memory spec) {
        spec.roles = new T.RoleSpec[](2);
        spec.roles[0] = role(ROLE_COORD, 1, 1, address(0), false);
        spec.roles[1] = role(ROLE_WORKER, 1, 0, address(0), false);
        spec.phases = new T.PhaseSpec[](1);
        spec.phases[0] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.GATED, T.Admission.RECRUIT, 0);
        spec.authorities = allAddress(coord);
        spec.activation = T.Activation.ROSTER_MET;
        spec.contributions = T.Contributions.MEMBERS;
        spec.minMembers = 2;
        spec.maxMembers = 0;
        spec.recruitmentWindow = 7 * DAY;
        spec.maxDuration = 30 * DAY;
        spec.inactivityTimeout = 0;
        spec.ineligibleGrace = DAY;
        spec.settlementWindow = DAY;
        spec.amendmentExitWindow = 2 * DAY;
        spec.descriptorHash = bytes32(0);
    }

    function defaultObjective() internal view returns (T.ObjectiveInput memory o) {
        o.objectiveHash = OBJECTIVE1;
        o.kind = T.ObjectiveKind.TERMINAL;
        o.acceptanceAuthority = judge;
        o.obligation = T.ExternalRef({chainId: 0, target: address(0), id: 0});
        o.milestoneCount = 0;
    }

    function origin() internal pure returns (T.Origin memory) {
        return T.Origin({kind: ORIGIN_INITIATOR, ref: bytes32(0)});
    }

    // ------------------------------------------------------------------ flows

    function formWith(T.SwarmSpec memory spec, T.ObjectiveInput memory o) internal returns (bytes32 id) {
        vm.prank(initiator);
        id = reg.form(spec, CHARTER1, COMMIT1, "ipfs://charter-v1", bytes32(0), origin(), o);
    }

    function formDefault() internal returns (bytes32 id) {
        return formWith(defaultSpec(), defaultObjective());
    }

    /// Authority admits, member accepts: a complete two-sided admission under the current charter.
    function admitAndAccept(bytes32 id, address account, bytes32 roleId) internal {
        vm.prank(coord);
        reg.admit(id, account, roleId);
        (bytes32 h,,) = (reg.getSwarm(id).charterHash, 0, 0);
        vm.prank(account);
        reg.acceptCharter(id, h);
    }

    /// Default roster: coord as coordinator, w1 as worker; then activates.
    function formAndActivate() internal returns (bytes32 id) {
        id = formDefault();
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
    }

    function status(bytes32 id, address a) internal view returns (T.MemberStatus s) {
        (s,) = reg.memberStatus(id, a);
    }

    function exitReason(bytes32 id, address a) internal view returns (T.ExitReason r) {
        (, r) = reg.memberStatus(id, a);
    }

    function state(bytes32 id) internal view returns (T.LifecycleState) {
        return reg.getSwarm(id).state;
    }
}
