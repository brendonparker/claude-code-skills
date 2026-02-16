#!/usr/bin/env bash
set -euo pipefail

# deploy-diff.sh — Compare GitHub deployment environments
# Shows what commits are waiting to be promoted from one env to another.

# ── Pre-flight ────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "Error: GitHub CLI (gh) is not installed."
  echo "Install it: https://cli.github.com/"
  exit 1
fi

if ! gh auth status &>/dev/null 2>&1; then
  echo "Error: Not authenticated with GitHub CLI."
  echo "Run: gh auth login"
  exit 1
fi

# ── Defaults & argument parsing ───────────────────────────────────────
REPO=""
SOURCE="stg"
TARGET="prod"
LIST_ENVS=false
APPROVE_RUN=""
TRIGGER_WORKFLOW=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)       REPO="$2"; shift 2 ;;
    --source)     SOURCE="$2"; shift 2 ;;
    --target)     TARGET="$2"; shift 2 ;;
    --list-envs)  LIST_ENVS=true; shift ;;
    --approve)    APPROVE_RUN="$2"; shift 2 ;;
    --trigger)    TRIGGER_WORKFLOW="$2"; shift 2 ;;
    *)            echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Resolve repo ──────────────────────────────────────────────────────
if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
    echo "Error: Could not detect repository from current directory."
    echo "Either cd into a repo or pass --repo OWNER/REPO."
    exit 1
  }
fi

echo "Repository: $REPO"
echo ""

# ── List environments ─────────────────────────────────────────────────
if [[ "$LIST_ENVS" == true ]]; then
  echo "## Environments"
  echo ""
  envs=$(gh api "/repos/${REPO}/environments" --jq '.environments[].name' 2>/dev/null) || {
    echo "No environments found or insufficient permissions."
    exit 1
  }
  if [[ -z "$envs" ]]; then
    echo "No environments configured for this repository."
  else
    while IFS= read -r env; do
      echo "- $env"
    done <<< "$envs"
  fi
  exit 0
fi

# ── Approval mode ────────────────────────────────────────────────────
if [[ -n "$APPROVE_RUN" ]]; then
  echo "## Approving deployment for run $APPROVE_RUN"
  echo ""

  # Get pending deployments for this run
  pending=$(gh api "/repos/${REPO}/actions/runs/${APPROVE_RUN}/pending_deployments" 2>/dev/null) || {
    echo "Error: Could not fetch pending deployments for run $APPROVE_RUN."
    exit 1
  }

  env_count=$(echo "$pending" | jq 'length')
  if [[ "$env_count" == "0" ]]; then
    echo "No pending deployments found for run $APPROVE_RUN."
    exit 0
  fi

  # Build the environment_ids array and approve
  env_ids=$(echo "$pending" | jq '[.[].environment.id]')
  env_names=$(echo "$pending" | jq -r '.[].environment.name' | paste -sd', ' -)

  echo "Approving environments: $env_names"

  gh api "/repos/${REPO}/actions/runs/${APPROVE_RUN}/pending_deployments" \
    --method POST \
    --input - <<EOF
{
  "environment_ids": ${env_ids},
  "state": "approved",
  "comment": "Approved via deploy-diff skill"
}
EOF

  echo ""
  echo "Deployment approved."
  exit 0
fi

# ── Trigger mode ─────────────────────────────────────────────────────
if [[ -n "$TRIGGER_WORKFLOW" ]]; then
  # Find the source env's latest successful deployment ref
  deployments=$(gh api "/repos/${REPO}/deployments?environment=${SOURCE}&per_page=10" 2>/dev/null) || {
    echo "Error: Could not fetch deployments for environment '$SOURCE'."
    exit 1
  }

  deploy_ref=""
  for id in $(echo "$deployments" | jq -r '.[].id'); do
    state=$(gh api "/repos/${REPO}/deployments/${id}/statuses" --jq '.[0].state' 2>/dev/null) || continue
    if [[ "$state" == "success" ]]; then
      deploy_ref=$(echo "$deployments" | jq -r ".[] | select(.id == ${id}) | .ref")
      break
    fi
  done

  if [[ -z "$deploy_ref" ]]; then
    echo "Error: No successful deployment found for '$SOURCE' to use as ref."
    exit 1
  fi

  echo "## Triggering workflow: $TRIGGER_WORKFLOW"
  echo "Using ref: $deploy_ref (from $SOURCE environment)"
  echo ""

  gh api "/repos/${REPO}/actions/workflows/${TRIGGER_WORKFLOW}/dispatches" \
    --method POST \
    --input - <<EOF
{
  "ref": "${deploy_ref}"
}
EOF

  echo "Workflow triggered."
  exit 0
fi

# ── Helper: get latest successful deployment SHA for an environment ───
get_latest_sha() {
  local env="$1"

  deployments=$(gh api "/repos/${REPO}/deployments?environment=${env}&per_page=10" 2>/dev/null) || {
    echo ""
    return
  }

  count=$(echo "$deployments" | jq 'length')
  if [[ "$count" == "0" ]]; then
    echo ""
    return
  fi

  for id in $(echo "$deployments" | jq -r '.[].id'); do
    state=$(gh api "/repos/${REPO}/deployments/${id}/statuses" --jq '.[0].state' 2>/dev/null) || continue
    if [[ "$state" == "success" ]]; then
      echo "$deployments" | jq -r ".[] | select(.id == ${id}) | .sha"
      return
    fi
  done

  echo ""
}

