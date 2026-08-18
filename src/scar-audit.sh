#!/usr/bin/env bash
# scar-audit.sh — do the rules you wrote down actually fire?
#
# WHY THIS EXISTS. Every dated note in my agent instructions file is a healed
# wound: "bit me three times", "restated after it was violated again", "costs a
# full round trip". My dominant failure over three months was not a missing
# rule. It was a rule that was WRITTEN DOWN AND DID NOT FIRE. The file says so
# about itself, in a line explaining that it holds a rule because the earlier
# place holding it never fired. Prose has no exit code, so nothing ever tells
# you it was ignored. This does.
#
# A first scan of 574 sessions over 90 days found one rule stated without its
# required command in 10 of 19 mentions, and 41 sessions emitting a '#' line
# inside a fenced block meant for pasting. Those numbers are why this runs on a
# schedule instead of when I remember it.
#
# SCARS ARE DATA. Each rule is a row in scar_table() plus one detector function
# below it. Adding next month's wound is one row and one small function, never a
# redesign. That is the whole design constraint: this file has to stay cheap to
# extend, or it rots the way the prose rule rotted.
#
# NOISE BUDGET. Roughly 80% false positives makes a detector wallpaper, and a
# muted detector is worse than none. Every detector here is restricted to
# SHELL-ISH fenced blocks and assistant prose. A '#' inside ```python, a
# `git push` inside ```diff, and an array literal `arr=(a b)` are near-misses
# that MUST stay silent; --selftest asserts each one does.
#
# Usage:  scar-audit.sh [--days N] [--json]   audit recent sessions
#         scar-audit.sh --stdin               judge ONE message on stdin
#         scar-audit.sh --selftest            planted-fixture control
#
# --stdin exists so an emission-time hook and this after-the-fact audit share
# ONE definition of every scar. Once a violation rate is high enough that
# advisory prose is losing to the model's baseline habits, the answer is a
# deterministic check at the boundary, not more rules in the file. A hook can
# call this mode rather than reimplementing six detectors, so a scar can never
# mean one thing at the gate and another in the report.
# Exit:   0 clean · 1 violations found · 2 error
#
# CADENCE. Non-interactive, read-only, no network, no credentials. Safe to run
# unattended. Reads Claude Code session transcripts and writes only to stdout.
set -uo pipefail

DAYS=${SCAR_AUDIT_DAYS:-7}
ROOT=${SCAR_AUDIT_ROOT:-$HOME/.claude/projects}
JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS=${2:?--days needs a number}; shift 2 ;;
    --json) JSON=1; shift ;;
    --stdin) STDIN_MODE=1; shift ;;
    --selftest) selftest=1; shift ;;
    -h|--help) sed -n '2,41p' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { printf 'scar-audit: jq is required\n' >&2; exit 2; }

# ── scar table ────────────────────────────────────────────────────────────────
# id|severity|headline|the wound it came from
#
# These six are mine. Two of them (hash-in-fence, paren-in-fence) apply to
# anyone who pastes an agent's shell block into an interactive zsh. The other
# four are conventions of my own setup, kept here as worked examples, because
# the shape is the part worth copying: a trigger the agent said, and the
# evidence that has to appear alongside it.
scar_table() {
  cat <<'TABLE'
blocked-no-command|high|a turn says it is blocked on you and ships nothing to unblock it|you read "needs your approval" and then have to ask what to run. A full round trip, every time
hash-in-fence|high|a '#' comment line inside a shell block meant for pasting|an interactive zsh without interactive_comments RUNS that line instead of ignoring it. Bit me three times
paren-in-fence|med|a bare parenthetical inside a shell block meant for pasting|zsh reads it as a glob qualifier and the line dies
push-ask|med|a turn ends asking to push, or hands over a git push line|one batched step owns pushing; every session that asks instead puts back the friction that step exists to delete
deferred-no-handoff|med|work pushed to a NEW session with nothing to paste into it|a fresh session that opens by asking what it is doing has lost exactly the context the handoff was for
routine-no-brief|high|a scheduled routine created or changed with no brief in the same turn|three routines got scheduled and never explained, and I had to read their code to find out what they did
TABLE
}

