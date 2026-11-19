#!/bin/bash
# Everything this fork adds, checked: the unit tests, then one behaviour test per
# feature against the built app. Run ./build.sh first (or let this do it).
#
#   ./verify.sh            the lot
#   ./verify.sh units      the unit tests only
#   ./verify.sh behaviour  the Python tests only
set -u
cd "$(dirname "$0")"
what="${1:-all}"
fail=0

units() {
  for suite in UserscriptsTests LinkCardsTests BoostTests BoostFileTests BoostLookTests \
               BoostHiddenTests SnippetsTests DeveloperSetupTests AgentMemoryTests; do
    line=$(swift test --filter "$suite" 2>&1 | grep -E "Executed [0-9]+ test" | tail -1)
    if [ -z "$line" ]; then
      echo "FAIL $suite (did not run)"
      fail=1
    else
      echo "$suite:$(printf '%s' "$line" | sed 's/^\s*//')"
      case "$line" in *"with 0 failures"*) ;; *) fail=1 ;; esac
    fi
  done
}

behaviour() {
  if [ ! -d build/Search.app ]; then
    echo "no build/Search.app: building first"
    SEARCH_DEV=1 ./build.sh >/dev/null 2>&1 || { echo "FAIL the build"; exit 1; }
  fi
  for test in userscripts link_cards boosts snippets agent_wide developers call_window; do
    out=$(python3 -u "Tests/$test.py" 2>&1)
    tail=$(printf '%s' "$out" | grep -E "^[0-9]+ passed" | tail -1)
    if [ -z "$tail" ]; then
      echo "FAIL $test (no summary)"
      printf '%s\n' "$out" | tail -5
      fail=1
    else
      echo "$test: $tail"
      case "$tail" in *" 0 failed"*) ;; *) fail=1 ;; esac
    fi
  done
}

case "$what" in
  units) units ;;
  behaviour) behaviour ;;
  all) units; behaviour ;;
  *) echo "usage: ./verify.sh [units|behaviour|all]"; exit 2 ;;
esac

if [ "$fail" -eq 0 ]; then echo "all checks passed"; else echo "something failed"; fi
exit "$fail"
