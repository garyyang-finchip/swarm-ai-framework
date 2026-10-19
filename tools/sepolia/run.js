#!/usr/bin/env node
// Sepolia evidence run for ERC-8447: deploys the reference contracts and executes Case A and
// Case B against the live ERC-8436 registries and the live token-bound task tender kernel.
//
// Two modes, one step list:
//   direct  — an RPC the process can reach (a local anvil for rehearsal, or any node):
//             node tools/sepolia/run.js direct --rpc http://127.0.0.1:8545 --keys keys.json --fixtures
//             (--fixtures deploys the vendored ACDF registries and TaskToken first; omit it to use
//              the addresses in --env)
//   relay   — the process cannot reach the chain: it signs the next batch of transactions into
//             a file, a relay broadcasts them and returns the receipts, and the run resumes:
//             node tools/sepolia/run.js relay plan   --state state.json --keys keys.json --env sepolia.env.json
//             node tools/sepolia/run.js relay ingest --state state.json --receipts receipts-N.json
//
// Keys and state files hold private keys and are never committed. Everything the run derives
// (addresses, ids, hashes, packs) is written to --out (default deployments/sepolia).
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { ethers } = require("ethers");

const ROOT = path.resolve(__dirname, "..", "..");
const OUT_DIR = path.join(ROOT, "out");
const argv = process.argv.slice(2);
const mode = argv[0];
const sub = mode === "relay" ? argv[1] : null;
const opt = (name, dflt) => { const i = argv.indexOf("--" + name); return i >= 0 ? argv[i + 1] : dflt; };
const flag = (name) => argv.includes("--" + name);

const CHAIN_ID = BigInt(opt("chain", "11155111"));
const OUT = path.resolve(opt("out", path.join(ROOT, "deployments", "sepolia")));
fs.mkdirSync(OUT, { recursive: true });

// ---------------------------------------------------------------- constants
const id = (s) => ethers.id(s);
const DAY = 86400n;
const ROLE = { coordinator: id("sai.role.coordinator"), verifier: id("sai.role.verifier"), worker: id("sai.role.worker"), bidder: id("sai.role.bidder") };
const TERM = { shared: id("sai.payoff.shared"), exclusive: id("sai.payoff.exclusive"), partitioned: id("sai.topology.partitioned"),
  redundant: id("sai.topology.redundant"), leader: id("sai.coordination.leader"), collective: id("sai.coordination.collective") };
const ORIGIN = { initiator: id("sai.origin.initiator"), task: id("sai.origin.task") };
const DP = { ACTIVATE: 0, ABORT: 1, SUSPEND: 2, RESUME: 3, ADVANCE: 4, CONCLUDE: 5, DISSOLVE: 6, SUCCEED: 7, ADMIT: 8, REMOVE: 9,
  REINSTATE: 10, AMEND: 11, ATTACH: 12, DETACH: 13, SET_ACCOUNT: 14, REPRESENT: 15 };
const KIND = { NONE: 0, ADDRESS: 1, ROLE: 2, ANY_MEMBER: 3, INITIATOR: 4 };
const ZERO32 = ethers.ZeroHash;
const bytes32name = (s) => ethers.encodeBytes32String(s);

// ---------------------------------------------------------------- artifacts
function artifact(file, name) {
  return JSON.parse(fs.readFileSync(path.join(OUT_DIR, file, name + ".json"), "utf8"));
}
function linkedInitCode(art, libs) {
  let code = art.bytecode.object;
  const refs = art.bytecode.linkReferences || {};
  for (const [file, byName] of Object.entries(refs)) {
    for (const [lib, positions] of Object.entries(byName)) {
      const addr = libs[lib];
      if (!addr) throw new Error("unlinked library " + lib);
      const hex = addr.toLowerCase().replace("0x", "");
      for (const p of positions) {
        const start = 2 + p.start * 2;
        code = code.slice(0, start) + hex + code.slice(start + p.length * 2);
      }
    }
  }
  if (code.includes("$__")) throw new Error("placeholder left in " + file);
  return code;
}
const A = {
  SpecValidator: artifact("SpecValidator.sol", "SpecValidator"),
  LifecycleLib: artifact("LifecycleLib.sol", "LifecycleLib"),
  MembershipLib: artifact("MembershipLib.sol", "MembershipLib"),
  ResourceLib: artifact("ResourceLib.sol", "ResourceLib"),
  SwarmRegistry: artifact("SwarmRegistry.sol", "SwarmRegistry"),
  AllowlistEligibility: artifact("AllowlistEligibility.sol", "AllowlistEligibility"),
  SwarmDecisionAdapter: artifact("SwarmDecisionAdapter.sol", "SwarmDecisionAdapter"),
  SwarmTenderAdapter: artifact("SwarmTenderAdapter.sol", "SwarmTenderAdapter"),
  SwarmAccount: artifact("SwarmAccount.sol", "SwarmAccount"),
  ACDFPolicyRegistry: artifact("ACDFPolicyRegistry.sol", "ACDFPolicyRegistry"),
  ACDFRegistry: artifact("ACDFRegistry.sol", "ACDFRegistry"),
  TaskToken: artifact("TaskToken.sol", "TaskToken"),
};
const I = Object.fromEntries(Object.entries(A).map(([k, a]) => [k, new ethers.Interface(a.abi)]));

