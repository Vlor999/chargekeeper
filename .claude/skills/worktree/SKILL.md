---
name: worktree
description: Implement one feature or fix of Jauge in an isolated git worktree, from branch to GitHub PR on dev (checks, local validation, logical commits, push, PR). Use when asked to implement something in a worktree or to start a worktree for a task.
user-invocable: true
---

Implement one task in an isolated worktree, up to the PR on `dev`.
One task = one worktree = one PR.

**Signature:** `/worktree <GitHub issue number or task description>`

If the task is missing or unclear, ask before continuing.

## 1. Read the task

With an issue number: `gh issue view <n>`. If the work already exists on `dev`, say so
and do only what is really left.

## 2. Create the worktree

Branch: `<type>/<feature-slug>` (e.g. `fix/flow-animation`), `type` = Conventional Commit type.

```bash
git fetch origin
git worktree add .claude/worktrees/<feature-slug> -b <branch> origin/dev
cd .claude/worktrees/<feature-slug>
```

Work only inside this worktree.

## 3. Implement

- Load `ponytail` first: the simplest thing that works, reuse what the repo has.
- Follow `CLAUDE.md` and `.claude/rules/`.
- Stay inside the task scope. No refactor that was not asked for.

## 4. Verify

Run the checks of `CLAUDE.md` until green:

```bash
make check && make
```

Never push red, never use `--no-verify`. A visible change gets a local demo first (rendered
snapshot of the view, or the local build installed in `/Applications`) and explicit
validation by the user before any commit.

## 5. Commit and push

Use `logical-commit-sequencer` to split the work into atomic commits, ordered by
dependency. Conventional Commits, with the Co-Authored-By trailer. Then:

```bash
git push -u origin <branch>
```

## 6. Open the PR

```bash
gh pr create --base dev --title "<conventional commit>" --body "..."
```

Body:

```
## Intent
<What the PR does and why, 1-2 sentences. `Closes #<n>` if from an issue.>

## Choices and caveats
- <Each decision taken, as a statement.>
```

No question in the body. An open decision goes to the user in the conversation and is
settled before the PR is opened.

## 7. Report

Give the PR URL, the decisions taken, and the work left after the PR. Remove the
worktree once the PR is merged: `git worktree remove .claude/worktrees/<feature-slug>`.
