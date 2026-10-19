// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIBase, T} from "./SAIBase.t.sol";
import {ISwarmRegistry} from "../assets/erc-8447/contracts/interfaces/ISwarmRegistry.sol";
import {IEligibility} from "../assets/erc-8447/contracts/interfaces/IEligibility.sol";
import {ISwarmAccount} from "../assets/erc-8447/contracts/interfaces/ISwarmAccount.sol";
import {IResourceAdapter} from "../assets/erc-8447/contracts/interfaces/IResourceAdapter.sol";

/// Re-derives the vectors produced by tools/vectors.js (ethers v6) in Solidity.
contract SAIVectorsTest is SAIBase {
    string constant DIR = "assets/erc-8447/vectors/";

    address constant COORD = 0x1111111111111111111111111111111111111111;
    address constant ADAPTER = 0x2222222222222222222222222222222222222222;

    function read(string memory file) internal view returns (string memory) {
        return vm.readFile(string.concat(DIR, file));
    }

    function vectorAllAddress(address a) internal pure returns (T.Authority[] memory auths) {
        auths = new T.Authority[](16);
        for (uint256 i = 0; i < 16; i++) auths[i] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: a, roleId: bytes32(0)});
        auths[15] = T.Authority({kind: T.AuthorityKind.ROLE, target: address(0), roleId: keccak256("sai.role.coordinator")});
    }

    function specMinimal() internal pure returns (T.SwarmSpec memory spec) {
        spec.roles = new T.RoleSpec[](2);
        spec.roles[0] = T.RoleSpec(keccak256("sai.role.coordinator"), 1, 1, address(0), false);
        spec.roles[1] = T.RoleSpec(keccak256("sai.role.worker"), 1, 0, address(0), false);
        spec.phases = new T.PhaseSpec[](1);
        spec.phases[0] = T.PhaseSpec(bytes32("execution"), keccak256("sai.payoff.shared"), keccak256("sai.topology.partitioned"),
            keccak256("sai.coordination.leader"), T.Boundary.GATED, T.Admission.RECRUIT, 0, bytes32(0));
        spec.authorities = vectorAllAddress(COORD);
        spec.activation = T.Activation.ROSTER_MET;
        spec.contributions = T.Contributions.MEMBERS;
        spec.minMembers = 2; spec.maxMembers = 0;
        spec.recruitmentWindow = 7 days; spec.maxDuration = 30 days; spec.inactivityTimeout = 0;
        spec.ineligibleGrace = 1 days; spec.settlementWindow = 1 days; spec.amendmentExitWindow = 2 days;
        spec.descriptorHash = bytes32(0);
    }

    function specTender() internal pure returns (T.SwarmSpec memory spec) {
        spec.roles = new T.RoleSpec[](4);
        spec.roles[0] = T.RoleSpec(keccak256("sai.role.coordinator"), 1, 1, address(0), true);
        spec.roles[1] = T.RoleSpec(keccak256("sai.role.verifier"), 2, 2, address(0), true);
        spec.roles[2] = T.RoleSpec(keccak256("sai.role.bidder"), 0, 0, address(0), true);
        spec.roles[3] = T.RoleSpec(keccak256("sai.role.worker"), 0, 2, COORD, false);
        spec.phases = new T.PhaseSpec[](2);
        spec.phases[0] = T.PhaseSpec(bytes32("bidding"), keccak256("sai.payoff.exclusive"), keccak256("sai.topology.redundant"),
            keccak256("sai.coordination.collective"), T.Boundary.OPEN, T.Admission.RECRUIT, 2 days, keccak256("bidding"));
        spec.phases[1] = T.PhaseSpec(bytes32("execution"), keccak256("sai.payoff.shared"), keccak256("sai.topology.partitioned"),
            keccak256("sai.coordination.leader"), T.Boundary.CLOSED, T.Admission.SELECT, 0, keccak256("execution"));
        spec.authorities = vectorAllAddress(COORD);
        spec.authorities[4] = T.Authority({kind: T.AuthorityKind.ADDRESS, target: ADAPTER, roleId: bytes32(0)});
        spec.activation = T.Activation.ROSTER_MET;
        spec.contributions = T.Contributions.OPEN;
        spec.minMembers = 3; spec.maxMembers = 0;
        spec.recruitmentWindow = 7 days; spec.maxDuration = 90 days; spec.inactivityTimeout = 14 days;
        spec.ineligibleGrace = 1 days; spec.settlementWindow = 1 days; spec.amendmentExitWindow = 2 days;
        spec.descriptorHash = keccak256("spec");
    }

    function test_specHashVectors() public view {
        string memory json = read("spec-hash.json");
        T.SwarmSpec[2] memory specs = [specMinimal(), specTender()];
        for (uint256 i = 0; i < 2; i++) {
            string memory p = string.concat(".vectors[", vm.toString(i), "]");
            bytes memory encoding = vm.parseJsonBytes(json, string.concat(p, ".encoding"));
            bytes32 expected = vm.parseJsonBytes32(json, string.concat(p, ".specHash"));
            assertEq(keccak256(abi.encode(specs[i])), expected, "specHash");
            assertEq(keccak256(abi.encode(specs[i])), keccak256(encoding), "encoding");
            assertEq(reg.specHashOf(specs[i]), expected, "specHashOf");
        }
    }

    function test_joinDigestVectors() public view {
        string memory json = read("join-digest.json");
        bytes32 typeHash = keccak256("Join(bytes32 swarmId,address account,bytes32 roleId,bytes32 charterHash,uint256 seatEpoch,uint32 phase,uint256 deadline)");
        assertEq(vm.parseJsonBytes32(json, ".typeHash"), typeHash);
        bytes32 domain = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("SAI"), keccak256("1"), uint256(1), 0x3333333333333333333333333333333333333333));
        for (uint256 i = 0; i < 3; i++) {
            string memory p = string.concat(".vectors[", vm.toString(i), "].value");
            bytes32 structHash = keccak256(abi.encode(typeHash,
                vm.parseJsonBytes32(json, string.concat(p, ".swarmId")),
                vm.parseJsonAddress(json, string.concat(p, ".account")),
                vm.parseJsonBytes32(json, string.concat(p, ".roleId")),
                vm.parseJsonBytes32(json, string.concat(p, ".charterHash")),
                vm.parseJsonUint(json, string.concat(p, ".seatEpoch")),
                uint32(vm.parseJsonUint(json, string.concat(p, ".phase"))),
                vm.parseJsonUint(json, string.concat(p, ".deadline"))));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
            assertEq(digest, vm.parseJsonBytes32(json, string.concat(".vectors[", vm.toString(i), "].digest")), "digest");
        }
    }

    function test_registryDigestMatchesTheConvention() public {
        // the live registry's digest for epoch 0, phase 0 equals the manual computation with its own domain
        bytes32 id = formDefault();
        uint256 deadline = block.timestamp + 1 days;
        bytes32 typeHash = keccak256("Join(bytes32 swarmId,address account,bytes32 roleId,bytes32 charterHash,uint256 seatEpoch,uint32 phase,uint256 deadline)");
        bytes32 domain = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("SAI"), keccak256("1"), block.chainid, address(reg)));
        bytes32 structHash = keccak256(abi.encode(typeHash, id, w1, ROLE_WORKER, CHARTER1, uint256(0), uint32(0), deadline));
        assertEq(reg.joinDigest(id, w1, ROLE_WORKER, CHARTER1, deadline), keccak256(abi.encodePacked("\x19\x01", domain, structHash)));
    }

    function test_termIdVectors() public view {
        string memory json = read("term-ids.json");
        assertEq(vm.parseJsonBytes32(json, ".dimensions.payoff"), T.DIM_PAYOFF);
        assertEq(vm.parseJsonBytes32(json, ".dimensions.topology"), T.DIM_TOPOLOGY);
        assertEq(vm.parseJsonBytes32(json, ".dimensions.coordination"), T.DIM_COORDINATION);
        assertEq(vm.parseJsonBytes32(json, ".terms.payoff.shared"), keccak256("sai.payoff.shared"));
        assertEq(vm.parseJsonBytes32(json, ".terms.coordination.none"), keccak256("sai.coordination.none"));
        assertEq(vm.parseJsonBytes32(json, ".roles.initiator"), keccak256("sai.role.initiator"));
        assertEq(vm.parseJsonBytes32(json, ".origins.succession"), keccak256("sai.origin.succession"));
        assertEq(vm.parseJsonBytes32(json, ".resourceKinds.skill"), keccak256("sai.resource.skill"));
        assertEq(vm.parseJsonBytes32(json, ".decisionPointQuestions.admit.question"), keccak256("sai.dp.admit"));
        assertEq(vm.parseJsonUint(json, ".decisionPointQuestions.represent.index"), uint256(T.DecisionPoint.REPRESENT));
        assertEq(vm.parseJsonBytes32(json, ".effects.enact"), keccak256("sai.enact"));
        // every base term is registered in a fresh registry
        assertTrue(reg.isTerm(T.DIM_PAYOFF, keccak256("sai.payoff.mixed")));
        assertTrue(reg.isTerm(T.DIM_TOPOLOGY, keccak256("sai.topology.iterative")));
        assertTrue(reg.isTerm(T.DIM_COORDINATION, keccak256("sai.coordination.market")));
        assertFalse(reg.isTerm(T.DIM_PAYOFF, keccak256("sai.topology.free")));
    }

    function test_interfaceIdVectors() public view {
        string memory json = read("interface-ids.json");
        assertEq(id4(json, ".interfaces.ISwarmRegistry"), type(ISwarmRegistry).interfaceId);
        assertEq(id4(json, ".interfaces.IEligibility"), type(IEligibility).interfaceId);
        assertEq(id4(json, ".interfaces.ISwarmAccount"), type(ISwarmAccount).interfaceId);
        assertEq(id4(json, ".interfaces.IResourceAdapter"), type(IResourceAdapter).interfaceId);
    }

    function id4(string memory json, string memory key) internal pure returns (bytes4) {
        bytes memory b = vm.parseJsonBytes(json, key);
        require(b.length == 4, "id length");
        return bytes4(b);
    }
}
