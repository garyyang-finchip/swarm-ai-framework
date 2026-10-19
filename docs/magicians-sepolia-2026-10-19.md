# Magicians thread 29998 — Sepolia evidence note (2026-10-19)

Status: draft for the author's approval; posted as a new reply in the thread once the repository holds the evidence files it links to (`docs/sepolia-evidence.md`, `deployments/`). The first post's sentence "Sepolia deployments of both cases follow." is then edited to "Sepolia deployments of both cases: see post N below." with N the number of this reply.

---

## Reply — Sepolia evidence run

Revision 2.1 of the reference implementation is deployed on Sepolia and both end-to-end cases of the test suite have run against the live ERC-8436 registries and the live token-bound task tender kernel. Record: https://github.com/garyyang-finchip/swarm-ai-framework/blob/main/docs/sepolia-evidence.md (machine-readable: `deployments/sepolia.json`).

Registry `0x2C1065a0a892619c1c4288abaf319326C303a1bc`, with `LifecycleLib` `0xf0CA34139e77EE6Adae171930d330C77a75f09cd`, `MembershipLib` `0x8582a086749A32F7BFce5BB8D9835026eF85d121`, `ResourceLib` `0x77b7d8aaFe0Daa42b6E197392B29307A51c448a5`, `SpecValidator` `0xE27c429eb67C829312CAAd6Ac8F5359114BbCa00`; decision adapters (ERC-8436 relying contracts) `0xcaB2c509f79ADEd438b119A453f0560C33E7B21A` (2 of 3) and `0x073169857FEFb9120799b1299003074A361f777b` (2 of 2); tender adapter `0x821574AFB51BFBb0615811E354aa3b02dA09ABC6`; allowlist module `0x9Bd40264D0062Fb1E5550A63446b64DE4A123C20`. All ten contracts have exact Sourcify matches against the sources in the repository.

Case A, swarm `0x170bd7…80b0`: a coordinator forms a swarm bound to task token 19 of the live kernel (`0xA62059…bDdb7`), three verifiers join, a worker applies and is admitted by a 2-of-3 council decision filed, voted and settled in the live `ACDFRegistry` (`0x3bE57E…dB01`), the swarm account (`0x7EFDbc…FBB7`) submits the fulfillment as fulfiller of record, the judge accepts, the tender adapter concludes the swarm `ACHIEVED` from the kernel's record, the account pays the worker, the coordinator dissolves and recovers the remainder through `recoveryAddress()`. After dissolution `isAuthorized` answers `false` for the coordinator at every decision point and the account's balance is zero.

Case B, swarm `0xa82999…8487`: a two-phase tender — open bidding (three bidders, proof sketches), a 2-of-2 chamber advances to a selected execution phase, one bidder loses eligibility and is suspended by anyone's `challenge`, the coordinator substitutes a third bidder into the seat, two milestones are accepted, the swarm concludes `ACHIEVED`.

71 transactions, every one successful on the first attempt; the on-chain charter hashes equal SHA-256 over the canonical form of the packs in the repository, so what the members accepted is what is published. One observation for implementers: Sepolia currently prices the same transactions roughly 4–10× the local node (cancun rules) — the figures in the record are the live ones.
