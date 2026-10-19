# ERC-8447: Swarm AI Framework (SAI)

> Agents form, bound, run and dissolve purpose-bound swarms — collectives with an explicit membership boundary, an objective with attainment rules and a declared collaboration structure — as one interoperable on-chain record.

**Status:** reference v0.3 (2026-10-19), revision 2 of the draft. Filed as ethereum/ERCs PR #2081 and assigned **ERC-8447** on 2026-10-19; discussion at Ethereum Magicians topic 29998 (`ERC-8447: Swarm AI Framework`). Revision 2 answers the first review round (`docs/magicians-replies-2026-10-19.md`): the pack's economic commitment carries its own hash and makes amendments material by construction, `challenge` and `expel` re-adjudicate on evidence with a gas-remainder rule, and the account profile states its post-dissolution rule on-chain. The package: the full ERC text, the reference registry and its libraries, the swarm account, the collective-decision and task-tender adapters, five eligibility modules, schemas, example packs, deterministic vectors and a Foundry suite of 91 tests run against the real ERC-8436 registries and a real token-bound task tender kernel.

## What it is

A minimal interoperable kernel for agent swarms plus normative-optional profiles. In four clauses: **the charter organizes the swarm; boundary and eligibility decide who is inside; objective and attainment decide when it exists; the posture coordinate declares how it works.** The registry holds the normative record and never moves value; adapters connect decisions and obligations.

