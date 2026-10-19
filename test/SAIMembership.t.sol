// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIBase, T} from "./SAIBase.t.sol";
import "../assets/erc-8447/contracts/SAIErrors.sol";
import {AllowlistEligibility} from "../assets/erc-8447/contracts/modules/AllowlistEligibility.sol";

contract RevertingModule {
    function isEligible(bytes32, bytes32, address) external pure returns (bool) { revert("module down"); }
}

contract SwitchableModule {
    bool public reverting;
    mapping(address => bool) public allowed;
    function setReverting(bool v) external { reverting = v; }
    function setAllowed(address a, bool v) external { allowed[a] = v; }
    function isEligible(bytes32, bytes32, address a) external view returns (bool) {
        if (reverting) revert("module down");
        return allowed[a];
    }
}

/// A registry read that needs a fixed, sizeable amount of gas (stands in for a trust or identity
/// registry lookup) and answers true.
contract CostlyOracle {
    uint256 public immutable rounds;
    constructor(uint256 rounds_) { rounds = rounds_; }
    function check(address) external view returns (bool) {
        bytes32 x;
        for (uint256 i = 0; i < rounds; i++) x = keccak256(abi.encode(x, i));
        return x != bytes32(0);
    }
}

/// The common third-party pattern Zealynx described: every registry read wrapped in try/catch,
/// `false` on failure. A caller that starves the inner read can make it answer `false`.
contract CatchingModule {
    CostlyOracle public immutable oracle;
    constructor(CostlyOracle o) { oracle = o; }
    function isEligible(bytes32, bytes32, address a) external view returns (bool) {
        try oracle.check(a) returns (bool v) { return v; } catch { return false; }
    }
}

/// Minimal ERC-1271 account controlled by one EOA key.
contract Wallet1271 {
    address public immutable signer;
    constructor(address signer_) { signer = signer_; }
    function isValidSignature(bytes32 digest, bytes calldata sig) external view returns (bytes4) {
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(sig, (bytes32, bytes32, uint8));
        return ecrecover(digest, v, r, s) == signer ? bytes4(0x1626ba7e) : bytes4(0);
    }
}