# ── detectors ─────────────────────────────────────────────────────────────────
# Each reads assistant prose on stdin, prints one receipt line per hit, exit 0.
# Receipts are truncated: this is a report, not a transcript dump.

# Shell-ish fences only. An unlabeled fence counts (handoffs are usually bare);
# ```python / ```diff / ```json do not. This restriction IS the noise budget.
#
# A BLOCK MEANT FOR PASTING IS SHORT. This is the single most important
# restriction in the file. These rules govern blocks you paste into a terminal.
# They do not govern a script being displayed for review. Without a length gate
# every quoted shell script, including this one, which is mostly '#' lines
# inside a bash fence, reads as a violation. The first measured run returned
# 1524 raw hits over 574 sessions, 2.65 per session, which is wallpaper. Blocks
# longer than MAXLINES are treated as listings, not handoffs.
MAXLINES=${SCAR_MAX_HANDOFF_LINES:-12}

# kind: hash | paren | push. Buffers each shell fence and judges it whole, so
# block length is known before any line is emitted.
_fence_scan() {
  awk -v MAX="$MAXLINES" -v KIND="$1" '
    function shellish(l) {
      return (l=="" || l=="bash" || l=="sh" || l=="zsh" || l=="shell" || l=="console" || l=="terminal")
    }
    function flush(   i, L) {
      if (sh && nb > 0 && nb <= MAX) {
        for (i = 1; i <= nb; i++) {
          L = buf[i]
          if (KIND == "hash"  && L ~ /^[[:space:]]*#/)               print "  · " substr(L,1,90)
          # PRECISION OVER RECALL. The wound is an UNQUOTED PROSE parenthetical
          # appended to a command, "touch ~/x (valid 60 minutes)", which zsh
          # parses as a glob qualifier. A first cut flagged any "(" followed by
          # a letter and hit 92 sessions, because `grep -E (a|b)`, `sed s/\(x\)/`
          # and `awk { if (x) }` all match. Those are quoted, and a quoted paren
          # is inert. So: no quote characters anywhere on the line, and the
          # parenthetical must be two or more plain words.
          # `arr=(a b c)` is a bash array literal and reads as two plain words,
          # so the paren must NOT be preceded by "=" (assignment) or "$"
          # (substitution). The shell-syntax fixture caught this the moment the
          # rule was tightened the wrong way.
          if (KIND == "paren" && L !~ /^[[:space:]]*#/ &&
              L !~ /['"'"'"]/ && L !~ /[=$]\(/ &&
              L ~ /\([A-Za-z][A-Za-z0-9]*([ ]+[A-Za-z0-9]+)+\)/)      print "  · " substr(L,1,90)
          # FORCE PUSHES ARE EXEMPT. The scar is that one batched step owns the
          # ordinary push surface, so N sessions each handing over a push line
          # recreate the friction that step deletes. A force push is the one
          # shape a fast-forward-only batch cannot perform, so it is refused
          # there and no other channel exists. Blocking it left history
          # ceremonies with nowhere to go, and I ended up composing the line
          # from prose every time. Ordinary pushes still fire.
          # `git -C <path> push` and `git -c k=v push` were invisible to the
          # first version, which required push to sit immediately after git.
          # That is the form I use most, so the rule was blind to its commonest
          # shape. Now: git, then any run of its own options (a -flag,
          # optionally with a value), then push. A subcommand like
          # `git log --grep push` still cannot match, because `log` is not an
          # option and push has to follow the option run directly.
          if (KIND == "push"  &&
              L ~ /^[[:space:]]*git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)/ &&
              L !~ /--force/)                                          print "  · handed over: " substr(L,1,80)
        }
      }
      nb = 0
    }
    /^[[:space:]]*```/ {
      if (inb) { flush(); inb=0; sh=0; next }
      lang=$0; sub(/^[[:space:]]*```/,"",lang); gsub(/[^a-zA-Z0-9+-]/,"",lang)
      inb=1; sh=shellish(tolower(lang)); nb=0; next
    }
    inb { buf[++nb] = $0; next }
    # Prose-side push-asking lives outside any fence.
    KIND == "push" && tolower($0) ~ /(want|shall|should|ready)[^.]{0,20}(me )?to push|let me know[^.]{0,30}push|say the word[^.]{0,20}push/ {
      print "  · asked: " substr($0,1,80)
    }
    END { if (inb) flush() }
  '
}

