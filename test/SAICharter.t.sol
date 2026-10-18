// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIBase, T} from "./SAIBase.t.sol";
import "../assets/erc-sai/contracts/SAIErrors.sol";
import {SwarmRegistry} from "../assets/erc-sai/contracts/SwarmRegistry.sol";
import {SwarmAccount} from "../assets/erc-sai/contracts/account/SwarmAccount.sol";
import {IResourceAdapter} from "../assets/erc-sai/contracts/interfaces/IResourceAdapter.sol";

/// A resource adapter for a fake "skill" kind: anchors exist for ids < 100 and report sha-256 digests.
contract SkillAdapterStub is IResourceAdapter {
    bytes32 public constant KIND = keccak256("sai.resource.skill");
    bytes32 public constant SHA256_KIND = keccak256("sha-256");
    function kind() external pure returns (bytes32) { return KIND; }
    function exists(uint256, address, uint256 id) external pure returns (bool) { return id < 100; }
    function controllerOf(uint256, address, uint256) external pure returns (address) { return address(0xBEEF); }
    function digestOf(uint256, address, uint256 id) external pure returns (bytes32, bytes32) {
        return (keccak256(abi.encode("skill", id)), SHA256_KIND);
    }
}

contract SAICharterTest is SAIBase {
    // ------------------------------------------------------------------ contributions and milestones

    function test_contributionModes() public {
        bytes32 id = formAndActivate(); // MEMBERS
        vm.prank(stranger);
        vm.expectRevert(SAI_NotMember.selector);
        reg.recordContribution(id, keccak256("x"), "");
        vm.expectEmit(true, true, true, true, address(reg));
        emit Contribution(id, w1, 0, keccak256("w"), "ipfs://w", 1, true, false);
        vm.prank(w1);
        reg.recordContribution(id, keccak256("w"), "ipfs://w");
        vm.prank(coord);
        reg.suspendMember(id, w1);
        vm.expectEmit(true, true, true, true, address(reg));
        emit Contribution(id, w1, 0, keccak256("s"), "", 1, true, true); // whileSuspended
        vm.prank(w1);
        reg.recordContribution(id, keccak256("s"), "");

        T.SwarmSpec memory spec = defaultSpec();
        spec.contributions = T.Contributions.OPEN;
        bytes32 id2 = formWith(spec, defaultObjective());
        admitAndAccept(id2, coord, ROLE_COORD);
        admitAndAccept(id2, w1, ROLE_WORKER);
        reg.activate(id2);
        vm.expectEmit(true, true, true, true, address(reg));
        emit Contribution(id2, stranger, 0, keccak256("ext"), "", 1, false, false); // external contribution
        vm.prank(stranger);
        reg.recordContribution(id2, keccak256("ext"), "");

        spec.contributions = T.Contributions.DISABLED;
        bytes32 id3 = formWith(spec, defaultObjective());
        admitAndAccept(id3, coord, ROLE_COORD);
        admitAndAccept(id3, w1, ROLE_WORKER);
        reg.activate(id3);
        vm.prank(w1);
        vm.expectRevert(SAI_ContributionsDisabled.selector);
        reg.recordContribution(id3, keccak256("x"), "");
    }

    function test_milestonesGateAchievement() public {
        T.ObjectiveInput memory o = defaultObjective();
        o.kind = T.ObjectiveKind.MILESTONED;
        o.milestoneCount = 2;
        bytes32 id = formWith(defaultSpec(), o);
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        vm.prank(coord);
        vm.expectRevert(SAI_NotAuthorized.selector); // only the acceptance authority records milestones
        reg.recordMilestone(id, 0, T.MilestoneStatus.ACCEPTED, keccak256("m0"));
        vm.startPrank(judge);
        vm.expectRevert(SAI_MilestoneIndex.selector);
        reg.recordMilestone(id, 2, T.MilestoneStatus.ACCEPTED, bytes32(0));
        vm.expectRevert(SAI_MilestoneStatus.selector);
        reg.recordMilestone(id, 0, T.MilestoneStatus.PENDING, bytes32(0));
        reg.recordMilestone(id, 0, T.MilestoneStatus.REJECTED, keccak256("bad"));
        vm.expectRevert(SAI_MilestonesIncomplete.selector);
        reg.conclude(id, T.OutcomeType.PARTIAL, bytes32(0)); // nothing accepted yet
        reg.recordMilestone(id, 0, T.MilestoneStatus.ACCEPTED, keccak256("m0")); // a rejected milestone may be recorded again
        vm.expectRevert(SAI_MilestoneFinal.selector);
        reg.recordMilestone(id, 0, T.MilestoneStatus.REJECTED, bytes32(0));
        (T.MilestoneStatus st, bytes32 rh,) = reg.milestoneOf(id, 0);
        assertEq(uint8(st), uint8(T.MilestoneStatus.ACCEPTED)); assertEq(rh, keccak256("m0"));
        assertEq(reg.objectiveOf(id).milestonesAccepted, 1);
        vm.expectRevert(SAI_MilestonesIncomplete.selector);
        reg.conclude(id, T.OutcomeType.ACHIEVED, bytes32(0));
        reg.recordMilestone(id, 1, T.MilestoneStatus.ACCEPTED, keccak256("m1"));
        reg.conclude(id, T.OutcomeType.ACHIEVED, keccak256("all"));
        vm.stopPrank();
        assertEq(uint8(reg.getSwarm(id).outcome), uint8(T.OutcomeType.ACHIEVED));
    }

    // ------------------------------------------------------------------ amendments

    function test_minorAmendmentKeepsCommitments() public {
        bytes32 id = formAndActivate();
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.amend(id, CHARTER2, "uri2", bytes32(0), false);
        vm.prank(coord);
        vm.expectRevert(SAI_SameCharter.selector);
        reg.amend(id, CHARTER1, "uri2", bytes32(0), false);
        vm.prank(coord);
        reg.amend(id, CHARTER2, "uri2", bytes32(0), false);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(s.charterVersion, 2);
        assertEq(s.commitmentVersion, 1);
        assertEq(s.exitWindowUntil, 0);
        assertEq(reg.objectiveOf(id).version, 1); // objective unchanged
        // existing members remain accepted for the current commitment; a new candidate completes under v2
        vm.prank(coord);
        reg.admit(id, w2, ROLE_WORKER);
        vm.prank(w2);
        vm.expectRevert(SAI_StaleCharter.selector);
        reg.acceptCharter(id, CHARTER1);
        vm.prank(w2);
        reg.acceptCharter(id, CHARTER2);
        assertEq(uint8(status(id, w2)), uint8(T.MemberStatus.ACTIVE));
        // a leave during a minor amendment is not flagged
        vm.prank(w1);
        reg.leave(id);
    }

    function test_materialAmendmentOpensExitWindowAndHoldsCompletion() public {
        bytes32 id = formAndActivate();
        vm.prank(coord);
        reg.admit(id, w2, ROLE_WORKER); // authority side done before the amendment
        vm.prank(w2);
        reg.applyToJoin(id, ROLE_WORKER, CHARTER1); // accepted v1 ... completes immediately (both sides)
        assertEq(uint8(status(id, w2)), uint8(T.MemberStatus.ACTIVE));

        vm.prank(coord);
        reg.admit(id, w3, ROLE_WORKER);
        vm.prank(w3);
        reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        assertEq(uint8(status(id, w3)), uint8(T.MemberStatus.ACTIVE));

        vm.prank(coord);
        reg.amend(id, CHARTER2, "uri2", keccak256("objective v2"), true);
        T.Swarm memory s = reg.getSwarm(id);
        assertEq(s.commitmentVersion, 2);
        assertEq(s.exitWindowUntil, uint64(block.timestamp) + 2 * DAY);
        assertEq(reg.objectiveOf(id).objectiveHash, keccak256("objective v2"));
        assertEq(reg.objectiveOf(id).version, 2);
        // members keep their recorded acceptance of v1 until they accept v2
        (bytes32 h, uint32 cv, uint32 mv) = reg.acceptedCharterOf(id, w1);
        assertEq(h, CHARTER1); assertEq(cv, 1); assertEq(mv, 1);
        // a candidate admitted now but who accepted only v1 waits for acceptCharter(v2)
        vm.prank(coord);
        reg.admit(id, stranger, ROLE_WORKER);
        assertEq(uint8(status(id, stranger)), uint8(T.MemberStatus.CANDIDATE));
        // leaving inside the window without having accepted v2 is flagged onAmendment
        vm.expectEmit(true, true, false, true, address(reg));
        emit MemberExited(id, w3, T.ExitReason.LEFT, true, w3);
        vm.prank(w3);
        reg.leave(id);
        // accepting v2 then leaving is an ordinary leave
        vm.prank(w2);
        reg.acceptCharter(id, CHARTER2);
        (, cv, mv) = reg.acceptedCharterOf(id, w2);
        assertEq(cv, 2); assertEq(mv, 2);
        vm.expectEmit(true, true, false, true, address(reg));
        emit MemberExited(id, w2, T.ExitReason.LEFT, false, w2);
        vm.prank(w2);
        reg.leave(id);
        // after the window a leave is not flagged even without acceptance
        vm.warp(block.timestamp + 2 * DAY + 1);
        vm.expectEmit(true, true, false, true, address(reg));
        emit MemberExited(id, w1, T.ExitReason.LEFT, false, w1);
        vm.prank(w1);
        reg.leave(id);
    }

    function test_setCharterURIAndTransferAuthority() public {
        bytes32 id = formDefault();
        vm.prank(coord);
        reg.setCharterURI(id, "ipfs://moved");
        assertEq(reg.getSwarm(id).charterURI, "ipfs://moved");
        assertEq(reg.getSwarm(id).charterVersion, 1);
        vm.prank(stranger);
        vm.expectRevert(SAI_NotHolder.selector);
        reg.transferAuthority(id, T.DecisionPoint.ADMIT, stranger);
        vm.prank(coord);
        vm.expectRevert(SAI_NotTransferable.selector);
        reg.transferAuthority(id, T.DecisionPoint.REPRESENT, stranger); // a ROLE authority
        vm.prank(coord);
        vm.expectRevert(SAI_ZeroAuthority.selector);
        reg.transferAuthority(id, T.DecisionPoint.ADMIT, address(0));
        vm.prank(coord);
        reg.transferAuthority(id, T.DecisionPoint.ADMIT, w3);
        assertEq(reg.authorityOf(id, T.DecisionPoint.ADMIT).target, w3);
        assertEq(reg.specOf(id).authorities[uint256(T.DecisionPoint.ADMIT)].target, coord); // the spec is unchanged
        vm.prank(coord);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.admit(id, w1, ROLE_WORKER);
        vm.prank(w3);
        reg.admit(id, w1, ROLE_WORKER);
    }

    // ------------------------------------------------------------------ account

    function test_setAccountOnceAndBindingChecked() public {
        bytes32 id = formAndActivate();
        SwarmAccount acct = new SwarmAccount(reg, id);
        SwarmAccount other = new SwarmAccount(reg, keccak256("other"));
        vm.prank(coord);
        vm.expectRevert(SAI_AccountMismatch.selector);
        reg.setAccount(id, address(other));
        vm.prank(coord);
        vm.expectRevert(SAI_AccountMismatch.selector);
        reg.setAccount(id, stranger);
        vm.prank(coord);
        reg.setAccount(id, address(acct));
        assertEq(reg.getSwarm(id).account, address(acct));
        vm.prank(coord);
        vm.expectRevert(SAI_AccountSet.selector);
        reg.setAccount(id, address(acct));
        // only a REPRESENT-authorized member may act through the account
        vm.deal(address(acct), 1 ether);
        vm.prank(w1);
        vm.expectRevert(SwarmAccount.SwarmAccount_NotRepresentative.selector);
        acct.execute(w1, 0.5 ether, "");
        vm.prank(coord);
        acct.execute(w1, 0.5 ether, "");
        assertEq(w1.balance, 0.5 ether);
    }

    // ------------------------------------------------------------------ resources

    function test_attachDetachAndAdapterVerification() public {
        SkillAdapterStub adapter = new SkillAdapterStub();
        bytes32[] memory kinds = new bytes32[](1); kinds[0] = adapter.KIND();
        address[] memory adapters = new address[](1); adapters[0] = address(adapter);
        reg = new SwarmRegistry(kinds, adapters);
        assertEq(reg.resourceAdapterOf(adapter.KIND()), address(adapter));
        bytes32 id = formAndActivate();

        T.ResourceInput memory r = T.ResourceInput({
            kind: adapter.KIND(), chainId: block.chainid, target: address(0xCAFE), id: 7,
            digest: keccak256(abi.encode("skill", uint256(7))), digestKind: adapter.SHA256_KIND(),
            uri: "ipfs://skill7", roleId: ROLE_WORKER, provider: address(0xBEEF)
        });
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.attach(id, r);
        vm.prank(coord);
        bytes32 rid = reg.attach(id, r);
        T.Resource memory stored = reg.getResource(id, rid);
        assertEq(stored.digest, r.digest);
        assertEq(stored.provider, address(0xBEEF));
        assertEq(stored.attachedBy, coord);
        assertEq(reg.resourceCount(id), 1);
        assertEq(reg.resourceAt(id, 0), rid);

        r.id = 500; // anchor does not exist
        vm.prank(coord);
        vm.expectRevert(SAI_AnchorMissing.selector);
        reg.attach(id, r);
        r.id = 8; // digest does not match what the anchor reports
        vm.prank(coord);
        vm.expectRevert(SAI_DigestMismatch.selector);
        reg.attach(id, r);
        r.digest = keccak256(abi.encode("skill", uint256(8)));
        r.digestKind = keccak256("keccak256"); // wrong digest kind
        vm.prank(coord);
        vm.expectRevert(SAI_DigestMismatch.selector);
        reg.attach(id, r);

        // an unanchored resource of a verified kind is accepted on its commitment alone
        T.ResourceInput memory doc = T.ResourceInput({
            kind: keccak256("sai.resource.document"), chainId: 0, target: address(0), id: 0,
            digest: keccak256("doc"), digestKind: keccak256("sha-256"), uri: "ipfs://doc", roleId: bytes32(0), provider: address(0)
        });
        vm.prank(coord);
        bytes32 did = reg.attach(id, doc);
        vm.prank(coord);
        reg.detach(id, did);
        assertTrue(reg.getResource(id, did).detached);
        vm.prank(coord);
        vm.expectRevert(SAI_Detached.selector);
        reg.detach(id, did);
        vm.prank(coord);
        vm.expectRevert(SAI_UnknownResource.selector);
        reg.detach(id, keccak256("nope"));
        doc.digest = bytes32(0);
        vm.prank(coord);
        vm.expectRevert(SAI_ZeroDigest.selector);
        reg.attach(id, doc);
        doc.digest = keccak256("doc"); doc.roleId = keccak256("nope");
        vm.prank(coord);
        vm.expectRevert(SAI_UnknownRole.selector);
        reg.attach(id, doc);
    }

    event Contribution(bytes32 indexed swarmId, address indexed contributor, uint32 indexed phase,
                       bytes32 contributionHash, string uri, uint32 charterVersion, bool isMember, bool whileSuspended);
    event MemberExited(bytes32 indexed swarmId, address indexed account, T.ExitReason reason, bool onAmendment, address by);
}