// ---------------------------------------------------------------- JCS + sha256 (as tools/vectors.js)
function jcs(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(jcs).join(",") + "]";
  const keys = Object.keys(value).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return "{" + keys.map((k) => JSON.stringify(k) + ":" + jcs(value[k])).join(",") + "}";
}
const sha256 = (s) => "0x" + crypto.createHash("sha256").update(Buffer.from(s, "utf8")).digest("hex");

// ---------------------------------------------------------------- specs
function authorities(coord, overrides) {
  const auths = [];
  for (let i = 0; i < 16; i++) auths.push({ kind: KIND.ADDRESS, target: coord, roleId: ZERO32 });
  auths[DP.REPRESENT] = { kind: KIND.ROLE, target: ethers.ZeroAddress, roleId: ROLE.coordinator };
  for (const [dp, a] of Object.entries(overrides || {})) auths[DP[dp]] = a;
  return auths;
}
function phase(name, payoff, topology, coordination, boundary, admission, inputWindow, descriptorHash) {
  return { name: bytes32name(name), payoff, topology, coordination, boundary, admission, inputWindow, descriptorHash };
}
function specA(coord, council, allowlist, phaseDescriptor) {
  return {
    roles: [
      { roleId: ROLE.coordinator, min: 1, max: 1, eligibility: ethers.ZeroAddress, selfJoin: true },
      { roleId: ROLE.verifier, min: 3, max: 3, eligibility: ethers.ZeroAddress, selfJoin: true },
      { roleId: ROLE.worker, min: 1, max: 3, eligibility: allowlist, selfJoin: false },
    ],
    phases: [phase("execution", TERM.shared, TERM.partitioned, TERM.collective, 0 /*OPEN*/, 0 /*RECRUIT*/, 0n, phaseDescriptor)],
    authorities: authorities(coord, {
      ADMIT: { kind: KIND.ADDRESS, target: council, roleId: ZERO32 },
      REMOVE: { kind: KIND.ADDRESS, target: council, roleId: ZERO32 },
    }),
    activation: 2 /*BOTH*/, contributions: 1 /*MEMBERS*/, minMembers: 5, maxMembers: 0,
    recruitmentWindow: 7n * DAY, maxDuration: 90n * DAY, inactivityTimeout: 0n, ineligibleGrace: DAY,
    settlementWindow: DAY, amendmentExitWindow: 2n * DAY, descriptorHash: ZERO32,
  };
}
function specB(coord, chamber, allowlist, descriptors) {
  return {
    roles: [
      { roleId: ROLE.coordinator, min: 1, max: 1, eligibility: ethers.ZeroAddress, selfJoin: true },
      { roleId: ROLE.verifier, min: 2, max: 2, eligibility: ethers.ZeroAddress, selfJoin: true },
      { roleId: ROLE.bidder, min: 0, max: 0, eligibility: ethers.ZeroAddress, selfJoin: true },
      { roleId: ROLE.worker, min: 0, max: 2, eligibility: allowlist, selfJoin: false },
    ],
    phases: [
      phase("bidding", TERM.exclusive, TERM.redundant, TERM.collective, 0 /*OPEN*/, 0 /*RECRUIT*/, 0n, descriptors[0]),
      phase("execution", TERM.shared, TERM.partitioned, TERM.leader, 2 /*CLOSED*/, 2 /*SELECT*/, 0n, descriptors[1]),
    ],
    authorities: authorities(coord, { ADVANCE: { kind: KIND.ADDRESS, target: chamber, roleId: ZERO32 } }),
    activation: 0 /*ROSTER_MET*/, contributions: 1, minMembers: 3, maxMembers: 0,
    recruitmentWindow: 7n * DAY, maxDuration: 90n * DAY, inactivityTimeout: 0n, ineligibleGrace: DAY,
    settlementWindow: DAY, amendmentExitWindow: 2n * DAY, descriptorHash: ZERO32,
  };
}
const SPEC_TYPE = I.SwarmRegistry.getFunction("specHashOf").inputs[0];
function specHash(spec) { return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode([SPEC_TYPE], [spec])); }
function swarmIdOf(registry, n) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "address", "uint256"], [CHAIN_ID, registry, n]));
}

