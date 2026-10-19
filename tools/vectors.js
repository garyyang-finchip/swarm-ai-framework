#!/usr/bin/env node
// Regenerates the deterministic vectors under assets/erc-8447/vectors with an independent ABI coder
// (ethers v6). The Foundry suite test/SAIVectors.t.sol re-derives every value in Solidity.
//
//   npm install && node tools/vectors.js
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { ethers } = require("ethers");

const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "assets", "erc-8447", "vectors");
const EXAMPLES = path.join(ROOT, "assets", "erc-8447", "examples");
fs.mkdirSync(OUT, { recursive: true });

const id = (s) => ethers.id(s);
const coder = ethers.AbiCoder.defaultAbiCoder();

// ---------------------------------------------------------------- vocabulary and identifiers

const DIMENSIONS = {
  payoff: id("sai.dimension.payoff"),
  topology: id("sai.dimension.topology"),
  coordination: id("sai.dimension.coordination"),
};
const TERMS = {
  payoff: ["shared", "exclusive", "mixed"],
  topology: ["redundant", "partitioned", "sequential", "hierarchical", "iterative", "free"],
  coordination: ["leader", "collective", "market", "automated", "none"],
};
const ROLES = ["initiator", "coordinator", "worker", "verifier", "observer", "bidder"];
const ORIGINS = ["initiator", "joint", "task", "trigger", "decision", "succession"];
const RESOURCES = ["skill", "dataset", "tool", "code", "model", "document", "oracle", "fund"];
const DECISION_POINTS = ["activate", "abort", "suspend", "resume", "advance", "conclude", "dissolve", "succeed",
  "admit", "remove", "reinstate", "amend", "attach", "detach", "set-account", "represent"];

const termIds = {
  description: "Identifiers of the base vocabulary and the reserved names. Dimension ids are keccak256('sai.dimension.<d>'); term ids keccak256('sai.<d>.<name>'); roles keccak256('sai.role.<name>'); origins keccak256('sai.origin.<name>'); resource kinds keccak256('sai.resource.<name>'); decision-point questions keccak256('sai.dp.<name>'); effects keccak256('sai.enact') / keccak256('sai.refuse') / keccak256('sai.status-quo').",
  dimensions: DIMENSIONS,
  terms: Object.fromEntries(Object.entries(TERMS).map(([d, names]) => [d, Object.fromEntries(names.map((n) => [n, id(`sai.${d}.${n}`)]))])),
  roles: Object.fromEntries(ROLES.map((n) => [n, id(`sai.role.${n}`)])),
  origins: Object.fromEntries(ORIGINS.map((n) => [n, id(`sai.origin.${n}`)])),
  resourceKinds: Object.fromEntries(RESOURCES.map((n) => [n, id(`sai.resource.${n}`)])),
  decisionPointQuestions: Object.fromEntries(DECISION_POINTS.map((n, i) => [n, { index: i, question: id(`sai.dp.${n}`) }])),
  effects: { enact: id("sai.enact"), refuse: id("sai.refuse"), statusQuo: id("sai.status-quo") },
  digestKinds: { "sha-256": id("sha-256"), keccak256: id("keccak256") },
};
fs.writeFileSync(path.join(OUT, "term-ids.json"), JSON.stringify(termIds, null, 2) + "\n");

// ---------------------------------------------------------------- spec hash

const SPEC_TYPE =
  "tuple(" +
  "tuple(bytes32 roleId,uint32 min,uint32 max,address eligibility,bool selfJoin)[] roles," +
  "tuple(bytes32 name,bytes32 payoff,bytes32 topology,bytes32 coordination,uint8 boundary,uint8 admission,uint64 inputWindow,bytes32 descriptorHash)[] phases," +
  "tuple(uint8 kind,address target,bytes32 roleId)[] authorities," +
  "uint8 activation,uint8 contributions,uint32 minMembers,uint32 maxMembers," +
  "uint64 recruitmentWindow,uint64 maxDuration,uint64 inactivityTimeout,uint64 ineligibleGrace," +
  "uint64 settlementWindow,uint64 amendmentExitWindow,bytes32 descriptorHash)";

const ZERO32 = "0x" + "00".repeat(32);
const COORD = "0x1111111111111111111111111111111111111111";
const ADAPTER = "0x2222222222222222222222222222222222222222";
const bytes32str = (s) => ethers.encodeBytes32String(s);
const Boundary = { OPEN: 0, GATED: 1, CLOSED: 2 };
const Admission = { RECRUIT: 0, INHERIT: 1, SELECT: 2 };
const Kind = { NONE: 0, ADDRESS: 1, ROLE: 2, ANY_MEMBER: 3, INITIATOR: 4 };
const Activation = { ROSTER_MET: 0, AUTHORITY: 1, BOTH: 2 };
const Contributions = { DISABLED: 0, MEMBERS: 1, OPEN: 2 };
const DAY = 86400;
const T = termIds.terms;
const R = termIds.roles;

