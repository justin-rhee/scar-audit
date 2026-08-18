# Architecture Decision Records (ADRs)

## The first version was wallpaper

The first real run came back with 1524 findings across 574 sessions. That's about
two and a half per session, and it's a number nobody acts on. I'd built a tool
that was technically correct and practically useless, and the failure mode is
worth naming because it's the one that kills this kind of check: a detector that
cries wolf gets muted, and a muted detector is worse than not having written it.

Nearly all of it came from one confusion. The rules are about blocks I paste into
a terminal. I'd applied them to every fenced block, which includes every script
an agent shows me for review. `scar-audit.sh` itself is mostly `#` lines inside a
bash fence, so the tool would have flagged its own source dozens of times.

The fix is a length gate. A block over 12 lines is a listing, something I'm
reading, and the fence rules skip it. Everything else followed from taking the
false-positive rate seriously as a design constraint rather than a nuisance:
shell-ish fence languages only, so a `#` in ```python and a push line in ```diff
are both invisible. That single change is why the tool is still switched on.

There's a cost, and it's in the README as well as here. A real handoff longer
than 12 lines carrying a hazard is missed. I took the trade because a report I
read beats a report I mute.

## The parenthetical rule, tightened twice

The wound is a command with a prose aside stuck on the end, `touch ~/x (valid 60
minutes)`, which zsh parses as a glob qualifier and the line dies. My first
version flagged any `(` followed by a letter and hit 92 sessions. Every one was
`grep -E (a|b)` or `sed s/\(x\)/` or `awk { if (x) }`, all of which are quoted,
and a quoted parenthesis is inert.

So the rule became: no quote character anywhere on the line, and the parenthetical
has to be two or more plain words. That was still wrong. `arr=(a b c)` is a bash
array literal and reads as two plain words, so the rule now also refuses a paren
preceded by `=` or `$`.

I found the second mistake because a near-miss fixture went red the moment I
tightened the rule the wrong way. That's the argument for writing the near-miss
at the same time as the rule and not afterwards. The positive fixture would have
stayed green through both errors.

## Force pushes are exempt, which reverses the rule

`push-ask` exists because one batched step owns pushing in my setup, so every
session that hands over a push line puts back the friction that step deletes.

Then I hit the case the rule couldn't hold. A force push isn't a fast-forward, so
the batched step refuses it, and there's no other channel. Blocking it left
history rewrites with nowhere to go, and I ended up assembling the command from
prose every time, which is exactly the cost the rule was written to prevent.

So `--force` is exempt. What makes this safe rather than a hole is the pair of
fixtures: the exempt force push has to stay silent, and a plain push on the same
line shape has to fire. Without the second one the exemption could widen into
"any push line passes" and nothing would notice.

The same rule had a blind spot I'd call embarrassing. It required `push` to sit
immediately after `git`, so `git -C <path> push` was invisible, and that's the
form I use most. The rule now allows a run of git's own options in between, while
still refusing `git log --grep push`, because `log` isn't an option.

## The self-test that passed against nothing

An early version of `--selftest` built its fixtures with `jq -n` and no `-c`. `jq`
pretty-prints by default, so it wrote multi-line JSON with `"type": "assistant"`,
space included. That's not valid JSONL and doesn't match the scan's prefilter, so
every fixture was skipped.

The scan then printed its clean summary, which lists every rule id by name. The
assertions were matching against summary text, they found the ids they were
looking for, and four rules reported passing against zero parsed input.

That's a fail-open in a tool whose entire job is catching fail-open, and I'd have
shipped it. Two things came out of it. Assertions now key on the exit code of a
scan over one isolated fixture, which no summary line can satisfy. And the suite
opens by proving a fixture parses at all, because without that check every
assertion after it can be vacuous while looking green.

## Two modes, one definition

There's an after-the-fact audit and a `--stdin` mode that judges a single message.
The second exists so a hook that reads a message before it reaches me can call
this rather than reimplement six rules.

The alternative was letting the hook keep its own copies, and the reason not to
is that they'd drift. A rule would come to mean one thing at the gate and
something else in the weekly report, and the report is what I'd trust. One
definition, two entry points.

That's also the honest reason the tool exists in the first place. Once a rule is
being broken at a rate this high, writing more prose about it isn't the fix. The
prose already said the right thing, twice, with the date of the last violation
next to it. What was missing was an exit code.

## Rules are data, up to a point

The header of the file says scars are data, not code, and that's half true. A new
rule is one row in `scar_table()` plus one small function under it, dispatched by
name from the id. It was worth being precise about this in the README because the
claim as first written was that a new rule costs a table row, and it doesn't. It
costs a row and a detector.

The reason to keep the table anyway is that the row carries the wound. When a
finding prints, it prints why the rule exists next to what it caught, so the
report says something more useful than "you broke rule four". Six rules in, each
addition has cost about fifteen lines, which is the bar the design has to keep
clearing or the file rots the same way the written rule did.

Four of the six are conventions of my own setup rather than anything universal.
They ship anyway, as worked examples, because the shape is the transferable part
and an empty table teaches nobody how to write the near-miss that keeps a rule
alive.
