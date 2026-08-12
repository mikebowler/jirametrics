# CLAUDE.md

This file provides Claude Code-specific guidance. All general project guidance is in AGENTS.md.

## ⚠️ Beads data must stay OUT of this public repo

This repository (`github.com/mikebowler/jirametrics`) is **public**. Beads issue
content can contain client-sensitive material (logs, project keys, customer data
pasted from support cases) and must **never** be committed or pushed here.

- Beads issue data lives in the **private** repo `github.com/mikebowler/jirametrics-beads`.
- `.beads/issues.jsonl` (and `events.jsonl`/`interactions.jsonl`) are gitignored in
  this repo - do **not** force-add them or remove those `.gitignore` entries.
- `bd dolt push` is configured to push to the private repo's Dolt remote, NOT here.
- In the session-close workflow below, `git push` sends **code only** to the public
  repo; `bd dolt push` sends **beads data only** to the private repo. Keep them separate.
- If you ever see `.beads/issues.jsonl` staged for the public repo, stop and unstage it.

## Separate an instruction from an observation

Not every remark about behaviour is a request to change it. Before writing code, decide which
you were given.

**An instruction** tells you to act: "fix it", "add X", "do that next", "make it configurable".
Act on it. Do not ask for permission you already have, and do not offer to do work that was
just deferred - if asked to file an issue, file it and carry on rather than proposing to do it
now anyway.

**An observation** describes expected or surprising behaviour and invites discussion:

- "I would have thought it would ..."
- "I'm not convinced that ..."
- "It's reasonable that it does X"
- "Is it possible to ...?"
- "That's a good starting default"

These are opinions being tested, not specifications. Answer them, put the options and the
trade-offs, and get a decision before implementing. A wrong guess here costs more than the
question would have: it produces work that has to be unpicked, and it quietly transfers design
authority from the person who owns the project to you.

Passing a test is not evidence you built the right thing.

## Name the decisions you made

When you do implement, a request rarely determines every choice. Wording, where output goes,
how much detail to show, what the default is - these get decided whether or not anyone notices.
State the ones a reasonable person might have decided differently, briefly, when you report the
work. Burying them in a diff is how the wrong behaviour ships unchallenged.

If you find yourself making the third or fourth such choice in a row without checking, stop and
ask instead.

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

- Use `bd` for ALL task tracking - do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge - do NOT use MEMORY.md files

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
