# AGENTS.md

Always do the following:

1. Make beads first
2. Commit after each bead is complete, do NOT skip hooks

<!-- br-agent-instructions-v1 -->

---

## Beads Workflow Integration

This project uses [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`/`bd`) for issue tracking. Issues are stored in `.beads/` and tracked in git.

### Essential Commands

```bash
# View ready issues (unblocked, not deferred)
br ready              # or: bd ready

# List and search
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br search "keyword"   # Full-text search

# Create and update
br create --title="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason="Completed"
br close <id1> <id2>  # Close multiple issues at once

# Sync with git
br sync --flush-only  # Export DB to JSONL
br sync --status      # Check sync status
```

### Workflow Pattern

1. **Start**: Run `br ready` to find actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>`
5. **Sync**: Always run `br sync --flush-only` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers 0-4, not words)
- **Types**: task, bug, feature, epic, question, docs
- **Blocking**: `br dep add <issue> <depends-on>` to add dependencies

### Session Protocol

**Before ending any session, run this checklist:**

```bash
git status              # Check what changed
git add <files>         # Stage code changes
br sync --flush-only    # Export beads changes to JSONL
git commit -m "..."     # Commit everything
git push                # Push to remote
```

### Best Practices

- Check `br ready` at session start to find available work
- Update status as you work (in_progress → closed)
- Create new issues with `br create` when you discover tasks
- Use descriptive titles and set appropriate priority/type
- Always sync before ending session

<!-- end-br-agent-instructions -->

## Running Benchmarks

MLX requires xcodebuild (not `swift build`) for GPU support:

```bash
# Build release benchmark
xcodebuild -scheme micro-swift-bench -configuration Release -destination 'platform=macOS' build

# Run it (path is in DerivedData)
/Users/bkase/Library/Developer/Xcode/DerivedData/micro-swift6-gxzohxwhspffsodzynbxfsdjchpb/Build/Products/Release/micro-swift-bench
```

Tests that use MLX (`requiresMLXEval`) also need xcodebuild, not `swift test`.

## Parallel Codex Orchestration

When spawning multiple `codex exec` instances across clones via `zmx`:

```bash
# Use -C to set working directory (NOT cd in bash -c)
codex exec --dangerously-bypass-approvals-and-sandbox -C /path/to/clone "prompt"

# DON'T pipe echo — codex exec errors with "stdin is not a terminal"
# DON'T use bash -c wrapping — zmx passes args directly to the process

# Use zmx wait with stdout AND stderr silenced to avoid spammy output
/opt/homebrew/bin/zmx wait session1 session2 >/dev/null 2>/dev/null

# Full pattern: write a script file, then zmx run it
cat > /tmp/run-fix.sh << 'SCRIPT'
#!/bin/bash
codex exec --dangerously-bypass-approvals-and-sandbox -C /path/to/clone "$(cat /tmp/prompt.txt)"
SCRIPT
chmod +x /tmp/run-fix.sh
/opt/homebrew/bin/zmx run session-name /tmp/run-fix.sh
```

- Write prompts to temp files first, then `$(cat /tmp/prompt.txt)` to avoid shell escaping issues
- Each clone (micro-swift, micro-swift2, ..., micro-swift5) should get its own codex instance
- After codex finishes, fetch branches from clones: `git fetch /path/to/clone branch:branch`
- Resolve `.beads/issues.jsonl` conflicts with `git checkout --ours` then re-export
- Use `br update <id> --status=closed` to force-close beads blocked by parent-child deps