function allAddress(a) {
  const auths = Array.from({ length: 16 }, () => ({ kind: Kind.ADDRESS, target: a, roleId: ZERO32 }));
  auths[15] = { kind: Kind.ROLE, target: ethers.ZeroAddress, roleId: R.coordinator }; // REPRESENT
  return auths;
}

const specMinimal = {
  roles: [
    { roleId: R.coordinator, min: 1, max: 1, eligibility: ethers.ZeroAddress, selfJoin: false },
    { roleId: R.worker, min: 1, max: 0, eligibility: ethers.ZeroAddress, selfJoin: false },
  ],
  phases: [
    { name: bytes32str("execution"), payoff: T.payoff.shared, topology: T.topology.partitioned, coordination: T.coordination.leader,
      boundary: Boundary.GATED, admission: Admission.RECRUIT, inputWindow: 0, descriptorHash: ZERO32 },
  ],
  authorities: allAddress(COORD),
  activation: Activation.ROSTER_MET, contributions: Contributions.MEMBERS, minMembers: 2, maxMembers: 0,
  recruitmentWindow: 7 * DAY, maxDuration: 30 * DAY, inactivityTimeout: 0, ineligibleGrace: DAY,
  settlementWindow: DAY, amendmentExitWindow: 2 * DAY, descriptorHash: ZERO32,
};

const authsTender = allAddress(COORD);
authsTender[4] = { kind: Kind.ADDRESS, target: ADAPTER, roleId: ZERO32 }; // ADVANCE held by a decision adapter
const specTender = {
  roles: [
    { roleId: R.coordinator, min: 1, max: 1, eligibility: ethers.ZeroAddress, selfJoin: true },
    { roleId: R.verifier, min: 2, max: 2, eligibility: ethers.ZeroAddress, selfJoin: true },
    { roleId: R.bidder, min: 0, max: 0, eligibility: ethers.ZeroAddress, selfJoin: true },
    { roleId: R.worker, min: 0, max: 2, eligibility: COORD, selfJoin: false },
  ],
  phases: [
    { name: bytes32str("bidding"), payoff: T.payoff.exclusive, topology: T.topology.redundant, coordination: T.coordination.collective,
      boundary: Boundary.OPEN, admission: Admission.RECRUIT, inputWindow: 2 * DAY, descriptorHash: id("bidding") },
    { name: bytes32str("execution"), payoff: T.payoff.shared, topology: T.topology.partitioned, coordination: T.coordination.leader,
      boundary: Boundary.CLOSED, admission: Admission.SELECT, inputWindow: 0, descriptorHash: id("execution") },
  ],
  authorities: authsTender,
  activation: Activation.ROSTER_MET, contributions: Contributions.OPEN, minMembers: 3, maxMembers: 0,
  recruitmentWindow: 7 * DAY, maxDuration: 90 * DAY, inactivityTimeout: 14 * DAY, ineligibleGrace: DAY,
  settlementWindow: DAY, amendmentExitWindow: 2 * DAY, descriptorHash: id("spec"),
};

function specVector(name, spec) {
  const encoded = coder.encode([SPEC_TYPE], [spec]);
  return { name, spec, encoding: encoded, specHash: ethers.keccak256(encoded) };
}
const specHash = {
  description: "specHash = keccak256(abi.encode(spec)) over the full SwarmSpec struct. `encoding` is the ABI encoding of the single struct argument (ethers v6 AbiCoder); re-derived in Solidity by test/SAIVectors.t.sol.",
  type: SPEC_TYPE,
  vectors: [specVector("minimal single-phase gated swarm", specMinimal), specVector("two-phase tender", specTender)],
};
fs.writeFileSync(path.join(OUT, "spec-hash.json"), JSON.stringify(specHash, (k, v) => (typeof v === "bigint" ? v.toString() : v), 2) + "\n");

// ---------------------------------------------------------------- join digest (EIP-712)