detect_hash_in_fence()  { _fence_scan hash; }
# A parenthetical that is NOT command substitution $(...), NOT an array literal
# arr=(...), and NOT an empty function def foo(). Requires a letter immediately
# after '(' and a non-$/= character before it.
detect_paren_in_fence() { _fence_scan paren; }
detect_push_ask()       { _fence_scan push; }

detect_deferred_no_handoff() {
  # Added the same day the rule was written down, which is this file's "scars
  # are data" claim being cashed: a new wound cost one table row and one small
  # function, not a redesign.
  # Whole-text: recommending a fresh session is fine; recommending one with
  # nothing to paste is the violation. A shell fence anywhere in the session is
  # taken as the handoff having been shipped.
  local txt; txt=$(cat)
  printf '%s' "$txt" | grep -qiE "worth its own session|pick (this|that|it) up (in a )?fresh|fresh (context|session)|(a|its own|separate|new) session" || return 0
  printf '%s' "$txt" | grep -qE '^[[:space:]]*```(bash|sh|zsh|shell|console|terminal)?[[:space:]]*$' && return 0
  printf '%s' "$txt" | grep -iEm1 "worth its own session|pick (this|that|it) up (in a )?fresh|fresh (context|session)|(a|its own|separate|new) session" \
    | sed 's/^[[:space:]]*/  · deferred: /' | cut -c1-90
}

detect_routine_no_brief() {
  # Three scheduled routines got created without one consolidated explanation of
  # what they do or why. The reasoning sat scattered through build narration,
  # commit bodies and file headers, and I had to go and ask. A routine nobody
  # can describe is a routine nobody can audit, disable, or trust.
  #
  # WHY A LITERAL MARKER rather than "did the turn explain it well". Fuzzy
  # intent is not machine-checkable, and a detector that guesses is a detector
  # that gets muted. The contract is explicit: any turn that creates or updates
  # a routine writes the words "Routine brief" and, under them, what it does,
  # when it runs, what it is worth, and what it will not do.
  local txt; txt=$(cat)
  printf '%s' "${SCAR_TOOLS:-}" | grep -qE 'RemoteTrigger (create|update)' || return 0
  printf '%s' "$txt" | grep -qiF 'routine brief' && return 0
  printf '  · scheduled a routine with no Routine brief in the same turn\n'
}

detect_blocked_no_command() {
  # Whole-text decision, not per-line: the violation is the ABSENCE of anything
  # actionable in the same session that said it was blocked on me.
  #
  # SATISFIED BY A COMMAND OR A QUESTION. The rule this came from asks for the
  # exact runnable command OR the exact question, because sometimes what is
  # needed is a decision and there is no command to give. So a shell fence
  # clears it, and so does a direct question. Without that second half this
  # fires on every turn that correctly stopped to ask something.
  local txt; txt=$(cat)
  printf '%s' "$txt" | grep -qiE 'blocked on you|waiting on you|needs your (approval|key|sign-?off|go-?ahead)|need you to|before I can (proceed|continue)' || return 0
  printf '%s' "$txt" | grep -qE '^[[:space:]]*```(bash|sh|zsh|shell|console|terminal)?[[:space:]]*$' && return 0
  printf '%s' "$txt" | grep -qF '?' && return 0
  printf '%s' "$txt" | grep -iEm1 'blocked on you|waiting on you|needs your (approval|key|sign-?off|go-?ahead)|need you to|before I can (proceed|continue)' \
    | sed 's/^[[:space:]]*/  · said: /' | cut -c1-90
}

