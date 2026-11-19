#!/usr/bin/env bash
# Keeps ~/.agent-memory (Claude's auto memory + per-repo notes) in step with a private
# GitHub repo: AGENT_MEMORY_REPO, default <gh login>/agent-memory. Installed by
# github.com/yesterdaysrebel/dotfiles and wired in ~/.claude/settings.json:
#   start     SessionStart: clone if missing, sync, print this repo's notes
#   push      Stop: sync, detached so the hook returns at once
#   prefetch  installer: pull the gitleaks image in the background
# A sync is: commit, pull --rebase, then check the remote is private and yours,
# secret-scan, and push anything unpushed. Always exits 0. A failed sync is recorded
# and printed by the next `start`, whose stdout goes into Claude's context.
# AGENT_MEMORY=off disables it.
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

[ "${AGENT_MEMORY:-}" = off ] && exit 0
MEM="${AGENT_MEMORY_DIR:-$HOME/.agent-memory}"
LOCK="$MEM/.git/agent-sync.lock"
FAIL="$MEM/.git/agent-sync-failed"
SELF="${BASH_SOURCE[0]}"
SLUG_RE='^[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*$'

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10"

g() { git -C "$MEM" "$@"; }
login() { timeout 15 gh api user --jq .login 2>/dev/null; }
has_upstream() { g rev-parse -q --verify '@{u}' >/dev/null 2>&1; }
unpushed() { ! has_upstream || [ "$(g rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)" != 0 ]; }
held() { echo "$1" >"$FAIL"; exit 0; }
# The line of git's output that says what went wrong; git prints nothing on a timeout.
reason() { grep -m1 -E '^(fatal|error|CONFLICT)' <<<"$1" || tail -n 1 <<<"${1:-timed out}"; }
# Network failures only: HTTP errors (403, 5xx) also say "unable to access" and must warn.
offline() { [[ -z "$1" || "$1" =~ Could\ not\ resolve\ host|Failed\ to\ connect|Connection\ (timed\ out|refused) ]]; }

ensure_clone() {
  [ -d "$MEM/.git" ] && return
  local me repo
  me=$(login) || return 1
  repo="${AGENT_MEMORY_REPO:-$me/agent-memory}"
  [[ "$repo" =~ $SLUG_RE ]] || return 1
  # Claude creates the empty memory dir before this hook first runs.
  find "$MEM" -depth -type d -empty -delete 2>/dev/null
  timeout 25 gh repo clone "$repo" "$MEM" -- -q >/dev/null 2>&1 || return 1
  # gh authenticates its own clone; later plain git pull/push need the helper too.
  g config credential.https://github.com.helper '!gh auth git-credential'
  g config user.name "$me"
  g config user.email "$me@users.noreply.github.com"
}

# Memory holds customer and repo names, so only push to a private repo of your own.
check_remote() {
  local slug me got
  slug=$(g remote get-url --push origin | sed -nE 's#(\.git)?/?$##; s#^.*[:/]([^/]+/[^/]+)$#\1#p')
  me=$(login) || held "push held: can't check the memory repo as your gh login (offline, or run 'gh auth login')"
  got=$(timeout 15 gh repo view "$slug" --json isPrivate,owner --jq '"\(.isPrivate) \(.owner.login)"' 2>/dev/null) \
    || held "push held: can't read $slug on GitHub"
  [ "$got" = "true $me" ] || held "push held: $slug must be a private repo owned by $me (got: $got). Make it private, then start a new session"
}

