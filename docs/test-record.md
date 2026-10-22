# Test record — reference v0.3.2 (2026-10-20)

## Toolchain

| Tool | Version |
|---|---|
| forge | 1.5.1-stable (b0a9dd9) |
| solc | 0.8.24+commit.e11b9ed9, IR pipeline, optimizer runs = 1 |
| forge-std | v1.17.0 (f3dae6e) |
| node / ethers | v22.22.0 / 6.13.4 (`tools/vectors.js`) |
| eipw-lint-js | 0.11.0 with `ethereum/ERCs` `config/eipw.toml` |
| python | 3 (`scripts/make-filing-package.py`, JCS cross-check, schema validation with `jsonschema`) |

## Results

`forge test`: **93 passed, 0 failed, 0 skipped** across 10 suites.

| Suite | Tests | Covers |
|---|---|---|
| `SAISpec` | 17 | every validation rule of ERC Section 3.2 and Section 8: role and phase bounds, duplicate and zero roles, authority shape and length (16), activation authority, advance authority and the `RECRUIT` admitter rule, conclusion path, fallbacks required, member bounds, duration cap, initiator role module, objective validation, parent state, phase 0 `RECRUIT`, unknown and registered vocabulary terms, `specHash`, ERC-165 |
| `SAILifecycle` | 15 | activation under `ROSTER_MET`, `AUTHORITY`, `BOTH`; abort by authority or after the window; suspend and resume; `enforceRoster` with permissionless resume once the roster holds; two-stage inactivity; hard deadline (also while suspended); conclude by acceptance authority and by authority; `CONCLUDING` allows only `leave`; dissolve by authority or after the settlement window; succession carrying members as candidates and rejecting bad shapes; revision counter and `Changed` |
| `SAIMembership` | 21 | admit-then-accept and apply-then-admit; seat uniqueness; open-phase self-join; gated refusal; caps and unknown roles; eligibility at admission; challenge with true, false and reverting modules; a gas-starved module that catches its own reads (a sweep of gas limits never suspends the honest member; without the remainder rule it does from about 1.0M gas); reinstatement on evidence through `challenge`; `expel` re-evaluating the module (reinstates on true, reverts `SAI_Unevaluable` when unevaluable, exits on false); expulsion after grace and reinstatement on judgment; removal of candidates versus members; `leave` always; `joinBySig` by an EOA and by an ERC-1271 wallet, expired and wrong-charter rejection, replay after exit and after a phase change; substitution in a closed phase |
| `SAIPhases` | 6 | `INHERIT`, `RECRUIT` and `SELECT` advances with lazy exits and counter resets; role maxima and eligibility on `SELECT`; input window closing admissions and contributions; last phase; role authority following the ledger |
| `SAICharter` | 10 | minor versus material amendments (exit window, completion hold); a changed commitment or objective hash made material by construction and the one-way `material` flag (with the `CharterAmended` event); nobody authorized of any kind after dissolution; the account's recovery path (set only by a representative before dissolution, `recover` only after, zero means nothing leaves); milestones gating `ACHIEVED`; contribution modes; `setCharterURI` and authority transfer; account binding once; resources with a verifying adapter and detachment |
| `SAIDecision` | 9 | the decision adapter against the vendored ERC-8436 registries: `open` checks, Yes admits through the real registry (subject and obligation carry the phase), No records refusal, `NoDecision` is the status quo, removal by council, a material amendment invalidating a pending proposal, a proposal approved in phase 0 refused after an advance and re-filed in phase 1, two approved `ADVANCE` proposals that do not chain across phases (the second-round regression), a failed enactment recorded and retried |
| `SAIModules` | 5 | ERC-8004 identity (declare, wallet move, reinstatement), trust-assertion level, identity state (stale, retired), composite all/any, allowlist ownership |
| `SAICaseA` | 3 | tender-bound cooperative swarm end to end (council admission, swarm account as fulfiller, acceptance pays the account, tender adapter concludes `ACHIEVED`, allocation from the account, recovery address set before dissolution, dissolution, representation refused after dissolution, remainder recovered through the account's own rule); cancellation -> `ABANDONED`; expiry -> `FAILED` |
| `SAICaseB` | 2 | two-phase tender end to end (open bidding, challenge suspends an ineligible bidder, `SELECT` into closed execution, substitution, milestones, conclusion); the chamber cannot advance an ineligible bidder |
| `SAIVectors` | 5 | `spec-hash.json`, `join-digest.json`, `term-ids.json`, `interface-ids.json` re-derived in Solidity; the live registry's `joinDigest` matches the convention |

The fixtures under `test/fixtures/` are unmodified copies of the ERC-8436 reference registries (`ethereum/ERCs` `assets/erc-8436/contracts` at `4dec821b`) and of the token-bound task tender kernel (`garyyang-finchip/task-token-standard` at `3196db87`); see `test/fixtures/README.md`.

## Sizes (runtime bytes, `forge build --sizes`)

| Contract | Runtime | Margin to EIP-170 |
|---|---|---|
| SwarmRegistry | 16,480 | 8,096 |
| LifecycleLib | 20,903 | 3,673 |
| MembershipLib | 12,047 | 12,529 |
| ResourceLib | 4,819 | 19,757 |
| SpecValidator | 2,759 | 21,817 |
| SwarmDecisionAdapter | 12,319 | 12,257 |
| SwarmTenderAdapter | 3,753 | 20,823 |
| SwarmAccount | 2,672 | 21,904 |
| eligibility modules | 457 - 1,128 | — |

## Vectors

`node tools/vectors.js` regenerates `assets/erc-8447/vectors/`. Charter hashes are computed by the JavaScript canonicalizer in the tool and cross-checked by an independent Python canonicalizer; spec hashes by ethers v6 and re-derived by `abi.encode` in Solidity; interface identifiers by XOR over the compiled ABIs and by `type(I).interfaceId`.

| Vector | Values |
|---|---|
| `interface-ids.json` | `ISwarmRegistry` `0x085203a4`, `IEligibility` `0xd0ede3d8`, `ISwarmAccount` `0x25e98353`, `IResourceAdapter` `0x8e20b298` |
| `charter-hash.json` | cooperative tender pack `0xe1521d9b...0f07` (commitment `0x8959f292...2b49`), two-phase tender pack `0x7726c87a...c435` (commitment `0x3ff5ac7d...d801`) |
| `join-digest.json` | three digests across seat epochs 0 and 1 and phases 0 and 1 |
| `spec-hash.json` | a minimal single-phase gated spec and a two-phase tender spec, with their ABI encodings |
| `term-ids.json` | dimensions, fourteen base terms, roles, origins, resource kinds, decision-point questions, effects, digest kinds |

## Lint

- `eipw` 0.11.0 under the ERCs config over `ERCS/erc-8447.md` (placed beside the merged ERCs for link resolution): **0 findings**.
- `python3 scripts/make-filing-package.py --allow-tbd`: package ok (38 files), preamble order and limits, required sections, CC0 line, no smart quotes, no external links outside `rfc-editor.org`, first mentions linked, no proposal reference in backticks, no RFC 2119 keywords in Security Considerations, asset links resolve, no CJK characters in any shipped file.
- Both example packs validate against `swarm-pack.schema.json` (JSON Schema 2020-12).
- solc warnings: none in the proposal's contracts. forge-lint: style notes (unaliased plain imports of `SAIErrors.sol`) and one `unsafe-typecast` note on a cast that is range-checked on the line before (`SwarmDecisionAdapter._consumerDeadline`).

## Sepolia run (2026-10-19)

The same step list run against Sepolia: `docs/sepolia-evidence.md` (71 transactions, all successful; exact Sourcify matches for the ten deployed contracts; final state read back and checked against the packs in `deployments/sepolia/`). Case R (2026-10-22, `--case-r`): the revision-2.2 adapter deployed and the second-round regression run on-chain — 35 transactions, of which the two refusals the step list expects (`SAIDecision: phase changed`, read back by replaying each call at its block) and 33 successes. The rehearsal of that list against a local anvil (`tools/sepolia/run.js direct --fixtures`) deployed the vendored fixtures first and finished with the same final states; its gas figures are the "vs rehearsal" column of the record.
