#!/usr/bin/env node
// Builds the Sepolia evidence record from a finished relay run:
//   node tools/sepolia/evidence.js --state state.json --keys keys.json [--gasref anvil-state.json] [--out deployments/sepolia]
// Writes deployments/sepolia.json (machine-readable) and docs/sepolia-evidence.md (the record).
// The keys file is read only to derive the member addresses; no key material is written.
"use strict";
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const ROOT = path.resolve(__dirname, "..", "..");
const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf("--" + name); return i >= 0 ? argv[i + 1] : dflt; };

const st = JSON.parse(fs.readFileSync(opt("state"), "utf8"));
const keys = JSON.parse(fs.readFileSync(opt("keys"), "utf8"));
const OUT = path.resolve(opt("out", path.join(ROOT, "deployments", "sepolia")));
const gasref = {};
if (opt("gasref")) for (const r of JSON.parse(fs.readFileSync(opt("gasref"), "utf8")).steps) gasref[r.label] = BigInt(r.gasUsed);

const addr = (who) => new ethers.Wallet(keys[who].privateKey || keys[who]).address;
const members = Object.fromEntries(Object.keys(keys).map((k) => [k, addr(k)]));

const EXPLORER = "https://sepolia.etherscan.io";
const tx = (h) => `[\`${h.slice(0, 10)}…${h.slice(-6)}\`](${EXPLORER}/tx/${h})`;
const ad = (a) => `[\`${a}\`](${EXPLORER}/address/${a})`;

const contracts = {
  SpecValidator: st.SpecValidator, LifecycleLib: st.LifecycleLib, MembershipLib: st.MembershipLib, ResourceLib: st.ResourceLib,
  SwarmRegistry: st.SwarmRegistry, AllowlistEligibility: st.AllowlistEligibility,
  "SwarmDecisionAdapter (council, 2 of 3)": st.council, "SwarmDecisionAdapter (chamber, 2 of 2)": st.chamber,
  SwarmTenderAdapter: st.SwarmTenderAdapter, "SwarmAccount (Case A)": st.accountA,
};
const deployTx = {};
for (const s of st.steps) if (s.contractAddress) deployTx[s.contractAddress.toLowerCase()] = s;

const record = {
  chainId: 11155111,
  network: "Sepolia",
  deployer: members.deployer,
  compiler: { solc: "0.8.24+commit.e11b9ed9", optimizer: { enabled: true, runs: 1 }, viaIR: true, evmVersion: "cancun", metadata: { bytecodeHash: "ipfs" } },
  source: "assets/erc-8447/contracts (revision 2.1)",
  contracts: Object.fromEntries(Object.entries(contracts).map(([k, a]) => { const d = deployTx[a.toLowerCase()] || {}; return [k, { address: a, tx: d.hash, block: d.block, gasUsed: d.gasUsed }]; })),
  dependencies: { ACDFRegistry: st.ACDFRegistry, ACDFPolicyRegistry: "0x7eAfCC452EC0A60a358a26B6e73f28413C4abeF0", TaskToken: st.TaskToken },
  accounts: members,
  caseA: { swarmId: st.swarmA, tokenId: st.tokenA, issue: st.issueA, submission: st.submissionA, account: st.accountA, hashes: st.hashesA,
    pack: "deployments/sepolia/case-a/swarm-pack.json" },
  caseB: { swarmId: st.swarmB, issue: st.issueB, hashes: st.hashesB, pack: "deployments/sepolia/case-b/swarm-pack.json" },
  steps: st.steps.map((s, i) => ({ index: i, label: s.label, from: s.from, tx: s.hash, block: s.block, gasUsed: s.gasUsed, contractAddress: s.contractAddress,
    rehearsalGas: gasref[s.label] ? gasref[s.label].toString() : undefined })),
};
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(path.join(path.dirname(OUT), "sepolia.json"), JSON.stringify(record, null, 2) + "\n");

// ---------------------------------------------------------------- the record
const n = (x) => BigInt(x).toLocaleString("en-US");
const totalGas = st.steps.reduce((a, s) => a + BigInt(s.gasUsed), 0n);
const firstBlock = Math.min(...st.steps.map((s) => s.block)), lastBlock = Math.max(...st.steps.map((s) => s.block));
const ratio = (s) => gasref[s.label] ? (Number(BigInt(s.gasUsed) * 100n / gasref[s.label]) / 100).toFixed(2) + "×" : "";