- A **Swarm Specification** is an immutable, content-addressed set of executed parameters: `specHash = keccak256(abi.encode(SwarmSpec))`. Roles with eligibility modules, phases with their posture, one authority per decision point (sixteen, `ACTIVATE` through `REPRESENT`), the activation rule, the contribution mode and the liveness fallbacks all live inside the hashed object, so the registered rule and the executed rule are the same thing. Structural change is succession: a new swarm, the old one `SUPERSEDED`.
- A **Charter** is the off-chain Swarm Pack committed by `charterHash` (SHA-256 over the RFC 8785 canonical form): the charter text, the objective descriptor, the members' economic **commitment** (allocation per phase, costs, liabilities, data access, actions in their name), the collaboration structure per phase, the roles, the resource manifest, the version chain. The objective and the commitment carry hashes of their own, committed on-chain; an amendment that changes either is *material* by construction — commitment version incremented, exit window opened — and the `material` flag can only add to that, never subtract. Members accept commitment versions.
- **Lifecycle** keeps three dimensions apart: procedural state (`FORMING -> ACTIVE <-> SUSPENDED -> CONCLUDING -> DISSOLVED`), outcome type (`ACHIEVED / PARTIAL / FAILED / ABANDONED / SUPERSEDED`) and settlement (authoritative at the swarm account or the bound obligation). An objective, a roster or a decision ends a swarm; a clock only guards it — every state has a permissionless exit after a declared fallback, and a spec without one is invalid. A per-swarm revision counter and a `Changed` event make the event stream an organizational change log.
- **Membership** is a ledger: admission is two-sided (an authority admits, the member accepts the current commitment version), leaving is always available, anyone may `challenge` a member against its role's eligibility module (`false` suspends, `true` reinstates a member suspended for ineligibility; a revert, a non-boolean or a `false` returned with less than one eighth of the pre-call gas is unevaluable and changes nothing), `expel` after the grace period asks the module again before acting, substitution hands a seat to a successor account even in a closed phase. Signed acceptance binds the charter hash, the seat epoch and the phase, so no relayed signature re-seats an account.
- **Posture** is a coordinate per phase over five dimensions. Two are executed by the registry — boundary (`OPEN / GATED / CLOSED`) and admission (`RECRUIT / INHERIT / SELECT`). Three are declared as terms of a write-once **vocabulary** kept by the registry — payoff (`shared / exclusive / mixed`), topology (`redundant / partitioned / sequential / hierarchical / iterative / free`), coordination (`leader / collective / market / automated / none`) — and anyone may register a new term under a dimension with a descriptor URI. Cooperation, competition, co-opetition, tenders, staged elimination, debate, ensembles and pipelines are points and trajectories in this space, not entries in a list.
- **Objective** kinds `TERMINAL`, `MILESTONED`, `EXPLORATORY`, `STANDING`; an acceptance authority (verifier, judge, decision adapter or obligation adapter) records attainment; an optional external obligation binds the objective to a task tender or any contract. An **origin** record says how the swarm came to exist (initiator, joint action, task, trigger, decision, succession), separately from who submitted the formation and who holds power.
- **Resources** are non-principal elements (executable skills, datasets, tools, code, models, documents, oracles, funds) attached by kind, optional anchor, digest plus digest kind, provider and role scope; they hold no seat and receive no allocation. A deployment may bind a per-kind adapter that verifies anchors at attach time. Members are accounts: whether one is an agent, a human, an organization or a contract is a property eligibility establishes, not one the kernel assumes.
- **Account**: an optional swarm account acts for the swarm under the `REPRESENT` authority while it lives; the registry authorizes nobody once a swarm is dissolved, and the account states its post-dissolution rule on-chain (`recoveryAddress()`), independent of the `REPRESENT` kind.
- **Profiles**: collective decisions through ERC-8436 (a decision adapter holds decision points, snapshots the deciding role as a policy version per decision, files the exact call as the issue subject and enacts only `Final x Yes`), member identities through ERC-8004, eligibility modules over trust-assertion and agent-identity registries, binding to a token-bound task tender (the swarm account is the fulfiller of record; the tender adapter concludes from the tender's record), resource adapters, signed charter acceptance, succession and nesting.

## Repository

```
ERCS/erc-8447.md                  the proposal (ERC-8447; eipw 0 findings under the ERCs config)
assets/erc-8447/contracts/         SAITypes, SAIErrors, SwarmRegistry + libraries/ (LifecycleLib, MembershipLib,
                                  ResourceLib, SpecValidator, SAIStore, SignatureChecker), interfaces/, account/,
                                  adapters/ (SwarmDecisionAdapter, SwarmTenderAdapter), modules/ (five eligibility modules)
assets/erc-8447/schemas/           swarm-spec.schema.json (mirror of the struct), swarm-pack.schema.json (the charter root)
assets/erc-8447/examples/          two packs: a tender-bound cooperative swarm; a two-phase tender (open bidding, selected execution)
assets/erc-8447/vectors/           spec-hash, join-digest, charter-hash, term-ids, interface-ids (tools/vectors.js, ethers v6)
test/                             Foundry suite (91 tests); test/fixtures/ vendors the ERC-8436 registries and the task tender kernel
tools/vectors.js                  regenerates the vectors with an independent ABI coder and canonicalizer
scripts/make-filing-package.py    builds and lints the ethereum/ERCs submission package (ERCS/erc-N.md + assets/erc-N/)
docs/                             design memo (decisions log), Magicians post and reply drafts, test record
```

## Build and test

```bash
forge build --sizes                             # solc 0.8.24, via-IR, optimizer runs = 1; lib/forge-std v1.17.0 is vendored
forge test                                      # 91 tests
npm install && node tools/vectors.js            # regenerate assets/erc-8447/vectors (ethers 6.13.4)
python3 scripts/make-filing-package.py --allow-tbd   # dry run of the filing package and lints
```

Runtime sizes under the pinned toolchain: `SwarmRegistry` 16,480 B; `LifecycleLib` 20,903 B; `MembershipLib` 12,047 B; `ResourceLib` 4,819 B; `SpecValidator` 2,759 B; `SwarmDecisionAdapter` 12,165 B; `SwarmTenderAdapter` 3,753 B; `SwarmAccount` 2,672 B. The registry delegates to external libraries, each within the EIP-170 limit; Foundry links them automatically at deployment.

ERC-165 identifiers: `ISwarmRegistry` `0x085203a4`, `IEligibility` `0xd0ede3d8`, `ISwarmAccount` `0x25e98353`, `IResourceAdapter` `0x8e20b298`.

## Identifiers

| Kind | Form | Base set |
|---|---|---|
| dimension | `keccak256("sai.dimension.<d>")` | `payoff`, `topology`, `coordination` |
| posture term | `keccak256("sai.<d>.<name>")` | the fourteen base terms above, registered at deployment; further terms by anyone, write-once |
| role | `keccak256("sai.role.<name>")` | `initiator` (checked at formation when present), `coordinator`, `worker`, `verifier`, `observer`, `bidder` as conventions |
| origin | `keccak256("sai.origin.<name>")` | `initiator`, `joint`, `task`, `trigger`, `decision`, `succession` |
| resource kind | `keccak256("sai.resource.<name>")` | `skill`, `dataset`, `tool`, `code`, `model`, `document`, `oracle`, `fund`; unknown kinds accepted |
| digest kind | `keccak256("sha-256")`, `keccak256("keccak256")` | or a kind an adapter defines |
| decision question | `keccak256("sai.dp.<name>")` | one per decision point; effects `sai.enact` / `sai.refuse`, disposition `sai.status-quo` |
| EIP-712 | domain `SAI` / `1` | `Join(bytes32 swarmId,address account,bytes32 roleId,bytes32 charterHash,uint256 seatEpoch,uint32 phase,uint256 deadline)` |

## Position in the standards family

| Standard | Role | Relation to SAI |
|---|---|---|
| ERC-8001 Agent Coordination Framework (Final) | one coordinated act: intent + unanimous acceptances + one execution | SAI is the organization within which such acts happen; the joint-action binding is a reserved extension |
| ERC-8436 Agent Collective Decision Framework | how a group decides | SAI says what the group is and does; a decision adapter is a relying contract of ERC-8436 holding decision points |
| ERC-8004 Trustless Agents | identity, reputation, validation | optional member identity through an eligibility module; outcome feedback may flow back |
| ERC-8063 token-gated groups | balance as membership | a balance can gate a role; a working group also needs charter, roles, commitments and closure |
| Token-Bound Task Tenders (draft) | demand side: what is wanted, where the bounty is, who judges | SAI is the supply-side organization; the swarm account fulfils, the tender adapter concludes the swarm |
| Know-Your-Agent Framework, Agent Identity (drafts) | who the members are, whether they are trusted | eligibility modules; `challenge` moves the boundary when an assertion is revoked or an identity goes stale |
| Token-Bound Executable Skills (draft) | skill assets | the `skill` resource kind; the adapter reads the package digest the skill reports |
| ERC-8444 ARD Onchain | discovery | a recruiting swarm can be published as a value record (informative) |

## Next steps

Editor review and merge of PR #2081 (ERC-8447 files on the branch); the Sepolia evidence run of Case A and Case B (`deployments/`); Case C (standing committee with `succeed()`) in a later round.

## License

CC0-1.0 — see `LICENSE.md`.
