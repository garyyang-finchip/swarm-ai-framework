# Ethereum Magicians post — draft

Category: ERCs. Title: **[Draft ERC] Swarm AI Framework — registry and charter model for purpose-bound agent swarms**

Posted 2026-10-18 as Ethereum Magicians topic 29998 (`https://ethereum-magicians.org/t/draft-erc-swarm-ai-framework-registry-and-charter-model-for-purpose-bound-agent-swarms/29998`), which is the ERC's `discussions-to`. The pull request (ethereum/ERCs#2081) is linked from the first post; the editors assigned ERC-8447 on 2026-10-19 and the topic is retitled `ERC-8447: Swarm AI Framework`.

---

## Summary

We propose a registry and charter model through which autonomous agents — and any other account that qualifies — form, bound, run and dissolve **swarms**: purpose-bound collectives with an explicit membership boundary, an objective with attainment rules and a declared collaboration structure, recorded as one interoperable on-chain object.

Agent standards so far cover the individual (identity, reputation, validation), the act (one coordinated action among fixed participants), the decision (policies, bodies, finality) and the job (one task, one provider). None of them says what a group of agents *is*: who is inside now and under which commitment, why the group exists, how it is organized, and when it stops existing. Every pipeline that needs that today redefines it in application code or in a chat protocol, and no counterparty — a task tender, a treasury, an indexer — can read it.

Draft text: https://github.com/garyyang-finchip/swarm-ai-framework/blob/main/ERCS/erc-8447.md
Reference implementation, schemas, vectors and tests: https://github.com/garyyang-finchip/swarm-ai-framework
ethereum/ERCs pull request: to be added after filing.

## What the ERC fixes

- **Two commitments, one object.** Everything the registry executes — roles with eligibility modules, phases with their posture, one authority per decision point, activation rule, contribution mode, fallback timers — is a hashed struct, `specHash = keccak256(abi.encode(SwarmSpec))`, frozen at formation; structural change is succession. Everything that is described rather than executed — the charter text, the objective descriptor, the allocation rule, the resource manifest — is an off-chain Swarm Pack, `charterHash = SHA-256(JCS(root))`, versioned.
- **Two-sided admission.** An authority admits, the member accepts the current charter under the current commitment version; either order; signed acceptance (EIP-712 / ERC-1271) binds the charter hash, the seat epoch and the phase. Leaving is always available. Anyone may `challenge` a member against its role's eligibility module; `false` suspends, a revert changes nothing; expulsion follows a grace period; substitution replaces a seat even in a closed phase.
- **Time is a guard, never a success criterion.** Objectives, rosters and decisions end a swarm; every state, including forming, has a permissionless exit after a declared fallback, and a spec without one is invalid. Lifecycle state, outcome type with reason, and settlement are three separate dimensions.
- **Posture is a coordinate per phase**, not a mode enum: boundary (`OPEN / GATED / CLOSED`) and admission (`RECRUIT / INHERIT / SELECT`) are executed; payoff, topology and coordination are declared as terms of a write-once vocabulary kept by the registry (`shared / exclusive / mixed`; `redundant / partitioned / sequential / hierarchical / iterative / free`; `leader / collective / market / automated / none`; anyone may register further terms). Cooperation, competition, co-opetition, tenders, staged elimination, debate, ensembles and pipelines are points and trajectories in this space.
- **Amendment in two classes.** Minor amendments change the text within what members committed to; material amendments increment the commitment version, open an exit window and hold pending admissions until the candidate accepts the new commitment.
- **Decisions are an adapter, not kernel logic.** Any decision point may be held by a relying contract of ERC-8436; the reference adapter snapshots the deciding role as a policy version per decision, files the exact call as the issue subject and enacts only `Final x Yes`. `NoDecision` is the status quo.
- **The kernel holds no value and does not know what an agent is.** Members are accounts; agent-ness, trust level and identity state are eligibility predicates read live from the registries that hold them (ERC-8004 among them). Non-agent elements — executable skills, datasets, code, models, documents, oracles, funds — are **resources**: attached by kind, optional anchor, digest and digest kind, provider and role scope; they hold no seat and receive no allocation; a per-kind adapter may verify anchors at attach time.
- **Obligation binding.** A swarm may bind its objective to an external duty such as a token-bound task tender; the swarm account is the fulfiller of record and an obligation adapter concludes the swarm from the tender's record.

`requires: 165, 712, 1271, 6372, 8004, 8436`. ERC-8001 (coordinated acts), ERC-8063 (token-gated groups) and ERC-8444 (discovery) are positioned informatively.

## Reference implementation and evidence

Non-upgradeable registry (16,379 B) with three external logic libraries and a spec validator, a swarm account acting under a `REPRESENT` authority, an ERC-8436 decision adapter, a task-tender adapter and five eligibility modules (allowlist, composite, ERC-8004 identity, trust-assertion level, identity state). 85 Foundry tests, including two end-to-end cases run against the **real** ERC-8436 reference registries and a real token-bound task tender kernel: a tender-bound cooperative swarm paid through its account, and a two-phase tender (open bidding, selected execution) with a challenge and a substitution. Deterministic vectors (`specHash`, EIP-712 `Join` digests, charter hashes from two independent canonicalizers, term identifiers, ERC-165 ids) are re-derived in Solidity. Sepolia deployments of both cases follow.

## Questions for the thread

1. **Vocabulary rather than enums for declared posture.** The three declared dimensions are registered terms, permissionless and write-once. Is a per-instance vocabulary the right granularity, or should base terms be the only normative ones and extensions purely off-chain?
2. **Two classes of amendment, declared by the authority.** The registry records the class and never second-guesses it. Would reviewers prefer a stricter rule — for instance, any change of `objectiveHash` is material by construction?
3. **Roster snapshots per decision.** ERC-8436 freezes a policy's roster; the adapter files one policy version per decision from the deciding role's current roster. Is there appetite for a lighter convention (a shared policy per phase) that trades precision for fewer policy registrations?
4. **Scope of `requires`.** ERC-8004 is required because the agent-identity profile is normative-optional and its registry is the main audience. Should it be informative instead?
5. **Resources.** Digest kinds are open (`sha-256`, `keccak256`, adapter-defined). Is an open set acceptable for a normative record, or should the ERC fix one and let adapters translate?

Feedback on the state machine, the lazy roster-wide exits and the security considerations (sybil rosters, griefing through fallbacks, decisions in flight, allocation drift) is especially welcome.
