# Vendored test fixtures (unmodified)

- `acdf/` — the ERC-8436 reference registries (`ACDFTypes.sol`, `ACDFPolicyRegistry.sol`, `ACDFRegistry.sol`,
  `interfaces/`, `libraries/SignatureChecker.sol`), copied verbatim from `ethereum/ERCs` `assets/erc-8436/contracts`
  at commit `4dec821bcb7dfbd739c843dcb7247e750781dd55`, so that the decision adapter is tested against the real
  collective-decision kernel: policy validation, the obligation rule, rounds, finality and enactment records.
- `task-token/` — the token-bound task tender kernel (`TaskToken.sol`, `TaskVault.sol`, `interfaces/`), copied
  verbatim from https://github.com/garyyang-finchip/task-token-standard at commit
  `3196db8752ca8c82b89dc9e1494683d5014c6e31`, so that the tender adapter and the swarm account are tested against
  the real kernel's vault, submission records, acceptance path and credit withdrawal.

They are test fixtures only (CC0-1.0); they are not part of the proposal's assets.
