#!/usr/bin/env bash
#
# Integration test for the installer (index.html). Runs it end-to-end as root inside
# a fresh Debian container with the repo mounted read-only at /repo -- see
# tests/run-in-docker.sh and CI. Uses a throwaway $HOME, local git fixtures for this
# repo and for ai-rules-central, and stub `cde-init`/`claude`/`code` binaries, so it
# never touches real dotfiles and needs no GitHub credentials.

# shellcheck disable=SC2088  # "~" in pass/fail messages is display text
set -euo pipefail

REPO="${REPO:-/repo}"
export DEBIAN_FRONTEND=noninteractive TERM="${TERM:-xterm}"
HOME="$(mktemp -d)"; export HOME
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
FIX="$(mktemp -d)"
OUT="$FIX/out.log"

note() { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; [ -f "$OUT" ] && sed 's/^/    | /' "$OUT" >&2; exit 1; }
# Piped, like `curl ... | zsh`: any child that reads stdin would swallow the script.
install() { zsh < "$REPO/index.html" >"$OUT" 2>&1; }
backups() { find "$HOME" -maxdepth 1 -name '.dotfiles-backup-*' | wc -l; }
summaries() { grep -c '^dotfiles (' "$OUT" || true; }

note "Install prerequisites (zsh git curl tmux vim jq)"
apt-get update -qq
apt-get install -y -qq zsh git curl ca-certificates tmux vim jq >/dev/null
printf 'using: '; zsh --version; printf 'using: '; tmux -V

note "Static checks"
zsh -n "$REPO/index.html" && pass "zsh -n parses index.html" || fail "index.html has syntax errors"
zsh -n "$REPO/dotfiles.zsh" && pass "zsh -n parses dotfiles.zsh" || fail "dotfiles.zsh has syntax errors"
[ "$(head -1 "$REPO/index.html")" = '#<plaintext>' ] \
  && pass "line 1 is the #<plaintext> browser marker" || fail "line 1 is not '#<plaintext>'"

note "Version resolution (local git fixture, no TTY)"
src="$FIX/dotfiles-src"; git init -q -b main "$src"
raw="https://raw.githubusercontent.com/yesterdaysrebel/dotfiles"
resolve() { REPO_GIT="$src" DOTFILES_RESOLVE_ONLY=1 zsh "$REPO/index.html" 2>/dev/null | grep "^REPO_RAW=" || true; }
git -C "$src" commit -q --allow-empty -m one
got="$(resolve)"
[ "$got" = "REPO_RAW=$raw/$(git -C "$src" rev-parse main)" ] \
  && pass "no TTY + no tags falls back to main" || fail "no-tag default wrong: $got"
git -C "$src" tag -a v1.0.0 -m v1.0.0
got="$(resolve)"   # one tag: a one-element array must not be indexed by character
[ "$got" = "REPO_RAW=$raw/$(git -C "$src" rev-parse 'v1.0.0^{commit}')" ] \
  && pass "no TTY + a single tag picks that tag" || fail "single-tag default wrong: $got"
git -C "$src" commit -q --allow-empty -m two; git -C "$src" tag v1.1.0
git -C "$src" checkout -q -b feat/main; git -C "$src" commit -q --allow-empty -m three; git -C "$src" checkout -q main
want_tag="$(git -C "$src" rev-parse 'v1.0.0^{commit}')"; want_new="$(git -C "$src" rev-parse v1.1.0)"
want_main="$(git -C "$src" rev-parse main)"
got="$(DOTFILES_REF=v1.0.0 resolve)"
[ "$got" = "REPO_RAW=$raw/$want_tag" ] && pass "annotated tag resolves to its commit SHA" || fail "tag resolution wrong: $got"
got="$(resolve)"
[ "$got" = "REPO_RAW=$raw/$want_new" ] && pass "no TTY + no ref picks the newest tag" || fail "newest-tag default wrong: $got"
got="$(DOTFILES_REF=main resolve)"
[ "$got" = "REPO_RAW=$raw/$want_main" ] && pass "'main' matches exactly (not feat/main)" || fail "main resolved wrong: $got"
if REPO_GIT="$src" DOTFILES_REF=v9.9.9 zsh "$REPO/index.html" >"$OUT" 2>&1; then fail "unknown ref should fail"; fi
grep -q "No tag or branch named 'v9.9.9'" "$OUT" && grep -qE 'FAIL +version' "$OUT" && [ ! -e "$HOME/.oh-my-zsh" ] \
  && pass "unknown ref fails with a summary before changing anything" || fail "unknown ref not reported"
if REPO_GIT="$FIX/missing" zsh "$REPO/index.html" >"$OUT" 2>&1; then fail "unreachable repo should fail"; fi
grep -q "Can't reach" "$OUT" && grep -qE 'FAIL +version' "$OUT" \
  && pass "unreachable repo fails loudly, with a summary" || fail "offline failure was silent"

