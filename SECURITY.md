# Security policy: scar-audit

## Posture

scar-audit is provided as-is, with no warranty (see LICENSE). It's a correctness
tool for people who keep written rules for an agent. It isn't a security boundary
and makes no promise about stopping anything malicious.

The honest ceiling: it finds sessions where a rule you wrote down was not
followed. It doesn't find a rule that's wrong, a rule someone deleted on purpose,
or a fixture written around a misunderstanding of what the rule should catch.
Anyone who can edit `scar_table()` can edit the fixtures beside it, and
`--selftest` will certify the result.

Three properties worth knowing before you rely on it.

It reads transcripts, not actions. Findings come from assistant text plus the
names of tools that were called. A rule about what an agent actually did to your
filesystem is out of reach here.

The length gate is a deliberate blind spot. Fenced blocks longer than
`SCAR_MAX_HANDOFF_LINES` (12 by default) are treated as listings rather than
things you'd paste, so the fence rules skip them entirely. That's what keeps the
report readable, and it means a genuine long handoff carrying a hazard is missed.

The report quotes your transcripts. A finding includes a truncated line from
your own session, printed to stdout, which is the whole point of the report and
also means the output carries whatever those sessions carried. Treat a saved
report, a CI log, or a pasted findings list the way you would treat the
transcripts themselves. `--json` prints counts only, with no excerpts, if you
need something safe to store.

Transcript content is read as data. `jq` parses the JSONL and every detector is a
grep or an awk over the resulting text. Nothing from a transcript reaches a shell
as a command, and nothing in one is executed or interpreted. Malformed lines are
dropped by `jq` rather than raised.

## Validation status

The offline suite in `tests/test-scar-audit.sh` has been run: 29 checks, all
passing, on macOS 26.5.2 with bash 3.2.57 and jq 1.7.1. The built-in `--selftest`
has been run and passes: 7 rules proved to fire against isolated fixtures, 9
near-misses proved to stay silent, and a planted defect that trips the audit and
reverts clean.

Both load-bearing mutations were run. Raising `SCAR_MAX_HANDOFF_LINES` to 999
makes a script listing fire that's otherwise silent, which is what demonstrates
the length gate is carrying the noise budget. Gutting a detector's body on a
throwaway copy turns `--selftest` red, with a third assertion confirming the
gutted detector really went blind. Both run in the suite now, so neither can
quietly stop being true.

Linux has not been run by hand. It comes from the CI matrix in
`.github/workflows/test.yml`, and the badge on the README is the receipt.

There's no adversarial corpus. The threat model is an honest author whose written
rule is being skipped without anyone noticing, not somebody trying to smuggle a
violation past the detectors. Someone doing that succeeds easily: pad a handoff
past 12 lines, or label the fence ```python. Those are limits of the design
rather than bugs to fix, and they're stated in the README too.

## Reporting a problem

Report privately through this repository's Security tab, using GitHub's
"Report a vulnerability" flow, or by opening a minimal issue describing the
impact without a working exploit. Please give a reasonable window for a fix
before publishing details.

For a correctness bug that isn't security sensitive, a normal issue with a
reproduction is the fastest path.