# ── scan ──────────────────────────────────────────────────────────────────────
scan() {
  local root=$1 days=$2
  local -a files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "$root" -name '*.jsonl' -mtime "-$days" 2>/dev/null)

  local total=0 sessions=0
  local -a ids=() sids=() hits=()

  # bash 3.2, the only bash on a stock Mac, treats "${arr[@]}" on an EMPTY array
  # as an unbound variable under `set -u` and aborts. Guarding every expansion is
  # not style. An unguarded one turns "no sessions in window" into a crash, and a
  # crashing audit reports clean.
  [ ${#files[@]} -eq 0 ] || for f in "${files[@]}"; do
    # Cheap prefilter: skip files with no assistant text at all before paying for
    # jq. Across a few hundred transcripts this is the difference between a
    # scheduled job and a chore.
    grep -q '"type":"assistant"' "$f" 2>/dev/null || continue
    local txt
    txt=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$f" 2>/dev/null)
    [ -z "$txt" ] && continue
    sessions=$((sessions+1))
    local sid; sid=$(basename "$f" .jsonl | cut -c1-8)

    # Some scars are about what a session DID, not only what it said. Tool calls
    # are exported alongside the prose so a detector can key on an action.
    SCAR_TOOLS=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | "\(.name) \(.input.action // "")"' "$f" 2>/dev/null)
    export SCAR_TOOLS

    while IFS='|' read -r id sev headline _wound; do
      [ -z "$id" ] && continue
      local out
      out=$(printf '%s\n' "$txt" | "detect_${id//-/_}" 2>/dev/null)
      [ -z "$out" ] && continue
      local n; n=$(printf '%s\n' "$out" | grep -c .)
      total=$((total+n))
      ids+=("$id"); sids+=("$sid"); hits+=("$out")
    done < <(scar_table)
  done

  if [ "$JSON" -eq 1 ]; then
    printf '{"window_days":%s,"sessions":%s,"violations":%s}\n' "$days" "$sessions" "$total"
    [ "$total" -eq 0 ] && return 0 || return 1
  fi

  printf '\n\033[1mSCAR AUDIT\033[0m  last %s days · %s sessions with assistant text\n' "$days" "$sessions"
  printf '%s\n' "──────────────────────────────────────────────────────────────"

  if [ "$total" -eq 0 ]; then
    # Silence must never be indistinguishable from clean. Say which rules were
    # checked, or "no output" reads as "nothing ran".
    printf '\033[32mclean\033[0m — 0 violations across %s scars:\n' "$(scar_table | grep -c .)"
    scar_table | while IFS='|' read -r id _sev headline _w; do printf '  ✓ %-20s %s\n' "$id" "$headline"; done
    return 0
  fi

  local i=0
  while IFS='|' read -r id sev headline wound; do
    [ -z "$id" ] && continue
    local count=0
    for i in "${!ids[@]}"; do [ "${ids[$i]}" = "$id" ] && count=$((count+1)); done
    [ "$count" -eq 0 ] && continue
    case "$sev" in
      high) printf '\n\033[31m● %s\033[0m — %s session(s)\n' "$id" "$count" ;;
      *)    printf '\n\033[33m● %s\033[0m — %s session(s)\n' "$id" "$count" ;;
    esac
    printf '  %s\n  \033[2mwound: %s\033[0m\n' "$headline" "$wound"
    for i in "${!ids[@]}"; do
      [ "${ids[$i]}" = "$id" ] || continue
      printf '  \033[2m[%s]\033[0m\n%s\n' "${sids[$i]}" "${hits[$i]}"
    done
  done < <(scar_table)

  printf '\n\033[1m%s violation(s) across %s session(s)\033[0m\n' "$total" "$sessions"
  return 1
}

# ── selftest ──────────────────────────────────────────────────────────────────
# The instrument is an assertion until it has been run against a KNOWN CONTROL.
# Positive fixtures MUST fire; near-miss fixtures MUST NOT.
# -c is load-bearing, not cosmetic. `jq -n` PRETTY-PRINTS: it emits multi-line
# JSON with `"type": "assistant"` (note the space), which is neither valid JSONL
# nor a match for the scan prefilter. The first version of this selftest built
# fixtures that way, so scan() skipped all of them, printed its CLEAN summary,
# which lists every scar id, and the positive assertions matched those ids and
# went green. Four detectors "passed" against zero parsed input. That is a
# textbook fail-open. The assertions below key on EXIT CODE per isolated
# fixture, which no summary line can satisfy.
mkfixture() {
  local dir=$1 name=$2 text=$3
  jq -nc --arg t "$text" \
    '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$dir/$name.jsonl"
}

