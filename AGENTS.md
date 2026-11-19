# AGENTS.md — yesterdaysrebel/dotfiles

Debian/Ubuntu dev-environment installer for GlueOps VMs, codespaces and devcontainers:

```bash
curl -fsSL https://yesterdaysrebel.github.io/dotfiles/ | zsh
```

Adapted from [venkatamutyala/dotfiles](https://github.com/venkatamutyala/dotfiles).

## Repo map

| Path | Role |
|------|------|
| `index.html` | The installer: a zsh script despite the name, served by GitHub Pages from `main`. Line 1 `#<plaintext>` makes browsers show it as text. |
| `tmux.conf`, `tmux-cheatsheet.txt`, `vimrc` | Installed to `~/.tmux.conf`, `~/.tmux-cheatsheet.txt` (shown by `prefix + ?`), `~/.vimrc`. |
| `dotfiles.zsh` | Installed to `~/.oh-my-zsh/custom/`; enables the pinned zsh plugins without editing `~/.zshrc`. |
| `claude/CLAUDE.md` | Installed to `~/.claude/CLAUDE.md`; imports the shared rules from `internal-GlueOps/ai-rules-central`. |
| `claude/hooks/agent-memory-sync.sh` | Installed to `~/.claude/hooks/`; SessionStart/Stop hook that syncs `~/.agent-memory` with the user's private `<gh login>/agent-memory` repo (gitleaks-scanned, private-and-owner checked before every push). |
| `tests/` | Docker integration test (`integration-test.sh`) and local runner. |
| `.github/workflows/` | CI (integration test on bookworm + trixie, shellcheck) and release-please (cuts the `vX.Y.Z` tags the installer offers). |

## What the installer does

`cde-init` (if present) → OS/deps check → pick a tag, resolve it to one commit SHA →
Oh-My-Zsh (pinned) → config files (tmux, vim, vim-plug, `dotfiles.zsh`, `~/.claude/CLAUDE.md`) →
clone/pull ai-rules-central to `~/.local/share/ai-rules-central` and link each prompt
to `~/.claude/commands/<name>.md` → zsh plugins (SHA-verified) → `vim +PlugInstall` →
Claude auth check → agent memory (hook script, merge its keys into `~/.claude/settings.json`,
create `<gh login>/agent-memory` as a private repo if it's missing) → VS Code
`anthropic.claude-code` extension. It ends with an OK/SKIP/WARN/FAIL summary, also on failure (`die` → EXIT trap; errexit inside a
function skips EXIT traps in zsh, so `TRAPZERR` covers that case).

## Releases

release-please opens a release PR from Conventional Commits on `main`; merging it cuts
the `vX.Y.Z` tag the installer offers. It needs either a `RELEASE_PLEASE` secret (a
fine-grained PAT with contents + pull requests: write, so release PRs also get CI) or
Settings → Actions → General → "Allow GitHub Actions to create and approve pull
requests" turned on. New repos have that setting off.

## Rules

- Keep `index.html` line 1 = `#<plaintext>`.
- `curl | zsh` means stdin is the script: prompts read `/dev/tty`, and every child
  process that could read stdin gets `</dev/null`.
- Idempotent: only replace a file when its content changed, and back it up first.
- Never install system packages.
- Keep every third-party fetch pinned (commit SHA, or tag verified against a SHA).
- Never print, copy, or persist `CLAUDE_CODE_OAUTH_TOKEN`; Claude Code reads it from the env.
- Missing optional pieces (`code`, `claude`, `gh`, the token, AI-rules access, a
  usable `settings.json`) warn and continue; only integrity and core download failures
  are fatal.
- `~/.claude/settings.json` belongs to the user: merge only the keys memory needs
  (with jq, backed up first), never overwrite it.
- Memory only ever pushes to a private repo owned by the gh login, after a gitleaks
  scan; any doubt holds the push instead.
- Commits follow Conventional Commits (release-please builds the changelog from them).

## Test (Docker)

```bash
tests/run-in-docker.sh bookworm
tests/run-in-docker.sh trixie
```

Each must end with `ALL CHECKS PASSED`.

## Decisions

Settled; reviewers shouldn't re-raise these.

- The Claude config is minimal: `CLAUDE.md` plus the agent-memory hook, whose
  `settings.json` keys are merged, never owned. Skills, prompts and rules live in
  `internal-GlueOps/ai-rules-central`, not here.
- The installer creates the memory repo itself, but only on a clear "not found", only
  under the gh login, and always private. The hook never creates anything.
- Memory sync is fail-closed: no Docker (for gitleaks) means no push.
- ai-rules-central tracks `main` (like its own `ais update`), not a pin.
- Its Copilot prompts are used as Claude commands unchanged, and the instruction files
  are imported in full (Copilot `applyTo` globs aren't honored).
- `~/.zshrc` is never edited; plugins are enabled by the `dotfiles.zsh` drop-in.
- The installer doesn't install the `claude` CLI (images ship it); it only warns.
- The VS Code extension is unpinned (latest) and only installs when `code` works.
- zsh must already be installed (`curl | zsh` can't run without it).
- `vimrc` keeps fzf's `do: fzf#install()` hook, which downloads the fzf binary without
  a checksum (same as upstream).
