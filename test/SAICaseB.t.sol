// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIScenarioBase, T, A, SwarmDecisionAdapter} from "./SAIScenarioBase.t.sol";
import "../assets/erc-sai/contracts/SAIErrors.sol";
import {ISwarmRegistry} from "../assets/erc-sai/contracts/interfaces/ISwarmRegistry.sol";

/// Case B — a two-phase tender: open bidding, selected execution, a challenge and a substitution.
/// Phase 0 is OPEN: bidders join by themselves and record proposals within a two-day input window;
/// an evaluation chamber of two (2-of-2 through the real ERC-8436 registries) holds ADVANCE and
/// carries two bidders into a CLOSED execution phase as workers. A worker loses its eligibility,
/// anyone challenges it, the coordinator substitutes the third bidder into the closed phase, the
/// verifier accepts both milestones and concludes the swarm ACHIEVED.
contract SAICaseBTest is SAIScenarioBase {
    SwarmDecisionAdapter chamber;
    bytes32 id;
    address b1 = makeAddr("b1");
    address b2 = makeAddr("b2");
    address b3 = makeAddr("b3");

    function setUp() public override {
        super.setUp();
        chamber = newDecisionAdapter(ROLE_VERIFIER, 2, 2, DAY);
        list.setAllowed(b1, true);
        list.setAllowed(b2, true);
        list.setAllowed(b3, true);

        T.SwarmSpec memory spec = defaultSpec();
        spec.roles = new T.RoleSpec[](4);
        spec.roles[0] = role(ROLE_COORD, 1, 1, address(0), true);
        spec.roles[1] = role(ROLE_VERIFIER, 2, 2, address(0), true);
        spec.roles[2] = role(ROLE_BIDDER, 0, 0, address(0), true);
        spec.roles[3] = role(ROLE_WORKER, 0, 2, address(list), false);
        spec.phases = new T.PhaseSpec[](2);
        spec.phases[0] = phase(P_EXCLUSIVE, T_REDUNDANT, C_COLLECTIVE, T.Boundary.OPEN, T.Admission.RECRUIT, 2 * DAY);
        spec.phases[1] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.CLOSED, T.Admission.SELECT, 0);
        spec.authorities[uint256(T.DecisionPoint.ADVANCE)] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: address(chamber), roleId: bytes32(0)});
        spec.minMembers = 3;
        spec.maxDuration = 90 * DAY;

        T.ObjectiveInput memory o = defaultObjective();
        o.kind = T.ObjectiveKind.MILESTONED;
        o.milestoneCount = 2;
        o.acceptanceAuthority = judge; // a verifier contract in production; an account here

        vm.prank(coord);
        id = reg.form(spec, CHARTER1, COMMIT1, "ipfs://charter-b", bytes32(0), origin(), o);
    }

    function test_caseB_endToEnd() public {
        // --- bidding phase
        vm.prank(coord); reg.join(id, ROLE_COORD, CHARTER1);
        vm.prank(c1); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c2); reg.join(id, ROLE_VERIFIER, CHARTER1);
        reg.activate(id);
        vm.prank(b1); reg.join(id, ROLE_BIDDER, CHARTER1);
        vm.prank(b2); reg.join(id, ROLE_BIDDER, CHARTER1);
        vm.prank(b3); reg.join(id, ROLE_BIDDER, CHARTER1);
        vm.prank(b1); reg.recordContribution(id, keccak256("sketch A"), "ipfs://a");
        vm.prank(b2); reg.recordContribution(id, keccak256("sketch B"), "ipfs://b");
        vm.prank(b3); reg.recordContribution(id, keccak256("sketch C"), "ipfs://c");
        vm.warp(block.timestamp + 2 * DAY + 1);
        assertFalse(reg.inputOpen(id)); // bids closed; the phase waits for the chamber

        // --- the evaluation chamber selects: coordinator and chamber carry over, b1 and b2 become workers
        address[] memory carried = new address[](5);
        carried[0] = coord; carried[1] = c1; carried[2] = c2; carried[3] = b1; carried[4] = b2;
        bytes32[] memory roles = new bytes32[](5);
        roles[0] = ROLE_COORD; roles[1] = ROLE_VERIFIER; roles[2] = ROLE_VERIFIER; roles[3] = ROLE_WORKER; roles[4] = ROLE_WORKER;
        bytes memory call = abi.encodeCall(ISwarmRegistry.advance, (id, carried, roles));
        bytes32 issue = chamber.open(id, T.DecisionPoint.ADVANCE, call, roster2(c1, c2));
        // the proposal's deadline is bounded by the swarm's hard deadline only: the input window has passed
        vote(issue, roster2(c1, c2), true);
        chamber.execute(issue);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(s.phase, 1);
        assertEq(uint8(status(id, b3)), uint8(T.MemberStatus.EXITED));
        assertEq(uint8(exitReason(id, b3)), uint8(T.ExitReason.NOT_CARRIED));
        assertEq(reg.getMember(id, b1).roleId, ROLE_WORKER);
        (uint32 ra,) = reg.roleCount(id, ROLE_WORKER);
        assertEq(ra, 2);
        // the execution phase is CLOSED: nobody can join or apply
        vm.prank(b3);
        vm.expectRevert(SAI_BoundaryClosed.selector);
        reg.applyToJoin(id, ROLE_WORKER, CHARTER1);

        // --- a worker's eligibility lapses; anyone challenges; the coordinator substitutes the third bidder
        list.setAllowed(b2, false);
        vm.prank(stranger);
        (bool ev, bool ok) = reg.challenge(id, b2);
        assertTrue(ev); assertFalse(ok);
        assertEq(uint8(status(id, b2)), uint8(T.MemberStatus.SUSPENDED));
        vm.prank(b2);
        reg.recordContribution(id, keccak256("late work"), ""); // recorded, flagged whileSuspended
        vm.prank(coord);
        reg.substitute(id, b2, b3);
        vm.prank(b3);
        reg.acceptCharter(id, CHARTER1); // completes in the CLOSED phase: the seat already existed
        assertEq(uint8(status(id, b3)), uint8(T.MemberStatus.ACTIVE));
        assertEq(uint8(exitReason(id, b2)), uint8(T.ExitReason.REPLACED));
        (ra,) = reg.roleCount(id, ROLE_WORKER);
        assertEq(ra, 2);

        // --- milestones and conclusion by the verifier
        vm.prank(b1); reg.recordContribution(id, keccak256("lemma A proof"), "ipfs://pa");
        vm.prank(b3); reg.recordContribution(id, keccak256("lemma B proof"), "ipfs://pb");
        vm.startPrank(judge);
        reg.recordMilestone(id, 0, T.MilestoneStatus.ACCEPTED, keccak256("lemma A proof"));
        vm.expectRevert(SAI_MilestonesIncomplete.selector);
        reg.conclude(id, T.OutcomeType.ACHIEVED, bytes32(0));
        reg.recordMilestone(id, 1, T.MilestoneStatus.ACCEPTED, keccak256("lemma B proof"));
        reg.conclude(id, T.OutcomeType.ACHIEVED, keccak256("both lemmas"));
        vm.stopPrank();
        s = reg.getSwarm(id);
        assertEq(uint8(s.state), uint8(T.LifecycleState.CONCLUDING));
        assertEq(uint8(s.outcome), uint8(T.OutcomeType.ACHIEVED));
        assertEq(uint8(s.reason), uint8(T.Reason.ACCEPTANCE));
        vm.prank(coord);
        reg.dissolve(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.DISSOLVED));
    }

    function test_caseB_chamberCannotAdvanceAnIneligibleBidder() public {
        vm.prank(coord); reg.join(id, ROLE_COORD, CHARTER1);
        vm.prank(c1); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c2); reg.join(id, ROLE_VERIFIER, CHARTER1);
        reg.activate(id);
        vm.prank(b1); reg.join(id, ROLE_BIDDER, CHARTER1);
        list.setAllowed(b1, false); // not eligible for the worker role
        address[] memory carried = new address[](4);
        carried[0] = coord; carried[1] = c1; carried[2] = c2; carried[3] = b1;
        bytes32[] memory roles = new bytes32[](4);
        roles[0] = ROLE_COORD; roles[1] = ROLE_VERIFIER; roles[2] = ROLE_VERIFIER; roles[3] = ROLE_WORKER;
        bytes32 issue = chamber.open(id, T.DecisionPoint.ADVANCE, abi.encodeCall(ISwarmRegistry.advance, (id, carried, roles)), roster2(c1, c2));
        vote(issue, roster2(c1, c2), true);
        chamber.execute(issue); // the registry refuses: enactment Failed, the decision stands
        A.Enactment memory e = dec.getEnactment(issue, address(chamber), chamber.EFFECT_YES());
        assertEq(uint8(e.status), uint8(A.EnactmentStatus.Failed));
        assertEq(reg.getSwarm(id).phase, 0);
    }
}
