# Source verification — Sepolia deployment

All ten contracts of the evidence run are verified on Sourcify with an **exact match** (creation and runtime bytecode, metadata included), submitted 2026-10-19 09:02–09:03 UTC through the Sourcify v2 API (`POST /v2/verify/11155111/<address>`) with the standard JSON input below. Sourcify forwards verified contracts to Etherscan and Routescan; their pages may lag Sourcify's by a little.

Input: the 21 files under `assets/erc-8447/contracts` at commit `a78b92780818e3edbd630b95eee8ba73a3ee921c` of this repository (identical to the files compiled for the deployment), compiler `0.8.24+commit.e11b9ed9`, settings `{ optimizer: { enabled: true, runs: 1 }, viaIR: true, evmVersion: "cancun", metadata: { bytecodeHash: "ipfs" }, remappings: [":forge-std/=lib/forge-std/src/"] }` — the settings of `foundry.toml`. `verify-manifest.json` next to this file lists the per-contract identifiers and source sets.

| Contract | Address | Sourcify | Match |
|---|---|---|---|
| SpecValidator | `0xE27c429eb67C829312CAAd6Ac8F5359114BbCa00` | [lookup](https://repo.sourcify.dev/11155111/0xE27c429eb67C829312CAAd6Ac8F5359114BbCa00) | exact (2026-10-19T09:02:23Z) |
| LifecycleLib | `0xf0CA34139e77EE6Adae171930d330C77a75f09cd` | [lookup](https://repo.sourcify.dev/11155111/0xf0CA34139e77EE6Adae171930d330C77a75f09cd) | exact (2026-10-19T09:03:14Z) |
| MembershipLib | `0x8582a086749A32F7BFce5BB8D9835026eF85d121` | [lookup](https://repo.sourcify.dev/11155111/0x8582a086749A32F7BFce5BB8D9835026eF85d121) | exact (2026-10-19T09:03:11Z) |
| ResourceLib | `0x77b7d8aaFe0Daa42b6E197392B29307A51c448a5` | [lookup](https://repo.sourcify.dev/11155111/0x77b7d8aaFe0Daa42b6E197392B29307A51c448a5) | exact (2026-10-19T09:03:12Z) |
| SwarmRegistry | `0x2C1065a0a892619c1c4288abaf319326C303a1bc` | [lookup](https://repo.sourcify.dev/11155111/0x2C1065a0a892619c1c4288abaf319326C303a1bc) | exact (2026-10-19T09:03:17Z) |
| AllowlistEligibility | `0x9Bd40264D0062Fb1E5550A63446b64DE4A123C20` | [lookup](https://repo.sourcify.dev/11155111/0x9Bd40264D0062Fb1E5550A63446b64DE4A123C20) | exact (2026-10-19T09:03:15Z) |
| SwarmDecisionAdapter (council) | `0xcaB2c509f79ADEd438b119A453f0560C33E7B21A` | [lookup](https://repo.sourcify.dev/11155111/0xcaB2c509f79ADEd438b119A453f0560C33E7B21A) | exact (2026-10-19T09:03:21Z) |
| SwarmDecisionAdapter (chamber) | `0x073169857FEFb9120799b1299003074A361f777b` | [lookup](https://repo.sourcify.dev/11155111/0x073169857FEFb9120799b1299003074A361f777b) | exact (2026-10-19T09:03:25Z) |
| SwarmTenderAdapter | `0x821574AFB51BFBb0615811E354aa3b02dA09ABC6` | [lookup](https://repo.sourcify.dev/11155111/0x821574AFB51BFBb0615811E354aa3b02dA09ABC6) | exact (2026-10-19T09:03:25Z) |
| SwarmAccount (Case A) | `0x7EFDbc0821deb32139A459eB2E6C3E7D31B7FBB7` | [lookup](https://repo.sourcify.dev/11155111/0x7EFDbc0821deb32139A459eB2E6C3E7D31B7FBB7) | exact (2026-10-19T09:03:27Z) |

`SwarmRegistry` is linked against the three deployed libraries; Sourcify resolved the link references from the on-chain bytecode (an exact match with library transformations). To reproduce locally: `forge verify-contract --chain sepolia --verifier sourcify <address> assets/erc-8447/contracts/<path>:<Name>` from this repository at the commit above, with `--libraries assets/erc-8447/contracts/libraries/LifecycleLib.sol:LifecycleLib:0xf0CA34139e77EE6Adae171930d330C77a75f09cd` (and likewise MembershipLib, ResourceLib) for the registry.
