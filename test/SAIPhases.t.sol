// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIBase, T} from "./SAIBase.t.sol";
import "../assets/erc-sai/contracts/SAIErrors.sol";

contract SAIPhasesTest is SAIBase {
    /// bidding (OPEN, selfJoin bidders, 2-day input window) -> execution (CLOSED, SELECT) -> review (INHERIT) -> re-recruit (RECRUIT, GATED)
    function tenderSpec() internal view returns (T.SwarmSpec memory spec) {
        spec = defaultSpec();
        spec.roles = new T.RoleSpec[](3);
        spec.roles[0] = role(ROLE_COORD, 1, 1, address(0), false);
        spec.roles[1] = role(ROLE_BIDDER, 0, 0, address(0), true);
        spec.roles[2] = role(ROLE_WORKER, 0, 2, address(0), false);
        spec.phases = new T.PhaseSpec[](4);
        spec.phases[0] = phase(P_EXCLUSIVE, T_REDUNDANT, C_LEADER, T.Boundary.OPEN, T.Admission.RECRUIT, 2 * DAY);
        spec.phases[1] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.CLOSED, T.Admission.SELECT, 0);
        spec.phases[2] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.CLOSED, T.Admission.INHERIT, 0);
        spec.phases[3] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.GATED, T.Admission.RECRUIT, 0);
        spec.minMembers = 1;
    }

    function formTender() internal returns (bytes32 id) {
        id = formWith(tenderSpec(), defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        vm.prank(w1); reg.join(id, ROLE_BIDDER, CHARTER1);
        vm.prank(w2); reg.join(id, ROLE_BIDDER, CHARTER1);
        vm.prank(w3); reg.join(id, ROLE_BIDDER, CHARTER1);
        reg.activate(id);
    }

    function test_inputWindowClosesAdmissionsAndContributions() public {
        bytes32 id = formTender();
        assertTrue(reg.inputOpen(id));
        vm.prank(w1);
        reg.recordContribution(id, keccak256("bid1"), "ipfs://bid1");
        vm.warp(block.timestamp + 2 * DAY + 1);
        assertFalse(reg.inputOpen(id));
        vm.prank(w1);
        vm.expectRevert(SAI_InputClosed.selector);
        reg.recordContribution(id, keccak256("late"), "");
        vm.prank(stranger);
        vm.expectRevert(SAI_InputClosed.selector);
        reg.join(id, ROLE_BIDDER, CHARTER1);
        // the phase itself continues until the ADVANCE authority advances
        assertEq(reg.getSwarm(id).phase, 0);
    }

    function test_selectCarriesRerolesAndExitsTheRest() public {
        bytes32 id = formTender();
        address[] memory carried = new address[](3);
        carried[0] = coord; carried[1] = w1; carried[2] = w2;
        bytes32[] memory roles = new bytes32[](3);
        roles[0] = ROLE_COORD; roles[1] = ROLE_WORKER; roles[2] = ROLE_WORKER;
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.advance(id, carried, roles);
        vm.prank(coord);
        vm.expectRevert(SAI_CarriedShape.selector); // roles length mismatch
        reg.advance(id, carried, new bytes32[](1));
        vm.prank(coord);
        reg.advance(id, carried, roles);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(s.phase, 1);
        assertEq(s.rosterPhase, 1);
        assertEq(uint8(status(id, w3)), uint8(T.MemberStatus.EXITED));
        assertEq(uint8(exitReason(id, w3)), uint8(T.ExitReason.NOT_CARRIED));
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        assertEq(reg.getMember(id, w1).roleId, ROLE_WORKER);
        (uint32 a, uint32 su, uint32 c) = reg.memberCount(id);
        assertEq(a, 3); assertEq(su, 0); assertEq(c, 0);
        (uint32 ra,) = reg.roleCount(id, ROLE_WORKER);
        assertEq(ra, 2);
        (ra,) = reg.roleCount(id, ROLE_BIDDER);
        assertEq(ra, 0);
        // the exited bidder cannot act; its seat is gone
        vm.prank(w3);
        vm.expectRevert(SAI_NoSeat.selector);
        reg.leave(id);
        vm.prank(w3);
        vm.expectRevert(SAI_NotMember.selector);
        reg.recordContribution(id, keccak256("x"), "");
    }

    function test_selectRespectsRoleMaxAndEligibility() public {
        bytes32 id = formTender();
        address[] memory carried = new address[](4);
        carried[0] = coord; carried[1] = w1; carried[2] = w2; carried[3] = w3;
        bytes32[] memory roles = new bytes32[](4);
        roles[0] = ROLE_COORD; roles[1] = ROLE_WORKER; roles[2] = ROLE_WORKER; roles[3] = ROLE_WORKER; // worker max 2
        vm.prank(coord);
        vm.expectRevert(SAI_RoleFull.selector);
        reg.advance(id, carried, roles);
        carried = new address[](2);
        carried[0] = w1; carried[1] = w1; // duplicate
        roles = new bytes32[](2);
        roles[0] = ROLE_WORKER; roles[1] = ROLE_WORKER;
        vm.prank(coord);
        vm.expectRevert(SAI_NotCarriedMember.selector);
        reg.advance(id, carried, roles);
        carried[1] = stranger; // not a member
        vm.prank(coord);
        vm.expectRevert(SAI_NotCarriedMember.selector);
        reg.advance(id, carried, roles);
    }

    function test_inheritKeepsEveryoneAndRecruitEmptiesTheRoster() public {
        bytes32 id = formTender();
        address[] memory carried = new address[](2);
        carried[0] = coord; carried[1] = w1;
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_COORD; roles[1] = ROLE_WORKER;
        vm.prank(coord);
        reg.advance(id, carried, roles);
        vm.prank(coord);
        reg.suspendMember(id, w1);
        // INHERIT: carried and roles must be empty; suspended members keep their status
        vm.prank(coord);
        vm.expectRevert(SAI_CarriedShape.selector);
        reg.advance(id, carried, roles);
        vm.prank(coord);
        reg.advance(id, new address[](0), new bytes32[](0));
        assertEq(reg.getSwarm(id).phase, 2);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        (uint32 a, uint32 su,) = reg.memberCount(id);
        assertEq(a, 1); assertEq(su, 1);
        // RECRUIT: everyone exits lazily, counters restart, the coordinator must re-admit itself? No: the ADMIT
        // authority is an ADDRESS here, so it can rebuild the roster; enforceRoster is deferred for the window.
        vm.prank(coord);
        reg.advance(id, new address[](0), new bytes32[](0));
        assertEq(reg.getSwarm(id).phase, 3);
        assertEq(uint8(status(id, coord)), uint8(T.MemberStatus.EXITED));
        (a, su,) = reg.memberCount(id);
        assertEq(a + su, 0);
        vm.expectRevert(SAI_RosterCheckDeferred.selector);
        reg.enforceRoster(id);
        admitAndAccept(id, w2, ROLE_COORD);
        assertTrue(reg.rosterMet(id)); // minMembers 1, coordinator min 1
        vm.warp(block.timestamp + 7 * DAY + 1);
        vm.expectRevert(SAI_RosterMet.selector);
        reg.enforceRoster(id);
    }

    function test_lastPhaseCannotAdvance() public {
        bytes32 id = formAndActivate(); // single phase
        vm.prank(coord);
        vm.expectRevert(SAI_LastPhase.selector);
        reg.advance(id, new address[](0), new bytes32[](0));
    }

    function test_roleAuthorityFollowsTheLedger() public {
        // REPRESENT is held by the coordinator role in the default spec
        bytes32 id = formAndActivate();
        assertTrue(reg.isAuthorized(id, T.DecisionPoint.REPRESENT, coord));
        assertFalse(reg.isAuthorized(id, T.DecisionPoint.REPRESENT, w1));
        vm.prank(coord);
        reg.leave(id);
        assertFalse(reg.isAuthorized(id, T.DecisionPoint.REPRESENT, coord));
        // the ADDRESS authority of ADMIT is still coord even after it left the roster
        assertTrue(reg.isAuthorized(id, T.DecisionPoint.ADMIT, coord));
    }
}
