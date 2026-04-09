# Stacked PR Workflow

This repo's current stacked-PR workflow is built around one integration branch and a linear chain of review branches.

## Roles

- `latitude-e2e-harness-next`: integration/scratch branch for the full combined work
- `stack/01-upstream-improvements`
- `stack/02-ha-core`
- `stack/03-ha-validator-integration`
- `stack/04-ha-operator-workflow`
- `stack/05-harness-docs`
- `stack/06-harness-core`
- `stack/07-compose-target`
- `stack/08-latitude-target`
- `stack/09-vm-target`
- `stack/10-harness-ci`

Each `stack/*` branch is based on the previous branch, not directly on `main`.

## PR Bases

- `stack/01-upstream-improvements` -> `main`
- `stack/02-ha-core` -> `stack/01-upstream-improvements`
- `stack/03-ha-validator-integration` -> `stack/02-ha-core`
- `stack/04-ha-operator-workflow` -> `stack/03-ha-validator-integration`
- `stack/05-harness-docs` -> `stack/04-ha-operator-workflow`
- `stack/06-harness-core` -> `stack/05-harness-docs`
- `stack/07-compose-target` -> `stack/06-harness-core`
- `stack/08-latitude-target` -> `stack/07-compose-target`
- `stack/09-vm-target` -> `stack/08-latitude-target`
- `stack/10-harness-ci` -> `stack/09-vm-target`

Never open a PR directly from `latitude-e2e-harness-next`.

## Review Feedback Workflow

When PR `stack/0N-*` receives review feedback:

```bash
git switch stack/0N-branch
# make fixes
git commit -m "fix: address review feedback"
git push origin stack/0N-branch
```

Then rebase each downstream branch onto its updated parent:

```bash
git switch stack/0N+1-branch
git rebase stack/0N-branch
git push --force-with-lease origin stack/0N+1-branch
```

Repeat downward through the rest of the stack.

Do not merge parent branches into child branches.

## After a Squash Merge

These branches are expected to merge into `main` with squash merge.

After `stack/01-upstream-improvements` merges:

```bash
git fetch origin
git switch stack/02-ha-core
git rebase --onto origin/main stack/01-upstream-improvements stack/02-ha-core
git push --force-with-lease origin stack/02-ha-core
```

Then update the GitHub base branch for the next PR from the old parent to `main`, and cascade the remaining branches:

```bash
git switch stack/03-ha-validator-integration
git rebase stack/02-ha-core
git push --force-with-lease origin stack/03-ha-validator-integration
```

Repeat for the rest of the stack.

## Integration Branch Rule

`latitude-e2e-harness-next` remains the source-of-truth integration branch.

If a review-fix commit lands on a `stack/*` branch, replay it back into `latitude-e2e-harness-next`:

- use `git merge --ff-only <stack-branch>` when it fast-forwards cleanly
- otherwise use `git cherry-pick -x <fix-commit-sha>`

This keeps future branch cuts aligned with reviewed code.

## Publishing

Use plain Git plus `gh`.

Typical GitHub CLI commands:

```bash
gh pr create --base stack/01-upstream-improvements --head stack/02-ha-core
gh pr edit <pr-number> --base main
gh pr view <pr-number>
```

Always use `git push --force-with-lease` for rebased `stack/*` branches.
