// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIScenarioBase, T, A, SwarmDecisionAdapter, SwarmTenderAdapter, SwarmAccount, ITaskTenderKernel} from "./SAIScenarioBase.t.sol";
import "../assets/erc-sai/contracts/SAIErrors.sol";
import {ISwarmRegistry} from "../assets/erc-sai/contracts/interfaces/ISwarmRegistry.sol";

/// Case A — a tender-bound cooperative swarm.
/// A coordinator forms a swarm bound to a funded task tender; a council of three (2-of-3, through
/// the real ERC-8436 registries) admits workers; workers record contributions; the coordinator
/// submits the fulfillment from the swarm account; the tender's judge accepts; the tender adapter
/// concludes the swarm ACHIEVED from the tender's record; the reward sits in the swarm account and
/// the coordinator pays the worker from it; the swarm dissolves after the settlement window.
contract SAICaseATest is SAIScenarioBase {
    SwarmDecisionAdapter council;
    SwarmTenderAdapter tender;
    SwarmAccount acct;
    uint256 tokenId;
    bytes32 id;

    function setUp() public override {
        super.setUp();
        tokenId = mintTender(1 ether);
        council = newDecisionAdapter(ROLE_VERIFIER, 2, 3, DAY);
        tender = new SwarmTenderAdapter(ISwarmRegistry(address(reg)), ITaskTenderKernel(address(task)));
        list.setAllowed(w1, true);

        T.SwarmSpec memory spec = defaultSpec();
        spec.roles = new T.RoleSpec[](3);
        spec.roles[0] = role(ROLE_COORD, 1, 1, address(0), true);
        spec.roles[1] = role(ROLE_VERIFIER, 3, 3, address(0), true);
        spec.roles[2] = role(ROLE_WORKER, 1, 3, address(list), false);
        spec.phases[0] = phase(P_SHARED, T_PARTITIONED, C_COLLECTIVE, T.Boundary.OPEN, T.Admission.RECRUIT, 0);
        spec.authorities[uint256(T.DecisionPoint.ADMIT)] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: address(council), roleId: bytes32(0)});
        spec.authorities[uint256(T.DecisionPoint.REMOVE)] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: address(council), roleId: bytes32(0)});
        spec.activation = T.Activation.BOTH;
        spec.minMembers = 5;
        spec.maxDuration = 90 * DAY;

        T.ObjectiveInput memory o = defaultObjective();
        o.acceptanceAuthority = address(tender);
        o.obligation = T.ExternalRef({chainId: block.chainid, target: address(task), id: tokenId});

        vm.prank(coord);
        id = reg.form(spec, CHARTER1, COMMIT1, "ipfs://charter-a", bytes32(0),
                      T.Origin({kind: keccak256("sai.origin.task"), ref: keccak256(abi.encode(block.chainid, address(task), tokenId))}), o);
    }

    function test_caseA_endToEnd() public {
        // --- recruitment: self-join roles, then a worker applies and the council decides
        vm.prank(coord); reg.join(id, ROLE_COORD, CHARTER1);
        vm.prank(c1); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c2); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c3); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(w1); reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        assertFalse(reg.rosterMet(id)); // worker min 1 not yet met

        bytes32 issue = council.open(id, T.DecisionPoint.ADMIT, abi.encodeCall(ISwarmRegistry.admit, (id, w1, ROLE_WORKER)), roster3());
        vote(issue, roster2(c1, c3), true);
        council.execute(issue);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        assertTrue(reg.rosterMet(id));
        vm.prank(coord);
        reg.activate(id); // BOTH: authority plus thresholds
        assertEq(uint8(state(id)), uint8(T.LifecycleState.ACTIVE));

        // --- the swarm account: fulfiller of record on the tender
        acct = new SwarmAccount(ISwarmRegistry(address(reg)), id, address(0));
        vm.prank(coord);
        reg.setAccount(id, address(acct));

        // --- work: attribution through the contribution stream
        vm.prank(w1);
        reg.recordContribution(id, keccak256("track-1 results"), "ipfs://track1");
        // the tender adapter cannot settle yet: nothing accepted, not cancelled, not expired
        uint256 none = tender.NO_SUBMISSION();
        vm.expectRevert("SAITender: not settled");
        tender.settle(id, none);

        // --- the coordinator (REPRESENT role) submits the deliverable from the account
        vm.prank(coord);
        bytes memory ret = acct.execute(address(task), 0,
            abi.encodeCall(ITaskTenderKernel.submitFulfillment, (tokenId, keccak256("report"), "ipfs://report")));
        uint256 submissionId = abi.decode(ret, (uint256));
        ITaskTenderKernel.Submission memory s = ITaskTenderKernel(address(task)).submissionOf(tokenId, submissionId);
        assertEq(s.fulfiller, address(acct));
        // a stranger cannot act through the account
        vm.prank(stranger);
        vm.expectRevert(SwarmAccount.SwarmAccount_NotRepresentative.selector);
        acct.execute(address(task), 0, "");

        // --- the tender's judge accepts: the vault pays the swarm account
        assertEq(address(acct).balance, 0);
        vm.prank(judge);
        task.acceptFulfillment(tokenId, submissionId);
        assertEq(address(acct).balance, 1 ether);

        // --- the swarm concludes from the tender's own record
        vm.expectRevert(); // a non-existent submission: the kernel itself refuses the lookup
        tender.settle(id, 999);
        vm.prank(stranger);
        tender.settle(id, submissionId);
        T.Swarm memory sw = reg.getSwarm(id);
        assertEq(uint8(sw.state), uint8(T.LifecycleState.CONCLUDING));
        assertEq(uint8(sw.outcome), uint8(T.OutcomeType.ACHIEVED));
        assertEq(uint8(sw.reason), uint8(T.Reason.ACCEPTANCE));
        assertEq(sw.resultHash, keccak256("report"));

        // --- settlement: the coordinator pays the worker from the account (the charter's allocation rule)
        vm.prank(coord);
        acct.execute(w1, 0.7 ether, "");
        assertEq(w1.balance, 0.7 ether);
        // the charter names who may recover what is left after dissolution; set while the swarm lives
        vm.prank(coord);
        acct.setRecoveryAddress(coord);
        // --- dissolution after the settlement window, by anyone; the ledger exits lazily
        vm.warp(block.timestamp + DAY + 1);
        vm.prank(stranger);
        reg.dissolve(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.DISSOLVED));
        assertEq(uint8(exitReason(id, w1)), uint8(T.ExitReason.SWARM_DISSOLVED));
        // the registry authorizes nobody in a dissolved swarm: no representative acts through the account
        vm.prank(coord);
        vm.expectRevert(SwarmAccount.SwarmAccount_NotRepresentative.selector);
        acct.execute(coord, 0.3 ether, "");
        // what is left goes out only through the account's own recovery rule
        vm.prank(coord);
        acct.recover(coord, 0.3 ether, "");
        assertEq(coord.balance, 0.3 ether);
        assertEq(address(acct).balance, 0);
    }

    function test_caseA_tenderCancelledAbandonsTheSwarm() public {
        vm.prank(coord); reg.join(id, ROLE_COORD, CHARTER1);
        vm.prank(c1); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c2); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c3); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(w1); reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        bytes32 issue = council.open(id, T.DecisionPoint.ADMIT, abi.encodeCall(ISwarmRegistry.admit, (id, w1, ROLE_WORKER)), roster3());
        vote(issue, roster2(c1, c2), true);
        council.execute(issue);
        vm.prank(coord); reg.activate(id);
        acct = new SwarmAccount(ISwarmRegistry(address(reg)), id, address(0));
        vm.prank(coord); reg.setAccount(id, address(acct));

        vm.prank(sponsor);
        task.cancelTask(tokenId);
        tender.settle(id, tender.NO_SUBMISSION());
        assertEq(uint8(reg.getSwarm(id).outcome), uint8(T.OutcomeType.ABANDONED));
    }

    function test_caseA_expiryFailsTheSwarm() public {
        vm.prank(coord); reg.join(id, ROLE_COORD, CHARTER1);
        vm.prank(c1); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c2); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(c3); reg.join(id, ROLE_VERIFIER, CHARTER1);
        vm.prank(w1); reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        bytes32 issue = council.open(id, T.DecisionPoint.ADMIT, abi.encodeCall(ISwarmRegistry.admit, (id, w1, ROLE_WORKER)), roster3());
        vote(issue, roster2(c1, c2), true);
        council.execute(issue);
        vm.prank(coord); reg.activate(id);
        acct = new SwarmAccount(ISwarmRegistry(address(reg)), id, address(0));
        vm.prank(coord); reg.setAccount(id, address(acct));

        vm.warp(block.timestamp + 61 * DAY);
        tender.settle(id, tender.NO_SUBMISSION());
        assertEq(uint8(reg.getSwarm(id).outcome), uint8(T.OutcomeType.FAILED));
    }
}