const CHAIN_ID = 1;
const REGISTRY = "0x3333333333333333333333333333333333333333";
const domain = { name: "SAI", version: "1", chainId: CHAIN_ID, verifyingContract: REGISTRY };
const types = {
  Join: [
    { name: "swarmId", type: "bytes32" }, { name: "account", type: "address" }, { name: "roleId", type: "bytes32" },
    { name: "charterHash", type: "bytes32" }, { name: "seatEpoch", type: "uint256" }, { name: "phase", type: "uint32" },
    { name: "deadline", type: "uint256" },
  ],
};
const joinValues = [
  { swarmId: id("swarm-1"), account: "0x4444444444444444444444444444444444444444", roleId: R.worker, charterHash: id("charter v1"), seatEpoch: 0, phase: 0, deadline: 1800086400 },
  { swarmId: id("swarm-1"), account: "0x4444444444444444444444444444444444444444", roleId: R.worker, charterHash: id("charter v1"), seatEpoch: 1, phase: 0, deadline: 1800086400 },
  { swarmId: id("swarm-2"), account: "0x5555555555555555555555555555555555555555", roleId: R.bidder, charterHash: id("charter v2"), seatEpoch: 0, phase: 1, deadline: 1900000000 },
];
const joinDigest = {
  description: "EIP-712 digests of Join(bytes32 swarmId,address account,bytes32 roleId,bytes32 charterHash,uint256 seatEpoch,uint32 phase,uint256 deadline) under EIP712Domain(name 'SAI', version '1', chainId 1, verifyingContract 0x3333...3333). The seat epoch and phase bind a signature to one seat in one phase.",
  domain,
  typeHash: id("Join(bytes32 swarmId,address account,bytes32 roleId,bytes32 charterHash,uint256 seatEpoch,uint32 phase,uint256 deadline)"),
  vectors: joinValues.map((v) => ({ value: v, digest: ethers.TypedDataEncoder.hash(domain, types, v) })),
};
fs.writeFileSync(path.join(OUT, "join-digest.json"), JSON.stringify(joinDigest, null, 2) + "\n");

// ---------------------------------------------------------------- charter hash (JCS + SHA-256)

function jcs(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(jcs).join(",") + "]";
  const keys = Object.keys(value).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return "{" + keys.map((k) => JSON.stringify(k) + ":" + jcs(value[k])).join(",") + "}";
}
const sha256 = (s) => "0x" + crypto.createHash("sha256").update(Buffer.from(s, "utf8")).digest("hex");
const packs = ["swarm-pack-cooperative-tender.json", "swarm-pack-two-phase-tender.json"].map((f) => {
  const root = JSON.parse(fs.readFileSync(path.join(EXAMPLES, f), "utf8"));
  const canonical = jcs(root);
  return {
    file: f,
    canonicalLength: canonical.length,
    canonicalSha256: sha256(canonical),
    charterHash: sha256(canonical),
    objectiveHash: sha256(jcs(root.objective)),
    commitmentHash: root.commitment ? sha256(jcs(root.commitment)) : "0x" + "00".repeat(32),
    phaseDescriptorHashes: root.mode.phases.map((p) => sha256(jcs(p))),
    canonicalPrefix: canonical.slice(0, 120),
  };
});
const charterHash = {
  description: "charterHash = SHA-256 over the RFC 8785 (JCS) canonical form of the Swarm Pack root; objectiveHash = SHA-256 over the canonical form of the `objective` member; commitmentHash = SHA-256 over the canonical form of the `commitment` member (zero when absent); a phase's descriptorHash = SHA-256 over the canonical form of the matching `mode.phases` member. Computed from the example packs under assets/erc-8447/examples.",
  vectors: packs,
};
fs.writeFileSync(path.join(OUT, "charter-hash.json"), JSON.stringify(charterHash, null, 2) + "\n");

// ---------------------------------------------------------------- interface ids (ERC-165)

function interfaceIdFromAbi(abiPath, name) {
  const art = JSON.parse(fs.readFileSync(abiPath, "utf8"));
  const iface = new ethers.Interface(art.abi);
  let x = 0n;
  iface.forEachFunction((f) => { x ^= BigInt(f.selector); });
  return { name, id: "0x" + x.toString(16).padStart(8, "0") };
}
const outDir = path.join(ROOT, "out");
const ids = [];
for (const [file, name] of [["ISwarmRegistry.sol/ISwarmRegistry.json", "ISwarmRegistry"], ["IEligibility.sol/IEligibility.json", "IEligibility"],
  ["ISwarmAccount.sol/ISwarmAccount.json", "ISwarmAccount"], ["IResourceAdapter.sol/IResourceAdapter.json", "IResourceAdapter"]]) {
  const p = path.join(outDir, file);
  if (fs.existsSync(p)) ids.push(interfaceIdFromAbi(p, name));
}
if (ids.length === 4) {
  fs.writeFileSync(path.join(OUT, "interface-ids.json"), JSON.stringify({
    description: "ERC-165 interface identifiers: XOR of the selectors of every function declared in the interface (supportsInterface included for ISwarmRegistry), computed from the compiled ABIs and re-derived in Solidity with type(I).interfaceId.",
    interfaces: Object.fromEntries(ids.map((i) => [i.name, i.id])),
  }, null, 2) + "\n");
} else {
  console.error("interface-ids.json skipped: run `forge build` first (compiled ABIs not found under out/)");
}

console.log("vectors written to", path.relative(ROOT, OUT));