note "Fixtures: ai-rules-central clone + stub cde-init/claude/code"
rules="$FIX/ai-rules-central"; mkdir -p "$rules/.github/prompts" "$rules/.github/instructions"
for p in ai-review ai-plan; do printf -- '---\nname: "%s"\n---\nDo %s.\n' "$p" "$p" > "$rules/.github/prompts/$p.prompt.md"; done
echo "# Baseline" > "$rules/.github/instructions/copilot-workspace.instructions.md"
git -C "$rules" init -q -b main && git -C "$rules" add -A && git -C "$rules" commit -q -m init
export AI_RULES_REPO="$rules"
mkdir -p "$FIX/bin"
# Reads stdin on purpose: under `curl | zsh` it would eat the script without </dev/null.
cat > "$FIX/bin/cde-init" <<EOF
#!/bin/sh
cat >/dev/null
umask > "$FIX/cde-umask"
EOF
cat > "$FIX/bin/claude" <<'EOF'
#!/bin/sh
[ "$1 $2" = "auth status" ] || exit 1
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then echo '{"authMethod":"oauth_token"}'; else echo '{"authMethod":"none"}'; fi
EOF
cat > "$FIX/bin/code" <<EOF
#!/bin/sh
case "\$1" in
  --list-extensions) cat "$FIX/exts" 2>/dev/null; exit 0 ;;
  --install-extension) echo "\$2" >> "$FIX/exts"; echo "\$2" >> "$FIX/installs" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FIX/bin/cde-init" "$FIX/bin/claude" "$FIX/bin/code"
export PATH="$FIX/bin:$PATH"
TOKEN="test-oauth-token-DO-NOT-PRINT"
export REPO_RAW="file://$REPO"

note "First install, piped like curl | zsh (token set, VS Code available)"
CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" install || fail "installer exited non-zero"
grep -q '^Next: ' "$OUT" && pass "piped install runs to the end (no child ate stdin)" || fail "piped install stopped early"
grep -qE 'OK +cde-init' "$OUT" && [ "$(cat "$FIX/cde-umask")" = 0022 ] \
  && pass "cde-init ran, before the installer's umask 077" || fail "cde-init not run, or ran under umask 077"
grep -qF "$TOKEN" "$OUT" && fail "token value appeared in installer output" || pass "token never printed"
[ "$(summaries)" = 1 ] && pass "summary printed once" || fail "summary printed $(summaries) times"
omz_ref="$(grep -E '^OMZ_REF=' "$REPO/index.html" | cut -d'"' -f2)"
[ "$(git -C "$HOME/.oh-my-zsh" rev-parse HEAD)" = "$omz_ref" ] && pass "Oh-My-Zsh pinned at $omz_ref" || fail "Oh-My-Zsh not at pin"
for p in zsh-syntax-highlighting zsh-autosuggestions you-should-use; do
  [ -d "$HOME/.oh-my-zsh/custom/plugins/$p/.git" ] && pass "zsh plugin cloned: $p" || fail "zsh plugin missing: $p"
done
cmp -s "$REPO/dotfiles.zsh" "$HOME/.oh-my-zsh/custom/dotfiles.zsh" && pass "dotfiles.zsh drop-in installed" || fail "drop-in missing"
zsh -ic '(( ${+functions[_zsh_autosuggest_start]} )) && [[ -n $ZSH_HIGHLIGHT_VERSION ]] && echo loaded' 2>/dev/null | grep -qx loaded \
  && pass "interactive zsh loads autosuggestions + syntax highlighting" || fail "zsh plugins not loaded in interactive shell"
grep -q '^plugins=(git)$' "$HOME/.zshrc" && pass "~/.zshrc plugins=() left untouched" || fail "~/.zshrc was edited"
for f in tmux.conf tmux-cheatsheet.txt vimrc; do
  cmp -s "$REPO/$f" "$HOME/.${f}" && pass "~/.$f installed" || fail "~/.$f missing or differs"
done
tmux -L citest -f "$HOME/.tmux.conf" new-session -d -s t 'sleep 2' && tmux -L citest kill-server \
  && pass "tmux starts with the installed config" || fail "tmux rejected ~/.tmux.conf"
[ -d "$HOME/.vim/plugged/gruvbox" ] && pass "vim plugins installed" || fail "vim +PlugInstall failed"
cmp -s "$REPO/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" && pass "~/.claude/CLAUDE.md installed" || fail "CLAUDE.md missing"
for p in ai-review ai-plan; do
  [ "$(readlink "$HOME/.claude/commands/$p.md")" = "$HOME/.local/share/ai-rules-central/.github/prompts/$p.prompt.md" ] \
    && pass "/$p command links to the synced prompt" || fail "/$p command link wrong"
done
jq -e '.hasCompletedOnboarding == true' "$HOME/.claude.json" >/dev/null && pass "onboarding marked complete" || fail "~/.claude.json not set"
grep -qE 'OK +Claude auth +oauth_token' "$OUT" && pass "summary: Claude auth OK (oauth_token)" || fail "auth not reported OK"
grep -qx anthropic.claude-code "$FIX/installs" && grep -qE 'OK +VS Code extension +installed' "$OUT" \
  && pass "VS Code extension installed" || fail "extension not installed"
