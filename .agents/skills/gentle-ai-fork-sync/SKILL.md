---
name: gentle-ai-fork-sync
description: "Trigger: sync fork, upstream main, refresh beta pins, render parity, gentle-shell sync. Safely synchronize Gentle AI forks and Nix branch pins."
license: Apache-2.0
metadata:
  author: gentleman-programming
  version: "1.0"
---

## Activation Contract

Use for fork/main sync and branch pins, not releases or contract rebases.

## Hard Rules

- First inspect scope, clean worktrees, remotes and live upstream/fork/shell/Engram refs read-only.
- Preserve the fork's declarative-config feature and contract pin. Never rebase, force-push, or repin the contract without explicit authorization.
- Keep stable channels intact unless releases changed; verify live refs.

## Decision Gates

| Condition | Action |
| --- | --- |
| Fork main is an ancestor of upstream main | Allow authorized fast-forward only. |
| Divergence/non-fast-forward | Stop for a separate explicit decision. |
| Missing render parity | Stop before pinning/publication; scope the fix separately. |
| Publication unauthorized | Keep changes local. |

## Execution Steps

1. Audit upstream commit diffs for imperative install/config-generated artifacts against `gentle-ai config render`. Compare semantic outputs/tests; never blindly copy imperative side effects.
2. Fast-forward eligible fork main only.
3. Refresh beta in `packages/versions.nix`, shell in `packages/pi-versions.nix`, and Engram main in `packages/engram-versions.nix` only if it moved. Verify source/vendor hashes with builds and both shell literals in `checks/default.nix`.
4. Branch/commit scoped changes; build affected packages and run full `nix flake check`. Obtain native review through the provider-owned route.
5. Publish only with authorization and satisfied checks; follow native review transitions without treating a receipt as delivery authority. If review is unavailable, ask whether to publish this candidate unreviewed. Recheck tips/clean state.

## Output Contract

Report files, refs, parity/hash evidence, checks, review, registry-refresh needs, stale tips and unverified platforms/activation.

## References

- `packages/versions.nix`
- `lib/render.nix`
- `checks/default.nix`