// ---------------------------------------------------------------- packs (built from the examples)
function buildPackA(ctx, tokenId) {
  const p = JSON.parse(fs.readFileSync(path.join(ROOT, "assets", "erc-8447", "examples", "swarm-pack-cooperative-tender.json"), "utf8"));
  p.origin.ref = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "address", "uint256"], [CHAIN_ID, ctx.taskToken, tokenId]));
  p.origin.description = "Formed by the coordinator to fulfil the task tender below; ref = keccak256(abi.encode(chainId, tender, tokenId))";
  p.objective.goal = "Deliver the accepted fulfillment of the bound task tender: a reproducible benchmark report (Sepolia evidence run of ERC-8447, Case A).";
  p.objective.acceptance.authority = ctx.tenderAdapter;
  p.objective.acceptance.obligation = { chainId: Number(CHAIN_ID), target: ctx.taskToken, id: tokenId.toString() };
  p.roles[2].eligibility.module = ctx.allowlist;
  p.roles[2].eligibility.description = "allowlisted by the deployer-held allowlist module (stands in for a trust-assertion module on this run)";
  p.roles[2].eligibility.requires = ["allowlisted"];
  p.resources = [];
  p.decisionPoints.ADMIT.adapter = ctx.council; p.decisionPoints.REMOVE.adapter = ctx.council;
  delete p.decisionPoints.ADMIT.policyId; delete p.decisionPoints.REMOVE.policyId;
  p.decisionPoints.ADMIT.description = "Collective: the verifier council decides admissions 2-of-3 through the collective decision adapter (live ERC-8436 registries); each decision snapshots the council roster as a policy version";
  p.commitment.allocation[0].params = { coordinator: 20, worker: 70, verifier: 10 };
  p.commitment.allocation[0].description = "Percent of the tender reward credited to the swarm account; on this run the coordinator pays the worker 70% from the account in CONCLUDING and recovers the remainder after dissolution.";
  p.commitment.costs = ["No bond is required"];
  p.commitment.externalActions = ["The coordinator submits the fulfillment to the bound tender from the swarm account in the members' name", "The coordinator pays the allocation from the swarm account"];
  return p;
}
function buildPackB(ctx) {
  const p = JSON.parse(fs.readFileSync(path.join(ROOT, "assets", "erc-8447", "examples", "swarm-pack-two-phase-tender.json"), "utf8"));
  p.objective.acceptance.authority = ctx.judge;
  p.objective.acceptance.kind = "judge";
  p.objective.acceptance.description = "A designated judge account records the milestones on this run (a verifier contract in production)";
  p.roles[2].eligibility.module = ctx.allowlist;
  p.roles[2].eligibility.requires = ["allowlisted by the deployer-held allowlist module"];
  p.roles[3].eligibility.requires = ["allowlisted; re-checked on challenge"];
  p.mode.phases[0].inputWindow = 0;
  p.mode.phases[0].description = "Any eligible bidder joins and records a proof sketch as a contribution. The evaluation chamber scores the sketches and selects. (Unbounded input window on this evidence run; the test suite uses a two-day window.)";
  p.resources = [];
  p.decisionPoints.ADVANCE.adapter = ctx.chamber; delete p.decisionPoints.ADVANCE.policyId;
  return p;
}
function packHashes(pack, phases) {
  const descriptors = phases.map((i) => sha256(jcs(pack.mode.phases[i])));
  return { descriptors, objectiveHash: sha256(jcs(pack.objective)), commitmentHash: sha256(jcs(pack.commitment)) };
}

// ---------------------------------------------------------------- the run (a list of steps)
// Each step: { label, from, to|null, data, value, gas, after(receipt, st) }.
// A step may read st.* values produced by earlier receipts; when a value is missing in relay
// mode the planner stops there (a batch boundary).
class NeedValue extends Error {}
function need(st, key) { if (st[key] === undefined) throw new NeedValue(key); return st[key]; }

