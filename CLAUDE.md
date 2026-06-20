# CLAUDE.md

This file provides Claude Code-specific guidance. All general project guidance is in AGENTS.md.

## ⚠️ Beads data must stay OUT of this public repo

This repository (`github.com/mikebowler/jirametrics`) is **public**. Beads issue
content can contain client-sensitive material (logs, project keys, customer data
pasted from support cases) and must **never** be committed or pushed here.

- Beads issue data lives in the **private** repo `github.com/mikebowler/jirametrics-beads`.
- `.beads/issues.jsonl` (and `events.jsonl`/`interactions.jsonl`) are gitignored in
  this repo — do **not** force-add them or remove those `.gitignore` entries.
- `bd dolt push` is configured to push to the private repo's Dolt remote, NOT here.
- In the session-close workflow below, `git push` sends **code only** to the public
  repo; `bd dolt push` sends **beads data only** to the private repo. Keep them separate.
- If you ever see `.beads/issues.jsonl` staged for the public repo, stop and unstage it.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