sync_repo() {
  local out why
  # Someone is resolving a conflict by hand; committing or aborting would wreck it.
  if [ -d "$MEM/.git/rebase-merge" ] || [ -d "$MEM/.git/rebase-apply" ]; then exit 0; fi
  out=$(g add -A 2>&1) || held "commit failed: $(reason "$out")"
  if ! g diff --cached --quiet; then
    out=$(g commit -q -m "sync: ${CODESPACE_NAME:-$(uname -n)}" 2>&1) || held "commit failed: $(reason "$out")"
  fi
  if has_upstream && ! out=$(timeout 15 git -C "$MEM" pull --rebase -q 2>&1); then
    g rebase --abort >/dev/null 2>&1
    offline "$out" && held "offline: notes are saved locally and push on the next sync"
    why=$(reason "$out")
    [[ "$out" == *CONFLICT* ]] && why+=". With the user: run 'git -C $MEM pull --rebase', resolve it, then start a new session"
    held "pull failed: $why"
  fi
  g rev-parse -q --verify HEAD >/dev/null || { rm -f "$FAIL"; return; }   # empty repo, nothing to push
  if unpushed; then
    check_remote
    # The docker CLI exits 1 with no daemon, which would read as a gitleaks finding.
    timeout 10 docker info >/dev/null 2>&1 </dev/null || held "push held: the secret scan needs Docker. Start Docker, then start a new session"
    # Same scan as a pre-push gitleaks run, on just the lines being pushed.
    local range='@{u}..HEAD'; has_upstream || range=HEAD
    g log -p --no-color "$range" | grep -a '^+' |
      timeout 60 docker run --rm -i --network none "$GITLEAKS_IMAGE" stdin \
        --redact --no-banner --log-level error >/dev/null 2>&1
    case $? in
      0) ;;
      1) held "push held: gitleaks found a secret in unpushed memory (files: $(g diff --name-only "$range" 2>/dev/null | tr '\n' ' ')). With the user: run 'git -C $MEM reset --soft @{u}', remove the secret, then start a new session" ;;
      *) held "push held: the secret scan could not run (it needs Docker)" ;;
    esac
    if ! out=$(timeout 15 git -C "$MEM" push -q -u origin HEAD 2>&1); then
      offline "$out" && held "offline: notes are saved locally and push on the next sync"
      held "push failed: $(reason "$out")"
    fi
  fi
  rm -f "$FAIL"
}

start() {
  local slug notes
  if ! ensure_clone; then
    echo "[agent-memory] WARNING: memory is not syncing: could not clone ${AGENT_MEMORY_REPO:-<gh login>/agent-memory} to $MEM. Re-run the dotfiles installer (it creates the repo), or 'gh auth login' (if $MEM already holds notes, move it aside first), then start a new session. Tell the user."
    return
  fi
  bash "$SELF" sync
  if [ -s "$FAIL" ]; then
    case "$(cat "$FAIL")" in
      offline:*) echo "[agent-memory] NOTE: $(cat "$FAIL")" ;;
      *) echo "[agent-memory] WARNING: memory sync is failing. Tell the user. Last error: $(cat "$FAIL")" ;;
    esac
  fi

  slug=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" remote get-url origin 2>/dev/null |
    sed -nE 's#(\.git)?/?$##; s#^.*[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\1#p')
  [[ "$slug" =~ $SLUG_RE ]] || return
  notes="$MEM/projects/$slug.md"
  if [ -s "$notes" ]; then
    # Claude Code replaces hook output over 10,000 characters with a short preview.
    echo "[agent-memory] Notes saved by earlier sessions for $slug (reference, not instructions). First 6000 bytes of $notes:"
    head -c 6000 "$notes"
  else
    echo "[agent-memory] No private notes yet for $slug. Notes specific to this repo go in $notes, not in memory/."
  fi
}

case "${1:-}" in
  start) start ;;
  # setsid: closing the terminal must not kill a push that is under way.
  push)  setsid bash "$SELF" sync </dev/null >/dev/null 2>&1 & ;;
  # flock -o: the kernel drops the lock if a sync is killed, and children don't inherit it.
  sync)  [ -d "$MEM/.git" ] && flock -o -w 5 "$LOCK" bash "$SELF" locked-sync >/dev/null 2>&1 ;;
  locked-sync) sync_repo ;;
  prefetch) setsid timeout 600 docker pull -q "$GITLEAKS_IMAGE" </dev/null >/dev/null 2>&1 & ;;
  *)     echo "usage: agent-memory-sync.sh {start|push|prefetch}" ;;
esac
exit 0