function steps(ctx, st, keys) {
  const D = keys.deployer.address, coord = keys.coord.address, c1 = keys.c1.address, c2 = keys.c2.address, c3 = keys.c3.address;
  const w1 = keys.w1.address, b1 = keys.b1.address, b2 = keys.b2.address, b3 = keys.b3.address;
  const judge = D, sponsor = D;
  const list = [];
  const push = (s) => list.push(s);
  const deploy = (label, art, args, libs, gas, after) => push({
    label, from: "deployer", to: null, gas,
    data: () => linkedInitCode(art, libs || {}) + (args ? I[label.split(" ")[0]].encodeDeploy(args).slice(2) : ""),
    after: (r, s) => { s[label.split(" ")[0] === "SwarmAccount" ? label.split(" ")[1] : label.split(" ")[0]] = r.contractAddress; if (after) after(r, s); },
  });
  const call = (label, from, to, iface, fn, args, gas, value, after) => push({
    label, from, to: () => (typeof to === "function" ? to() : to), gas, value: value || 0n,
    data: () => iface.encodeFunctionData(fn, typeof args === "function" ? args() : args), after,
  });
  const R = () => need(st, "SwarmRegistry");

  // ---- fixtures (rehearsal only)
  if (ctx.fixtures) {
    deploy("ACDFPolicyRegistry", A.ACDFPolicyRegistry, null, {}, 2_500_000n);
    push({ label: "ACDFRegistry", from: "deployer", to: null, gas: 6_000_000n,
      data: () => A.ACDFRegistry.bytecode.object + I.ACDFRegistry.encodeDeploy([need(st, "ACDFPolicyRegistry")]).slice(2),
      after: (r, s) => { s.ACDFRegistry = r.contractAddress; } });
    push({ label: "TaskToken", from: "deployer", to: null, gas: 6_000_000n,
      data: () => A.TaskToken.bytecode.object + I.TaskToken.encodeDeploy(["Task Tender", "TASK"]).slice(2),
      after: (r, s) => { s.TaskToken = r.contractAddress; } });
  } else {
    st.ACDFRegistry = ctx.acdfRegistry; st.TaskToken = ctx.taskToken;
  }

  // ---- reference contracts
  deploy("SpecValidator", A.SpecValidator, null, {}, 1_500_000n);
  push({ label: "LifecycleLib", from: "deployer", to: null, gas: 9_000_000n,
    data: () => linkedInitCode(A.LifecycleLib, { SpecValidator: need(st, "SpecValidator") }),
    after: (r, s) => { s.LifecycleLib = r.contractAddress; } });
  deploy("MembershipLib", A.MembershipLib, null, {}, 6_000_000n);
  deploy("ResourceLib", A.ResourceLib, null, {}, 3_000_000n);
  push({ label: "SwarmRegistry", from: "deployer", to: null, gas: 9_000_000n,
    data: () => linkedInitCode(A.SwarmRegistry, { LifecycleLib: need(st, "LifecycleLib"), MembershipLib: need(st, "MembershipLib"), ResourceLib: need(st, "ResourceLib") })
      + I.SwarmRegistry.encodeDeploy([[], []]).slice(2),
    after: (r, s) => { s.SwarmRegistry = r.contractAddress; } });
  push({ label: "AllowlistEligibility", from: "deployer", to: null, gas: 1_000_000n,
    data: () => A.AllowlistEligibility.bytecode.object + I.AllowlistEligibility.encodeDeploy([D]).slice(2),
    after: (r, s) => { s.AllowlistEligibility = r.contractAddress; } });
  push({ label: "SwarmDecisionAdapter council", from: "deployer", to: null, gas: 6_000_000n,
    data: () => A.SwarmDecisionAdapter.bytecode.object + I.SwarmDecisionAdapter.encodeDeploy([R(), need(st, "ACDFRegistry"), ROLE.verifier, 2, 3, 15n * 60n, 2n * 60n]).slice(2),
    after: (r, s) => { s.council = r.contractAddress; } });
  push({ label: "SwarmDecisionAdapter chamber", from: "deployer", to: null, gas: 6_000_000n,
    data: () => A.SwarmDecisionAdapter.bytecode.object + I.SwarmDecisionAdapter.encodeDeploy([R(), need(st, "ACDFRegistry"), ROLE.verifier, 2, 2, 15n * 60n, 2n * 60n]).slice(2),
    after: (r, s) => { s.chamber = r.contractAddress; } });
  push({ label: "SwarmTenderAdapter", from: "deployer", to: null, gas: 2_000_000n,
    data: () => A.SwarmTenderAdapter.bytecode.object + I.SwarmTenderAdapter.encodeDeploy([R(), need(st, "TaskToken")]).slice(2),
    after: (r, s) => { s.SwarmTenderAdapter = r.contractAddress; } });

  // ---- fund the member keys
  for (const who of ["coord", "c1", "c2", "c3", "w1", "b1", "b2", "b3"]) {
    const amount = who === "coord" ? (ctx.fundCoord || ctx.fund || "0.01") : (ctx.fund || "0.004");
    push({ label: "fund " + who, from: "deployer", to: () => keys[who].address, gas: 30_000n, value: ethers.parseEther(amount), data: () => "0x" });
  }

  // ======================================================== Case A
  const terms = () => [ethers.ZeroAddress, ethers.parseEther(ctx.reward || "0.002"), 1, 0, BigInt(ctx.settleBy), 0, 0, 7n * DAY];
  call("A: mintTask", "deployer", () => need(st, "TaskToken"), I.TaskToken, "mintTask",
    () => [sponsor, sponsor, judge, id("sai case A task document"), id("sai case A task"), "ipfs://sai-case-a-task", terms()], 2_500_000n, 0n,
    (r, s) => { const ev = r.logs.find((l) => l.topics[0] === I.TaskToken.getEvent("Transfer").topicHash); s.tokenA = BigInt(ev.topics[3]).toString(); });
  call("A: fundTask", "deployer", () => need(st, "TaskToken"), I.TaskToken, "fundTask", () => [need(st, "tokenA"), ethers.parseEther(ctx.reward || "0.002")], 400_000n, ethers.parseEther(ctx.reward || "0.002"));
  call("A: allow w1", "deployer", () => need(st, "AllowlistEligibility"), I.AllowlistEligibility, "setAllowed", [w1, true], 100_000n);
  // the pack and its hashes need the token id and the addresses
  const packA = () => {
    if (st.packA) return st.packA;
    const p = buildPackA({ taskToken: need(st, "TaskToken"), tenderAdapter: need(st, "SwarmTenderAdapter"), allowlist: need(st, "AllowlistEligibility"), council: need(st, "council") }, BigInt(need(st, "tokenA")));
    const h = packHashes(p, [0]);
    const spec = specA(coord, st.council, st.AllowlistEligibility, h.descriptors[0]);
    p.specHash = specHash(spec);
    const charterHash = sha256(jcs(p));
    st.packA = p; st.hashesA = { ...h, charterHash, specHash: p.specHash }; st.specA = spec;
    fs.mkdirSync(path.join(OUT, "case-a"), { recursive: true });
    fs.writeFileSync(path.join(OUT, "case-a", "swarm-pack.json"), JSON.stringify(p, null, 2) + "\n");
    return p;
  };
  call("A: form", "coord", R, I.SwarmRegistry, "form", () => { packA(); return [st.specA, st.hashesA.charterHash, st.hashesA.commitmentHash, ctx.charterURIA, ZERO32,
      { kind: ORIGIN.task, ref: st.packA.origin.ref },
      { objectiveHash: st.hashesA.objectiveHash, kind: 0, acceptanceAuthority: st.SwarmTenderAdapter, obligation: { chainId: CHAIN_ID, target: st.TaskToken, id: BigInt(st.tokenA) }, milestoneCount: 0 }]; },
    4_000_000n, 0n, (r, s) => { s.swarmA = swarmIdOf(s.SwarmRegistry, 1); });
  const chA = () => need(st, "hashesA").charterHash;
  call("A: coord joins", "coord", R, I.SwarmRegistry, "join", () => [need(st, "swarmA"), ROLE.coordinator, chA()], 600_000n);
  call("A: c1 joins", "c1", R, I.SwarmRegistry, "join", () => [need(st, "swarmA"), ROLE.verifier, chA()], 600_000n);
  call("A: c2 joins", "c2", R, I.SwarmRegistry, "join", () => [need(st, "swarmA"), ROLE.verifier, chA()], 600_000n);
  call("A: c3 joins", "c3", R, I.SwarmRegistry, "join", () => [need(st, "swarmA"), ROLE.verifier, chA()], 600_000n);
  call("A: w1 applies", "w1", R, I.SwarmRegistry, "applyToJoin", () => [need(st, "swarmA"), ROLE.worker, chA()], 600_000n);
  call("A: council opens ADMIT", "deployer", () => need(st, "council"), I.SwarmDecisionAdapter, "open",
    () => [need(st, "swarmA"), DP.ADMIT, I.SwarmRegistry.encodeFunctionData("admit", [st.swarmA, w1, ROLE.worker]), [c1, c2, c3]], 2_500_000n, 0n,
    (r, s) => { const ev = r.logs.find((l) => l.topics[0] === I.SwarmDecisionAdapter.getEvent("ProposalOpened").topicHash); s.issueA = ev.topics[1]; });
  call("A: c1 votes yes", "c1", () => need(st, "ACDFRegistry"), I.ACDFRegistry, "castBallot", () => [need(st, "issueA"), 1, 0, true], 400_000n);
  call("A: c3 votes yes", "c3", () => need(st, "ACDFRegistry"), I.ACDFRegistry, "castBallot", () => [need(st, "issueA"), 1, 0, true], 400_000n);
  call("A: settle round", "deployer", () => need(st, "ACDFRegistry"), I.ACDFRegistry, "settleRound", () => [need(st, "issueA")], 600_000n);
  call("A: council executes (admit w1)", "deployer", () => need(st, "council"), I.SwarmDecisionAdapter, "execute", () => [need(st, "issueA")], 1_200_000n);
  call("A: activate", "coord", R, I.SwarmRegistry, "activate", () => [need(st, "swarmA")], 300_000n);
  push({ label: "SwarmAccount accountA", from: "deployer", to: null, gas: 2_000_000n,
    data: () => A.SwarmAccount.bytecode.object + I.SwarmAccount.encodeDeploy([R(), need(st, "swarmA"), coord]).slice(2),
    after: (r, s) => { s.accountA = r.contractAddress; } });
  call("A: setAccount", "coord", R, I.SwarmRegistry, "setAccount", () => [need(st, "swarmA"), need(st, "accountA")], 300_000n);
  call("A: w1 records contribution", "w1", R, I.SwarmRegistry, "recordContribution", () => [need(st, "swarmA"), id("track-1 results"), "ipfs://sai-case-a-track-1"], 200_000n);
  call("A: account submits fulfillment", "coord", () => need(st, "accountA"), I.SwarmAccount, "execute",
    () => [need(st, "TaskToken"), 0n, I.TaskToken.encodeFunctionData("submitFulfillment", [BigInt(need(st, "tokenA")), id("sai case A report"), "ipfs://sai-case-a-report"])], 900_000n, 0n,
    (r, s) => { const ev = r.logs.find((l) => l.topics[0] === I.TaskToken.getEvent("FulfillmentSubmitted").topicHash); s.submissionA = BigInt(ev.topics[2]).toString(); });
  call("A: judge accepts", "deployer", () => need(st, "TaskToken"), I.TaskToken, "acceptFulfillment", () => [BigInt(need(st, "tokenA")), BigInt(need(st, "submissionA"))], 600_000n);
  call("A: tender adapter settles", "deployer", () => need(st, "SwarmTenderAdapter"), I.SwarmTenderAdapter, "settle", () => [need(st, "swarmA"), BigInt(need(st, "submissionA"))], 500_000n);
  call("A: account pays w1", "coord", () => need(st, "accountA"), I.SwarmAccount, "execute", () => [w1, ethers.parseEther(ctx.reward || "0.002") * 7n / 10n, "0x"], 200_000n);
  call("A: dissolve", "coord", R, I.SwarmRegistry, "dissolve", () => [need(st, "swarmA")], 300_000n);
  call("A: recover remainder", "coord", () => need(st, "accountA"), I.SwarmAccount, "recover", () => [coord, ethers.parseEther(ctx.reward || "0.002") * 3n / 10n, "0x"], 200_000n);

  // ======================================================== Case B
  call("B: allow b1", "deployer", () => need(st, "AllowlistEligibility"), I.AllowlistEligibility, "setAllowed", [b1, true], 100_000n);
  call("B: allow b2", "deployer", () => need(st, "AllowlistEligibility"), I.AllowlistEligibility, "setAllowed", [b2, true], 100_000n);
  call("B: allow b3", "deployer", () => need(st, "AllowlistEligibility"), I.AllowlistEligibility, "setAllowed", [b3, true], 100_000n);
  const packB = () => {
    if (st.packB) return st.packB;
    const p = buildPackB({ judge, allowlist: need(st, "AllowlistEligibility"), chamber: need(st, "chamber") });
    const h = packHashes(p, [0, 1]);
    const spec = specB(coord, st.chamber, st.AllowlistEligibility, h.descriptors);
    p.specHash = specHash(spec);
    const charterHash = sha256(jcs(p));
    st.packB = p; st.hashesB = { ...h, charterHash, specHash: p.specHash }; st.specB = spec;
    fs.mkdirSync(path.join(OUT, "case-b"), { recursive: true });
    fs.writeFileSync(path.join(OUT, "case-b", "swarm-pack.json"), JSON.stringify(p, null, 2) + "\n");
    return p;
  };
  call("B: form", "coord", R, I.SwarmRegistry, "form", () => { packB(); return [st.specB, st.hashesB.charterHash, st.hashesB.commitmentHash, ctx.charterURIB, ZERO32,
      { kind: ORIGIN.initiator, ref: ZERO32 },
      { objectiveHash: st.hashesB.objectiveHash, kind: 1 /*MILESTONED*/, acceptanceAuthority: judge, obligation: { chainId: 0n, target: ethers.ZeroAddress, id: 0n }, milestoneCount: 2 }]; },
    5_000_000n, 0n, (r, s) => { s.swarmB = swarmIdOf(s.SwarmRegistry, 2); });
  const chB = () => need(st, "hashesB").charterHash;
  call("B: coord joins", "coord", R, I.SwarmRegistry, "join", () => [need(st, "swarmB"), ROLE.coordinator, chB()], 600_000n);
  call("B: c1 joins", "c1", R, I.SwarmRegistry, "join", () => [need(st, "swarmB"), ROLE.verifier, chB()], 600_000n);
  call("B: c2 joins", "c2", R, I.SwarmRegistry, "join", () => [need(st, "swarmB"), ROLE.verifier, chB()], 600_000n);
  call("B: activate", "deployer", R, I.SwarmRegistry, "activate", () => [need(st, "swarmB")], 300_000n);
  call("B: b1 joins", "b1", R, I.SwarmRegistry, "join", () => [need(st, "swarmB"), ROLE.bidder, chB()], 600_000n);
  call("B: b2 joins", "b2", R, I.SwarmRegistry, "join", () => [need(st, "swarmB"), ROLE.bidder, chB()], 600_000n);
  call("B: b3 joins", "b3", R, I.SwarmRegistry, "join", () => [need(st, "swarmB"), ROLE.bidder, chB()], 600_000n);
  call("B: b1 sketch", "b1", R, I.SwarmRegistry, "recordContribution", () => [need(st, "swarmB"), id("sketch A"), "ipfs://sai-case-b-sketch-a"], 200_000n);
  call("B: b2 sketch", "b2", R, I.SwarmRegistry, "recordContribution", () => [need(st, "swarmB"), id("sketch B"), "ipfs://sai-case-b-sketch-b"], 200_000n);
  call("B: b3 sketch", "b3", R, I.SwarmRegistry, "recordContribution", () => [need(st, "swarmB"), id("sketch C"), "ipfs://sai-case-b-sketch-c"], 200_000n);
  const carried = [coord, c1, c2, b1, b2], roles = [ROLE.coordinator, ROLE.verifier, ROLE.verifier, ROLE.worker, ROLE.worker];
  call("B: chamber opens ADVANCE", "deployer", () => need(st, "chamber"), I.SwarmDecisionAdapter, "open",
    () => [need(st, "swarmB"), DP.ADVANCE, I.SwarmRegistry.encodeFunctionData("advance", [st.swarmB, carried, roles]), [c1, c2]], 2_500_000n, 0n,
    (r, s) => { const ev = r.logs.find((l) => l.topics[0] === I.SwarmDecisionAdapter.getEvent("ProposalOpened").topicHash); s.issueB = ev.topics[1]; });
  call("B: c1 votes yes", "c1", () => need(st, "ACDFRegistry"), I.ACDFRegistry, "castBallot", () => [need(st, "issueB"), 1, 0, true], 400_000n);
  call("B: c2 votes yes", "c2", () => need(st, "ACDFRegistry"), I.ACDFRegistry, "castBallot", () => [need(st, "issueB"), 1, 0, true], 400_000n);
  call("B: settle round", "deployer", () => need(st, "ACDFRegistry"), I.ACDFRegistry, "settleRound", () => [need(st, "issueB")], 600_000n);
  call("B: chamber executes (advance)", "deployer", () => need(st, "chamber"), I.SwarmDecisionAdapter, "execute", () => [need(st, "issueB")], 1_500_000n);
  call("B: b2 loses eligibility", "deployer", () => need(st, "AllowlistEligibility"), I.AllowlistEligibility, "setAllowed", [b2, false], 100_000n);
  call("B: anyone challenges b2", "deployer", R, I.SwarmRegistry, "challenge", () => [need(st, "swarmB"), b2], 400_000n);
  call("B: b2 records while suspended", "b2", R, I.SwarmRegistry, "recordContribution", () => [need(st, "swarmB"), id("late work"), ""], 200_000n);
  call("B: coord substitutes b3 for b2", "coord", R, I.SwarmRegistry, "substitute", () => [need(st, "swarmB"), b2, b3], 600_000n);
  call("B: b3 accepts the charter", "b3", R, I.SwarmRegistry, "acceptCharter", () => [need(st, "swarmB"), chB()], 400_000n);
  call("B: b1 proof", "b1", R, I.SwarmRegistry, "recordContribution", () => [need(st, "swarmB"), id("lemma A proof"), "ipfs://sai-case-b-proof-a"], 200_000n);
  call("B: b3 proof", "b3", R, I.SwarmRegistry, "recordContribution", () => [need(st, "swarmB"), id("lemma B proof"), "ipfs://sai-case-b-proof-b"], 200_000n);
  call("B: milestone 0 accepted", "deployer", R, I.SwarmRegistry, "recordMilestone", () => [need(st, "swarmB"), 0, 1, id("lemma A proof")], 200_000n);
  call("B: milestone 1 accepted", "deployer", R, I.SwarmRegistry, "recordMilestone", () => [need(st, "swarmB"), 1, 1, id("lemma B proof")], 200_000n);
  call("B: conclude ACHIEVED", "deployer", R, I.SwarmRegistry, "conclude", () => [need(st, "swarmB"), 1, id("both lemmas")], 300_000n);
  call("B: dissolve", "coord", R, I.SwarmRegistry, "dissolve", () => [need(st, "swarmB")], 300_000n);
  return list;
}

