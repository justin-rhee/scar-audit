#!/usr/bin/env bash
# test-scar-audit.sh — offline suite. No network, and none of your transcripts
# are read; every case builds its own input.
#   bash tests/test-scar-audit.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$HERE/../src/scar-audit.sh"
command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok    $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $*"; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/scar-tests.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

# Judge one message through --stdin. Echoes 0 (clean) or 1 (violation).
judge() { printf '%s' "$1" | bash "$AUDIT" --stdin >/dev/null 2>&1; echo $?; }
fires()  { local rc; rc=$(judge "$2"); [ "$rc" = 1 ] && ok "$1" || bad "$1 (stayed silent, expected a hit; rc=$rc)"; }
silent() { local rc; rc=$(judge "$2"); [ "$rc" = 0 ] && ok "$1" || bad "$1 (FIRED, expected silence; rc=$rc)"; }

echo "== the built-in control =="
bash "$AUDIT" --selftest >/dev/null 2>&1
[ $? -eq 0 ] && ok "--selftest passes" || bad "--selftest did not pass"

echo "== modes and exit codes =="
bash "$AUDIT" --help >/dev/null 2>&1 && ok "--help exits 0" || bad "--help did not exit 0"
bash "$AUDIT" --help 2>/dev/null | grep -q 'Usage:' && ok "--help prints usage" || bad "--help printed no usage"
bash "$AUDIT" --nonsense >/dev/null 2>&1; [ $? -eq 2 ] && ok "unknown argument exits 2" || bad "unknown argument did not exit 2"
mkdir -p "$TMP/empty"
SCAR_AUDIT_ROOT="$TMP/empty" bash "$AUDIT" --days 7 >/dev/null 2>&1
[ $? -eq 0 ] && ok "empty transcript dir exits 0 (bash 3.2 empty-array guard holds)" \
             || bad "empty transcript dir did not exit 0 — the set -u guard has regressed"
SCAR_AUDIT_ROOT="$TMP/empty" bash "$AUDIT" --json --days 7 2>/dev/null | jq -e '.violations == 0' >/dev/null \
  && ok "--json emits parseable JSON" || bad "--json output did not parse or violations was not 0"

echo "== each scar fires on its own wound =="
fires "blocked-no-command"  'This part is blocked on you. I will pick it up once that is done.'
fires "hash-in-fence"       'Run this:
```bash
cd /tmp
# this line executes in an interactive zsh
ls
```'
fires "paren-in-fence"      'Run this:
```bash
touch /tmp/thing (valid 60 minutes)
```'
fires "push-ask (prose)"    'All committed. Do you want me to push these'
fires "push-ask (handover)" '```bash
git -C /tmp/repo push origin main
```'
fires "deferred-no-handoff" 'That migration is worth its own session with fresh context.'

SCAR_TOOLS='RemoteTrigger create' \
  bash -c 'printf "%s" "Created the audit routine. It runs Mondays." | bash "$0" --stdin >/dev/null 2>&1' "$AUDIT"
[ $? -eq 1 ] && ok "routine-no-brief" || bad "routine-no-brief (stayed silent, expected a hit)"

echo "== the noise budget: near-misses stay silent =="
silent "a satisfied blocked line"   'This is blocked on you. Run:
```bash
touch /tmp/approved
```'
silent "a blocked line that asks"   'This is blocked on you. Which of the two do you want?'
silent "# inside a python fence"    '```python
# not a zsh paste hazard
x = 1
```'
silent "git push inside a diff"     '```diff
- git push origin main
+ nothing
```'
silent "a bash array literal"       '```bash
arr=(a b c)
value=$(date +%s)
```'
silent "a force push handed over"   '```bash
git -C /tmp/repo push --force-with-lease origin main
```'
silent "git log --grep push"        '```bash
git log --grep push
```'
silent "a deferral with a block"    'Worth its own session. Paste this to start it:
```bash
cd /tmp/repo
git switch -c feat/x
```'
silent "ordinary clean prose"       'Committed on branch fix/foo. Nothing else owed.'

SCAR_TOOLS='RemoteTrigger create' \
  bash -c 'printf "%s" "Routine brief: nightly audit, 8am. It reports findings. It will not commit." | bash "$0" --stdin >/dev/null 2>&1' "$AUDIT"
[ $? -eq 0 ] && ok "a routine WITH a brief" || bad "a routine WITH a brief (FIRED, expected silence)"

# ── BREAK THE CLAIM ───────────────────────────────────────────────────────────
# The headline promise is that this stays quiet on everything that is not the
# wound. So: one message carrying every near-miss shape at once, including the
# long script listing that drove the first raw count to 1524. If the promise
# holds anywhere, it has to hold here.
echo "== break the claim: every near-miss in one message =="
NOISE='Here is the script I am about to add, for review:
```bash
#!/usr/bin/env bash
# tools/example.sh — a listing, not a handoff
#
# You are reading this, not pasting it.
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
```

And the python equivalent:
```python
# a comment that is not a zsh hazard
x = 1
```

The diff I am reverting:
```diff
- git push origin main
+ nothing
```

Some shell syntax that looks like a parenthetical and is not:
```bash
arr=(a b c)
value=$(date +%s)
```

Committed on branch fix/foo. Nothing else owed.'
silent "a realistic mixed message stays clean" "$NOISE"

# ── LOAD-BEARING ──────────────────────────────────────────────────────────────
# Two mutations. Each disables the thing that makes the promise true and asserts
# something goes red. A test that cannot fail proves nothing.
echo "== load-bearing: the length gate is what keeps it quiet =="
LISTING='```bash
#!/usr/bin/env bash
# tools/example.sh — a listing, not a handoff
#
# You are reading this, not pasting it.
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
printf '%s' "$LISTING" | bash "$AUDIT" --stdin >/dev/null 2>&1
[ $? -eq 0 ] && ok "the listing is silent with the gate in place" \
             || bad "the listing fired with the gate in place"
printf '%s' "$LISTING" | SCAR_MAX_HANDOFF_LINES=999 bash "$AUDIT" --stdin >/dev/null 2>&1
[ $? -eq 1 ] && ok "raising MAXLINES makes the SAME listing fire (the gate is load-bearing)" \
             || bad "raising MAXLINES changed nothing — the length gate is not what keeps it quiet"

echo "== load-bearing: the selftest can actually fail =="
# Delete one detector's body on a throwaway copy. Its positive fixture must stop
# firing and --selftest must go red. If it stays green, the control is decorative.
MUT="$TMP/mutant.sh"
cp "$AUDIT" "$MUT"
# detect_hash_in_fence delegates to _fence_scan; stub it so it can never hit.
sed -i.bak 's|^detect_hash_in_fence()  { _fence_scan hash; }$|detect_hash_in_fence()  { : ; }|' "$MUT"
grep -q 'detect_hash_in_fence()  { : ; }' "$MUT" \
  && ok "mutation applied (detector body removed)" || bad "mutation did NOT apply — the next assertion is vacuous"
bash "$MUT" --selftest >/dev/null 2>&1
[ $? -eq 1 ] && ok "--selftest goes RED when a detector is gutted" \
             || bad "--selftest stayed green with a gutted detector — the control proves nothing"
printf '%s' 'Run this:
```bash
# a comment that would execute
ls
```' | bash "$MUT" --stdin >/dev/null 2>&1
[ $? -eq 0 ] && ok "the gutted detector really is blind (the mutation took)" \
             || bad "the gutted detector still fired — the mutation did not take"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