[ "$(backups)" = 0 ] && pass "fresh install creates no backups" || fail "unexpected backup dir"
[ "$(stat -c %a "$HOME/.tmux.conf")" = 600 ] && pass "installed files are private (umask 077)" || fail "umask not applied"

note "Re-run is a no-op"
CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" install || fail "re-run exited non-zero"
[ "$(backups)" = 0 ] && pass "unchanged files are not backed up again" || fail "re-run created a backup"
grep -qE 'OK +config files +0 updated' "$OUT" && pass "0 config files updated" || fail "re-run rewrote files"
grep -qE 'already installed' "$OUT" && [ "$(wc -l < "$FIX/installs")" = 1 ] \
  && pass "extension not reinstalled" || fail "extension reinstalled"

note "Edits backed up, symlinks replaced not written through, ~/.claude.json merged"
echo "# local edit" >> "$HOME/.tmux.conf"
echo "my own vimrc" > "$FIX/my-vimrc"; ln -sf "$FIX/my-vimrc" "$HOME/.vimrc"
echo '{"keep": 1}' > "$HOME/.claude.json"
ysu="$HOME/.oh-my-zsh/custom/plugins/you-should-use"
git -C "$ysu" commit -q --allow-empty -m tamper
git -C "$rules" rm -q .github/prompts/ai-plan.prompt.md && git -C "$rules" commit -q -m "drop ai-plan"
CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" install || fail "third run exited non-zero"
cmp -s "$REPO/tmux.conf" "$HOME/.tmux.conf" && pass "edited ~/.tmux.conf restored" || fail "~/.tmux.conf not restored"
grep -q '# local edit' "$HOME"/.dotfiles-backup-*/.tmux.conf && pass "edited copy kept in backup" || fail "edit not backed up"
[ "$(cat "$FIX/my-vimrc")" = "my own vimrc" ] && [ ! -L "$HOME/.vimrc" ] && cmp -s "$REPO/vimrc" "$HOME/.vimrc" \
  && pass "symlinked ~/.vimrc replaced; its target left untouched" || fail "installer wrote through the ~/.vimrc symlink"
jq -e '.keep == 1 and .hasCompletedOnboarding == true' "$HOME/.claude.json" >/dev/null \
  && jq -e '. == {"keep": 1}' "$HOME"/.dotfiles-backup-*/.claude.json >/dev/null \
  && pass "existing ~/.claude.json merged (and backed up)" || fail "~/.claude.json not merged"
ysu_sha="$(grep -oE 'YOU_SHOULD_USE_SHA="[0-9a-f]{40}"' "$REPO/index.html" | grep -oE '[0-9a-f]{40}')"
[ "$(git -C "$ysu" rev-parse HEAD)" = "$ysu_sha" ] && pass "drifted plugin re-cloned at the pinned SHA" || fail "plugin drift not repaired"
[ ! -e "$HOME/.claude/commands/ai-plan.md" ] && [ ! -L "$HOME/.claude/commands/ai-plan.md" ] \
  && pass "link to a removed upstream prompt cleaned up" || fail "stale /ai-plan link left behind"

note "No token, no VS Code, no AI-rules access: warns, still exits 0"
rm -f "$HOME/.claude.json"; rm -rf "$HOME/.local/share/ai-rules-central"
rm "$FIX/bin/code"
env -u CLAUDE_CODE_OAUTH_TOKEN AI_RULES_REPO="$FIX/no-access" zsh < "$REPO/index.html" >"$OUT" 2>&1 || fail "exited non-zero"
grep -qE 'WARN +Claude auth +CLAUDE_CODE_OAUTH_TOKEN not set' "$OUT" && pass "missing token warns" || fail "missing token not reported"
[ ! -e "$HOME/.claude.json" ] && pass "~/.claude.json untouched without a token" || fail "~/.claude.json written without token"
grep -qE "SKIP +VS Code extension" "$OUT" && grep -q 'code --install-extension anthropic.claude-code' "$OUT" \
  && pass "no 'code': skipped with the command to run later" || fail "missing 'code' not reported"
grep -qE "WARN +AI rules" "$OUT" && pass "no access to AI rules: warns" || fail "AI rules failure not reported"

note "Fatal errors still print the summary"
if REPO_RAW="file:///nonexistent" install; then fail "missing source should fail"; fi
grep -qE 'FAIL +config files +download failed' "$OUT" && pass "download failure shows in the summary" || fail "no FAIL line in summary"
mv "$HOME/.claude" "$FIX/claude-dir"; touch "$HOME/.claude"     # makes `mkdir -p ~/.claude` fail
if install; then fail "unexpected error should fail"; fi
grep -qE 'FAIL +config files +unexpected error' "$OUT" && [ "$(summaries)" = 1 ] \
  && pass "unexpected errors (set -e inside a function) print the summary once" || fail "unexpected error exited silently"
rm "$HOME/.claude"; mv "$FIX/claude-dir" "$HOME/.claude"

note "ALL CHECKS PASSED"