contract SAIMembershipTest is SAIBase {
    AllowlistEligibility list;

    function setUp() public override {
        super.setUp();
        list = new AllowlistEligibility(address(this));
    }

    function specWithModule() internal view returns (T.SwarmSpec memory spec) {
        spec = defaultSpec();
        spec.roles[1].eligibility = address(list);
    }

    // ------------------------------------------------------------------ two-sided admission

    function test_admitThenAccept() public {
        bytes32 id = formDefault();
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.admit(id, w1, ROLE_WORKER);
        vm.prank(coord);
        reg.admit(id, w1, ROLE_WORKER);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.CANDIDATE));
        (,, uint32 cand) = reg.memberCount(id);
        assertEq(cand, 1);
        vm.prank(w1);
        vm.expectRevert(SAI_StaleCharter.selector);
        reg.acceptCharter(id, CHARTER2);
        vm.prank(w1);
        reg.acceptCharter(id, CHARTER1);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        (uint32 a,, uint32 c) = reg.memberCount(id);
        assertEq(a, 1); assertEq(c, 0);
        (uint32 ra,) = reg.roleCount(id, ROLE_WORKER);
        assertEq(ra, 1);
        (bytes32 h, uint32 cv, uint32 mv) = reg.acceptedCharterOf(id, w1);
        assertEq(h, CHARTER1); assertEq(cv, 1); assertEq(mv, 1);
    }

    function test_applyThenAdmit() public {
        bytes32 id = formDefault();
        vm.prank(w1);
        reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.CANDIDATE));
        vm.prank(coord);
        vm.expectRevert(SAI_RoleMismatch.selector);
        reg.admit(id, w1, ROLE_COORD);
        vm.prank(coord);
        reg.admit(id, w1, ROLE_WORKER);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
    }

    function test_joinRefusedInGatedPhase() public {
        bytes32 id = formDefault();
        vm.prank(w1);
        vm.expectRevert(SAI_Gated.selector);
        reg.join(id, ROLE_WORKER, CHARTER1);
    }

    function test_joinInOpenPhaseWithSelfJoin() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.phases[0].boundary = T.Boundary.OPEN;
        spec.roles[1].selfJoin = true;
        bytes32 id = formWith(spec, defaultObjective());
        vm.prank(w1);
        reg.join(id, ROLE_WORKER, CHARTER1);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        // the coordinator role has selfJoin false: join refused, apply allowed
        vm.prank(coord);
        vm.expectRevert(SAI_Gated.selector);
        reg.join(id, ROLE_COORD, CHARTER1);
        vm.prank(coord);
        reg.applyToJoin(id, ROLE_COORD, CHARTER1);
        assertEq(uint8(status(id, coord)), uint8(T.MemberStatus.CANDIDATE));
    }

    function test_candidateCannotHoldTwoSeatsAndSeatTaken() public {
        bytes32 id = formDefault();
        admitAndAccept(id, w1, ROLE_WORKER);
        vm.prank(coord);
        vm.expectRevert(SAI_SeatTaken.selector);
        reg.admit(id, w1, ROLE_COORD);
        vm.prank(w1);
        vm.expectRevert(SAI_SeatTaken.selector);
        reg.applyToJoin(id, ROLE_COORD, CHARTER1);
    }

    function test_rosterCapsAndUnknownRole() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.maxMembers = 2;
        bytes32 id = formWith(spec, defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        vm.prank(coord);
        vm.expectRevert(SAI_RoleFull.selector); // coordinator max 1
        reg.admit(id, w1, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        vm.prank(coord);
        vm.expectRevert(SAI_SwarmFull.selector);
        reg.admit(id, w2, ROLE_WORKER);
        vm.prank(coord);
        vm.expectRevert(SAI_UnknownRole.selector);
        reg.admit(id, w2, keccak256("nope"));
    }

    function test_acceptCharterRequiresSeat() public {
        bytes32 id = formDefault();
        vm.prank(w1);
        vm.expectRevert(SAI_NoSeat.selector);
        reg.acceptCharter(id, CHARTER1);
    }

    // ------------------------------------------------------------------ eligibility

    function test_eligibilityAtAdmission() public {
        bytes32 id = formWith(specWithModule(), defaultObjective());
        vm.prank(coord);
        reg.admit(id, w1, ROLE_WORKER);
        vm.prank(w1);
        vm.expectRevert(SAI_Ineligible.selector); // evaluated at completion
        reg.acceptCharter(id, CHARTER1);
        list.setAllowed(w1, true);
        vm.prank(w1);
        reg.acceptCharter(id, CHARTER1);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
    }

    function test_challengeExpelReinstate() public {
        list.setAllowed(w1, true);
        bytes32 id = formWith(specWithModule(), defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        // the coordinator role has no module
        vm.expectRevert(SAI_NoModule.selector);
        reg.challenge(id, coord);
        (bool ev, bool ok) = reg.challenge(id, w1);
        assertTrue(ev && ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        list.setAllowed(w1, false);
        vm.prank(stranger);
        (ev, ok) = reg.challenge(id, w1);
        assertTrue(ev); assertFalse(ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        assertEq(uint8(reg.getMember(id, w1).suspension), uint8(T.SuspensionCause.INELIGIBLE));
        (uint32 a, uint32 su,) = reg.memberCount(id);
        assertEq(a, 1); assertEq(su, 1);
        // reinstatement re-evaluates the module
        vm.prank(coord);
        vm.expectRevert(SAI_Ineligible.selector);
        reg.reinstate(id, w1);
        // expulsion after the grace period, by anyone
        vm.prank(stranger);
        vm.expectRevert(SAI_GraceRunning.selector);
        reg.expel(id, w1);
        vm.warp(block.timestamp + DAY + 1);
        vm.prank(stranger);
        reg.expel(id, w1);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.EXITED));
        assertEq(uint8(exitReason(id, w1)), uint8(T.ExitReason.INELIGIBLE));
        assertEq(reg.seatEpochOf(id, w1), 1);
    }

    function test_reinstateAfterEligibilityReturnsAndResumesRoster() public {
        list.setAllowed(w1, true);
        bytes32 id = formWith(specWithModule(), defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        list.setAllowed(w1, false);
        reg.challenge(id, w1);
        reg.enforceRoster(id); // worker min 1 lost
        assertEq(uint8(state(id)), uint8(T.LifecycleState.SUSPENDED));
        list.setAllowed(w1, true);
        vm.prank(coord);
        reg.reinstate(id, w1); // judgment paths stay open while suspended
        assertTrue(reg.rosterMet(id));
        vm.prank(stranger); // ROSTER_LOST and the roster holds again: anyone resumes
        reg.resume(id);
        assertEq(uint8(state(id)), uint8(T.LifecycleState.ACTIVE));
    }

    function test_challengeWithRevertingModuleChangesNothing() public {
        RevertingModule bad = new RevertingModule();
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles[1].eligibility = address(bad);
        bytes32 id = formWith(spec, defaultObjective());
        vm.prank(coord);
        reg.admit(id, w1, ROLE_WORKER);
        vm.prank(w1);
        vm.expectRevert(SAI_Ineligible.selector); // a revert refuses admission
        reg.acceptCharter(id, CHARTER1);
    }

    function test_challengeUnevaluableOnLiveMember() public {
        SwitchableModule mod = new SwitchableModule();
        mod.setAllowed(w1, true);
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles[1].eligibility = address(mod);
        bytes32 id = formWith(spec, defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        uint64 revBefore = reg.getSwarm(id).revision;
        mod.setReverting(true);
        (bool ev, bool ok) = reg.challenge(id, w1); // the module reverts: unevaluable, nothing changes
        assertFalse(ev); assertFalse(ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        assertEq(reg.getSwarm(id).revision, revBefore);
        mod.setReverting(false);
        mod.setAllowed(w1, false);
        (ev, ok) = reg.challenge(id, w1);
        assertTrue(ev); assertFalse(ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
    }

    function test_challengeGasStarvedCatchingModuleIsUnevaluable() public {
        // an inner read costing a few million gas: a composite over several registries, say
        CatchingModule mod = new CatchingModule(new CostlyOracle(15_000));
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles[1].eligibility = address(mod);
        bytes32 id = formWith(spec, defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        // with ample gas the module evaluates and the member is eligible
        (bool ev, bool ok) = reg.challenge{gas: 12_000_000}(id, w1);
        assertTrue(ev && ok);
        // a challenger sweeps gas limits: the inner read runs out for some of them, the module
        // answers false with one sixty-fourth of its budget kept, and that is enough for the registry
        // to record a suspension; the registry treats every such answer as unevaluable instead
        uint256 starved;
        for (uint256 g = 300_000; g <= 4_000_000; g += 100_000) {
            vm.prank(stranger);
            (bool ok2, bytes memory ret) = address(reg).call{gas: g}(abi.encodeCall(reg.challenge, (id, w1)));
            if (!ok2) continue; // the registry itself ran out of gas: no answer at all
            (bool ev2, bool el2) = abi.decode(ret, (bool, bool));
            if (!ev2) starved++;
            else assertTrue(el2, "an evaluated answer under starvation would be wrong");
            assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE), "honest member suspended");
        }
        assertGt(starved, 0, "the sweep never hit the starved window");
    }

    function test_challengeReinstatesOnEvidence() public {
        SwitchableModule mod = new SwitchableModule();
        mod.setAllowed(w1, true);
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles[1].eligibility = address(mod);
        bytes32 id = formWith(spec, defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        mod.setAllowed(w1, false);
        reg.challenge(id, w1);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        // still false: evaluated, stays suspended
        vm.prank(stranger);
        (bool ev, bool ok) = reg.challenge(id, w1);
        assertTrue(ev); assertFalse(ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        // unevaluable: stays suspended
        mod.setReverting(true);
        (ev, ok) = reg.challenge(id, w1);
        assertFalse(ev);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        // the identity comes back: anyone's challenge reinstates, no authority needed
        mod.setReverting(false);
        mod.setAllowed(w1, true);
        vm.prank(stranger);
        (ev, ok) = reg.challenge(id, w1);
        assertTrue(ev && ok);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        (uint32 a, uint32 su,) = reg.memberCount(id);
        assertEq(a, 2); assertEq(su, 0);
        // a suspension on judgment is not a question for the module
        vm.prank(coord);
        reg.suspendMember(id, w1);
        vm.expectRevert(SAI_NotMember.selector);
        reg.challenge(id, w1);
    }

    function test_expelReevaluatesTheModule() public {
        SwitchableModule mod = new SwitchableModule();
        mod.setAllowed(w1, true);
        T.SwarmSpec memory spec = defaultSpec();
        spec.roles[1].eligibility = address(mod);
        bytes32 id = formWith(spec, defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        mod.setAllowed(w1, false);
        reg.challenge(id, w1);
        vm.warp(block.timestamp + DAY + 1);
        // the identity lapsed for a day and came back; nobody reinstated in time
        mod.setAllowed(w1, true);
        vm.prank(stranger);
        reg.expel(id, w1); // re-adjudicates on current evidence: reinstated, not expelled
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        assertEq(reg.seatEpochOf(id, w1), 0);
        // lapses again; an unevaluable module decides nothing and says so
        mod.setAllowed(w1, false);
        reg.challenge(id, w1);
        vm.warp(block.timestamp + DAY + 1);
        mod.setReverting(true);
        vm.expectRevert(SAI_Unevaluable.selector);
        reg.expel(id, w1);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.SUSPENDED));
        // still ineligible on evidence: expelled
        mod.setReverting(false);
        vm.prank(stranger);
        reg.expel(id, w1);
        assertEq(uint8(exitReason(id, w1)), uint8(T.ExitReason.INELIGIBLE));
    }

    // ------------------------------------------------------------------ departure, removal, substitution

    function test_leaveAlwaysAndRemoveAuthorities() public {
        bytes32 id = formAndActivate();
        admitAndAccept(id, w2, ROLE_WORKER);
        vm.prank(w3);
        reg.applyToJoin(id, ROLE_WORKER, CHARTER1);
        // a candidate is dropped by the ADMIT authority, not REMOVE
        vm.prank(coord);
        reg.remove(id, w3);
        assertEq(uint8(status(id, w3)), uint8(T.MemberStatus.EXITED));
        assertEq(uint8(exitReason(id, w3)), uint8(T.ExitReason.REMOVED));
        vm.prank(stranger);
        vm.expectRevert(SAI_NotAuthorized.selector);
        reg.remove(id, w2);
        vm.prank(coord);
        reg.suspendMember(id, w2);
        assertEq(uint8(status(id, w2)), uint8(T.MemberStatus.SUSPENDED));
        vm.prank(coord);
        reg.reinstate(id, w2);
        assertEq(uint8(status(id, w2)), uint8(T.MemberStatus.ACTIVE));
        vm.prank(coord);
        reg.remove(id, w2);
        assertEq(uint8(exitReason(id, w2)), uint8(T.ExitReason.REMOVED));
        vm.prank(w1);
        reg.leave(id);
        assertEq(uint8(exitReason(id, w1)), uint8(T.ExitReason.LEFT));
        vm.prank(w1);
        vm.expectRevert(SAI_NoSeat.selector);
        reg.leave(id);
        // re-admission opens a new seat
        admitAndAccept(id, w1, ROLE_WORKER);
        assertEq(uint8(status(id, w1)), uint8(T.MemberStatus.ACTIVE));
        assertEq(reg.seatEpochOf(id, w1), 1);
    }

    function test_substituteWorksInClosedPhase() public {
        T.SwarmSpec memory spec = defaultSpec();
        spec.phases = new T.PhaseSpec[](2);
        spec.phases[0] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.GATED, T.Admission.RECRUIT, 0);
        spec.phases[1] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.CLOSED, T.Admission.INHERIT, 0);
        bytes32 id = formWith(spec, defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        admitAndAccept(id, w1, ROLE_WORKER);
        reg.activate(id);
        vm.prank(coord);
        reg.advance(id, new address[](0), new bytes32[](0));
        // the phase is CLOSED: no admission, but substitution completes
        vm.prank(coord);
        vm.expectRevert(SAI_BoundaryClosed.selector);
        reg.admit(id, w2, ROLE_WORKER);
        vm.prank(coord);
        reg.substitute(id, w1, w2);
        assertEq(uint8(exitReason(id, w1)), uint8(T.ExitReason.REPLACED));
        assertEq(uint8(status(id, w2)), uint8(T.MemberStatus.CANDIDATE));
        assertTrue(reg.getMember(id, w2).substituted);
        vm.prank(w2);
        reg.acceptCharter(id, CHARTER1);
        assertEq(uint8(status(id, w2)), uint8(T.MemberStatus.ACTIVE));
        (uint32 a,,) = reg.memberCount(id);
        assertEq(a, 2);
        vm.prank(coord);
        vm.expectRevert(SAI_SuccessorHasSeat.selector);
        reg.substitute(id, w2, coord);
    }

    // ------------------------------------------------------------------ signed acceptance

    function signJoin(uint256 pk, bytes32 id, address account, bytes32 roleId, bytes32 charter, uint256 deadline)
        internal view returns (bytes memory)
    {
        bytes32 digest = reg.joinDigest(id, account, roleId, charter, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_joinBySigEOA_appliesInGatedPhase() public {
        (address agent, uint256 pk) = makeAddrAndKey("agent");
        bytes32 id = formDefault();
        uint256 deadline = block.timestamp + DAY;
        bytes memory sig = signJoin(pk, id, agent, ROLE_WORKER, CHARTER1, deadline);
        vm.prank(stranger); // anyone relays
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, deadline, sig);
        assertEq(uint8(status(id, agent)), uint8(T.MemberStatus.CANDIDATE)); // gated: applied
        vm.prank(coord);
        reg.admit(id, agent, ROLE_WORKER);
        assertEq(uint8(status(id, agent)), uint8(T.MemberStatus.ACTIVE));
        // replay: the seat is live, so the account already holds a seat
        vm.expectRevert(SAI_SeatTaken.selector);
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, deadline, sig);
        // after leaving, the epoch changed: the old signature is invalid
        vm.prank(agent);
        reg.leave(id);
        vm.expectRevert(SAI_BadSignature.selector);
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, deadline, sig);
        // a fresh signature works again
        bytes memory sig2 = signJoin(pk, id, agent, ROLE_WORKER, CHARTER1, deadline);
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, deadline, sig2);
        assertEq(uint8(status(id, agent)), uint8(T.MemberStatus.CANDIDATE));
    }

    function test_joinBySigOpenPhaseActivatesAndRejectsExpiredOrWrongCharter() public {
        (address agent, uint256 pk) = makeAddrAndKey("agent");
        T.SwarmSpec memory spec = defaultSpec();
        spec.phases[0].boundary = T.Boundary.OPEN;
        spec.roles[1].selfJoin = true;
        bytes32 id = formWith(spec, defaultObjective());
        uint256 deadline = block.timestamp + DAY;
        bytes memory expired = signJoin(pk, id, agent, ROLE_WORKER, CHARTER1, block.timestamp - 1);
        vm.expectRevert(SAI_SignatureExpired.selector);
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, block.timestamp - 1, expired);
        bytes memory wrong = signJoin(pk, id, agent, ROLE_WORKER, CHARTER2, deadline);
        vm.expectRevert(SAI_BadSignature.selector); // digest over CHARTER2 does not match the CHARTER1 call
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, deadline, wrong);
        bytes memory sig = signJoin(pk, id, agent, ROLE_WORKER, CHARTER1, deadline);
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, deadline, sig);
        assertEq(uint8(status(id, agent)), uint8(T.MemberStatus.ACTIVE));
    }

    function test_joinBySigContractAccount() public {
        (address signer, uint256 pk) = makeAddrAndKey("signer");
        Wallet1271 wallet = new Wallet1271(signer);
        bytes32 id = formDefault();
        uint256 deadline = block.timestamp + DAY;
        bytes32 digest = reg.joinDigest(id, address(wallet), ROLE_WORKER, CHARTER1, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory sig = abi.encode(r, s, v);
        reg.joinBySig(id, address(wallet), ROLE_WORKER, CHARTER1, deadline, sig);
        assertEq(uint8(status(id, address(wallet))), uint8(T.MemberStatus.CANDIDATE));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(pk, keccak256("other"));
        vm.expectRevert(SAI_BadSignature.selector);
        reg.joinBySig(id, address(wallet), ROLE_COORD, CHARTER1, deadline, abi.encode(r2, s2, v2));
    }

    function test_signatureBoundToPhase() public {
        (address agent, uint256 pk) = makeAddrAndKey("agent");
        T.SwarmSpec memory spec = defaultSpec();
        spec.phases = new T.PhaseSpec[](2);
        spec.phases[0] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.OPEN, T.Admission.RECRUIT, 0);
        spec.phases[1] = phase(P_SHARED, T_PARTITIONED, C_LEADER, T.Boundary.OPEN, T.Admission.RECRUIT, 0);
        spec.roles[1].selfJoin = true;
        bytes32 id = formWith(spec, defaultObjective());
        admitAndAccept(id, coord, ROLE_COORD);
        uint256 deadline = block.timestamp + 10 * DAY;
        bytes memory sig = signJoin(pk, id, agent, ROLE_WORKER, CHARTER1, deadline);
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, deadline, sig);
        reg.activate(id);
        vm.prank(coord);
        reg.advance(id, new address[](0), new bytes32[](0)); // RECRUIT: everyone exits lazily
        assertEq(uint8(status(id, agent)), uint8(T.MemberStatus.EXITED));
        assertEq(uint8(exitReason(id, agent)), uint8(T.ExitReason.NOT_CARRIED));
        // the old signature was for phase 0; replaying it in phase 1 fails
        vm.expectRevert(SAI_BadSignature.selector);
        reg.joinBySig(id, agent, ROLE_WORKER, CHARTER1, deadline, sig);
    }
}
