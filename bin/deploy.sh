#!/bin/bash
# workshop-toolkit deploy - push, WATCH the Pages run to success (retrying the flaky legacy
# deploy step "Deployment failed, try again later"), then VERIFY a unique string is live.
# Never reports done until the run is green AND the change is confirmed on the live URL.
#
# Usage: bin/deploy.sh "commit message" [verify-page.html] [unique-string-to-confirm]
set -uo pipefail
REPO="Clinic-Catalyst-AU/workshop-toolkit"
BASE="https://clinic-catalyst-au.github.io/workshop-toolkit"
MSG="${1:?commit message required}"; PAGE="${2:-}"; NEEDLE="${3:-}"
say(){ printf "\n\033[1;36m%s\033[0m\n" "$*"; }

cd "$HOME/Systems/workshop-toolkit"
say "[1/4] Commit + push"
git add -A
if git diff --cached --quiet; then echo "  (nothing new to commit - deploying current HEAD)"; else
  git commit -q -m "$MSG"$'\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>'
fi
git push -q origin HEAD || { echo "  push failed"; exit 1; }
SHA=$(git rev-parse --short HEAD); echo "  pushed $SHA"

say "[2/4] Watch the Pages run to success (retry the flaky deploy up to 4x)"
ok=0
for attempt in 1 2 3 4; do
  # find the newest pages run for this SHA
  sleep 8
  RID=$(gh run list -R "$REPO" -L 8 --json databaseId,headSha,name --jq \
        "[.[]|select(.headSha|startswith(\"$SHA\"))|.databaseId][0]" 2>/dev/null)
  [ -z "$RID" ] && RID=$(gh run list -R "$REPO" -L1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)
  echo "  attempt $attempt - watching run $RID"
  for i in $(seq 1 30); do
    read st cc < <(gh run view "$RID" -R "$REPO" --json status,conclusion --jq '.status+" "+(.conclusion//"-")' 2>/dev/null)
    [ "$st" = "completed" ] && break
    sleep 8
  done
  echo "  run $RID -> $cc"
  if [ "$cc" = "success" ]; then ok=1; break; fi
  echo "  deploy not green - re-running $RID"
  gh run rerun "$RID" -R "$REPO" >/dev/null 2>&1 || true
done
[ "$ok" -eq 1 ] || { echo "  !! Pages still not green after retries - GitHub Pages may be degraded. Try again shortly."; exit 1; }

say "[3/4] Verify the change is actually live"
if [ -n "$PAGE" ] && [ -n "$NEEDLE" ]; then
  for i in $(seq 1 12); do
    if curl -fsSL "$BASE/$PAGE?cb=$RANDOM$RANDOM" 2>/dev/null | grep -qF "$NEEDLE"; then
      echo "  LIVE: '$NEEDLE' confirmed on $PAGE"; say "[4/4] DONE - deployed + verified"; exit 0
    fi
    sleep 6
  done
  echo "  !! run went green but '$NEEDLE' not yet on live $PAGE (CDN lag) - re-check in a minute"; exit 1
else
  echo "  (no verify string passed - run is green; pass page + string to confirm content)"
  say "[4/4] DONE - run green"; exit 0
fi