// ---------------------------------------------------------------- keys
function loadKeys(file) {
  const raw = JSON.parse(fs.readFileSync(file, "utf8"));
  const keys = {};
  for (const [k, pk] of Object.entries(raw)) keys[k] = new ethers.Wallet(pk);
  return keys;
}

// ---------------------------------------------------------------- direct mode
async function runDirect() {
  const provider = new ethers.JsonRpcProvider(opt("rpc"), undefined, { staticNetwork: true });
  const keys = loadKeys(opt("keys"));
  const env = opt("env") ? JSON.parse(fs.readFileSync(opt("env"), "utf8")) : {};
  const ctx = { fixtures: flag("fixtures"), ...env };
  ctx.settleBy = ctx.settleBy || Math.floor(Date.now() / 1000) + 60 * 86400;
  ctx.charterURIA = ctx.charterURIA || "ipfs://sai-case-a-pack"; ctx.charterURIB = ctx.charterURIB || "ipfs://sai-case-b-pack";
  const st = { steps: [] };
  const list = steps(ctx, st, keys);
  const fee = await provider.getFeeData();
  for (const s of list) {
    const wallet = keys[s.from].connect(provider);
    const tx = { to: s.to ? s.to() : null, data: s.data(), value: s.value || 0n, gasLimit: s.gas,
      maxFeePerGas: fee.maxFeePerGas, maxPriorityFeePerGas: fee.maxPriorityFeePerGas };
    const sent = await wallet.sendTransaction(tx);
    const r = await sent.wait();
    if (r.status !== 1) throw new Error("failed: " + s.label);
    if (s.after) s.after(r, st);
    st.steps.push({ label: s.label, hash: r.hash, gasUsed: r.gasUsed.toString(), block: r.blockNumber, contractAddress: r.contractAddress || undefined });
    console.log(`${s.label.padEnd(36)} gas ${r.gasUsed.toString().padStart(8)}  ${r.hash}`);
  }
  fs.writeFileSync(path.join(OUT, "state.json"), JSON.stringify(st, (k, v) => (typeof v === "bigint" ? v.toString() : v), 2));
  console.log("done; state written to", path.join(OUT, "state.json"));
}

