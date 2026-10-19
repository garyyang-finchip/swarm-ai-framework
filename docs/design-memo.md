# Swarm AI Framework (SAI) — Design Memo

Version 0.3.2 — 2026-10-20 — status tags: [Decided] fixed for the proposal, [Open] left for a later round.

## 0. What this document is

The mechanism memo behind `ERCS/erc-8447.md`. It records the three definitions the proposal rests on — formation and boundary, objective and attainment, collaboration modes — as an object model, a state machine and rules; the orthogonal classification of collaboration modes; the compatibility map to the surrounding standards; and, in Section 11, the decisions log: the twelve rulings taken on the v0.1 open questions, the items added from the advisory review, and the first review round of the Magicians thread (revision 2). The ERC text is normative; this memo explains why it says what it says. Where v0.1 differed, the v0.2 text wins.

## 1. Positioning

### 1.1 One-sentence definition [Decided]

> SAI defines how autonomous agents — and any other account that qualifies — form, bound, run and dissolve a swarm: a purpose-bound collective with an explicit membership boundary, an objective with attainment rules and a declared collaboration structure, recorded as one interoperable on-chain object.

In four clauses: **the charter organizes the swarm; boundary and eligibility decide who is inside; objective and attainment decide when it exists; the posture coordinate declares how it works.** The registry holds the normative record and never executes external effects; adapters connect decisions and obligations.

### 1.2 Naming [Decided]

| Where | Name |
|---|---|
| ERC title | Swarm AI Framework (18 characters; no "standard"); number ERC-8447 |
| Abbreviation | SAI |
| Identifier prefix | `sai.` — `keccak256("sai.role.<name>")`, `keccak256("sai.resource.<name>")`, `keccak256("sai.dp.<name>")`, `keccak256("sai.origin.<name>")`, `keccak256("sai.dimension.<d>")`, `keccak256("sai.<d>.<term>")` |
| EIP-712 domain | name `SAI`, version `1` |
| Core objects | Swarm, Spec, Charter (Swarm Pack), Member, Role, Phase, Posture, Decision Point, Authority, Objective, Outcome, Origin, Resource, Term |

"Swarm" is used in the collective-intelligence sense — autonomous members acting in concert around a purpose — and the proposal is unrelated to decentralized storage networks that share the word; the Rationale says so in one sentence.

### 1.3 What it is, what it is not

