// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIScenarioBase, T, A, SwarmDecisionAdapter} from "./SAIScenarioBase.t.sol";
import "../assets/erc-sai/contracts/SAIErrors.sol";
import {ISwarmRegistry} from "../assets/erc-sai/contracts/interfaces/ISwarmRegistry.sol";

/// The decision adapter against the real ERC-8436 registries: a council of three (2-of-3) holds
/// ADMIT and REMOVE; everything else is held by `coord`.
contract SAIDecisionTest is SAIScenarioBase {
    SwarmDecisionAdapter adapter;
    bytes32 id;

    function setUp() public override {
        super.setUp();
        adapter = newDecisionAdapter(ROLE_VERIFIER, 2, 3, DAY);
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles = new T.RoleSpec[](3);
        spec.roles[0] = role(ROLE_COORD, 1, 1, address(0), true);
        spec.roles[1] = role(ROLE_VERIFIER, 3, 3, address(0), true);
        spec.roles[2] = role(ROLE_WORKER, 0, 0, address(0), false);
        spec.phases[0] = phase(P_SHARED, T_PARTITIONED, C_COLLECTIVE, T.Boundary.OPEN, T.Admission.RECRUIT, 0);
        spec.authorities[uint256(T.DecisionPoint.ADMIT)] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: address(adapter), roleId: bytes32(0)});
        spec.authorities[uint256(T.DecisionPoint.REMOVE)] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: address(adapter), roleId: bytes32(0)});
        spec.minMembers = 4;
        id = formWith(spec, defaultObjective());
        vm.prank(coord); reg.join(id, ROLE_COORD, CHARTER1);
        vm.prank(c1); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c2); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c3); reg.join(id, ROLE_VERIFIER, CHARTER1);
        reg.activate(id);
        vm.prank(w1); reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
    }

    function admitCall(address who) internal view returns (bytes memory) {
        return abi.encodeCall(ISwarmRegistry.admit, (id, who, ROLE_WORKER));
    }

    function test_openChecks() public {
        // not the authority for CONCLUDE
        vm.expectRevert("SAIDecision: not the authority");
        adapter.open(id, T.DecisionPoint.CONCLUDE, abi.encodeCall(ISwarmRegistry.conclude, (id, T.OutcomeType.ACHIEVED, bytes32(0))), roster3());
        // a call the decision point does not allow
        vm.expectRevert("SAIDecision: call not allowed");
        adapter.open(id, T.DecisionPoint.ADMIT, abi.encodeCall(ISwarmRegistry.conclude, (id, T.OutcomeType.ACHIEVED, bytes32(0))), roster3());
        // a call that targets another swarm
        vm.expectRevert("SAIDecision: call targets another swarm");
        adapter.open(id, T.DecisionPoint.ADMIT, abi.encodeCall(ISwarmRegistry.admit, (keccak256("other"), w1, ROLE_WORKER)), roster3());
        // an incomplete roster, a non-member, a duplicate
        vm.expectRevert("SAIDecision: roster incomplete");
        adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster2(c1, c2));
        address[] memory bad = roster3(); bad[2] = coord;
        vm.expectRevert("SAIDecision: not a deciding member");
        adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), bad);
        bad[2] = c1;
        vm.expectRevert("SAIDecision: duplicate member");
        adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), bad);
    }

    function test_yesAdmitsThroughTheRealRegistry() public {
        bytes32 issueId = adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());
        // policy: 2-of-3 roster snapshot, one body, no appeal
        (, , bytes32 policyId, , ) = _proposal(issueId);
        assertTrue(policies.policyExists(policyId));
        A.Issue memory issue = _issue(issueId);
        assertEq(issue.consumer, address(adapter));
        assertEq(issue.obligationId, keccak256(abi.encode(id, T.DecisionPoint.ADMIT, admitCall(w1))));
        // the same proposal cannot be filed twice while one is live (ERC-8436 obligation rule)
        vm.expectRevert("ACDF: obligation active");
        adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());

        vm.expectRevert("SAIDecision: not final");
        adapter.execute(issueId);
        vote(issueId, roster2(c1, c2), true);
        A.Result memory r = dec.getResult(issueId);
        assertEq(uint8(r.state), uint8(A.ProcedureState.Final));
        assertTrue(r.outcomeYes);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.CANDIDATE));
        vm.prank(stranger);
        adapter.execute(issueId);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        A.Enactment memory e = dec.getEnactment(issueId, address(adapter), adapter.EFFECT_YES());
        assertEq(uint8(e.status), uint8(A.EnactmentStatus.Enacted));
        vm.expectRevert("SAIDecision: already enacted");
        adapter.execute(issueId);
        // a second proposal in the family is a new policy version
        vm.prank(w2); reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        bytes32 issue2 = adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w2), roster3());
        assertEq(adapter.familyVersion(adapter.familyOf(id, T.DecisionPoint.ADMIT)), 2);
        assertTrue(issue2 != issueId);
    }

    function test_noRecordsRefusalAndNothingChanges() public {
        bytes32 issueId = adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());
        vote(issueId, roster2(c1, c2), false); // 2 blocks of 3 under 2-of-3: No
        A.Result memory r = dec.getResult(issueId);
        assertEq(uint8(r.outcomeType), uint8(A.OutcomeType.Decided));
        assertFalse(r.outcomeYes);
        adapter.execute(issueId);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.CANDIDATE));
        A.Enactment memory e = dec.getEnactment(issueId, address(adapter), adapter.EFFECT_NO());
        assertEq(uint8(e.status), uint8(A.EnactmentStatus.Enacted));
    }

    function test_noDecisionIsStatusQuo() public {
        bytes32 issueId = adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());
        vm.prank(c1);
        acdf.castBallot(issueId, 1, 0, true); // one approval only
        vm.warp(block.timestamp + DAY + 1);
        acdf.settleRound(issueId);
        A.Result memory r = dec.getResult(issueId);
        assertEq(uint8(r.state), uint8(A.ProcedureState.Final));
        assertEq(uint8(r.outcomeType), uint8(A.OutcomeType.NoDecision));
        vm.expectRevert("SAIDecision: no decision; status quo");
        adapter.execute(issueId);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.CANDIDATE));
        // after a NoDecision the obligation is free again: the proposal can be re-filed
        adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());
    }

    function test_materialAmendmentInvalidatesPendingProposal() public {
        bytes32 issueId = adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());
        vote(issueId, roster2(c1, c2), true);
        vm.prank(coord);
        reg.amend(id, CHARTER2, "uri2", bytes32(0), true);
        vm.expectRevert("SAIDecision: commitments changed");
        adapter.execute(issueId);
        // a minor amendment would not have blocked it
        bytes32 issue2 = adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());
        vote(issue2, roster2(c1, c3), true);
        vm.prank(coord);
        reg.amend(id, keccak256("charter v3"), "uri3", bytes32(0), false);
        adapter.execute(issue2);
        // w1 accepted v1 only: admitted, but completion waits for its acceptance of the current commitment
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.CANDIDATE));
        vm.prank(w1);
        reg.acceptCharter(id, keccak256("charter v3"));
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
    }

    function test_executionFailureIsRecordedNotFatal() public {
        bytes32 issueId = adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());
        vote(issueId, roster2(c1, c2), true);
        vm.prank(w1);
        reg.leave(id); // the candidate withdrew: admit will refuse? No: admit re-opens a seat for a non-member, so it succeeds.
        adapter.execute(issueId);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.CANDIDATE)); // admitted again; must accept
        // a proposal whose call fails at execution: remove a member that is no longer a member
        vm.prank(w2); reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        bytes32 issue2 = adapter.open(id, T.DecisionPoint.REMOVE, abi.encodeCall(ISwarmRegistry.remove, (id, w2)), roster3());
        vote(issue2, roster2(c1, c2), true);
        vm.prank(w2); reg.leave(id); // nothing left to remove
        adapter.execute(issue2);
        A.Enactment memory e = dec.getEnactment(issue2, address(adapter), adapter.EFFECT_YES());
        assertEq(uint8(e.status), uint8(A.EnactmentStatus.Failed));
        // the decision stands; a later retry can still succeed if the state allows it
        vm.prank(w2); reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        adapter.execute(issue2);
        e = dec.getEnactment(issue2, address(adapter), adapter.EFFECT_YES());
        assertEq(uint8(e.status), uint8(A.EnactmentStatus.Enacted));
        assertEq(uint8(status(id, w2)), uint8(T.MemberStatus.EXITED));
    }

    function test_removeByCouncil() public {
        bytes32 issueId = adapter.open(id, T.DecisionPoint.ADMIT, admitCall(w1), roster3());
        vote(issueId, roster2(c1, c2), true);
        adapter.execute(issueId);
        bytes32 issue2 = adapter.open(id, T.DecisionPoint.REMOVE,
            abi.encodeCall(ISwarmRegistry.suspendMember, (id, w1)), roster3());
        vote(issue2, roster2(c2, c3), true);
        adapter.execute(issue2);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        assertEq(uint8(reg.getMember(id, w1).suspension), uint8(T.SuspensionCause.AUTHORITY));
    }

    // helpers reading the adapter's and the registry's records
    function _proposal(bytes32 issueId) internal view returns (bool exists, bool enacted, bytes32 policyId, bytes32 swarmId, uint32 charterVersion) {
        (exists, enacted, swarmId, , charterVersion, , ) = adapter.proposalOf(issueId);
        policyId = dec.getIssue(issueId).policyId;
    }

    function _issue(bytes32 issueId) internal view returns (A.Issue memory) {
        return dec.getIssue(issueId);
    }
}
