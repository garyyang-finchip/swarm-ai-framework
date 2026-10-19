// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIBase, T} from "./SAIBase.t.sol";
import "../assets/erc-8447/contracts/SAIErrors.sol";
import {ISwarmRegistry} from "../assets/erc-8447/contracts/interfaces/ISwarmRegistry.sol";

contract SAISpecTest is SAIBase {
    function expectFormRevert(T.SwarmSpec memory spec, bytes4 err) internal {
        vm.expectRevert(err);
        vm.prank(initiator);
        reg.form(spec, CHARTER1, COMMIT1, "uri", bytes32(0), origin(), defaultObjective());
    }

    function test_formRecordsSpecHashAndCharter() public {
        T.SwarmSpec memory spec = defaultSpec();
        bytes32 id = formWith(spec, defaultObjective());
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(s.specHash, reg.specHashOf(spec));
        assertEq(s.charterHash, CHARTER1);
        assertEq(s.charterVersion, 1);
        assertEq(s.commitmentVersion, 1);
        assertEq(s.initiator, initiator);
        assertEq(uint8(s.state), uint8(T.LifecycleState.FORMING));
        assertEq(s.origin.kind, ORIGIN_INITIATOR);
        assertEq(s.revision, 1);
        assertEq(reg.objectiveOf(id).version, 1);
        assertEq(reg.specOf(id).roles.length, 2);
        assertEq(reg.phaseSpecOf(id, 0).payoff, P_SHARED);
        assertEq(reg.roleSpecOf(id, ROLE_WORKER).min, 1);
        assertEq(reg.authorityOf(id, T.DecisionPoint.ADMIT).target, coord);
    }

    function test_rolesOutOfRange() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles = new T.RoleSpec[](0);
        expectFormRevert(spec, SAI_RolesOutOfRange.selector);
    }

    function test_zeroAndDuplicateRole() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles[1].roleId = bytes32(0);
        expectFormRevert(spec, SAI_ZeroRole.selector);
        spec = defaultSpec();
        spec.roles[1].roleId = ROLE_COORD;
        expectFormRevert(spec, SAI_DuplicateRole.selector);
    }

    function test_roleBoundsAndModule() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles[0].min = 3; spec.roles[0].max = 2;
        expectFormRevert(spec, SAI_RoleBounds.selector);
        spec = defaultSpec();
        spec.roles[0].eligibility = stranger; // no code
        expectFormRevert(spec, SAI_ModuleNotContract.selector);
    }

    function test_phase0MustRecruitAndTerms() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.phases[0].admission = T.Admission.INHERIT;
        expectFormRevert(spec, SAI_Phase0MustRecruit.selector);
        spec = defaultSpec();
        spec.phases[0].payoff = keccak256("sai.payoff.unknown");
        expectFormRevert(spec, SAI_UnknownTerm.selector);
        spec = defaultSpec();
        spec.phases[0].topology = P_SHARED; // a payoff term is not a topology term
        expectFormRevert(spec, SAI_UnknownTerm.selector);
    }

    function test_registeredTermIsAccepted() public {
        bytes32 term = keccak256("sai.topology.tournament-tree");
        reg.registerTerm(T.DIM_TOPOLOGY, term, "ipfs://tournament-tree");
        assertTrue(reg.isTerm(T.DIM_TOPOLOGY, term));
        assertEq(reg.termURI(T.DIM_TOPOLOGY, term), "ipfs://tournament-tree");
        T.SwarmSpec memory spec = defaultSpec();
        spec.phases[0].topology = term;
        formWith(spec, defaultObjective());
        vm.expectRevert(SAI_TermExists.selector);
        reg.registerTerm(T.DIM_TOPOLOGY, term, "again");
        vm.expectRevert(SAI_UnknownDimension.selector);
        reg.registerTerm(keccak256("sai.dimension.other"), term, "x");
        vm.expectRevert(SAI_ZeroTerm.selector);
        reg.registerTerm(T.DIM_PAYOFF, bytes32(0), "x");
    }

    function test_authoritiesLengthAndShape() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.authorities = new T.Authority[](15);
        expectFormRevert(spec, SAI_AuthoritiesLength.selector);
        spec = defaultSpec();
        spec.authorities[0] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: address(0), roleId: bytes32(0)});
        expectFormRevert(spec, SAI_AuthorityShape.selector);
        spec = defaultSpec();
        spec.authorities[0] = T.Authority({kind: T.AuthorityKind.NONE, target: coord, roleId: bytes32(0)});
        expectFormRevert(spec, SAI_AuthorityShape.selector);
        spec = defaultSpec();
        spec.authorities[0] = T.Authority({kind: T.AuthorityKind.ROLE, target: address(0), roleId: keccak256("nope")});
        expectFormRevert(spec, SAI_UnknownRoleAuthority.selector);
        spec = defaultSpec();
        spec.roles = new T.RoleSpec[](3);
        spec.roles[0] = role(ROLE_COORD, 1, 1, address(0), false);
        spec.roles[1] = role(ROLE_WORKER, 1, 0, address(0), false);
        spec.roles[2] = role(ROLE_INITIATOR, 0, 0, address(0), false);
        spec.authorities[0] = T.Authority({kind: T.AuthorityKind.ROLE, target: address(0), roleId: ROLE_INITIATOR});
        expectFormRevert(spec, SAI_InitiatorRoleAuthority.selector);
        spec.authorities = allAddress(coord);
        spec.roles[2].min = 1;
        expectFormRevert(spec, SAI_InitiatorRoleMin.selector);
    }

    function test_memberBounds() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.minMembers = 0;
        expectFormRevert(spec, SAI_MinMembers.selector);
        spec = defaultSpec();
        spec.maxMembers = 1; // < minMembers 2
        expectFormRevert(spec, SAI_MaxMembers.selector);
    }

    function test_activationAuthorityRequired() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.activation = T.Activation.AUTHORITY;
        spec.authorities[uint256(T.DecisionPoint.ACTIVATE)] = T.Authority({kind: T.AuthorityKind.NONE, target: address(0), roleId: bytes32(0)});
        expectFormRevert(spec, SAI_ActivationAuthority.selector);
    }

    function test_fallbacksRequired() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.recruitmentWindow = 0;
        expectFormRevert(spec, SAI_RecruitmentWindow.selector);
        spec = defaultSpec();
        spec.maxDuration = 0; spec.inactivityTimeout = 0;
        expectFormRevert(spec, SAI_NoLivenessFallback.selector);
        spec = defaultSpec();
        spec.maxDuration = 0; spec.inactivityTimeout = DAY; // inactivity alone suffices
        formWith(spec, defaultObjective());
    }

    function test_conclusionPathRequired() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.authorities[uint256(T.DecisionPoint.CONCLUDE)] = T.Authority({kind: T.AuthorityKind.NONE, target: address(0), roleId: bytes32(0)});
        T.ObjectiveInput memory o = defaultObjective();
        o.acceptanceAuthority = address(0);
        vm.expectRevert(SAI_NoConclusionPath.selector);
        vm.prank(initiator);
        reg.form(spec, CHARTER1, COMMIT1, "uri", bytes32(0), origin(), o);
        // with an acceptance authority the spec is fine
        formWith(spec, defaultObjective());
    }

    function test_advanceAuthorityAndRecruitAdmitter() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.phases = new T.PhaseSpec[](2);
        spec.phases[0] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.GATED, T.Admission.RECRUIT, 0);
        spec.phases[1] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.GATED, T.Admission.RECRUIT, 0);
        spec.authorities[uint256(T.DecisionPoint.ADVANCE)] = T.Authority({kind: T.AuthorityKind.NONE, target: address(0), roleId: bytes32(0)});
        expectFormRevert(spec, SAI_AdvanceAuthority.selector);
        spec.authorities = allAddress(coord);
        spec.authorities[uint256(T.DecisionPoint.ADMIT)] = T.Authority({kind: T.AuthorityKind.ROLE, target: address(0), roleId: ROLE_COORD});
        expectFormRevert(spec, SAI_RecruitAdmitter.selector);
        spec.authorities[uint256(T.DecisionPoint.ADMIT)] = T.Authority({kind: T.AuthorityKind.INITIATOR, target: address(0), roleId: bytes32(0)});
        formWith(spec, defaultObjective());
    }

    function test_durationTooLong() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.maxDuration = type(uint64).max;
        expectFormRevert(spec, SAI_DurationTooLong.selector);
    }

    function test_objectiveValidation() public {
        T.ObjectiveInput memory o = defaultObjective();
        o.objectiveHash = bytes32(0);
        vm.expectRevert(SAI_ZeroObjective.selector);
        vm.prank(initiator);
        reg.form(defaultSpec(), CHARTER1, COMMIT1, "uri", bytes32(0), origin(), o);
        o = defaultObjective();
        o.kind = T.ObjectiveKind.MILESTONED; // count 0
        vm.expectRevert(SAI_MilestoneCount.selector);
        vm.prank(initiator);
        reg.form(defaultSpec(), CHARTER1, COMMIT1, "uri", bytes32(0), origin(), o);
        o = defaultObjective();
        o.milestoneCount = 2; // TERMINAL with milestones
        vm.expectRevert(SAI_MilestoneCount.selector);
        vm.prank(initiator);
        reg.form(defaultSpec(), CHARTER1, COMMIT1, "uri", bytes32(0), origin(), o);
    }

    function test_parentMustBeFormingOrActive() public {
        bytes32 parent = formDefault();
        vm.prank(initiator);
        bytes32 child = reg.form(defaultSpec(), CHARTER1, COMMIT1, "uri", parent, origin(), defaultObjective());
        assertEq(reg.getSwarm(child).parentId, parent);
        vm.expectRevert(SAI_ParentUnavailable.selector);
        vm.prank(initiator);
        reg.form(defaultSpec(), CHARTER1, COMMIT1, "uri", keccak256("nope"), origin(), defaultObjective());
    }

    function test_initiatorRoleChecked() public {
        // an allowlist as initiator module: the initiator must be listed
        AllowlistStub stub = new AllowlistStub();
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles = new T.RoleSpec[](3);
        spec.roles[0] = role(ROLE_COORD, 1, 1, address(0), false);
        spec.roles[1] = role(ROLE_WORKER, 1, 0, address(0), false);
        spec.roles[2] = role(ROLE_INITIATOR, 0, 0, address(stub), false);
        expectFormRevert(spec, SAI_Ineligible.selector);
        stub.set(initiator, true);
        bytes32 id = formWith(spec, defaultObjective());
        // the initiator role is never seated
        vm.prank(coord);
        vm.expectRevert(SAI_InitiatorRoleSeated.selector);
        reg.admit(id, w1, ROLE_INITIATOR);
    }

    function test_supportsInterface() public view {
        assertTrue(reg.supportsInterface(type(ISwarmRegistry).interfaceId));
        assertTrue(reg.supportsInterface(0x01ffc9a7));
        assertFalse(reg.supportsInterface(0xffffffff));
        assertEq(reg.CLOCK_MODE(), "mode=timestamp");
        assertEq(reg.clock(), uint48(block.timestamp));
    }
}

contract AllowlistStub {
    mapping(address => bool) public ok;
    function set(address a, bool v) external { ok[a] = v; }
    function isEligible(bytes32, bytes32, address a) external view returns (bool) { return ok[a]; }
}
