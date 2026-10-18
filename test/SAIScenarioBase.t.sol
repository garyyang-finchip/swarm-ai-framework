// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAIBase, T} from "./SAIBase.t.sol";
import {ISwarmRegistry} from "../assets/erc-sai/contracts/interfaces/ISwarmRegistry.sol";
import {SwarmDecisionAdapter} from "../assets/erc-sai/contracts/adapters/SwarmDecisionAdapter.sol";
import {SwarmTenderAdapter} from "../assets/erc-sai/contracts/adapters/SwarmTenderAdapter.sol";
import {IACDFRegistry} from "../assets/erc-sai/contracts/adapters/interfaces/IACDFRegistry.sol";
import {ITaskTenderKernel} from "../assets/erc-sai/contracts/adapters/interfaces/ITaskTenderKernel.sol";
import {ACDFTypes as A} from "../assets/erc-sai/contracts/adapters/interfaces/ACDFTypes.sol";
import {SwarmAccount} from "../assets/erc-sai/contracts/account/SwarmAccount.sol";
import {AllowlistEligibility} from "../assets/erc-sai/contracts/modules/AllowlistEligibility.sol";
// real kernels, vendored unmodified
import {ACDFPolicyRegistry} from "./fixtures/acdf/ACDFPolicyRegistry.sol";
import {ACDFRegistry} from "./fixtures/acdf/ACDFRegistry.sol";
import {IACDFPolicyRegistry as FixturePolicies} from "./fixtures/acdf/interfaces/IACDFPolicyRegistry.sol";
import {TaskToken} from "./fixtures/task-token/TaskToken.sol";
import {ITaskTender} from "./fixtures/task-token/interfaces/ITaskTender.sol";

/// Deploys the real ERC-8436 registries and the real task tender kernel next to the swarm registry.
abstract contract SAIScenarioBase is SAIBase {
    ACDFPolicyRegistry policies;
    ACDFRegistry acdf;
    IACDFRegistry dec; // the same registry seen through the adapter's vendored interface types
    TaskToken task;
    AllowlistEligibility list;

    address sponsor = makeAddr("sponsor");
    address c1 = makeAddr("c1");
    address c2 = makeAddr("c2");
    address c3 = makeAddr("c3");

    function setUp() public virtual override {
        super.setUp();
        policies = new ACDFPolicyRegistry();
        acdf = new ACDFRegistry(FixturePolicies(address(policies)));
        dec = IACDFRegistry(address(acdf));
        task = new TaskToken("Task Tender", "TASK");
        list = new AllowlistEligibility(address(this));
    }

    function newDecisionAdapter(bytes32 decidingRole, uint32 num, uint32 den, uint64 window) internal returns (SwarmDecisionAdapter) {
        return new SwarmDecisionAdapter(ISwarmRegistry(address(reg)), IACDFRegistry(address(acdf)), decidingRole, num, den, window, 1 hours);
    }

    /// Mints and funds a native-currency tender judged by `judge`, settling within 60 days.
    function mintTender(uint256 reward) internal returns (uint256 tokenId) {
        ITaskTender.TenderTerms memory terms = ITaskTender.TenderTerms({
            asset: address(0), rewardPerCompletion: reward, maxCompletions: 1, submitBy: 0,
            settleBy: uint64(block.timestamp + 60 * DAY), epochLength: 0, maxCompletionsPerEpoch: 0, judgmentWindow: 7 * DAY
        });
        vm.deal(sponsor, 10 ether);
        vm.startPrank(sponsor);
        tokenId = task.mintTask(sponsor, sponsor, judge, keccak256("td"), keccak256("task"), "ipfs://task", terms);
        task.fundTask{value: reward}(tokenId, reward);
        vm.stopPrank();
    }

    /// Everyone in `voters` approves (or blocks) the first round, then the round is settled.
    function vote(bytes32 issueId, address[] memory voters, bool approve) internal {
        for (uint256 i = 0; i < voters.length; i++) {
            vm.prank(voters[i]);
            acdf.castBallot(issueId, 1, 0, approve);
        }
        acdf.settleRound(issueId);
    }

    function roster3() internal view returns (address[] memory r) {
        r = new address[](3); r[0] = c1; r[1] = c2; r[2] = c3;
    }

    function roster2(address x, address y) internal pure returns (address[] memory r) {
        r = new address[](2); r[0] = x; r[1] = y;
    }
}