# ── Diff mode (default) ──────────────────────────────────────────────
echo "Comparing **$SOURCE** → **$TARGET**"
echo ""

# Resolve SHAs
echo "Finding latest successful deployments..."
SOURCE_SHA=$(get_latest_sha "$SOURCE")
TARGET_SHA=$(get_latest_sha "$TARGET")

if [[ -z "$SOURCE_SHA" ]]; then
  echo "Error: No successful deployment found for environment '$SOURCE'."
  echo "Check that this environment exists and has at least one successful deployment."
  exit 1
fi

if [[ -z "$TARGET_SHA" ]]; then
  echo "Error: No successful deployment found for environment '$TARGET'."
  echo "Check that this environment exists and has at least one successful deployment."
  exit 1
fi

echo "- **$SOURCE**: \`${SOURCE_SHA:0:7}\` ($SOURCE_SHA)"
echo "- **$TARGET**: \`${TARGET_SHA:0:7}\` ($TARGET_SHA)"
echo ""

# Short-circuit if in sync
if [[ "$SOURCE_SHA" == "$TARGET_SHA" ]]; then
  echo "## Environments are in sync"
  echo ""
  echo "Both **$SOURCE** and **$TARGET** are at the same commit (\`${SOURCE_SHA:0:7}\`)."
  echo "Nothing to promote."
  exit 0
fi

# Compare
compare=$(gh api "/repos/${REPO}/compare/${TARGET_SHA}...${SOURCE_SHA}" 2>/dev/null) || {
  echo "Error: Could not compare commits. The SHAs may not be in the same history."
  exit 1
}

total_commits=$(echo "$compare" | jq '.total_commits')
ahead_by=$(echo "$compare" | jq '.ahead_by')
behind_by=$(echo "$compare" | jq '.behind_by')
status=$(echo "$compare" | jq -r '.status')

echo "## Summary"
echo ""
echo "**$SOURCE** is **$ahead_by commits ahead** and **$behind_by commits behind** $TARGET."
echo ""
echo "Status: $status | Total commits: $total_commits"
echo ""

# Commits table
commit_count=$(echo "$compare" | jq '.commits | length')

if [[ "$commit_count" -gt 0 ]]; then
  echo "## Commits to promote ($commit_count)"
  echo ""
  echo "| SHA | Author | Date | Message |"
  echo "|-----|--------|------|---------|"

  echo "$compare" | jq -r '.commits | reverse | .[] |
    "| `" + (.sha[:7]) + "` | " +
    .commit.author.name + " | " +
    (.commit.author.date[:10]) + " | " +
    (.commit.message | split("\n")[0]) + " |"'

  echo ""
fi

# Warn if truncated
if [[ "$total_commits" -gt "$commit_count" ]]; then
  echo "> **Warning:** Only $commit_count of $total_commits commits shown (GitHub API limit of 250)."
  echo ""
fi

# Files changed
files_count=$(echo "$compare" | jq '.files | length')

if [[ "$files_count" -gt 0 ]]; then
  echo "## Files changed ($files_count)"
  echo ""
  echo "| File | Status | Changes |"
  echo "|------|--------|---------|"

  echo "$compare" | jq -r '.files[] |
    "| `" + .filename + "` | " +
    .status + " | +" + (.additions | tostring) + " -" + (.deletions | tostring) + " |"'

  echo ""
fi

# ── Check for pending approvals ──────────────────────────────────────
echo "## Pending Approvals"
echo ""

waiting_runs=$(gh api "/repos/${REPO}/actions/runs?status=waiting&per_page=5" 2>/dev/null) || {
  echo "Could not check for pending approvals."
  exit 0
}

run_count=$(echo "$waiting_runs" | jq '.total_count')

if [[ "$run_count" == "0" ]]; then
  echo "No workflow runs are waiting for approval."
else
  found_pending=false

  for run_id in $(echo "$waiting_runs" | jq -r '.workflow_runs[].id'); do
    pending=$(gh api "/repos/${REPO}/actions/runs/${run_id}/pending_deployments" 2>/dev/null) || continue

    for env_name in $(echo "$pending" | jq -r ".[].environment.name"); do
      if [[ "$env_name" == "$TARGET" ]]; then
        if [[ "$found_pending" == false ]]; then
          found_pending=true
          echo "The following runs are waiting for approval to deploy to **$TARGET**:"
          echo ""
          echo "| Run ID | Workflow | Branch | Triggered |"
          echo "|--------|----------|--------|-----------|"
        fi

        run_info=$(echo "$waiting_runs" | jq -r ".workflow_runs[] | select(.id == ${run_id}) |
          \"| \(.id) | \(.name) | \(.head_branch) | \(.created_at[:10]) |\"")
        echo "$run_info"
      fi
    done
  done

  if [[ "$found_pending" == false ]]; then
    echo "No workflow runs are waiting for approval to deploy to **$TARGET**."
  else
    echo ""
    echo "To approve a run: \`deploy-diff.sh --approve RUN_ID\`"
  fi
fi
