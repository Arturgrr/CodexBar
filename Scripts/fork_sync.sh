#!/usr/bin/env bash
# Sync the personal fork: fast-forward main to upstream, rebase the personal branch onto it, push both.
#
# Branch layout:
#   main      mirror of upstream/main (never commit here)
#   personal  main + personal commits (rebased on every sync)
#
# Usage: ./Scripts/fork_sync.sh [--no-push]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
FORK_REMOTE="${FORK_REMOTE:-origin}"
BASE_BRANCH="${BASE_BRANCH:-main}"
PERSONAL_BRANCH="${PERSONAL_BRANCH:-personal}"
PUSH=1

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    *) fail "unknown argument: $arg" ;;
  esac
done

cd "$ROOT_DIR"
[[ -z "$(git status --porcelain)" ]] || fail "working tree has uncommitted changes; commit or stash them first"
[[ ! -d "$(git rev-parse --git-path rebase-merge)" ]] || fail "a rebase is already in progress; finish it first"

log "==> Fetching ${UPSTREAM_REMOTE}/${BASE_BRANCH} and ${FORK_REMOTE}"
git fetch --quiet "$UPSTREAM_REMOTE" "$BASE_BRANCH"
git fetch --quiet "$FORK_REMOTE"

previous_base=$(git rev-parse "$BASE_BRANCH")
git switch --quiet "$BASE_BRANCH"
git merge --quiet --ff-only "${UPSTREAM_REMOTE}/${BASE_BRANCH}" \
  || fail "${BASE_BRANCH} has diverged from ${UPSTREAM_REMOTE}/${BASE_BRANCH}; keep personal commits on ${PERSONAL_BRANCH}"
new_commits=$(git rev-list --count "${previous_base}..${BASE_BRANCH}")
log "==> ${BASE_BRANCH}: ${new_commits} new upstream commit(s)"

git switch --quiet "$PERSONAL_BRANCH"
if ! git rebase --quiet "$BASE_BRANCH"; then
  fail "rebase stopped on a conflict. Resolve it, run 'git rebase --continue', then rerun this script"
fi
ahead=$(git rev-list --count "${BASE_BRANCH}..${PERSONAL_BRANCH}")
log "==> ${PERSONAL_BRANCH}: ${ahead} personal commit(s) on top of $(git rev-parse --short "$BASE_BRANCH")"

if [[ "$PUSH" == "1" ]]; then
  git push --quiet "$FORK_REMOTE" "$BASE_BRANCH"
  git push --quiet --force-with-lease "$FORK_REMOTE" "$PERSONAL_BRANCH"
  log "==> Pushed ${BASE_BRANCH} and ${PERSONAL_BRANCH} to ${FORK_REMOTE}"
fi

log "Next: ./Scripts/fork_install.sh to rebuild and reinstall CodexBar.app"