// ---------------------------------------------------------------- relay mode
function loadState(file) { return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : { steps: [], nonces: {}, next: 0, batches: 0 }; }
function saveState(file, st) { fs.writeFileSync(file, JSON.stringify(st, (k, v) => (typeof v === "bigint" ? v.toString() : v), 2)); }

async function relayPlan() {
  const stateFile = opt("state"); const st = loadState(stateFile);
  const keys = loadKeys(opt("keys"));
  const ctx = JSON.parse(fs.readFileSync(opt("env"), "utf8"));
  const list = steps(ctx, st, keys);
  const batch = [];
  let i = st.next;
  const maxFee = ethers.parseUnits(ctx.maxFeeGwei || "1", "gwei"), prio = ethers.parseUnits(ctx.priorityGwei || "0.1", "gwei");
  // gas limits: the measured usage of a rehearsal (--gasref state.json of a direct run) times a
  // multiplier, because the live schedule can price the same work several times higher than a
  // local node; the step's own limit is the floor
  const gasref = {};
  if (opt("gasref")) for (const r of JSON.parse(fs.readFileSync(opt("gasref"), "utf8")).steps) gasref[r.label] = BigInt(r.gasUsed);
  const mult = BigInt(ctx.gasMultiplier || 10);
  const limitFor = (s) => { const ref = gasref[s.label]; const scaled = ref ? ref * mult : 0n; return scaled > s.gas ? scaled : s.gas; };
  for (; i < list.length && batch.length < (ctx.batchSize || 14); i++) {
    const s = list[i];
    let to, data;
    try { to = s.to ? s.to() : null; data = s.data(); } catch (e) { if (e instanceof NeedValue) break; throw e; }
    const nonce = st.nonces[s.from] ?? (ctx.nonces || {})[s.from] ?? 0;
    const tx = { type: 2, chainId: CHAIN_ID, nonce, to, data, value: s.value || 0n, gasLimit: limitFor(s), maxFeePerGas: maxFee, maxPriorityFeePerGas: prio };
    const raw = await keys[s.from].signTransaction(tx);
    const predicted = to ? null : ethers.getCreateAddress({ from: keys[s.from].address, nonce });
    batch.push({ index: i, label: s.label, from: s.from, nonce, gasLimit: limitFor(s).toString(), raw, predictedAddress: predicted });
    st.nonces[s.from] = nonce + 1;
    if (predicted) { // deployments are deterministic: later steps may use the address right away
      const key = s.label.startsWith("SwarmAccount") ? s.label.split(" ")[1] : s.label.startsWith("SwarmDecisionAdapter") ? s.label.split(" ")[1] : s.label.split(" ")[0];
      st[key] = predicted;
    }
    if (s.label === "A: form") st.swarmA = swarmIdOf(st.SwarmRegistry, 1);
    if (s.label === "B: form") st.swarmB = swarmIdOf(st.SwarmRegistry, 2);
  }
  st.batches += 1;
  const file = path.join(OUT, `batch-${st.batches}.json`);
  fs.writeFileSync(file, JSON.stringify({ batch: st.batches, nextAfter: i, txs: batch }, null, 2));
  st.pendingBatch = { file, nextAfter: i, indices: batch.map((b) => b.index) };
  saveState(stateFile, st);
  console.log(`batch ${st.batches}: ${batch.length} transactions (steps ${st.next}..${i - 1}); ${list.length - i} steps remain`);
  for (const b of batch) console.log(`  ${b.index}  ${b.label}  (${b.from} nonce ${b.nonce})${b.predictedAddress ? "  -> " + b.predictedAddress : ""}`);
}

