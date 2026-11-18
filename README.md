# dotfiles

Sets up a GlueOps dev environment (VM, codespace or devcontainer) on Debian/Ubuntu:
Oh-My-Zsh with zsh plugins, tmux and vim config, the shared GlueOps AI rules for
Claude Code, Claude Code auth, and the Claude Code VS Code extension.

```bash
curl -fsSL https://yesterdaysrebel.github.io/dotfiles/ | zsh
```

You'll be asked which version (tag) to install. To skip the question, set
`DOTFILES_REF` on the `zsh` side of the pipe (on `curl` it does nothing):

```bash
curl -fsSL https://yesterdaysrebel.github.io/dotfiles/ | DOTFILES_REF=v1.2.3 zsh
```

Re-run any time to update; files you changed are backed up to
`~/.dotfiles-backup-<timestamp>/` before they're replaced.

## Prerequisites

- `zsh`, `git`, `curl` (required); `jq` and `vim` (for their steps), `tmux`
- GitHub access to `internal-GlueOps/ai-rules-central`. In a GlueOps codespace,
  `cde-init` sets this up from `GITHUB_TOKEN`; elsewhere run `gh auth login`.
- `CLAUDE_CODE_OAUTH_TOKEN` in your environment (set it in your profile via the Slack
  bot). Claude Code reads it directly; there's no login step.

## What you get

- `/ai-review`, `/ai-plan`, `/ai-code`, ... in Claude Code, plus the shared GlueOps
  instructions, from `internal-GlueOps/ai-rules-central`
- zsh-autosuggestions, zsh-syntax-highlighting and you-should-use, enabled without
  editing `~/.zshrc` (delete `~/.oh-my-zsh/custom/dotfiles.zsh` to opt out)
- tmux with mouse and clipboard support (`prefix + ?` shows a cheat sheet), vim with plugins
- The `anthropic.claude-code` VS Code extension, when run from a VS Code terminal

## Development

See [AGENTS.md](AGENTS.md). Tests run in Docker: `tests/run-in-docker.sh`.