# A fixture that performed an ACTION as well as speaking.
mkfixture_tool() {
  local dir=$1 name=$2 tool=$3 action=$4 text=$5
  jq -nc --arg t "$text" --arg n "$tool" --arg a "$action" \
    '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:{action:$a}},{type:"text",text:$t}]}}' \
    > "$dir/$name.jsonl"
}

# One fixture, one verdict. Returns scan's exit code: 0 clean, 1 violation.
verdict_for() {
  local src=$1 d rc
  d=$(_mktmp) || return 2
  cp "$src" "$d/" 2>/dev/null
  scan "$d" 3650 >/dev/null 2>&1; rc=$?
  rm -rf "$d"
  return $rc
}

# Explicit template under $TMPDIR: a bare `mktemp -d` resolves to /var/folders on
# a Mac, which a sandboxed agent shell cannot write. The selftest has to be
# runnable by the same agents the audit polices, or it only ever runs by hand.
_mktmp() { mktemp -d "${TMPDIR:-/tmp}/scar-audit.XXXXXX"; }

run_selftest() {
  # NOT local: the EXIT trap fires after this function returns, and a `local`
  # here leaves the trap dereferencing an unbound variable under `set -u`, which
  # turns a passing selftest into a nonzero exit and a scary message.
  tmp=$(_mktmp) || exit 2
  trap 'rm -rf "$tmp"' EXIT
  local fail=0

  # ── positives: each MUST be detected ──
  mkfixture "$tmp" pos-blocked 'This part is blocked on you. I will continue once that is done.'
  mkfixture "$tmp" pos-hash   'Run this:
```bash
cd ~/projects
# this comment will execute in an interactive zsh
ls
```'
  mkfixture "$tmp" pos-paren  'Run this:
```bash
touch ~/somefile (valid 60 minutes)
```'
  mkfixture "$tmp" pos-pushask 'All committed. Do you want me to push these?'
  mkfixture_tool "$tmp" pos-routine RemoteTrigger create 'Created the audit routine. It runs Mondays and reports findings.'
  mkfixture_tool "$tmp" neg-routine-ok RemoteTrigger create 'Routine brief: dead-gate audit, Mondays 8:07am. It asks whether each gate can still fail. Worth it because it catches a check that passes forever. It will not commit or push.'
  mkfixture "$tmp" pos-deferred 'The migration is worth its own session with fresh context. Start there next time.'

  # ── near-misses: each MUST stay silent (this is the noise budget) ──
  mkfixture "$tmp" neg-blocked-ok 'This part is blocked on you. Run:
```bash
touch ~/.config/example/approved
```'
  mkfixture "$tmp" neg-python '```python
# a comment in python is not a zsh paste hazard
x = 1
```'
  mkfixture "$tmp" neg-diff '```diff
- git push origin main
+ nothing
```'
  # A fast-forward-only batch cannot force push, so a history ceremony has no
  # other channel and is handed over in full. Paired with pos-pushforce-plain
  # below, which proves the exemption did not widen into "any push line passes".
  mkfixture "$tmp" neg-pushforce '```bash
git -C ~/projects/example push --force-with-lease origin main
```'
  mkfixture "$tmp" pos-pushforce-plain '```bash
git -C ~/projects/example push origin main
```'
  mkfixture "$tmp" neg-shellsyntax '```bash
arr=(a b c)
value=$(date +%s)
deploy() {
  echo ok
}
```'
  mkfixture "$tmp" neg-clean 'Committed on branch fix/foo. Nothing else owed.'
  # Deferring IS allowed. Deferring with nothing to paste is not.
  mkfixture "$tmp" neg-deferred-ok 'The migration is worth its own session. Paste this to start it:
```bash
cd ~/projects/example
git switch -c feat/migrate
```'
  # A SCRIPT LISTING, not a handoff. Same fence language, same '#' lines, but
  # longer than MAXLINES, so it is being read rather than pasted. Before the
  # length gate this fired and drove the raw count to 1524 across 90 days.
  mkfixture "$tmp" neg-listing '```bash
#!/usr/bin/env bash
# tools/example.sh — demonstration listing
#
# This is a file being shown for review, not a block to paste.
set -uo pipefail
# step one
one() { echo 1; }
# step two
two() { echo 2; }
# step three
three() { echo 3; }
# step four
four() { echo 4; }
one; two; three; four
```'

  printf 'scar-audit --selftest\n'

  # First, prove the harness itself parses fixtures. Without this the whole suite
  # can go green on zero input, which is exactly what it did once.
  local parsed
  parsed=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' \
            "$tmp/pos-blocked.jsonl" 2>/dev/null)
  if [ -z "$parsed" ]; then
    printf '  \033[31m✗ HARNESS DEAD — fixtures do not parse; every assertion below would be vacuous\033[0m\n'
    return 1
  fi
  printf '  ✓ harness parses fixtures (assertions are not vacuous)\n'

  printf ' positives (must fire — asserted by EXIT CODE, not by summary text):\n'
  local POS="pos-blocked pos-hash pos-paren pos-pushask pos-deferred pos-routine pos-pushforce-plain"
  local NEG="neg-blocked-ok neg-python neg-diff neg-shellsyntax neg-clean neg-listing neg-deferred-ok neg-routine-ok neg-pushforce"
  for pos in $POS; do
    verdict_for "$tmp/$pos.jsonl"
    if [ $? -eq 1 ]; then printf '  ✓ %s fires\n' "$pos"
    else printf '  \033[31m✗ %s did NOT fire\033[0m\n' "$pos"; fail=1; fi
  done

  printf ' near-misses (must stay silent — the noise budget):\n'
  for neg in $NEG; do
    verdict_for "$tmp/$neg.jsonl"
    if [ $? -eq 0 ]; then printf '  ✓ %s silent\n' "$neg"
    else printf '  \033[31m✗ %s FIRED (false positive)\033[0m\n' "$neg"; fail=1; fi
  done

  # ── the probe: plant the defect, confirm the check FAILS, revert ──
  printf ' probe (the check must be ABLE to fail):\n'
  local d; d=$(_mktmp)
  mkfixture "$d" planted 'I am blocked on you here before I can continue.'
  if scan "$d" 3650 >/dev/null 2>&1; then
    printf '  \033[31m✗ planted defect did NOT trip the audit — instrument is blind\033[0m\n'; fail=1
  else
    printf '  ✓ planted defect trips the audit (exit 1)\n'
  fi
  rm -f "$d/planted.jsonl"
  if scan "$d" 3650 >/dev/null 2>&1; then
    printf '  ✓ reverted, audit returns clean (exit 0)\n'
  else
    printf '  \033[31m✗ audit still red after revert — it fires on nothing\033[0m\n'; fail=1
  fi
  rm -rf "$d"

  if [ "$fail" -eq 0 ]; then
    printf '\n\033[32mselftest PASS\033[0m — %s detectors fire, %s near-misses silent, planted defect trips and reverts clean\n' \
      "$(printf '%s' "$POS" | wc -w | tr -d ' ')" "$(printf '%s' "$NEG" | wc -w | tr -d ' ')"; return 0
  fi
  printf '\n\033[31mselftest FAIL\033[0m\n'; return 1
}

# ── single-message mode, for an emission-time hook ────────────────────────────
# Reads assistant prose on stdin. Prints one line per violating scar. Exit 1 if
# any fired, 0 if clean. A hook turns that into an allow or a deny.
if [ "${STDIN_MODE:-0}" = 1 ]; then
  txt=$(cat); hits=0
  while IFS='|' read -r id sev headline wound; do
    [ -z "$id" ] && continue
    out=$(printf '%s\n' "$txt" | "detect_${id//-/_}" 2>/dev/null)
    [ -z "$out" ] && continue
    hits=$((hits+1))
    printf '%s [%s] %s\n' "$id" "$sev" "$headline"
    printf '%s\n' "$out"
    printf '  why: %s\n' "$wound"
  done < <(scar_table)
  [ "$hits" -eq 0 ] && exit 0 || exit 1
fi

if [ "${selftest:-0}" = 1 ]; then run_selftest; exit $?; fi
scan "$ROOT" "$DAYS"
