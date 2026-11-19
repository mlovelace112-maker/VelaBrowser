#!/bin/bash
# One-time: turns on GitHub's security settings for the VelaBrowser repo.
# Needs the GitHub command-line tool, signed in as the repo owner:
#   brew install gh && gh auth login        (only the first time)
#   bash scripts/secure-repo.sh
#
# Safe to run again; each step just sets the setting.
set -uo pipefail
REPO="mlovelace112-maker/VelaBrowser"
R="repos/$REPO"
ok()   { echo "  ✓ $1"; }
fail() { echo "  ✗ $1 (do it by hand: see "Repository security settings" in the README)"; }
step() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else fail "$label"; fi; }

command -v gh >/dev/null || { echo "✗ Install the GitHub tool first: brew install gh && gh auth login"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✗ Sign in first: gh auth login"; exit 1; }

echo "▸ Alerts and scanning"
step "Secret scanning and push protection (blocks committing keys)" \
  gh api -X PATCH "$R" --input - <<<'{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}'
step "Dependabot alerts" gh api -X PUT "$R/vulnerability-alerts"
step "Dependabot security fixes" gh api -X PUT "$R/automated-security-fixes"
step "Private vulnerability reporting" gh api -X PUT "$R/private-vulnerability-reporting"
step "Immutable releases (published releases can't be changed)" gh api -X PUT "$R/immutable-releases"
step "Delete branches after merging" gh api -X PATCH "$R" -F delete_branch_on_merge=true

echo "▸ GitHub Actions"
step "Workflows get read-only access unless they ask for more" \
  gh api -X PUT "$R/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
step "Only GitHub's own and verified actions may run" \
  gh api -X PUT "$R/actions/permissions" -F enabled=true -f allowed_actions=selected
step "  …allow GitHub-made and verified actions" \
  gh api -X PUT "$R/actions/permissions/selected-actions" -F github_owned_allowed=true -F verified_allowed=true
step "Pull requests from strangers need your approval before they run" \
  gh api -X PUT "$R/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors

echo "▸ Branch and tag protection"
ruleset() {
  local name="$1" body="$2"
  local id
  id=$(gh api "$R/rulesets" --jq ".[] | select(.name==\"$name\") | .id" 2>/dev/null)
  if [[ -n "$id" ]]; then
    gh api -X PUT "$R/rulesets/$id" --input - <<<"$body"
  else
    gh api -X POST "$R/rulesets" --input - <<<"$body"
  fi
}
step "main: changes only through pull requests that pass the Build check; no force-push or delete" ruleset "Protect main" '{
  "name":"Protect main","target":"branch","enforcement":"active",
  "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
  "bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}],
  "rules":[
    {"type":"deletion"},{"type":"non_fast_forward"},
    {"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":false}},
    {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":[{"context":"build"}]}}
  ]}'
step "appcast (the update feed): no force-push or delete" ruleset "Protect update feed" '{
  "name":"Protect update feed","target":"branch","enforcement":"active",
  "conditions":{"ref_name":{"include":["refs/heads/appcast"],"exclude":[]}},
  "rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}'
step "Release tags (v…): can't be moved or deleted" ruleset "Protect release tags" '{
  "name":"Protect release tags","target":"tag","enforcement":"active",
  "conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},
  "rules":[{"type":"deletion"},{"type":"update"},{"type":"non_fast_forward"}]}'

echo
echo "✓ Done. Check the result in the repo's Settings ▸ Rules and Settings ▸ Code security."
