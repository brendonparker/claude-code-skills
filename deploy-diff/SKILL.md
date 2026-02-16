---
name: deploy-diff
description: >
  Compare GitHub deployment environments to see what commits are waiting
  to be promoted. Use when asked about deployments, what's waiting to go
  to prod, promoting staging, or comparing environments.
allowed-tools: Bash(gh *), Bash(*deploy-diff*)
argument-hint: "[source-env] [target-env]"
---

# Deploy Diff

Compare two GitHub deployment environments to show what commits would be introduced by promoting one to the other.

## How to use

Run the deploy-diff script located at `$SKILL_DIR/scripts/deploy-diff.sh`.

### Default behavior

- **source** defaults to `stg`, **target** defaults to `prod`
- The repo is auto-detected from the current git remote unless the user specifies one

### Interpreting user intent

- "what's waiting for prod?" → source=stg, target=prod
- "compare stg and prod" → source=stg, target=prod
- "what would go out if we deploy staging?" → source=stg, target=prod
- "diff dev and staging" → source=dev, target=stg
- If the user hasn't specified environments and they can't be inferred, run with `--list-envs` first and ask the user which environments to compare

### Running the script

```bash
# Basic diff (auto-detect repo, stg → prod)
bash "$SKILL_DIR/scripts/deploy-diff.sh" --source stg --target prod

# List available environments
bash "$SKILL_DIR/scripts/deploy-diff.sh" --list-envs

# Specific repo
bash "$SKILL_DIR/scripts/deploy-diff.sh" --repo owner/repo --source stg --target prod

# Approve a pending deployment
bash "$SKILL_DIR/scripts/deploy-diff.sh" --approve RUN_ID

# Trigger a workflow dispatch
bash "$SKILL_DIR/scripts/deploy-diff.sh" --trigger workflow.yml
```

### Presenting results

- Interpret the markdown output from the script and present it conversationally
- Highlight the number of commits and key changes
- Call out any warnings (e.g., truncated commit lists due to API limits)

### Approvals and triggering deploys

- If the script output indicates **pending approvals**, offer to approve — but always confirm with the user first since approval is irreversible
- If there are no pending approvals but the user wants to deploy, offer to trigger via `--trigger`. Ask the user which workflow file if multiple could apply
- Never approve or trigger without explicit user confirmation
