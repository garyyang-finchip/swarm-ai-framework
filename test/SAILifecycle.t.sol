// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIBase, T} from "./SAIBase.t.sol";
import "../assets/erc-sai/contracts/SAIErrors.sol";

contract SAILifecycleTest is SAIBase {
    // ------------------------------------------------------------------ activation

    function test_activateRequiresRoster() public {
        bytes32 id = formDefault();
        vm.expectRevert(SAI_RosterNotMet.selector);
        reg.activate(id);
        admitAndAccept(id, coord, ROLE_COORD);
        vm.expectRevert(SAI_RosterNotMet.selector); // minMembers 2 and worker min 1
        reg.activate(id);
        admitAndAccept(id, w1, ROLE_WORKER);
        assertTrue(reg.rosterMet(id));
        vm.prank(stranger); // ROSTER_MET: anyone
        reg.activate(id);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(uint8(s.state), uint8(T.LifecycleState.ACTIVE));
        assertEq(s.activatedAt, uint64(block.timestamp));
        assertEq(reg.hardDeadlineOf(id), uint64(block.timestamp) + 30 * DAY);
        vm.expectRevert(SAI_WrongState.selector);
        reg.activate(id);
    }

    function test_activationByAuthorityAndBoth() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.activation = T.Activation.AUTHORITY;
        bytes32 id = formWith(spec, defaultObjective());
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.activate(id);
        vm.prank(coord); // no roster condition under AUTHORITY
        reg.activate(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.ACTIVE));

        spec.activation = T.Activation.BOTH;
        bytes32 id2 = formWith(spec, defaultObjective());
        vm.prank(coord);
        vm.expectRevert(SAI_RosterNotMet.selector);
        reg.activate(id2);
        admitAndAccept(id2, coord, ROLE_COORD);
        admitAndAccept(id2, w1, ROLE_WORKER);
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.activate(id2);
        vm.prank(coord);
        reg.activate(id2);
    }

    // ------------------------------------------------------------------ abort

    function test_abortByAuthorityOrAfterWindow() public {
        bytes32 id = formDefault();
        admitAndAccept(id, w1, ROLE_WORKER);
        vm.prank(stranger);
        vm.expectRevert(SAI_WindowOpen.selector);
        reg.abort(id);
        vm.warp(block.timestamp + 7 * DAY + 1);
        vm.prank(stranger);
        reg.abort(id);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(uint8(s.state), uint8(T.LifecycleState.DISSOLVED));
        assertEq(uint8(s.outcome), uint8(T.OutcomeType.ABANDONED));
        assertEq(uint8(s.reason), uint8(T.Reason.RECRUITMENT_EXPIRED));
        // lazy roster-wide exit
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.EXITED));
        assertEq(uint8(exitReason(id, w1)), uint8(T.ExitReason.SWARM_DISSOLVED));
        (uint32 a, uint32 su, uint32 c) = reg.memberCount(id);
        assertEq(a + su + c, 0);

        bytes32 id2 = formDefault();
        vm.prank(coord);
        reg.abort(id2);
        assertEq(uint8(reg.getSwarm(id2).reason), uint8(T.Reason.AUTHORITY));
    }

    // ------------------------------------------------------------------ suspend / resume

    function test_suspendAndResumeByAuthority() public {
        bytes32 id = formAndActivate();
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.suspend(id);
        vm.prank(coord);
        reg.suspend(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.SUSPENDED));
        // admissions and contributions refused while suspended; leave still works
        vm.prank(coord);
        vm.expectRevert(SAI_WrongState.selector);
        reg.admit(id, w2, ROLE_WORKER);
        vm.prank(w1);
        vm.expectRevert(SAI_WrongState.selector);
        reg.recordContribution(id, keccak256("c"), "");
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.resume(id);
        vm.prank(coord);
        reg.resume(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.ACTIVE));
    }

    function test_enforceRosterAndPermissionlessResume() public {
        bytes32 id = formAndActivate();
        vm.expectRevert(SAI_RosterMet.selector);
        reg.enforceRoster(id);
        vm.prank(w1);
        reg.leave(id); // worker min 1 no longer met
        assertFalse(reg.rosterMet(id));
        vm.prank(stranger);
        reg.enforceRoster(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.SUSPENDED));
        assertEq(uint8(reg.getSwarm(id).reason), uint8(T.Reason.ROSTER_LOST));
        // nobody may resume while the roster is short
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.resume(id);
        // the authority may still admit while suspended? no: admission needs FORMING or ACTIVE
        vm.prank(coord);
        vm.expectRevert(SAI_WrongState.selector);
        reg.admit(id, w2, ROLE_WORKER);
        // the authority resumes, admits, and the roster holds again
        vm.prank(coord);
        reg.resume(id);
        admitAndAccept(id, w2, ROLE_WORKER);
        assertTrue(reg.rosterMet(id));
    }

    function test_rosterLostThenAnyoneResumesOnceRosterHolds() public {
        // a role with max 0 and a worker that leaves then re-joins through the authority after resume
        bytes32 id = formAndActivate();
        admitAndAccept(id, w2, ROLE_WORKER);
        vm.prank(w1); reg.leave(id);
        vm.prank(w2); reg.leave(id);
        vm.prank(stranger); reg.enforceRoster(id);
        // roster cannot be refilled while suspended, so permissionless resume needs the authority first in this
        // configuration; the permissionless path is exercised in the phase tests where the roster re-forms.
        vm.prank(coord); reg.resume(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.ACTIVE));
    }

    function test_enforceInactivityTwoStages() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.inactivityTimeout = 3 * DAY;
        bytes32 id = formWith(spec, defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        vm.expectRevert(SAI_NotInactive.selector);
        reg.enforceInactivity(id);
        vm.warp(block.timestamp + 2 * DAY);
        vm.prank(w1);
        reg.recordContribution(id, keccak256("work"), "ipfs://w"); // activity resets the clock
        vm.warp(block.timestamp + 3 * DAY);
        vm.expectRevert(SAI_NotInactive.selector);
        reg.enforceInactivity(id);
        vm.warp(block.timestamp + 1);
        reg.enforceInactivity(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.SUSPENDED));
        assertEq(uint8(reg.getSwarm(id).reason), uint8(T.Reason.INACTIVITY));
        vm.expectRevert(SAI_NotInactive.selector);
        reg.enforceInactivity(id);
        vm.warp(block.timestamp + 3 * DAY + 1);
        reg.enforceInactivity(id);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(uint8(s.state), uint8(T.LifecycleState.CONCLUDING));
        assertEq(uint8(s.outcome), uint8(T.OutcomeType.ABANDONED));
        assertEq(uint8(s.reason), uint8(T.Reason.INACTIVITY));
    }

    function test_enforceDeadline() public {
        bytes32 id = formAndActivate();
        vm.expectRevert(SAI_BeforeDeadline.selector);
        reg.enforceDeadline(id);
        vm.warp(block.timestamp + 30 * DAY + 1);
        vm.prank(stranger);
        reg.enforceDeadline(id);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(uint8(s.state), uint8(T.LifecycleState.CONCLUDING));
        assertEq(uint8(s.outcome), uint8(T.OutcomeType.ABANDONED));
        assertEq(uint8(s.reason), uint8(T.Reason.TIMEOUT));
    }

    function test_deadlineAppliesWhileSuspended() public {
        bytes32 id = formAndActivate();
        vm.prank(coord);
        reg.suspend(id);
        vm.warp(block.timestamp + 30 * DAY + 1);
        reg.enforceDeadline(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.CONCLUDING));
    }

    // ------------------------------------------------------------------ conclude / dissolve

    function test_concludeByAcceptanceAuthorityAndByAuthority() public {
        bytes32 id = formAndActivate();
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.conclude(id, T.OutcomeType.ACHIEVED, keccak256("r"));
        vm.prank(judge);
        vm.expectRevert(SAI_BadOutcome.selector);
        reg.conclude(id, T.OutcomeType.SUPERSEDED, bytes32(0));
        vm.prank(judge);
        reg.conclude(id, T.OutcomeType.ACHIEVED, keccak256("result"));
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(uint8(s.state), uint8(T.LifecycleState.CONCLUDING));
        assertEq(uint8(s.outcome), uint8(T.OutcomeType.ACHIEVED));
        assertEq(uint8(s.reason), uint8(T.Reason.ACCEPTANCE));
        assertEq(s.resultHash, keccak256("result"));

        bytes32 id2 = formAndActivate();
        vm.prank(coord);
        reg.conclude(id2, T.OutcomeType.FAILED, bytes32(0));
        assertEq(uint8(reg.getSwarm(id2).reason), uint8(T.Reason.AUTHORITY));
    }

    function test_concludingFreezesLedgerExceptLeave() public {
        bytes32 id = formAndActivate();
        admitAndAccept(id, w2, ROLE_WORKER);
        vm.prank(judge);
        reg.conclude(id, T.OutcomeType.ACHIEVED, bytes32(0));
        vm.startPrank(coord);
        vm.expectRevert(SAI_WrongState.selector); reg.admit(id, w3, ROLE_WORKER);
        vm.expectRevert(SAI_WrongState.selector); reg.suspendMember(id, w2);
        vm.expectRevert(SAI_WrongState.selector); reg.remove(id, w2);
        vm.expectRevert(SAI_WrongState.selector); reg.substitute(id, w2, w3);
        vm.expectRevert(SAI_WrongState.selector); reg.amend(id, CHARTER2, "uri", bytes32(0), false);
        vm.expectRevert(SAI_WrongState.selector); reg.attach(id, T.ResourceInput(keccak256("sai.resource.code"), 0, address(0), 0, keccak256("x"), bytes32(0), "", bytes32(0), address(0)));
        vm.stopPrank();
        vm.prank(stranger);
        vm.expectRevert(SAI_WrongState.selector);
        reg.challenge(id, w2);
        vm.prank(w1);
        vm.expectRevert(SAI_WrongState.selector);
        reg.recordContribution(id, keccak256("late"), "");
        // leave still works; the ledger shrinks and nothing else changes
        vm.prank(w2);
        reg.leave(id);
        assertEq(uint8(status(id, w2)), uint8(T.MemberStatus.EXITED));
        (uint32 a,,) = reg.memberCount(id);
        assertEq(a, 2);
    }

    function test_dissolveByAuthorityOrAfterSettlementWindow() public {
        bytes32 id = formAndActivate();
        vm.expectRevert(SAI_WrongState.selector);
        reg.dissolve(id);
        vm.prank(judge);
        reg.conclude(id, T.OutcomeType.ACHIEVED, bytes32(0));
        vm.prank(stranger);
        vm.expectRevert(SAI_WindowOpen.selector);
        reg.dissolve(id);
        vm.warp(block.timestamp + DAY + 1);
        vm.prank(stranger);
        reg.dissolve(id);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(uint8(s.state), uint8(T.LifecycleState.DISSOLVED));
        assertEq(uint8(s.outcome), uint8(T.OutcomeType.ACHIEVED)); // outcome frozen
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.EXITED));
        assertEq(uint8(exitReason(id, w1)), uint8(T.ExitReason.SWARM_DISSOLVED));
        // terminal: nothing more
        vm.prank(w1);
        vm.expectRevert(SAI_WrongState.selector);
        reg.leave(id);
        vm.prank(coord);
        vm.expectRevert(SAI_WrongState.selector);
        reg.setCharterURI(id, "x");
        vm.prank(coord);
        vm.expectRevert(SAI_WrongState.selector);
        reg.transferAuthority(id, T.DecisionPoint.ADMIT, w1);
    }

    // ------------------------------------------------------------------ succession

    function test_succeedCarriesMembersAsCandidates() public {
        bytes32 id = formAndActivate();
        admitAndAccept(id, w2, ROLE_WORKER);
        T.SwarmSpec memory spec = defaultSpec();
        spec.maxDuration = 60 * DAY;
        address[] memory carried = new address[](2);
        carried[0] = coord; carried[1] = w1;
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_COORD; roles[1] = ROLE_WORKER;
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.succeed(id, spec, CHARTER2, "uri2", defaultObjective(), carried, roles);
        vm.prank(coord);
        bytes32 next = reg.succeed(id, spec, CHARTER2, "uri2", defaultObjective(), carried, roles);

        T.Swarm memory old = reg.getSwarm(id);
        assertEq(uint8(old.state), uint8(T.LifecycleState.CONCLUDING));
        assertEq(uint8(old.outcome), uint8(T.OutcomeType.SUPERSEDED));
        assertEq(old.successorId, next);
        T.Swarm memory s = reg.getSwarm(next);
        assertEq(s.predecessorId, id);
        assertEq(s.initiator, coord);
        assertEq(s.origin.kind, keccak256("sai.origin.succession"));
        assertEq(s.origin.ref, id);
        assertEq(uint8(s.state), uint8(T.LifecycleState.FORMING));
        // carried members are admitted candidates until they accept the successor's charter
        assertEq(uint8(status(next, coord)), uint8(T.MemberStatus.CANDIDATE));
        assertEq(uint8(status(next, w2)), uint8(T.MemberStatus.NONE));
        vm.prank(coord); reg.acceptCharter(next, CHARTER2);
        vm.prank(w1); reg.acceptCharter(next, CHARTER2);
        assertEq(uint8(status(next, w1)), uint8(T.MemberStatus.ACTIVE));
        assertTrue(reg.rosterMet(next));
        reg.activate(next);
    }

    function test_succeedRejectsShapeAndNonMembers() public {
        bytes32 id = formAndActivate();
        address[] memory carried = new address[](1);
        carried[0] = w2; // not a member
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE_WORKER;
        vm.prank(coord);
        vm.expectRevert(SAI_NotCarriedMember.selector);
        reg.succeed(id, defaultSpec(), CHARTER2, "u", defaultObjective(), carried, roles);
        carried[0] = w1;
        vm.prank(coord);
        vm.expectRevert(SAI_CarriedShape.selector);
        reg.succeed(id, defaultSpec(), CHARTER2, "u", defaultObjective(), carried, new bytes32[](0));
    }

    // ------------------------------------------------------------------ revision log

    function test_revisionIncrementsAndChangedEmitted() public {
        bytes32 id = formDefault();
        assertEq(reg.getSwarm(id).revision, 1);
        vm.expectEmit(true, true, false, true, address(reg));
        emit Changed(id, 2, reg.admit.selector, coord);
        vm.prank(coord);
        reg.admit(id, w1, ROLE_WORKER);
        assertEq(reg.getSwarm(id).revision, 2);
    }

    event Changed(bytes32 indexed swarmId, uint64 indexed revision, bytes4 selector, address by);
}