async function relayIngest() {
  const stateFile = opt("state"); const st = loadState(stateFile);
  const keys = loadKeys(opt("keys"));
  const ctx = JSON.parse(fs.readFileSync(opt("env"), "utf8"));
  const list = steps(ctx, st, keys);
  const receipts = JSON.parse(fs.readFileSync(opt("receipts"), "utf8"));
  const pending = st.pendingBatch;
  if (!pending) throw new Error("no pending batch");
  if (receipts.length !== pending.indices.length) console.warn(`warning: ${receipts.length} receipts for ${pending.indices.length} transactions`);
  for (let k = 0; k < receipts.length; k++) {
    const r = receipts[k]; const s = list[pending.indices[k]];
    if (Number(r.status) !== 1) { st.failed = { step: s.label, hash: r.transactionHash || r.hash }; saveState(stateFile, st); throw new Error(`step failed: ${s.label} (${r.transactionHash || r.hash})`); }
    const norm = { hash: r.transactionHash || r.hash, status: 1, contractAddress: r.contractAddress ? ethers.getAddress(r.contractAddress) : null, gasUsed: BigInt(r.gasUsed), blockNumber: Number(r.blockNumber), logs: r.logs || [] };
    if (s.after) s.after(norm, st);
    st.steps.push({ label: s.label, from: s.from, hash: norm.hash, gasUsed: norm.gasUsed.toString(), block: norm.blockNumber, contractAddress: norm.contractAddress || undefined });
  }
  st.next = pending.nextAfter;
  delete st.pendingBatch;
  saveState(stateFile, st);
  console.log(`ingested ${receipts.length} receipts; next step ${st.next} of ${list.length}`);
}

(async () => {
  if (mode === "direct") await runDirect();
  else if (mode === "relay" && sub === "plan") await relayPlan();
  else if (mode === "relay" && sub === "ingest") await relayIngest();
  else { console.error("usage: run.js direct --rpc URL --keys FILE [--fixtures] [--env FILE] | relay plan|ingest --state FILE --keys FILE --env FILE [--receipts FILE]"); process.exit(2); }
})().catch((e) => { console.error(e); process.exit(1); });