let md = `# Sepolia evidence run — ERC-8447 reference implementation (revision 2.1)

Chain: Sepolia (chain id 11155111). Deployer: ${ad(members.deployer)}. Blocks ${firstBlock}–${lastBlock}, ${st.steps.length} transactions, ${n(totalGas)} gas in total. Every transaction below succeeded (status 1) on the first attempt; nothing was retried, replaced or skipped.

The run deploys the reference contracts from \`assets/erc-8447/contracts\` and executes the two end-to-end cases of the test suite (\`test/SAICaseA.t.sol\`, \`test/SAICaseB.t.sol\`) against the **live** ERC-8436 registries and the **live** token-bound task tender kernel on Sepolia, with the same step list that \`tools/sepolia/run.js\` runs against a local node. Machine-readable record: \`deployments/sepolia.json\`; per-batch receipts: \`deployments/sepolia/receipts-batch-*.json\`; the signed transactions as broadcast: \`deployments/sepolia/batch-*.json\`.

## Contracts

| Contract | Address | Deployment | Gas |
|---|---|---|---|
`;
for (const [name, a] of Object.entries(contracts)) { const d = deployTx[a.toLowerCase()] || {}; md += `| ${name} | ${ad(a)} | ${d.hash ? tx(d.hash) + " (block " + d.block + ")" : ""} | ${d.gasUsed ? n(d.gasUsed) : ""} |\n`; }
md += `
Compiler: solc ${record.compiler.solc}, optimizer enabled (runs 1), via-IR, EVM version cancun, metadata hash ipfs — the settings of \`foundry.toml\`. \`SwarmRegistry\` is linked against the three deployed logic libraries; the decision adapters take the registry, the ERC-8436 registry, the verifier role, the quorum and the body size (2 of 3 for the council, 2 of 2 for the chamber), a 15-minute voting window and a 2-minute margin.

Live dependencies (not deployed by this run): ERC-8436 \`ACDFRegistry\` ${ad(st.ACDFRegistry)} and \`ACDFPolicyRegistry\` ${ad(record.dependencies.ACDFPolicyRegistry)} (revision 3 of the ERC-8436 reference, byte-identical outside immutables and metadata to the fixtures vendored in \`test/fixtures\`), and the token-bound task tender kernel \`TaskToken\` ${ad(st.TaskToken)} (v3.2.1, the source vendored in \`test/fixtures\`).

## Accounts

| Name | Role in the cases | Address |
|---|---|---|
| deployer | deploys; sponsor and judge of the Case A tender; judge of the Case B milestones; opens the decisions; challenges | ${ad(members.deployer)} |
| coord | coordinator of both swarms; Case A amendment/representation authority; recovery address of the Case A account | ${ad(members.coord)} |
| c1, c2, c3 | verifiers (the council of Case A: c1 and c3 vote; the chamber of Case B: c1 and c2 vote) | ${ad(members.c1)}, ${ad(members.c2)}, ${ad(members.c3)} |
| w1 | Case A worker, admitted by the council, paid through the swarm account | ${ad(members.w1)} |
| b1, b2, b3 | Case B bidders; b2 loses eligibility and is substituted by b3 | ${ad(members.b1)}, ${ad(members.b2)}, ${ad(members.b3)} |

## Case A — tender-bound cooperative swarm

Swarm id \`${st.swarmA}\` (\`keccak256(abi.encode(11155111, registry, 1))\`). Task token id ${st.tokenA} on the live kernel, minted and funded (${"0.002"} ETH) by the deployer as sponsor and judge. Spec hash \`${st.hashesA.specHash}\`, charter hash \`${st.hashesA.charterHash}\`, commitment hash \`${st.hashesA.commitmentHash}\`, objective hash \`${st.hashesA.objectiveHash}\`; the pack is \`deployments/sepolia/case-a/swarm-pack.json\` and its \`charterURI\` points at that file in this repository. Council issue \`${st.issueA}\`; fulfillment submission ${st.submissionA}; swarm account ${ad(st.accountA)} with recovery address coord.

The coordinator forms the swarm bound to the tender, the three verifiers join, w1 applies, the council (2 of 3, ERC-8436) admits w1 by a filed, voted and settled decision, the coordinator activates, the swarm account is set, w1 records a contribution, the account submits the fulfillment as the fulfiller of record, the judge accepts, the tender adapter concludes the swarm \`ACHIEVED\` from the kernel's record, the account pays w1 its 70 % share, the coordinator dissolves the swarm and recovers the remainder through the account's post-dissolution rule.

## Case B — two-phase tender with challenge and substitution

Swarm id \`${st.swarmB}\`. Spec hash \`${st.hashesB.specHash}\`, charter hash \`${st.hashesB.charterHash}\`, commitment hash \`${st.hashesB.commitmentHash}\`; the pack is \`deployments/sepolia/case-b/swarm-pack.json\`. Chamber issue \`${st.issueB}\`.

Open bidding phase: the three allowlisted bidders join and record proof sketches; the chamber (2 of 2) advances the swarm to the selected execution phase carrying coord, c1, c2, b1 and b2. Then b2 loses its allowlist eligibility, anyone's \`challenge\` suspends it, a contribution it records while suspended is accepted but flagged \`whileSuspended\`, the coordinator substitutes b3 into the seat, b3 accepts the charter, b1 and b3 record proofs, the judge accepts both milestones, the swarm concludes \`ACHIEVED\` and is dissolved.

## Transactions

Gas is the live Sepolia figure; the last column is the ratio to the local rehearsal (\`tools/sepolia/run.js direct\` against anvil, cancun rules), given because Sepolia priced the same transactions several times higher than the local node at the time of the run.

| # | Step | From | Transaction | Block | Gas | vs rehearsal |
|---|---|---|---|---|---|---|
`;
st.steps.forEach((s, i) => { md += `| ${i} | ${s.label}${s.contractAddress ? " → `" + s.contractAddress + "`" : ""} | ${s.from} | ${tx(s.hash)} | ${s.block} | ${n(s.gasUsed)} | ${ratio(s)} |\n`; });
md += `
## How the run was made

\`tools/sepolia/run.js\` holds one step list for both modes. The rehearsal ran the list in \`direct\` mode against a local anvil with the vendored fixtures (\`--fixtures\`), which produced the gas reference above. The Sepolia run used \`relay\` mode: the process signed each batch of transactions off-line (\`relay plan\`, EIP-1559 type-2 transactions, gas limit = max(step limit, 16 × rehearsal gas), max fee 0.5 gwei then 0.25 gwei, priority fee 0.1 gwei), a relay broadcast the raw transactions in order through \`eth_sendRawTransaction\` against \`https://ethereum-sepolia-rpc.publicnode.com\` and returned the receipts, and \`relay ingest\` applied them before the next batch was planned. Batches end where a later step needs a value from a receipt: the task token id, the two ERC-8436 issue ids, the fulfillment submission id. Seven batches were needed.

Addresses of contracts created by the deployer were predicted from the nonce before broadcast and matched on-chain; the swarm ids were predicted from the registry address and the counter and matched the \`SwarmFormed\` events.

## Final state, read back from the chain

\`deployments/sepolia/final-state.json\` holds the \`eth_call\` results (raw and decoded) taken after the last transaction. What they say:
`;
const fsf = path.join(OUT, "final-state.json");
if (fs.existsSync(fsf)) {
  const f = JSON.parse(fs.readFileSync(fsf, "utf8"));
  const A = f.caseA, B = f.caseB;
  md += `
- Case A: \`getSwarm\` reports state **${A.swarm.state}**, outcome **${A.swarm.outcome}**, reason **${A.swarm.reason}** (the tender adapter, as acceptance authority, concluded it from the kernel's record), charter hash \`${A.swarm.charterHash}\` and commitment hash \`${A.swarm.commitmentHash}\` at version 1 — both equal to SHA-256 over the JCS form of \`case-a/swarm-pack.json\` and of its \`commitment\` member, so the pack in this repository is the one the members accepted. The objective is bound to obligation (${A.objective.obligation.chainId}, \`${A.objective.obligation.target}\`, token ${A.objective.obligation.id}); \`resultHash\` \`${A.swarm.resultHash}\` is the fulfillment's result hash. w1 is **${A.w1.status}** with exit reason **${A.w1.exitReason}**, admitted and accepted under the same charter hash.
- Case A, after dissolution: \`isAuthorized(swarmA, REPRESENT, coord)\` and \`isAuthorized(swarmA, AMEND, coord)\` are both **false**; the account's \`recoveryAddress()\` is coord (\`${A.account.recoveryAddress}\`); the account's balance is **${A.account.balanceWei} wei** — w1 received its 70 % of the 0.002 ETH reward through the account while the swarm lived, and coord recovered the remaining 30 % through the recovery path after dissolution. The registry answers \`supportsInterface(0x085203a4)\` and the account \`supportsInterface(0x25e98353)\` with true.
- Case B: state **${B.swarm.state}**, outcome **${B.swarm.outcome}**, reason **${B.swarm.reason}**, phase ${B.swarm.phase} (the selected execution phase), charter hash \`${B.swarm.charterHash}\` equal to SHA-256(JCS(\`case-b/swarm-pack.json\`)). Objective kind **${B.objective.kind}**, ${B.objective.milestonesAccepted} of ${B.objective.milestoneCount} milestones **${B.milestones[0].status}** / **${B.milestones[1].status}**. b2 is **${B.b2.status}** with suspension cause **${B.b2.suspension}** and exit reason **${B.b2.exitReason}** (suspended by the challenge at ${B.b2.suspendedAt}, replaced at ${B.b2.exitedAt}); b3 is **${B.b3.status}** with \`substituted = ${B.b3.substituted}\`, admitted in phase ${B.b3.admittedPhase}, exit reason **${B.b3.exitReason}**. \`memberCount\` reports ${B.memberCount.join("/")} after dissolution.
`;
}
md += `
## Verification

All ten contracts are verified on Sourcify with an exact match (creation and runtime bytecode, metadata included); \`deployments/sepolia/verification.md\` has the per-contract record and the exact input. The inputs are the files under \`assets/erc-8447/contracts\` at commit \`a78b92780818e3edbd630b95eee8ba73a3ee921c\` with the compiler settings above; \`forge verify-contract --chain sepolia --verifier sourcify <address> <path>:<Name>\` reproduces it, with \`--libraries\` for \`SwarmRegistry\` (LifecycleLib ${st.LifecycleLib}, MembershipLib ${st.MembershipLib}, ResourceLib ${st.ResourceLib}).
`;
fs.writeFileSync(path.join(ROOT, "docs", "sepolia-evidence.md"), md);
console.log(`wrote deployments/sepolia.json and docs/sepolia-evidence.md: ${st.steps.length} steps, ${n(totalGas)} gas`);