A minimal interoperable kernel for swarms plus normative-optional profiles. It is not: an orchestration framework or message protocol (those implement the charter's `coordination`); a decision system (ERC-8436 is, and the swarm is its relying contract); a task standard (tenders are, and the swarm fulfils them); a credit system (eligibility reads trust registries and never writes credit); a treasury (the swarm account holds value, the registry holds none).

### 1.4 Place in the standards family [Decided]

| Standard | Role | Relation to SAI |
|---|---|---|
| ERC-8001 (Final) | one coordinated act among a fixed participant set | act versus organization: SAI defines the group within which acts happen; joint-action binding reserved; informative |
| ERC-8436 | how a group decides | SAI defines what the group is and does; decision points are held by a decision adapter that is an ERC-8436 relying contract; normative profile, `requires` |
| ERC-8004 | agent identity, reputation, validation | optional member identity through an eligibility module; a swarm that wants every member to be a registered agent binds the module to every role; `requires` |
| ERC-8063 | token balance as group membership | a balance can gate a role; a working group also needs charter, roles, commitments and closure; positioned in the Motivation |
| Token-Bound Task Tenders (draft) | demand side | SAI is the supply-side organization; the swarm account is the fulfiller of record; the tender adapter concludes the swarm from the tender's record |
| Know-Your-Agent, Agent Identity (drafts) | who the members are, whether they are trusted | eligibility modules at admission and on challenge; the initiator is checkable by address through the same registries |
| Token-Bound Executable Skills (draft) | skill assets | the `skill` resource kind; a skill adapter reports the package digest under the skill standard's own algorithm |
| ERC-8033 | information agents plus a judge for one query type | one point in the posture space (`mixed x redundant x leader`) |
| ERC-8183 | one job, one provider, one evaluator | single supplier; SAI covers plural suppliers |
| ERC-8444 | discovery | a recruiting swarm is, in posture, a demand for members; informative |

Unmerged drafts are referenced descriptively in the ERC text (eipw and HTMLProofer would reject links to files that do not exist in `ethereum/ERCs`); their kernel interfaces are vendored number-neutrally under the assets.

### 1.5 Why a registry record, not a token [Decided]

Skills and task tenders are assets and are ERC-721 extensions. A swarm is an organization: transferring a team is meaningless, but a team owns things. SAI is therefore a registry with records and an optional account, like the decision, trust and discovery registries of the family, and a swarm that wants to be found registers itself with the discovery layer.

## 2. Design principles [Decided]

1. **The kernel fixes invariants; charters fix rules.** Executed parameters are a hashed struct (`SwarmSpec`); descriptive content is a hashed off-chain pack (`charterHash`). Two commitments, two layers, one object.
2. **Authority slots, not hard-coded governance.** Sixteen decision points, each with one authority of kind `ADDRESS`, `ROLE`, `ANY_MEMBER`, `INITIATOR` or `NONE`. One mechanism covers initiator-run, coordinator-run, collective (through an adapter) and automated (verifier) steering. `ADDRESS` slots are transferable by their holder.
3. **Membership is a ledger, eligibility is a predicate, credit lives elsewhere.** The registry records states; modules answer "qualified?"; anyone may trigger a re-check; credit is never copied in.
4. **Leaving is always available; consequences are external.** An autonomous account cannot be held; bonds and reputation are profiles.
5. **Three result dimensions.** Lifecycle state, outcome type with reason, settlement status — kept apart as in ERC-8436.
6. **Typed conditions, authority-triggered, with a permissionless exit from every state.** Objective, roster, decision and external predicates are the primary paths; time is a guard, and at least one time guard is mandatory in every state including `FORMING`.
7. **Modes are coordinates, not an enum; declared dimensions are a vocabulary, not an enum either.**
8. **Nesting.** `parentId` for child swarms; co-opetition is a parent with `exclusive` payoff over children that are `shared` inside.
9. **The kernel does not know what an agent is.** Members are accounts; agent-ness is an eligibility predicate. Non-principal elements are resources.
10. **Credit and power are separate records.** Origin (what the formation came from), initiator (who submitted it) and authorities (who holds power) are three fields; none implies another.
11. **The kernel never interprets silence.** No proof received, a module that reverts, a decision body that does not decide are "unknown, no change", never success, failure or malice.

## 3. Definition 1 — formation and boundary

### 3.1 Recruitment triggers and origin [Decided]

| Trigger | Expression | `Origin.kind` |
|---|---|---|
| one account initiates | `form()`; `msg.sender` is the initiator, recorded for ever, powerless unless the spec says otherwise | `sai.origin.initiator` |
| several accounts initiate jointly | a joint-initiation contract (or an ERC-8001 execution) calls `form()`; the initiator is that contract | `sai.origin.joint` |
| a task calls for a swarm | anyone forms the swarm with the tender as `obligation`; `ref` hashes the task reference | `sai.origin.task` |
| a rule fires | a trigger contract forms on a condition; `ref` is the rule hash | `sai.origin.trigger` |
| a collective decides to form | a decision adapter forms on a `Final x Yes`; `ref` is the issue id | `sai.origin.decision` |
| a swarm succeeds itself | `succeed()`; `ref` is the predecessor id | `sai.origin.succession` |
| emergent | a matchmaker merges registered intents and forms; reserved extension | an extension kind |

The initiator's trust: `sai.role.initiator` may carry an eligibility module checked at `form()`; because the initiator is an address, any party can later evaluate it through the trust and identity registries. SAI guarantees only that the record cannot change.

### 3.2 Two-layer charter [Decided]

`SwarmSpec` (on-chain, executed, frozen): roles, phases with posture, sixteen authorities, activation rule, contribution mode, member bounds, fallback durations. Swarm Pack (off-chain, versioned, `charterHash = SHA-256(JCS(root))`): charter text, objective descriptor (`objectiveHash`), the members' economic commitment — allocation per phase, costs, liabilities, data access, actions in their name — (`commitmentHash`), collaboration structure per phase, roles in words, resource manifest, decision-point descriptions, `prev`. Three hashes are on-chain: the pack's, the objective's and the commitment's. The pack names the spec it describes; the spec is what runs.

### 3.3 Boundary [Decided]

`OPEN` (eligible accounts join; self-join roles), `GATED` (apply plus admit, in either order), `CLOSED` (no admission). Declared per phase, so a tender is open while bidding and closed while executing. Admission is two-sided: the authority side (`admit`, or self-join under `OPEN`) and the member side (`join` / `applyToJoin` / `acceptCharter` / `joinBySig` naming the current charter hash under the current commitment version). The signed form binds the seat epoch and the phase, so a relayed signature cannot re-seat an account that has left or been dropped by a phase change. A substituted seat already exists, so completing it is exempt from boundary, input-window and maximum checks — a compromised worker can be replaced in a `CLOSED` phase.

### 3.4 Member state machine [Decided]

`CANDIDATE -> ACTIVE <-> SUSPENDED -> EXITED{LEFT, REMOVED, INELIGIBLE, NOT_CARRIED, REPLACED, SWARM_DISSOLVED}`. Actions and their authorities are tabulated in ERC Section 6; `leave` is the member's alone and always succeeds; roster-wide exits are derived lazily.

### 3.5 Malfunctioning, retired, drifted or compromised members [Decided]

Three lines of defence, each with a clear owner: (1) the eligibility predicate — a revoked assertion, a stale or retired identity, a transferred agent makes `challenge` suspend the member automatically; a reverting module, a non-boolean answer or a `false` returned with less than one eighth of the pre-call gas (a starved inner read) changes nothing; the path back is symmetric — anyone's `challenge` reinstates a member suspended for ineligibility once the module answers `true` again, and `expel` after the grace period re-evaluates the module before acting, so nobody is expelled on the clock alone; (2) the `REMOVE` decision point — judgment, by a coordinator or by a collective decision; (3) substitution — a successor account takes the seat (`substitute`), the old one exits `REPLACED` with history kept. Contributions recorded while suspended carry a flag so allocation can exclude them. A suspension takes effect for the registry's own gates at once; what the member's software keeps doing off-chain is for execution environments. Decisions already filed are decided by the roster snapshotted at filing; the registry's refusal at execution is what stops an enactment the ledger no longer allows.

### 3.6 Start and end conditions [Decided]

| Kind | Start (FORMING -> ACTIVE) | End (-> CONCLUDING) | Who |
|---|---|---|---|
| ROSTER | thresholds met (`activate` by anyone under `ROSTER_MET`) | roster lost (`enforceRoster` by anyone; deferred for one recruitment window after a re-forming advance) | kernel |
| OBJECTIVE | — | acceptance authority records the outcome | acceptance authority |
| AUTHORITY | `ACTIVATE` slot | `CONCLUDE` slot | authority (may be a decision adapter) |
| EXTERNAL | an adapter reading an external predicate activates | an adapter reading the obligation concludes | adapter as authority |
| DEADLINE (guard) | `recruitmentWindow` -> anyone aborts | `maxDuration` -> anyone enforces (`ABANDONED`, `TIMEOUT`); `inactivityTimeout` -> suspend, then conclude | anyone |

Rule: `maxDuration > 0 || inactivityTimeout > 0`, and `recruitmentWindow > 0` so that `FORMING` always has a permissionless exit (an `ABORT` authority only adds an earlier one). Time is never the definition of attainment; it is always available as a guard. Standing swarms set a long cap and continue through `succeed()`.

### 3.7 Swarm lifecycle [Decided]

`FORMING -> ACTIVE <-> SUSPENDED -> CONCLUDING -> DISSOLVED`, with `abort` from `FORMING`, `conclude` from `ACTIVE` or `SUSPENDED`, `succeed` producing a successor and a `SUPERSEDED` outcome. In `CONCLUDING` the ledger can only shrink by a member's own `leave` while settlement reads it; `DISSOLVED` is terminal. Every transition increments the swarm's revision counter and emits `Changed(swarmId, revision, selector, by)`.

## 4. Definition 2 — objective and attainment

### 4.1 Objective object [Decided]

`objectiveHash` (versioned with the charter), `kind` (`TERMINAL`, `MILESTONED`, `EXPLORATORY`, `STANDING`), `acceptanceAuthority` (verifier contract, judge, decision adapter or obligation adapter — the same 0-of-0 -> 1-of-1 -> K-of-N spectrum the tender standard uses), `obligation` (optional external reference), `milestoneCount`. `EXPLORATORY` exists because a search that ends has not proved anything false: it concludes `PARTIAL` or `ABANDONED` unless infeasibility was established.

### 4.2 Start, process, attainment, change [Decided]

Start logic is the activation condition; process logic is phases plus milestones plus the contribution stream (attribution, never judgment; mode `DISABLED`, `MEMBERS` or `OPEN` per spec); attainment is `conclude(outcome, resultHash)` with `ACHIEVED` gated on all milestones for milestoned objectives; change logic is amendment for the pack — minor (objective and commitment hashes unchanged, not declared material: charter version only) or material (a changed objective or commitment hash makes it so by construction, or the authority declares it; commitment version increments, exit window opens, pending admissions hold until the candidate accepts the new commitment) — and succession for the spec; `ADDRESS` authorities transfer, `ROLE` authorities rotate with the ledger.

### 4.3 Swarm as fulfiller; tender calls swarm [Decided]

Normative-optional obligation profile: the swarm account is the tender's fulfiller of record; an obligation adapter is the acceptance authority and concludes `ACHIEVED` on acceptance, `ABANDONED` on cancellation, `FAILED` when the settlement deadline passes. The reverse convention (a tender naming an acceptable spec) is informative.

### 4.4 Result dimensions [Decided]

Lifecycle state (kernel), outcome type with reason (acceptance authority / `CONCLUDE` slot / guards), settlement (account or obligation). Allocation is to be computed by the record — roster, phase and charter version under which work was recorded — not by the roster at settlement.

## 5. Definition 3 — collaboration modes as coordinates

### 5.1 Why a flat list is not orthogonal [Decided]

"Cooperation / competition / co-opetition" answer how value is divided; "tender / staged elimination" answer how the roster changes across phases. One list mixes two axes, so it is both incomplete (no redundant-work-shared-reward, no pipeline, no hierarchy, no debate) and dependent (a tender is already competition then cooperation). The fix is a coordinate system.

### 5.2 Five dimensions, per phase [Decided]

| Dimension | Question | Executed? | Values |
|---|---|---|---|
| Payoff | how value maps to members | declared (vocabulary) | `shared`, `exclusive`, `mixed`, + registered terms |
| Topology | how the objective is decomposed | declared (vocabulary) | `redundant`, `partitioned`, `sequential`, `hierarchical`, `iterative`, `free`, + registered terms |
| Coordination | who steers | declared (vocabulary) | `leader`, `collective`, `market`, `automated`, `none`, + registered terms |
| Boundary | who may enter | executed | `OPEN`, `GATED`, `CLOSED` |
| Admission | how the roster passes from the previous phase | executed | `RECRUIT`, `INHERIT`, `SELECT` |

Plus the phase sequence itself. Independence: each dimension answers one question no other answers. Completeness: every organizational form lands on a coordinate or trajectory; not every coordinate is common, every one is meaningful. Extensibility: a new way of working is a new registered term under one dimension, usable by every swarm on the instance, with no kernel change. Verification (who checks whose work) is deliberately not a mode dimension: it belongs to the objective's acceptance authority and milestones. Elimination is a membership fact (`SELECT`), not a payoff fact: a phase that keeps every member while choosing among their proposals uses `INHERIT`.

### 5.3 The vocabulary registry [Decided]

Dimension identifiers `keccak256("sai.dimension.payoff|topology|coordination")`; term identifiers `keccak256("sai.<d>.<name>")` for the fourteen base terms, seeded by every conforming registry at deployment. `registerTerm(dimension, term, uri)` is permissionless and write-once; a spec naming an unregistered term is invalid at formation. This is the "registry form" of on-chain posture: small on-chain, extensible without a kernel change, every term resolvable to a published description.

### 5.4 Named modes as trajectories

Cooperation `shared x partitioned | sequential`; competition `exclusive x redundant x automated | leader`; contest with a shared purse `shared x redundant`; co-opetition parent `exclusive x hierarchical` over `shared` children (or single swarm `mixed`); tender `OPEN exclusive x redundant` -> `SELECT` -> `CLOSED shared x partitioned`; staged elimination repeated `exclusive x redundant` through `SELECT`; debate `iterative x collective`; ensemble `shared x redundant x automated`; oracle council (ERC-8033 shape) `mixed x redundant x leader`; pipeline `shared x sequential`; hierarchical decomposition `shared x hierarchical x leader` with child swarms; standing committee `OPEN` boundary with a `STANDING` objective; internal market `market` coordination.

### 5.5 Where ERC-8436 sits [Decided]

`collective` coordination means steering decisions run through ERC-8436. The executable hook is the authority slot: any decision point may be held by a decision adapter that is a relying contract of an ERC-8436 registry. The reference adapter: the deciding role's roster at the moment of filing becomes one policy version in a family keyed by (adapter, swarm, decision point), because that standard freezes a policy's roster; the issue is `CONSUMER_FILED` with subject `(dp, exact call, charterVersion, phase)`, question `sai.dp.<name>`, effects `sai.enact` / `sai.refuse`, disposition `sai.status-quo`, obligation `(swarmId, dp, call, phase)`; the consumer deadline is the earlier of the swarm's hard deadline and the phase's input window end (when still ahead) minus the execution margin; `execute` performs the recorded call only on `Final x Yes` and only while the commitment version and the phase are unchanged (revision 2.2: `advance` is relative, so an approval from an earlier phase would perform a different transition than the one voted on, and a `SELECT` advance replaces the deciding roster). `NoDecision` and `No` do nothing. Zero decision logic in the kernel. In one line: **the swarm decides what the group is; ERC-8436 decides how the group decides.**

### 5.6 Reserved [Decided]

Allocation functions; internal market primitives; bonds and penalties; joint-action binding to ERC-8001; matchmaking; privacy; cross-chain members and obligations; per-phase timers beyond the input window; delegated seats.

## 6. Non-agent participation [Decided]

Two forms. As a **member**: anything with an address — a deployed program that can sign or verify through ERC-1271 — may join, accept the charter, pass eligibility and receive allocation; the kernel does not ask whether it is an AI. As a **resource**: elements without agency (executable skills, datasets, tools, code digests, model references, documents, oracles, funds) are attached by kind, optional anchor, digest with digest kind, URI, role scope and provider; they hold no seat, pass no eligibility and receive no allocation; their controllers may be members or beneficiaries; metered resources bill through their own contracts. Both layers are used: an on-chain minimal anchor list so relying contracts can verify "this swarm uses skill #X at digest H", and the off-chain manifest for details. Verification is flexible and optional: `digestKind` says how a digest was computed (SHA-256, Keccak-256, or whatever an anchored standard reports), a deployment may bind a per-kind `IResourceAdapter` that checks `exists` and `digestOf` at attach time, and unknown kinds are always accepted. Four relations stay distinct: member, user of a resource, controller of a resource, beneficiary of a resource.

## 7. Compatibility and `requires` [Decided]

`requires: 165, 712, 1271, 6372, 8004, 8436`. ERC-8436, ERC-8004 and ERC-8444 are merged and may be linked. The task-tender, trust-assertion, agent-identity and executable-skill drafts are referenced descriptively, their kernel interfaces vendored number-neutrally in the assets; numbered references are restored in a follow-up once they merge. ERC-8001, ERC-8063 and ERC-8444 are informative.

## 8. Interface summary

See ERC Sections 12 and 13: `form / activate / abort / suspend / resume / enforceRoster / enforceInactivity / enforceDeadline / advance / conclude / dissolve / succeed`; `amend / setCharterURI / transferAuthority / setAccount`; `applyToJoin / join / joinBySig / acceptCharter / admit / leave / suspendMember / reinstate / remove / challenge / expel / substitute`; `recordContribution / recordMilestone`; `attach / detach / registerTerm`; views including `acceptedCharterOf`, `seatEpochOf`, `isAuthorized`, `hardDeadlineOf`, `joinDigest`, `isTerm`, `termURI`; `IEligibility`, `ISwarmAccount` (`swarmId`, `registry`, `recoveryAddress`), `IResourceAdapter`. Reference adapters: `SwarmDecisionAdapter` (ERC-8436), `SwarmTenderAdapter` (task-tender kernel); modules: allowlist, composite, ERC-8004 identity, trust-assertion level, identity state; `SwarmAccount` executing under `REPRESENT` while the swarm lives and `recover`ing through its recovery address after dissolution.

## 9. Security themes (expanded in the ERC)

Sybil rosters; initiator power; griefing through fallbacks and challenges; unbounded rosters (lazy exits); replayed acceptances; recruitment spam and seat squatting; frozen rules and transferred slots; compromised members; decisions under way; allocation drift; settlement after dissolution; arrival-time windows; untrusted URIs; registry instance trust.

## 10. Implementation notes

- The registry exceeded the EIP-170 limit as one contract (35,484 B). It is split into `SwarmRegistry` (16,480 B; storage, authority gates, revision log, views) and the external libraries `LifecycleLib` (20,903 B), `MembershipLib` (12,047 B), `ResourceLib` (4,819 B) and `SpecValidator` (2,759 B), all sharing one `SAIStore.Store` layout and executing by `DELEGATECALL` in the registry's context; events are emitted through the qualified `ISwarmRegistryEvents` interface so that they appear as the registry's. Solidity 0.8.24, IR pipeline, optimizer runs 1.
- Roster-wide exits (`SWARM_DISSOLVED`, `NOT_CARRIED`) are derived by `memberStatus` from `rosterPhase` / `carriedPhase` and the lifecycle state; no transition loops over the roster.
- `challenge` and `expel` share one module call: a revert, a non-boolean return or a `false` returned with less than one eighth of the pre-call gas is `(evaluated=false, eligible=false)`; `challenge` then changes nothing, `expel` reverts `SAI_Unevaluable`. One eighth because a catching layer keeps one sixty-fourth of its own budget, so a starved inner read returns with about two sixty-fourths and nested catches add one sixty-fourth each.
- `isAuthorized` returns `false` for every kind once the swarm is `DISSOLVED`; the account's `recoveryAddress()` is the only post-dissolution path.
- The decision adapter ignores an input-window end already in the past when computing the consumer deadline, so a decision taken after a bidding window closed (advancing the phase) is bounded by the hard deadline alone.
- Vectors are produced by ethers v6 and an independent JCS canonicalizer, cross-checked against a Python canonicalizer and re-derived in Solidity.

## 11. Decisions log (round 2)

### 11.1 Rulings on the v0.1 open questions

| # | Question | Ruling | Where it landed |
|---|---|---|---|
| 1 | Title and abbreviation | Swarm AI Framework; abbreviation **SAI**; `sai.` prefix | preamble; Section 1; every identifier; EIP-712 domain |
| 2 | `requires` | 165, 712, 1271, 6372, 8004, 8436 | preamble; Backwards Compatibility |
| 3 | Spec mutability | frozen; `succeed()` for structural change; `ADDRESS` slots transferable | Sections 3.3, 9.2, 11.3 |
| 4 | Member scope | any account; a swarm that wants ERC-8004 agents binds the module itself | Sections 6, 14.2; `ERC8004Eligibility` |
| 5 | Resources | on-chain anchor list plus off-chain manifest; hash verification flexible and optional, never fixed to one algorithm | Section 10: `digest` + `digestKind`, optional per-kind adapter, unknown kinds accepted |
| 6 | Swarm account | optional field plus minimal interface | Sections 11.1 (`SET_ACCOUNT`, `REPRESENT`), 13.2 |
| 7 | Posture on-chain | yes, in registry form rather than enums: a write-once term vocabulary | Section 7.1; `registerTerm`, `isTerm`, `termURI`; `term-ids.json` |
| 8 | Time guard | mandatory: `recruitmentWindow > 0`, and `maxDuration > 0 || inactivityTimeout > 0` | Section 3.2 |
| 9 | Tender direction | swarm-as-fulfiller normative-optional; tender-calls-swarm informative | Section 14.3; `SwarmTenderAdapter`; Case A |
| 10 | Contribution log | in the kernel, optional per swarm | Section 6.6: `Contributions {DISABLED, MEMBERS, OPEN}` |
| 11 | ERC-8001 | informative plus reserved extension | Motivation; Section 17; Rationale |
| 12 | Testnet cases | A and B now; C later | `test/SAICaseA.t.sol`, `test/SAICaseB.t.sol`; `script/DeployRegistry.s.sol` |

### 11.2 Items added from the advisory review

| Item | Resolution |
|---|---|
| Origin of a swarm distinct from its initiator and its authorities | `Origin {kind, ref}` recorded at formation (Section 3.4); succession sets it automatically; Rationale "three records" |
| Amendments that re-order work should not force every member to re-sign | two classes: minor (charter version only) and material (commitment version, exit window, completion hold) (Section 9.1) |
| Who may act for the swarm through its account | the `REPRESENT` decision point; `SwarmAccount.execute` gated on `isAuthorized(REPRESENT)` (Sections 11.1, 13.2) |
| An ordered change log readers can rely on | per-swarm revision counter and `Changed(swarmId, revision, selector, by)` (Section 5.4) |
| Research-type objectives whose end is not success or failure | `ObjectiveKind.EXPLORATORY` with its outcome rules (Section 8) |
| Resource provenance and digest algorithm | `provider` and `digestKind` on the resource record; `IResourceAdapter.digestOf` returns both (Sections 10, 13.3) |
| ERC-8436 freezes policy rosters while swarm rosters change | the decision adapter snapshots the deciding role per decision as a policy version in a per-(swarm, decision point) family (Section 14.1) |
| Decisions in flight when membership changes | decided by the snapshot; the registry's refusal at execution is the safeguard; `execute` requires an unchanged commitment version (Security Considerations) |
| Allocation by the roster at settlement rewrites entitlements | contribution records carry phase and charter version; the allocation-drift consideration advises paying by the record |
| Relation to token-gated groups | ERC-8063 positioned in the Motivation: a balance can gate a role, a group needs more |
| Unknown is not a verdict | Rationale on eligibility and challenge; reverting module = no change; `NoDecision` = status quo |
| Suspension versus the member's off-chain software | Security Considerations "Compromised members" distinguishes the registry's gates from execution environments |

### 11.3 First thread review — revision 2 (2026-10-19)

Posts #2–#4 of Magicians topic 29998, within eight hours of the opening post; all three accepted, all three implemented before the replies (`docs/magicians-replies-2026-10-19.md`). The second round (#8 Zealynx, Revinand's second post) followed within a day of revision 2 and is handled the same way.

| Post | Finding | Resolution |
|---|---|---|
| #2 SergeevDmitry | The amendment authority could change the allocation rule and call it minor: the exit window depended on the party it was meant to constrain, and allocation lived in the pack where the registry cannot see it | The pack gets a `commitment` member (allocation per phase, costs, liabilities, data access, actions in the members' name) with its own `commitmentHash`, committed at formation and passed to `amend` and `succeed`; a changed objective or commitment hash is material by construction, the `material` flag is one-way. Answers question 2 of the opening post. Schema moves `allocation` out of the phases; charter vectors regenerated; `ISwarmRegistry` id changed |
| #3 Zealynx | (a) A third-party module that catches its own reads answers `false` when a caller starves the inner read (63/64 rule), suspending an honest member; (b) `expel` never re-read the module, so a lapsed-and-recovered identity was expelled after grace unless someone reinstated in time; one suspension can cascade into `enforceRoster` | (a) Remainder rule in `challenge`/`expel`: a `false` with less than one eighth of the pre-call gas left is unevaluable (one eighth, not one sixty-fourth: a catching layer keeps 1/64 of its budget, nested catches add 1/64 each); the attack is in the suite. (b) `expel` re-evaluates — `true` reinstates, unevaluable reverts; `challenge` is symmetric and reinstates on `true`; `REINSTATE` stays for judgment. Cascade acknowledged in the text: `ROSTER_LOST` is a pause with permissionless `resume`, contributions stop and the inactivity clock runs |
| #4 Revinand | "The reference account stops acting once nobody is a member" held only for `ROLE`/`ANY_MEMBER` representatives; `ADDRESS`/`INITIATOR` kept acting after dissolution, so two swarms on the same account code recovered assets differently by authority kind | `isAuthorized` returns `false` for every kind in a `DISSOLVED` swarm; the account profile must state its post-dissolution rule on-chain (`recoveryAddress()`), independent of the `REPRESENT` kind, settable only by a representative before dissolution, frozen with the swarm; the reference account adds `recover`. Dissolution stays permissionless; distribution by representation happens in `CONCLUDING`. `ISwarmAccount` id changed |
| #R2 Revinand (second round) | `execute` compared only the commitment version; `advance` is relative and a phase change does not touch that version, so two `ADVANCE` proposals approved in phase 0 moved a three-phase swarm to phase 2 on phase 0's votes — and after a `SELECT` advance the phase-0 roster would have decided for the phase-1 one | Revision 2.2: every proposal is bound to the phase it was filed in — the phase is in the issue subject and in the obligation id, stored with the proposal, and `execute` refuses on `Yes` when the swarm's phase differs, as it does on a changed commitment version; chosen over an `ADVANCE`-only check (a list of phase-dependent points would have to be maintained) and over a target phase in `advance` (interface change for no gain). Two regressions: two approved advances that do not chain; an `ADMIT` approved in phase 0 refused in phase 1 and re-filed |
| #8 Zealynx (second round) | With reinstatement on evidence, a balance-gated module can be flash-loaned to `true`: a suspended member borrows the threshold, challenges itself back and repays in one transaction; admission and `SELECT` share the exposure | Revision 2.1 (text only): Section 6.4 binds every module — no answer from a quantity the evaluated account can change within the transaction; balance gates read checkpointed (ERC-5805 `getPastVotes`), time-weighted or held-since values; Security Considerations add "Modules that can be made to answer `true`". Reference modules are not balance-based |

### 11.4 Deferred [Open]

Case C (standing committee with `succeed()`); bonds and penalties; matchmaking (`sai.origin.*` extension kinds); cross-chain members and obligations; a normative joint-action binding to ERC-8001; outcome feedback scale into ERC-8004 reputation.

## 12. Next rounds

Round 3 (done 2026-10-18): Magicians thread 29998 and `discussions-to`; fork branch `add-erc-swarm-ai` cut from `ethereum/ERCs` master with the package from `scripts/make-filing-package.py`; PR #2081 under the placeholder number; revision 2 from the first review round; number **ERC-8447** assigned 2026-10-19 and the files renamed (`ERCS/erc-8447.md`, `assets/erc-8447/`, links `../assets/eip-8447/`). Sepolia evidence run done 2026-10-19 (`docs/sepolia-evidence.md`, `deployments/`): the reference contracts deployed from revision 2.1 with exact Sourcify matches, Cases A and B executed end to end against the live ERC-8436 registries and the live task tender kernel, 71 transactions, all successful; the live chain priced the same transactions 4–10× the local rehearsal, which changes nothing in the design. Revision 2.2 (2026-10-20, from the second review round): the decision adapter binds proposals to their filing phase; text in Section 14.1, the Rationale and Security Considerations; two regressions; the Sepolia adapters predate it. Next: editor merge. Later: Case C; numbered references to the companion drafts once they merge.
