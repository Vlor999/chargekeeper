---
description: "Jauge project rules: branches, commits, PRs, validation, release, security."
---

# Project

## Branches

- `dev` = working branch (default). Small change: commit directly on `dev`. Otherwise branch `<type>/<slug>` from `origin/dev` → PR to `dev` (skill `worktree`).
- `main` only receives the `dev → main` PR, as a merge commit (no squash: `dev` and `main` would diverge). Enforced by the ruleset and the `source-branch` check.
- Merge to `main` = release when `VERSION` is new (`docs/release.md`). No manual tag. Bump `VERSION` on `dev` before opening the release PR.
- No force-push or deletion on `dev`/`main`. After a push, fix with a new commit, not `--amend`.

## Commits and PRs

- Conventional Commits (`feat`, `fix`, `perf`, `ci`, `chore`, `docs`, `refactor`, `test`), with the `Co-Authored-By` trailer.
- Atomic commits ordered by dependency: skill `logical-commit-sequencer`.
- PR body: `## Intent` / `## Choices and caveats`. No question in the body: an open decision is settled with the user before the PR is opened.
- Review: skill `mr-review`.

## Validation

- Green checks before any push (`CLAUDE.md` § Checks). Never `--no-verify`.
- Visible change: local demo and explicit user validation before commit.
- Stay inside the requested scope: no refactor, no speculative feature. Simplicity first (`ponytail`).
- Menu bar app: nothing may run while no window is open (no animation, no polling). Measure CPU and memory with the menu closed after a UI change.

## Security

- The service runs as root: every socket input is validated or clamped (`Daemon/main.swift` `mutate`), the socket stays `root:admin 0660`, external commands use absolute paths and fixed arguments.
- Battery safety: on exit or crash recovery the service never leaves discharge on or sleep disabled.
- Never print or commit signing material or the Sparkle private key.
- GitHub workflows: actions pinned by SHA, minimal `permissions`, third-party code (XcodeGen, Sparkle) fetched and pinned before signing secrets are loaded, third-party-controlled values passed through `env`, never interpolated in `run`.
