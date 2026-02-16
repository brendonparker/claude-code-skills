# Claude Code Skills

A collection of reusable [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills.

## Skills

| Skill | Description |
|-------|-------------|
| [deploy-diff](./deploy-diff) | Compare GitHub deployment environments to see what commits are waiting to be promoted (e.g., stg → prod) |

## Installation

Clone this repo and symlink any skill into your project's `.claude/skills/` directory:

```bash
# Clone the collection
git clone https://github.com/brendonparker/claude-code-skills.git ~/claude-code-skills

# Symlink a skill into your project
mkdir -p .claude/skills
ln -s ~/claude-code-skills/deploy-diff .claude/skills/deploy-diff
```

Or copy a skill directory directly:

```bash
cp -r ~/claude-code-skills/deploy-diff .claude/skills/deploy-diff
```

## Requirements

Skills may have their own prerequisites. Check each skill's `SKILL.md` for details.

Common requirements across this collection:

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [GitHub CLI (`gh`)](https://cli.github.com/) — authenticated via `gh auth login`

## Contributing

Each skill lives in its own top-level directory and follows the Claude Code skill structure:

```
skill-name/
├── SKILL.md           # Skill definition (frontmatter + instructions)
└── scripts/           # Supporting scripts (optional)
    └── ...
```

See the [Claude Code skills docs](https://docs.anthropic.com/en/docs/claude-code/skills) for the full specification.
