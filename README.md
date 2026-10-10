# scar-audit

One bash script for agent rules files: **audit your session transcripts against the rules you wrote**, **show you which of them are quietly not being followed**, and **self-test that every rule it ships can still fire**. About 480 lines of bash that reads your Claude Code transcripts and writes nothing but stdout.

It exists because I had written a handoff rule for my agent, caught it broken once, rewritten it and dated the file, and only measuring showed the truth: across 475 sessions the rule was stated without its command in 10 of the 19 times it came up, one of six rules accounting for 294 findings. Prose does not have an exit code, and a rule that gets quietly skipped leaves no trace anywhere. So I stopped rewriting the rules and gave five of them an exit code instead, which is what this does; four of the six rules it ships with are mine rather than yours, sitting there as worked examples.

## Use it if

- you keep a rules file for an agent and have never checked whether it is followed
- an agent's shell block has run something in your terminal you did not mean to run
- you have rewritten the same instruction three times and it still is not sticking

If you do not keep a rules file for an agent, there is honestly nothing here for you yet.

## How it works

Your sessions are already saved to disk, so this reads them, pulls out everything the agent actually said, and checks that text against the rules. Each rule is one line in a table plus a short function underneath it: the line says what the rule catches and what went wrong the day you wrote it, the function does the looking, and a match gets you the rule, the session, the line itself and the reason the rule exists. Writing your own is the same two pieces, and the near-miss example alongside the rule is what stops a new rule firing on everything and getting muted a week later.

All six fire on my own transcripts. Over 90 days:

| rule | what it catches | sessions |
|---|---|---|
| `paren-in-fence` | a bare parenthetical after a command, which zsh reads as a glob qualifier | 31 |
| `deferred-no-handoff` | work pushed to a new session with nothing to paste into it | 25 |
| `hash-in-fence` | a `#` line in a block meant for pasting, which zsh runs rather than ignores | 24 |
| `push-ask` | a turn that ends asking to push, or hands over a push line | 23 |
| `blocked-no-command` | a turn saying it is blocked on you, with no command and no question | 12 |
| `routine-no-brief` | a scheduled job created or changed with no explanation beside it | 2 |

Five of mine are hooks now that call this tool rather than keeping their own copy, so the gate and the weekly report cannot drift apart on what a rule even means. The first run flagged 1524 things across 574 sessions, about two and a half each, and it sits around 0.6 now: long listings are read as scripts being shown to you, comments in Python snippets and lines inside diffs are ignored, ordinary shell syntax that only resembles a target no longer counts (which alone took one rule from 92 sessions to none), and nine harmless cases run in the self-test and must come back clean for it to pass.

## Install

Try it first; neither of these reads a transcript of yours, since the self-test builds its own:

```
bash src/scar-audit.sh --selftest
printf 'All committed. Do you want me to push these?' | bash src/scar-audit.sh --stdin
```

It is one file, `src/scar-audit.sh`, so copy it wherever you keep your scripts. It needs bash, awk and `jq`, reads only your Claude Code transcripts under `~/.claude/projects`, and writes nothing but stdout.

```
scar-audit.sh --days 7      # audit recent sessions, exit 0 clean, 1 findings
scar-audit.sh --json        # the same as one line of JSON
scar-audit.sh --stdin       # judge one message, for a hook
scar-audit.sh --selftest    # prove the rules can still fire
```

Point `SCAR_AUDIT_ROOT` elsewhere if your transcripts live somewhere else, and `SCAR_MAX_HANDOFF_LINES` at a different number if 12 is wrong for you.

## What it won't do

- work on another harness without a rewritten reader, which is about fifteen lines in `scan()`
- tell you whether the command it found was any good, only that one was there
- catch a rule that was wrong to begin with, since it looks for rules that went unapplied
- fit your setup as it ships, because four of the six rules are tuned to my own conventions
- say which turn went wrong, since two of the rules read a whole session at once
- see a handoff longer than 12 lines, which it treats as a listing and skips
- promise you the same numbers, since the ones here came off my transcripts and my rules file
- stand in for a security tool, because whoever can edit the rules can edit the examples too

## Platforms

macOS and Linux today, Windows on the way.

## How I tested it

29 offline checks, none of which read a real transcript, in `bash tests/test-scar-audit.sh`:

- `--selftest` asserts 7 rules fire against isolated examples and 9 near-misses stay silent
- a planted fault has to trip the audit, and removing it has to return a clean run
- every assertion keys on an exit code rather than summary text, after an earlier version did the opposite and passed four rules against zero parsed input
- one message carrying every near-miss shape at once, long listing included, has to come back clean
- raising `SCAR_MAX_HANDOFF_LINES` to 999 makes that same listing fire, which is what shows the length gate is doing the work
- gutting a rule's body on a throwaway copy turns `--selftest` red

Run locally on macOS 26.5.2 with bash 3.2.57 and jq 1.7.1: 29 passed, 0 failed. Linux comes from the CI matrix rather than anything I ran by hand. How the self-test once passed against nothing is in the [ADR](docs/ADR.md).

## License

MIT, see [LICENSE](LICENSE). No warranty. Security posture and how to report a problem: [SECURITY.md](SECURITY.md). Design decisions and what changed while building it: [docs/ADR.md](docs/ADR.md).

This little tool is one of a handful I pulled out of my own day-to-day agent setup. I use them all myself, so when something breaks I usually notice fast. If you spot anything off, open an issue. I read every one. More tools on my [GitHub profile](https://github.com/justin-rhee).
