# Global instructions (all projects)

Installed from github.com/yesterdaysrebel/dotfiles (`claude/CLAUDE.md`). Edit it there,
not in `~/.claude/`: the installer overwrites this file.

Shared GlueOps rules come from `internal-GlueOps/ai-rules-central`, which the installer
keeps in `~/.local/share/ai-rules-central`. Its prompts are available as `/ai-*` commands.
Some imported files mention Copilot; apply them the same way here.

@~/.local/share/ai-rules-central/.github/instructions/copilot-workspace.instructions.md
@~/.local/share/ai-rules-central/.github/instructions/coding-behavior.instructions.md
@~/.local/share/ai-rules-central/.github/repo-conventions.md

## Code reviews

These rules apply to every review, including `/ai-review`, and override the imported files.

- Never post comments, reviews or approvals to a PR yourself.
- End with a list of findings, each with `path:line`, severity, and comment text ready
  to paste into the PR.
