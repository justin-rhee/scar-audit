# scar-audit

[![tests](https://github.com/justin-rhee/scar-audit/actions/workflows/test.yml/badge.svg)](https://github.com/justin-rhee/scar-audit/actions/workflows/test.yml)

How do you know the rules you've set for an AI agent are actually being followed?

I'd written one for mine saying that whenever it stops and needs something from
me, it has to hand over the exact command, because otherwise I'm sitting there
reading "this needs your approval" and then going back to ask what I'm supposed
to run, which costs a whole round trip every time. I'd already caught it being
broken once and rewritten the rule, dated it in the file, the works. Then I
actually measured it, and across 475 sessions that rule had still been stated
without its command in 10 of the 19 times it came up, and it turned out to be
one of six rules that between them accounted for 294 findings.

None of which anything had ever told me about, because prose doesn't have an
exit code and a rule that gets quietly skipped leaves no trace anywhere.

So I stopped rewriting the rules and gave five of them an exit code instead,
which is what this does. It shows you which of your rules aren't really binding,
so you can stop rewriting the ones that were never going to hold and put them
behind something that actually stops the turn. It's about 480 lines of bash that reads
your session transcripts, and four of the six rules it ships with are mine
rather than yours, sitting there as worked examples.

## Use it if

- you keep a rules file for an agent and have never checked whether it's followed
- an agent's shell block has run something in your terminal you didn't mean to run
- you've rewritten the same instruction three times and it still isn't sticking

If you don't keep a rules file for an agent, there's honestly nothing here for
you yet.

## How it works

Your sessions are already saved to disk, so this reads them, pulls out
everything the agent actually said, and checks that text against the rules.

Each rule is one line in a table plus a short function underneath it. The line
says what the rule catches and what went wrong the day you wrote it, and the
function does the looking. When something matches you get the rule, the session,
the line itself, and the reason the rule exists, so you're told why it matters
rather than just that some string turned up.

Writing your own is the same two pieces, and the source walks through it. The
thing I'd stress is writing the near-miss example alongside the rule, because
that's what stops a new rule firing on everything and getting muted a week
later.

You can run it three ways: on a schedule to see the last week, against a single
message so a hook can check something before it ever reaches you, or as a
self-test that builds its own examples and proves every rule can still fire.

## What it found for me

All six fire on my own transcripts, which is what I'd have wanted to know about
somebody else's rule table before trusting it. Over 90 days:

| rule | what it catches | sessions |
|---|---|---|
| `paren-in-fence` | a bare parenthetical after a command, which zsh reads as a glob qualifier | 31 |
| `deferred-no-handoff` | work pushed to a new session with nothing to paste into it | 25 |
| `hash-in-fence` | a `#` line in a block meant for pasting, which zsh runs rather than ignores | 24 |
| `push-ask` | a turn that ends asking to push, or hands over a push line | 23 |
| `blocked-no-command` | a turn saying it's blocked on you, with no command and no question | 12 |
| `routine-no-brief` | a scheduled job created or changed with no explanation beside it | 2 |

What actually changed things wasn't the report, it was working out which rules
were never going to hold as prose no matter how many times I rewrote them. Five
of them are hooks now that check a message before it reaches me, and they call
this tool rather than keeping their own copy, so the gate and the weekly
report can't drift apart on what a rule even means.

Two of them would apply to anyone, since pasting an agent's block into an
interactive zsh runs a comment line as a command and a stray parenthetical kills
the line, whatever your rules file happens to say. The other four are my own
conventions.

## How I got the false alarms down

The first run flagged 1524 things across 574 sessions, about two and a half
each, and it sits around 0.6 now. What changed:

- anything over 12 lines is read as a script being shown to you, not a command to paste
- comments in a Python snippet are ignored, because the rules only apply to shell commands
- lines inside a diff are ignored, because they record a change instead of asking for one
- ordinary shell syntax that only resembles the thing being looked for no longer counts,
  which by itself took one rule from 92 sessions to none
- nine of those harmless cases run in the self-test, and every one has to come back
  clean for it to pass

## Install

Try it first, if you like. Neither of these reads a transcript of yours, since
the self-test builds its own.

```
bash src/scar-audit.sh --selftest
printf 'All committed. Do you want me to push these?' | bash src/scar-audit.sh --stdin
```

It's one file, `src/scar-audit.sh`, so copy it wherever you keep your scripts.
It needs bash, awk and `jq`, reads only your Claude Code transcripts under
`~/.claude/projects`, and writes nothing but stdout.

```
scar-audit.sh --days 7      # audit recent sessions, exit 0 clean, 1 findings
scar-audit.sh --json        # the same as one line of JSON
scar-audit.sh --stdin       # judge one message, for a hook
scar-audit.sh --selftest    # prove the rules can still fire
```

Point `SCAR_AUDIT_ROOT` elsewhere if your transcripts live somewhere else, and
`SCAR_MAX_HANDOFF_LINES` at a different number if 12 is wrong for you.

## What it won't do

- work on another harness without a rewritten reader, which is about fifteen lines in `scan()`
- tell you whether the command it found was any good, only that one was there
- catch a rule that was wrong to begin with, since it looks for rules that went unapplied
- fit your setup as it ships, because four of the six rules are tuned to my own conventions
- say which turn went wrong, since two of the rules read a whole session at once
- see a handoff longer than 12 lines, which it treats as a listing and skips
- promise you the same numbers, since the ones here came off my transcripts and my rules file
- stand in for a security tool, because whoever can edit the rules can edit the examples too
- run on Windows, which I haven't tested

## How I tested it

29 offline checks, none of which read a real transcript, in
`bash tests/test-scar-audit.sh`:

- `--selftest` asserts 7 rules fire against isolated examples and 9 near-misses stay silent
- a planted fault has to trip the audit, and removing it has to return a clean run
- every assertion keys on an exit code rather than summary text, after an earlier version
  did the opposite and passed four rules against zero parsed input
- one message carrying every near-miss shape at once, long listing included, has to come
  back clean
- raising `SCAR_MAX_HANDOFF_LINES` to 999 makes that same listing fire, which is what shows
  the length gate is doing the work
- gutting a rule's body on a throwaway copy turns `--selftest` red

Run locally on macOS 26.5.2 with bash 3.2.57 and jq 1.7.1: 29 passed, 0 failed. Linux
comes from the CI matrix rather than anything I ran by hand. How the self-test once
passed against nothing is in the [ADR](docs/ADR.md).

## License

MIT, see [LICENSE](LICENSE). No warranty. Security posture and how to report a
problem: [SECURITY.md](SECURITY.md).

Design decisions and what changed while building it: [docs/ADR.md](docs/ADR.md).

---

This little tool is one of a handful I pulled out of my own day-to-day agent setup. I use them all myself, so when something breaks I usually notice fast. But if you run into any issues, or see anything that looks off, open an issue. I read every one. More tools on my [GitHub profile](https://github.com/justin-rhee).
