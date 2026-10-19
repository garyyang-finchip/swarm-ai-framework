# Sepolia evidence run — ERC-8447 reference implementation (revision 2.1)

Chain: Sepolia (chain id 11155111). Deployer: [`0x91E946F5633306f173D6E5d93aD3a040c4211da1`](https://sepolia.etherscan.io/address/0x91E946F5633306f173D6E5d93aD3a040c4211da1). Blocks 11946924–11947119, 71 transactions, 191,753,765 gas in total. Every transaction below succeeded (status 1) on the first attempt; nothing was retried, replaced or skipped.

The run deploys the reference contracts from `assets/erc-8447/contracts` and executes the two end-to-end cases of the test suite (`test/SAICaseA.t.sol`, `test/SAICaseB.t.sol`) against the **live** ERC-8436 registries and the **live** token-bound task tender kernel on Sepolia, with the same step list that `tools/sepolia/run.js` runs against a local node. Machine-readable record: `deployments/sepolia.json`; per-batch receipts: `deployments/sepolia/receipts-batch-*.json`; the signed transactions as broadcast: `deployments/sepolia/batch-*.json`.

## Contracts

| Contract | Address | Deployment | Gas |
|---|---|---|---|
| SpecValidator | [`0xE27c429eb67C829312CAAd6Ac8F5359114BbCa00`](https://sepolia.etherscan.io/address/0xE27c429eb67C829312CAAd6Ac8F5359114BbCa00) | [`0xe2d402b4…1b2814`](https://sepolia.etherscan.io/tx/0xe2d402b47bbdbf2b6a8f146fa4eb38d2dae9ef836e9f0a4acd83cce92b1b2814) (block 11946924) | 4,474,572 |
| LifecycleLib | [`0xf0CA34139e77EE6Adae171930d330C77a75f09cd`](https://sepolia.etherscan.io/address/0xf0CA34139e77EE6Adae171930d330C77a75f09cd) | [`0xc571766c…8c9352`](https://sepolia.etherscan.io/tx/0xc571766c49a2edd1bc5414819a7f7061e1a14d52187974282b25ddbbf28c9352) (block 11946925) | 32,532,860 |
| MembershipLib | [`0x8582a086749A32F7BFce5BB8D9835026eF85d121`](https://sepolia.etherscan.io/address/0x8582a086749A32F7BFce5BB8D9835026eF85d121) | [`0xe4e17207…e75a05`](https://sepolia.etherscan.io/tx/0xe4e172078a46d2e6734aed84900492c35462f4a6ec263b12f4f883047be75a05) (block 11946944) | 18,837,224 |
| ResourceLib | [`0x77b7d8aaFe0Daa42b6E197392B29307A51c448a5`](https://sepolia.etherscan.io/address/0x77b7d8aaFe0Daa42b6E197392B29307A51c448a5) | [`0x1a8fee46…191618`](https://sepolia.etherscan.io/tx/0x1a8fee46ec7fdb16d2eec1325bea4097a83a80d8f8eff2d77167e275d6191618) (block 11946945) | 7,659,959 |
| SwarmRegistry | [`0x2C1065a0a892619c1c4288abaf319326C303a1bc`](https://sepolia.etherscan.io/address/0x2C1065a0a892619c1c4288abaf319326C303a1bc) | [`0x4b680d35…39022f`](https://sepolia.etherscan.io/tx/0x4b680d35c63ee5a2759b60591284a7370aea9233a98354bcd0c712426b39022f) (block 11946960) | 28,883,879 |
| AllowlistEligibility | [`0x9Bd40264D0062Fb1E5550A63446b64DE4A123C20`](https://sepolia.etherscan.io/address/0x9Bd40264D0062Fb1E5550A63446b64DE4A123C20) | [`0xc0d01f8f…af4dd2`](https://sepolia.etherscan.io/tx/0xc0d01f8f07af72e31609ec576cdff83a0f9f76de3fb1b8eab72602bce9af4dd2) (block 11946961) | 1,288,914 |
| SwarmDecisionAdapter (council, 2 of 3) | [`0xcaB2c509f79ADEd438b119A453f0560C33E7B21A`](https://sepolia.etherscan.io/address/0xcaB2c509f79ADEd438b119A453f0560C33E7B21A) | [`0x50b930f5…6730a7`](https://sepolia.etherscan.io/tx/0x50b930f57451790e9636ddaafc505c4adf654f231a6cc83c9334879db06730a7) (block 11946973) | 19,029,985 |
| SwarmDecisionAdapter (chamber, 2 of 2) | [`0x073169857FEFb9120799b1299003074A361f777b`](https://sepolia.etherscan.io/address/0x073169857FEFb9120799b1299003074A361f777b) | [`0x2c0a2fd8…39f34e`](https://sepolia.etherscan.io/tx/0x2c0a2fd86ca2fa4016a545e37f4b3654a151f9e65ceac1f76b2a4611e639f34e) (block 11946988) | 19,029,985 |
| SwarmTenderAdapter | [`0x821574AFB51BFBb0615811E354aa3b02dA09ABC6`](https://sepolia.etherscan.io/address/0x821574AFB51BFBb0615811E354aa3b02dA09ABC6) | [`0x0692d046…9fcf4b`](https://sepolia.etherscan.io/tx/0x0692d04671dd85c8680bca6919b77f4f7a4d9d39ba141b0bf856b81b2f9fcf4b) (block 11946989) | 6,012,374 |
| SwarmAccount (Case A) | [`0x7EFDbc0821deb32139A459eB2E6C3E7D31B7FBB7`](https://sepolia.etherscan.io/address/0x7EFDbc0821deb32139A459eB2E6C3E7D31B7FBB7) | [`0x19c16af2…414d34`](https://sepolia.etherscan.io/tx/0x19c16af26331c7a1b688e0facdc520ac8a877652d57cf48ab754b6a050414d34) (block 11947051) | 4,455,758 |

Compiler: solc 0.8.24+commit.e11b9ed9, optimizer enabled (runs 1), via-IR, EVM version cancun, metadata hash ipfs — the settings of `foundry.toml`. `SwarmRegistry` is linked against the three deployed logic libraries; the decision adapters take the registry, the ERC-8436 registry, the verifier role, the quorum and the body size (2 of 3 for the council, 2 of 2 for the chamber), a 15-minute voting window and a 2-minute margin.

Revisions since the run: the two decision adapters above are the revision-2.1 code and predate revision 2.2 (2026-10-20), which binds every proposal to the phase it was filed in (the finding of the second review round, `docs/design-memo.md` 11.3); the registry, the libraries, the module, the tender adapter and the account are the current code. Neither case enacts a decision across a phase change, so the record is unaffected; the revision-2.2 adapter is exercised by the regression tests in `test/SAIDecision.t.sol`.

Live dependencies (not deployed by this run): ERC-8436 `ACDFRegistry` [`0x3bE57E74f2E7c280073b6B16A1Db3F562758dB01`](https://sepolia.etherscan.io/address/0x3bE57E74f2E7c280073b6B16A1Db3F562758dB01) and `ACDFPolicyRegistry` [`0x7eAfCC452EC0A60a358a26B6e73f28413C4abeF0`](https://sepolia.etherscan.io/address/0x7eAfCC452EC0A60a358a26B6e73f28413C4abeF0) (revision 3 of the ERC-8436 reference, byte-identical outside immutables and metadata to the fixtures vendored in `test/fixtures`), and the token-bound task tender kernel `TaskToken` [`0xA62059A498E40C4Ae4aF926E2B00C1Ff122bDdb7`](https://sepolia.etherscan.io/address/0xA62059A498E40C4Ae4aF926E2B00C1Ff122bDdb7) (v3.2.1, the source vendored in `test/fixtures`).

## Accounts

| Name | Role in the cases | Address |
|---|---|---|
| deployer | deploys; sponsor and judge of the Case A tender; judge of the Case B milestones; opens the decisions; challenges | [`0x91E946F5633306f173D6E5d93aD3a040c4211da1`](https://sepolia.etherscan.io/address/0x91E946F5633306f173D6E5d93aD3a040c4211da1) |
| coord | coordinator of both swarms; Case A amendment/representation authority; recovery address of the Case A account | [`0xEa66e8bD35187F0cb0ee19178050dd9D652A77f9`](https://sepolia.etherscan.io/address/0xEa66e8bD35187F0cb0ee19178050dd9D652A77f9) |
| c1, c2, c3 | verifiers (the council of Case A: c1 and c3 vote; the chamber of Case B: c1 and c2 vote) | [`0x5E49afD47D0A474EA64b03C6a1854561946da4f3`](https://sepolia.etherscan.io/address/0x5E49afD47D0A474EA64b03C6a1854561946da4f3), [`0xBAE31786dA89E971796188759D435C3DecCEfD3e`](https://sepolia.etherscan.io/address/0xBAE31786dA89E971796188759D435C3DecCEfD3e), [`0x08F43E9C4aa64A5E106B1dF506b13A4ea4440dc7`](https://sepolia.etherscan.io/address/0x08F43E9C4aa64A5E106B1dF506b13A4ea4440dc7) |
| w1 | Case A worker, admitted by the council, paid through the swarm account | [`0x53df988Cdb52d8617AE6b1922226905e7FE9990b`](https://sepolia.etherscan.io/address/0x53df988Cdb52d8617AE6b1922226905e7FE9990b) |
| b1, b2, b3 | Case B bidders; b2 loses eligibility and is substituted by b3 | [`0x740Fd18Ff3bFcbb142Da829f9B56a9DAF77e2228`](https://sepolia.etherscan.io/address/0x740Fd18Ff3bFcbb142Da829f9B56a9DAF77e2228), [`0x342cbCd7A9955906b34D9F09c0c489578242D85A`](https://sepolia.etherscan.io/address/0x342cbCd7A9955906b34D9F09c0c489578242D85A), [`0x3B093cF33724da65949CE14BF038F20790F95c41`](https://sepolia.etherscan.io/address/0x3B093cF33724da65949CE14BF038F20790F95c41) |

## Case A — tender-bound cooperative swarm

Swarm id `0x170bd77e6ed40d99c9930799c381b997497e6ffe86c2e9f90659dbc2fbf280b0` (`keccak256(abi.encode(11155111, registry, 1))`). Task token id 19 on the live kernel, minted and funded (0.002 ETH) by the deployer as sponsor and judge. Spec hash `0x1ffb541e276bcc11edbe3316cedeb5bc84888a96946fac3a40b0d2a45448ae88`, charter hash `0x5c8dbbab30c3b8c0a5fcafcca24afcf4745282fc81c66444081f5746a590cf7d`, commitment hash `0xbcfdf7eb590242beff598151b0fe6c77be4ebc5ca5438e28963a3ffece8de79f`, objective hash `0xb657cacd8561db650729e1c48d0a112c3b2aa2576eccbdfeb98b106b2461ebe9`; the pack is `deployments/sepolia/case-a/swarm-pack.json` and its `charterURI` points at that file in this repository. Council issue `0xf4803aea2fdd406e27fc02e762033fa7abacb627cdc4a9911dc7d1e1ad181ce3`; fulfillment submission 1; swarm account [`0x7EFDbc0821deb32139A459eB2E6C3E7D31B7FBB7`](https://sepolia.etherscan.io/address/0x7EFDbc0821deb32139A459eB2E6C3E7D31B7FBB7) with recovery address coord.

The coordinator forms the swarm bound to the tender, the three verifiers join, w1 applies, the council (2 of 3, ERC-8436) admits w1 by a filed, voted and settled decision, the coordinator activates, the swarm account is set, w1 records a contribution, the account submits the fulfillment as the fulfiller of record, the judge accepts, the tender adapter concludes the swarm `ACHIEVED` from the kernel's record, the account pays w1 its 70 % share, the coordinator dissolves the swarm and recovers the remainder through the account's post-dissolution rule.

## Case B — two-phase tender with challenge and substitution

Swarm id `0xa82999407bc283e1aba303192ad133a68fb18dcd8a990ed4d15c17be5edd8487`. Spec hash `0x83c242d83255b8b19e8af01db5f0aea1d62e4475ee54c04c6d7519b64c421bf1`, charter hash `0xe4ce454d7e3a998c0da7751e2f3cf411407e0a1ec3447380f2e9723fb725538b`, commitment hash `0x3ff5ac7d889fa781d8b412e7bb7359aa55f911c44c4c19974164cd718c4fd801`; the pack is `deployments/sepolia/case-b/swarm-pack.json`. Chamber issue `0x294757ad4936517289d38d908043f216ff21c420af2b3ecdcdbde235e003cd77`.

Open bidding phase: the three allowlisted bidders join and record proof sketches; the chamber (2 of 2) advances the swarm to the selected execution phase carrying coord, c1, c2, b1 and b2. Then b2 loses its allowlist eligibility, anyone's `challenge` suspends it, a contribution it records while suspended is accepted but flagged `whileSuspended`, the coordinator substitutes b3 into the seat, b3 accepts the charter, b1 and b3 record proofs, the judge accepts both milestones, the swarm concludes `ACHIEVED` and is dissolved.

## Transactions

Gas is the live Sepolia figure; the last column is the ratio to the local rehearsal (`tools/sepolia/run.js direct` against anvil, cancun rules), given because Sepolia priced the same transactions several times higher than the local node at the time of the run.

| # | Step | From | Transaction | Block | Gas | vs rehearsal |
|---|---|---|---|---|---|---|
| 0 | SpecValidator → `0xE27c429eb67C829312CAAd6Ac8F5359114BbCa00` | deployer | [`0xe2d402b4…1b2814`](https://sepolia.etherscan.io/tx/0xe2d402b47bbdbf2b6a8f146fa4eb38d2dae9ef836e9f0a4acd83cce92b1b2814) | 11946924 | 4,474,572 | 6.88× |
| 1 | LifecycleLib → `0xf0CA34139e77EE6Adae171930d330C77a75f09cd` | deployer | [`0xc571766c…8c9352`](https://sepolia.etherscan.io/tx/0xc571766c49a2edd1bc5414819a7f7061e1a14d52187974282b25ddbbf28c9352) | 11946925 | 32,532,860 | 7.11× |
| 2 | MembershipLib → `0x8582a086749A32F7BFce5BB8D9835026eF85d121` | deployer | [`0xe4e17207…e75a05`](https://sepolia.etherscan.io/tx/0xe4e172078a46d2e6734aed84900492c35462f4a6ec263b12f4f883047be75a05) | 11946944 | 18,837,224 | 7.08× |
| 3 | ResourceLib → `0x77b7d8aaFe0Daa42b6E197392B29307A51c448a5` | deployer | [`0x1a8fee46…191618`](https://sepolia.etherscan.io/tx/0x1a8fee46ec7fdb16d2eec1325bea4097a83a80d8f8eff2d77167e275d6191618) | 11946945 | 7,659,959 | 6.99× |
| 4 | SwarmRegistry → `0x2C1065a0a892619c1c4288abaf319326C303a1bc` | deployer | [`0x4b680d35…39022f`](https://sepolia.etherscan.io/tx/0x4b680d35c63ee5a2759b60591284a7370aea9233a98354bcd0c712426b39022f) | 11946960 | 28,883,879 | 6.65× |
| 5 | AllowlistEligibility → `0x9Bd40264D0062Fb1E5550A63446b64DE4A123C20` | deployer | [`0xc0d01f8f…af4dd2`](https://sepolia.etherscan.io/tx/0xc0d01f8f07af72e31609ec576cdff83a0f9f76de3fb1b8eab72602bce9af4dd2) | 11946961 | 1,288,914 | 5.99× |
| 6 | SwarmDecisionAdapter council → `0xcaB2c509f79ADEd438b119A453f0560C33E7B21A` | deployer | [`0x50b930f5…6730a7`](https://sepolia.etherscan.io/tx/0x50b930f57451790e9636ddaafc505c4adf654f231a6cc83c9334879db06730a7) | 11946973 | 19,029,985 | 7.06× |
| 7 | SwarmDecisionAdapter chamber → `0x073169857FEFb9120799b1299003074A361f777b` | deployer | [`0x2c0a2fd8…39f34e`](https://sepolia.etherscan.io/tx/0x2c0a2fd86ca2fa4016a545e37f4b3654a151f9e65ceac1f76b2a4611e639f34e) | 11946988 | 19,029,985 | 7.06× |
| 8 | SwarmTenderAdapter → `0x821574AFB51BFBb0615811E354aa3b02dA09ABC6` | deployer | [`0x0692d046…9fcf4b`](https://sepolia.etherscan.io/tx/0x0692d04671dd85c8680bca6919b77f4f7a4d9d39ba141b0bf856b81b2f9fcf4b) | 11946989 | 6,012,374 | 6.94× |
| 9 | fund coord | deployer | [`0xab80d7c1…802390`](https://sepolia.etherscan.io/tx/0xab80d7c17422309ad7bc0f369818b7e86ff6e8a1ecd46888c151f950af802390) | 11946990 | 204,600 | 9.74× |
| 10 | fund c1 | deployer | [`0x8998456a…2cde56`](https://sepolia.etherscan.io/tx/0x8998456a574cb876e9c8ca73066b6249af26b8ff50f09741c9df27aea02cde56) | 11946991 | 204,600 | 9.74× |
| 11 | fund c2 | deployer | [`0xfe298b50…c94d37`](https://sepolia.etherscan.io/tx/0xfe298b504f3a05eef68c0c116cfbd448d6c403276c13fc622cdcd3a39bc94d37) | 11946992 | 204,600 | 9.74× |
| 12 | fund c3 | deployer | [`0xb3d05486…7c8487`](https://sepolia.etherscan.io/tx/0xb3d054861c0a61b8e62b27810c639abca2fd765a73d723063b7b0bce547c8487) | 11946993 | 204,600 | 9.74× |
| 13 | fund w1 | deployer | [`0xd18a7af9…ea982e`](https://sepolia.etherscan.io/tx/0xd18a7af977e55e49898102e8a67d07a88437cfed07ce57c28cba4d60f4ea982e) | 11946994 | 204,600 | 9.74× |
| 14 | fund b1 | deployer | [`0xec87a0df…331d41`](https://sepolia.etherscan.io/tx/0xec87a0df94d1d5604b9bd7ad5e7bfca4cbd4214d819348717c89ef7f22331d41) | 11947007 | 204,600 | 9.74× |
| 15 | fund b2 | deployer | [`0xa5cb5e23…ed078d`](https://sepolia.etherscan.io/tx/0xa5cb5e230453d1a2e8d685e4641d140d693ca59cc878318f920803af1ded078d) | 11947008 | 204,600 | 9.74× |
| 16 | fund b3 | deployer | [`0x6f14bb15…3a9777`](https://sepolia.etherscan.io/tx/0x6f14bb15698deb03658b91364d97545cfb66029566d8fb7835c02fcc993a9777) | 11947009 | 204,600 | 9.74× |
| 17 | A: mintTask | deployer | [`0x8ee7daf6…5e7ac9`](https://sepolia.etherscan.io/tx/0x8ee7daf6ba0c9538aa699afd6e8deaf714fbd157befb52b6ac6943c3e95e7ac9) | 11947010 | 3,408,591 | 6.56× |
| 18 | A: fundTask | deployer | [`0x74852c42…9b24b0`](https://sepolia.etherscan.io/tx/0x74852c42f7f6924c69eafff5f63b63e738f0e7b3be5010152ebca209e79b24b0) | 11947020 | 381,317 | 3.33× |
| 19 | A: allow w1 | deployer | [`0x8622eac4…b305c2`](https://sepolia.etherscan.io/tx/0x8622eac41566dfd2370b9000a61ac974f7e9828eb4c535d37b38bf15d6b305c2) | 11947021 | 129,633 | 2.72× |
| 20 | A: form | coord | [`0x9a5c3fc5…b81c42`](https://sepolia.etherscan.io/tx/0x9a5c3fc59cf12e87ab744099b23527756b3253fcabca608abe1c656313b81c42) | 11947022 | 8,383,421 | 4.68× |
| 21 | A: coord joins | coord | [`0xf5fa075e…52e1d4`](https://sepolia.etherscan.io/tx/0xf5fa075e995cada0802e50b56948d869b3c68a8aa8b5270d9ea9a7073452e1d4) | 11947023 | 857,743 | 3.68× |
| 22 | A: c1 joins | c1 | [`0x74e16305…606c36`](https://sepolia.etherscan.io/tx/0x74e16305fdce1bb3b97353e386a7df567c09a1dc087f0647c79f57028a606c36) | 11947024 | 759,823 | 3.52× |
| 23 | A: c2 joins | c2 | [`0x8abcdb74…22f971`](https://sepolia.etherscan.io/tx/0x8abcdb74686ba11789c007b7b04550ec40888afed62a24341cfafb940422f971) | 11947025 | 661,903 | 3.33× |
| 24 | A: c3 joins | c3 | [`0x4af0d3b1…fac2ba`](https://sepolia.etherscan.io/tx/0x4af0d3b17292eec40053d73e56f6cbc36cc59d98fd00506e9c1271f33afac2ba) | 11947026 | 661,903 | 3.33× |
| 25 | A: w1 applies | w1 | [`0xee6e22f6…f1bd49`](https://sepolia.etherscan.io/tx/0xee6e22f6086407b1edf6ae5f55028e40bfa50009b6ea2251a75ca7c51bf1bd49) | 11947027 | 643,754 | 3.42× |
| 26 | A: council opens ADMIT | deployer | [`0x7598e9b3…74765e`](https://sepolia.etherscan.io/tx/0x7598e9b39c09f086d9edfad4cc134e539be1d3250139c3737e5de1fecc74765e) | 11947028 | 5,188,829 | 4.20× |
| 27 | A: c1 votes yes | c1 | [`0xb76518f7…528beb`](https://sepolia.etherscan.io/tx/0xb76518f76bdc5d60c4211109e57960c87a5556340ffce8ed44f30d8ffe528beb) | 11947046 | 275,838 | 2.61× |
| 28 | A: c3 votes yes | c3 | [`0xe6cce0b3…0b9004`](https://sepolia.etherscan.io/tx/0xe6cce0b36bcb91a3385d93b124ca93b8da1471e244b695f1f1187ade8d0b9004) | 11947047 | 178,664 | 2.00× |
| 29 | A: settle round | deployer | [`0x0294d5eb…22d2df`](https://sepolia.etherscan.io/tx/0x0294d5eb5506e53f52910dca82c443d5328d7b83607010572b0c7867e322d2df) | 11947048 | 119,296 | 1.15× |
| 30 | A: council executes (admit w1) | deployer | [`0x728c1fc4…86edaf`](https://sepolia.etherscan.io/tx/0x728c1fc4f2e5425bce1a3610e28be7ae0970c30f7938f6f21d88833cb186edaf) | 11947049 | 665,826 | 2.44× |
| 31 | A: activate | coord | [`0x0221fc68…eb5659`](https://sepolia.etherscan.io/tx/0x0221fc68b07a53ce3bcef337e639db8a5eab9b56b0c2012ce92afac156eb5659) | 11947050 | 203,020 | 2.05× |
| 32 | SwarmAccount accountA → `0x7EFDbc0821deb32139A459eB2E6C3E7D31B7FBB7` | deployer | [`0x19c16af2…414d34`](https://sepolia.etherscan.io/tx/0x19c16af26331c7a1b688e0facdc520ac8a877652d57cf48ab754b6a050414d34) | 11947051 | 4,455,758 | 6.76× |
| 33 | A: setAccount | coord | [`0x0268a723…a181bc`](https://sepolia.etherscan.io/tx/0x0268a72370b7ed627a2eacdc655ed40596ac14de3d18c102c3969c5c83a181bc) | 11947052 | 56,820 | 1.19× |
| 34 | A: w1 records contribution | w1 | [`0xe4716c88…07c7f7`](https://sepolia.etherscan.io/tx/0xe4716c886cd68a1ca1f919147b9c67bdce6f151da29bcf8a2dd55ee67107c7f7) | 11947053 | 79,809 | 1.25× |
| 35 | A: account submits fulfillment | coord | [`0x4dca9508…f76c2a`](https://sepolia.etherscan.io/tx/0x4dca9508031f16911cc905c59508502b59a9746c18285041ffa7904f0cf76c2a) | 11947054 | 631,759 | 3.23× |
| 36 | A: judge accepts | deployer | [`0x3975b511…9b8c78`](https://sepolia.etherscan.io/tx/0x3975b5113f54e8f5aa8b582572d6d365a8e4b3da8719aae2c06b5a5e459b8c78) | 11947068 | 186,473 | 2.02× |
| 37 | A: tender adapter settles | deployer | [`0xfee8a944…bffbf1`](https://sepolia.etherscan.io/tx/0xfee8a94470708167699809106275d457423ee70398e8d8a94575f1cecebffbf1) | 11947069 | 257,164 | 1.80× |
| 38 | A: account pays w1 | coord | [`0x262cecdd…2c997f`](https://sepolia.etherscan.io/tx/0x262cecdd585d0c7a8cea6bf31aa8f9a98a63d88698e14048d756b7572d2c997f) | 11947070 | 50,651 | 0.94× |
| 39 | A: dissolve | coord | [`0x76fb1ec8…35322d`](https://sepolia.etherscan.io/tx/0x76fb1ec88c911a92a824e3ddc1e1d9cdd9570a3512a6d26bd85a6347e335322d) | 11947071 | 63,881 | 1.33× |
| 40 | A: recover remainder | coord | [`0xc4640bdd…99a253`](https://sepolia.etherscan.io/tx/0xc4640bdda13d4a8efc6f00074187759f47f8ba22f8a3c69b654e8bbf1c99a253) | 11947072 | 85,721 | 1.07× |
| 41 | B: allow b1 | deployer | [`0xc769630b…e41b1f`](https://sepolia.etherscan.io/tx/0xc769630b5296a6cbdc7d0140a8b358b904a46ebfe6355b86ccf9613274e41b1f) | 11947073 | 129,633 | 2.72× |
| 42 | B: allow b2 | deployer | [`0x14703b3d…e00a71`](https://sepolia.etherscan.io/tx/0x14703b3ddf1942dc8ce028c0445f57fa2c82d557a169529b99d3174ae4e00a71) | 11947074 | 129,633 | 2.72× |
| 43 | B: allow b3 | deployer | [`0xdd21392f…4df012`](https://sepolia.etherscan.io/tx/0xdd21392f25191b1148693be26a690eb0c558e229cfb16cfb078e00f98b4df012) | 11947075 | 129,633 | 2.72× |
| 44 | B: form | coord | [`0x15df345f…2cd623`](https://sepolia.etherscan.io/tx/0x15df345fae71ee6c78c7258f8d7306307481167c550d03d857782381ac2cd623) | 11947076 | 8,971,425 | 4.64× |
| 45 | B: coord joins | coord | [`0xfd3b1846…54599d`](https://sepolia.etherscan.io/tx/0xfd3b18461e819c55b5754777cca823f473cb288005d3434fe99092ae9154599d) | 11947077 | 857,743 | 3.68× |
| 46 | B: c1 joins | c1 | [`0xee6ce74a…ecc766`](https://sepolia.etherscan.io/tx/0xee6ce74a2a7190b6fe9394d14d5f7967162149f3d292fa34cd4e17a9e1ecc766) | 11947078 | 759,823 | 3.52× |
| 47 | B: c2 joins | c2 | [`0x6302f1cf…a8b804`](https://sepolia.etherscan.io/tx/0x6302f1cf03c9d89e11f5af28d1f0bde08031180b8ee841e5490c71d3eca8b804) | 11947079 | 661,903 | 3.33× |
| 48 | B: activate | deployer | [`0xb9a19c7f…9753d6`](https://sepolia.etherscan.io/tx/0xb9a19c7fab683533a28b5e1d8e1fd1225f62e3038ab9ef8072a6aba5579753d6) | 11947080 | 207,310 | 2.00× |
| 49 | B: b1 joins | b1 | [`0x4d8ae173…fe9b26`](https://sepolia.etherscan.io/tx/0x4d8ae1732503342a4ddc4d0f42953d89c95de09de69e68388461fe3768fe9b26) | 11947081 | 759,817 | 3.52× |
| 50 | B: b2 joins | b2 | [`0x685ca4a0…ec73c3`](https://sepolia.etherscan.io/tx/0x685ca4a04e68630d2613ce3f5433e9e0d8f53b7662120863cb0ad6d7c2ec73c3) | 11947092 | 661,897 | 3.33× |
| 51 | B: b3 joins | b3 | [`0xb32ef781…43ed40`](https://sepolia.etherscan.io/tx/0xb32ef781326c88be25cd3607deda70073493ff23c2891eae48278e14ac43ed40) | 11947093 | 661,897 | 3.33× |
| 52 | B: b1 sketch | b1 | [`0x17a12c5d…a3c1bc`](https://sepolia.etherscan.io/tx/0x17a12c5dd53a7f59b07442729e963ad7908c7c4fd115ac52ec1a27d3b4a3c1bc) | 11947094 | 79,821 | 1.25× |
| 53 | B: b2 sketch | b2 | [`0x668c4127…a30379`](https://sepolia.etherscan.io/tx/0x668c41273f10402df5faaf887daf167438d24d01c903aa61d0c5d778ada30379) | 11947095 | 79,821 | 1.25× |
| 54 | B: b3 sketch | b3 | [`0x87477702…44ad6b`](https://sepolia.etherscan.io/tx/0x874777029f95f5fcf3a2ef0254dd3f0b22cb43ae31e9e51082c2de29ca44ad6b) | 11947096 | 79,821 | 1.25× |
| 55 | B: chamber opens ADVANCE | deployer | [`0x4a94b45f…b6c31b`](https://sepolia.etherscan.io/tx/0x4a94b45fdedab52c4b0094fc68528334f66531e81f818528ac2f4fa082b6c31b) | 11947097 | 6,403,408 | 4.36× |
| 56 | B: c1 votes yes | c1 | [`0x4dbac66e…bb4d43`](https://sepolia.etherscan.io/tx/0x4dbac66ee7fbce8cef381dc6851a9a63d11f8c0428baaba99124d96d82bb4d43) | 11947105 | 273,404 | 2.65× |
| 57 | B: c2 votes yes | c2 | [`0xf6fe8298…64eb85`](https://sepolia.etherscan.io/tx/0xf6fe8298e8332b64e3b3f2fc3338120228297494ff4fd849049edceca864eb85) | 11947106 | 176,025 | 2.03× |
| 58 | B: settle round | deployer | [`0xecb0bbbf…4597be`](https://sepolia.etherscan.io/tx/0xecb0bbbfa6efd5c8b503664a653dc9c75a678713d120bf5075e2ad09804597be) | 11947107 | 116,861 | 1.15× |
| 59 | B: chamber executes (advance) | deployer | [`0x43a9c81b…fb7b85`](https://sepolia.etherscan.io/tx/0x43a9c81b60df5fd50f51c4fc36102760c605f1905aaa7eaaa0eeffb4fafb7b85) | 11947108 | 821,781 | 2.16× |
| 60 | B: b2 loses eligibility | deployer | [`0x8760fc00…cf8d02`](https://sepolia.etherscan.io/tx/0x8760fc005482506bced15f18f964b9952d101e03b195ce914fec955325cf8d02) | 11947109 | 25,361 | 0.98× |
| 61 | B: anyone challenges b2 | deployer | [`0x93d13d40…ff12b7`](https://sepolia.etherscan.io/tx/0x93d13d40cbbe5f5b3cfdfce6c3ec2e42842ed8118916e070c39058146bff12b7) | 11947110 | 98,390 | 1.31× |
| 62 | B: b2 records while suspended | b2 | [`0x9a3d4013…57203d`](https://sepolia.etherscan.io/tx/0x9a3d40134804c1e03c60aa917b26b346d459951e2f1261bae5b0dfa45457203d) | 11947111 | 79,182 | 1.25× |
| 63 | B: coord substitutes b3 for b2 | coord | [`0x97ce6fe6…522a07`](https://sepolia.etherscan.io/tx/0x97ce6fe6b650cf4e8f927b5b321f9b230df1fcdea0e0bb730ed3213c6c522a07) | 11947112 | 266,987 | 2.12× |
| 64 | B: b3 accepts the charter | b3 | [`0xd230ee6a…6ea21e`](https://sepolia.etherscan.io/tx/0xd230ee6a11ff9514a4198e520217f67a0bacdc972460f001c6046f1b246ea21e) | 11947113 | 349,777 | 2.57× |
| 65 | B: b1 proof | b1 | [`0x75a6adb5…adb7e4`](https://sepolia.etherscan.io/tx/0x75a6adb5c1a7f3fa869dda38a51d9f86636753225e5ab363041398bffaadb7e4) | 11947114 | 79,809 | 1.25× |
| 66 | B: b3 proof | b3 | [`0x0ad89a3c…d1318e`](https://sepolia.etherscan.io/tx/0x0ad89a3cbfb42f92fb1f5ef10827c50d6f681b2b969fe42e50e434fda3d1318e) | 11947115 | 79,809 | 1.25× |
| 67 | B: milestone 0 accepted | deployer | [`0x075d7722…378af5`](https://sepolia.etherscan.io/tx/0x075d77229835d3ca4e27980d18b782348ec74daeb05aefb489c1f352ee378af5) | 11947116 | 398,048 | 3.37× |
| 68 | B: milestone 1 accepted | deployer | [`0xa81b1988…0c7036`](https://sepolia.etherscan.io/tx/0xa81b1988f8deda5c3f0643496202d6e495c858f98484e37dabcec8393a0c7036) | 11947117 | 398,060 | 3.37× |
| 69 | B: conclude ACHIEVED | deployer | [`0x0a9dd166…222553`](https://sepolia.etherscan.io/tx/0x0a9dd166e5b7779ee8e2ebf1107601108983ff81417b03e217dafc8391222553) | 11947118 | 178,656 | 2.39× |
| 70 | B: dissolve | coord | [`0x54d68802…9572cc`](https://sepolia.etherscan.io/tx/0x54d6880288e0f49d490f758bbf332f0907a72f24a69006feb5e6beef849572cc) | 11947119 | 63,881 | 1.33× |

## How the run was made

`tools/sepolia/run.js` holds one step list for both modes. The rehearsal ran the list in `direct` mode against a local anvil with the vendored fixtures (`--fixtures`), which produced the gas reference above. The Sepolia run used `relay` mode: the process signed each batch of transactions off-line (`relay plan`, EIP-1559 type-2 transactions, gas limit = max(step limit, 16 × rehearsal gas), max fee 0.5 gwei then 0.25 gwei, priority fee 0.1 gwei), a relay broadcast the raw transactions in order through `eth_sendRawTransaction` against `https://ethereum-sepolia-rpc.publicnode.com` and returned the receipts, and `relay ingest` applied them before the next batch was planned. Batches end where a later step needs a value from a receipt: the task token id, the two ERC-8436 issue ids, the fulfillment submission id. Seven batches were needed.

Addresses of contracts created by the deployer were predicted from the nonce before broadcast and matched on-chain; the swarm ids were predicted from the registry address and the counter and matched the `SwarmFormed` events.

## Final state, read back from the chain

`deployments/sepolia/final-state.json` holds the `eth_call` results (raw and decoded) taken after the last transaction. What they say:

- Case A: `getSwarm` reports state **DISSOLVED**, outcome **ACHIEVED**, reason **ACCEPTANCE** (the tender adapter, as acceptance authority, concluded it from the kernel's record), charter hash `0x5c8dbbab30c3b8c0a5fcafcca24afcf4745282fc81c66444081f5746a590cf7d` and commitment hash `0xbcfdf7eb590242beff598151b0fe6c77be4ebc5ca5438e28963a3ffece8de79f` at version 1 — both equal to SHA-256 over the JCS form of `case-a/swarm-pack.json` and of its `commitment` member, so the pack in this repository is the one the members accepted. The objective is bound to obligation (11155111, `0xA62059A498E40C4Ae4aF926E2B00C1Ff122bDdb7`, token 19); `resultHash` `0x4bbd505dcfb2f9ba9ebaa1727c406f1a424121f8028e4263f9ae8d999299f1cf` is the fulfillment's result hash. w1 is **EXITED** with exit reason **SWARM_DISSOLVED**, admitted and accepted under the same charter hash.
- Case A, after dissolution: `isAuthorized(swarmA, REPRESENT, coord)` and `isAuthorized(swarmA, AMEND, coord)` are both **false**; the account's `recoveryAddress()` is coord (`0xEa66e8bD35187F0cb0ee19178050dd9D652A77f9`); the account's balance is **0 wei** — w1 received its 70 % of the 0.002 ETH reward through the account while the swarm lived, and coord recovered the remaining 30 % through the recovery path after dissolution. The registry answers `supportsInterface(0x085203a4)` and the account `supportsInterface(0x25e98353)` with true.
- Case B: state **DISSOLVED**, outcome **ACHIEVED**, reason **ACCEPTANCE**, phase 1 (the selected execution phase), charter hash `0xe4ce454d7e3a998c0da7751e2f3cf411407e0a1ec3447380f2e9723fb725538b` equal to SHA-256(JCS(`case-b/swarm-pack.json`)). Objective kind **MILESTONED**, 2 of 2 milestones **ACCEPTED** / **ACCEPTED**. b2 is **EXITED** with suspension cause **INELIGIBLE** and exit reason **REPLACED** (suspended by the challenge at 1792399956, replaced at 1792399980); b3 is **EXITED** with `substituted = true`, admitted in phase 1, exit reason **SWARM_DISSOLVED**. `memberCount` reports 0/0/0 after dissolution.

## Verification

All ten contracts are verified on Sourcify with an exact match (creation and runtime bytecode, metadata included); `deployments/sepolia/verification.md` has the per-contract record and the exact input. The inputs are the files under `assets/erc-8447/contracts` at commit `a78b92780818e3edbd630b95eee8ba73a3ee921c` with the compiler settings above; `forge verify-contract --chain sepolia --verifier sourcify <address> <path>:<Name>` reproduces it, with `--libraries` for `SwarmRegistry` (LifecycleLib 0xf0CA34139e77EE6Adae171930d330C77a75f09cd, MembershipLib 0x8582a086749A32F7BFce5BB8D9835026eF85d121, ResourceLib 0x77b7d8aaFe0Daa42b6E197392B29307A51c448a5).
