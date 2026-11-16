# scar-audit

[![tests](https://github.com/justin-rhee/scar-audit/actions/workflows/test.yml/badge.svg)](https://github.com/justin-rhee/scar-audit/actions/workflows/test.yml) [![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) ![shell](https://img.shields.io/badge/shell-bash-blue.svg) ![needs jq](https://img.shields.io/badge/needs-jq-lightgrey.svg)

Reads your saved Claude Code sessions and tells you which of the rules you wrote for your agent it's quietly not following.

All six rules it ships with fire on my own sessions. Over 90 days:

| rule | what it catches | sessions |
|---|---|---|
| `paren-in-fence` | a bare parenthetical after a command, which zsh reads as a glob qualifier | 31 |
| `deferred-no-handoff` | work pushed to a new session with nothing to paste into it | 25 |
| `hash-in-fence` | a `#` line in a block meant for pasting, which zsh runs rather than ignores | 24 |
| `push-ask` | a turn that ends asking to push, or hands over a push line | 23 |
| `blocked-no-command` | a turn saying it's blocked on you, with no command and no question | 12 |
| `routine-no-brief` | a scheduled job created or changed with no explanation beside it | 2 |

I wrote a handoff rule for my agent, caught it broken once, rewrote it and dated the file. Measuring showed the truth: across 475 sessions, the rule was stated without its command in 10 of the 19 times it came up. Prose has no exit code, so I gave five of my rules one.

## Use it if

- you keep a rules file for an agent and have never checked whether it's followed
- an agent's shell block has run something in your terminal you didn't mean to run
- you've rewritten the same instruction three times and it still isn't sticking

## Install

One file, about 480 lines of bash, needing bash, awk and `jq`. It reads only your transcripts under `~/.claude/projects` and writes nothing but stdout. Try it first; neither of these reads a transcript of yours:

```
bash src/scar-audit.sh --selftest
printf 'All committed. Do you want me to push these?' | bash src/scar-audit.sh --stdin
```

```
scar-audit.sh --days 7      # audit recent sessions, exit 0 clean, 1 findings
scar-audit.sh --json        # the same as one line of JSON
scar-audit.sh --stdin       # judge one message, for a hook
scar-audit.sh --selftest    # prove the rules can still fire
```

Set `SCAR_AUDIT_ROOT` if your transcripts live elsewhere, and `SCAR_MAX_HANDOFF_LINES` if 12 is wrong for you.

## How it works

Each rule is one line in a table plus a short function: the line says what it catches and what went wrong the day you wrote it, and the function does the looking. A match gives you the rule, the session, the line and the reason the rule exists. A near-miss example beside each rule keeps a new one from firing on everything and getting muted a week later. Five of mine are hooks now that call this tool, so the gate and the weekly report can't disagree on what a rule means.

## What it won't do

- work on another harness without a rewritten reader, about fifteen lines in `scan()`
- tell you whether the command it found was any good, only that one was there
- catch a rule that was wrong to begin with
- fit your setup as it ships, because four of the six rules are tuned to my own conventions
- say which turn went wrong, since two rules read a whole session at once
- see a handoff longer than 12 lines, which it treats as a listing and skips
- promise you my numbers, which came off my sessions and my rules file
- stand in for a security tool, because whoever can edit the rules can edit the examples too
- run on Windows yet

## How I tested it

- 29 offline checks, none reading a real transcript: `bash tests/test-scar-audit.sh`
- `--selftest` asserts 7 rules fire on isolated examples and 9 near-misses stay silent, and gutting a rule's body turns it red
- every assertion keys on an exit code, after an earlier version passed four rules against zero parsed input; that story is in the [ADR](docs/ADR.md)

## License

MIT. See [LICENSE](LICENSE). No warranty. Security notes and how to report a problem: [SECURITY.md](SECURITY.md).

<!-- related:start -->
## Related

- [hook-canary](https://github.com/justin-rhee/hook-canary): proves an installed hook still works by running it
- [linter-selftest](https://github.com/justin-rhee/linter-selftest): proves each lint rule can still fire

Part of a small set of tools I pulled out of my own agent harness. I use them myself and read every issue. More on my [GitHub profile](https://github.com/justin-rhee).
<!-- related:end -->
