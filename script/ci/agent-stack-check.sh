#!/usr/bin/env bash
set -uo pipefail
mkdir -p tmp/agent-stack
status=0
check() {
  local name="$1"
  shift
  "$@" >"tmp/agent-stack/$name.log" 2>&1
  local result=$?
  printf '%s\t%s\n' "$name" "$result" | tee -a tmp/agent-stack/results.tsv
  tail -n 35 "tmp/agent-stack/$name.log"
  if test "$result" -ne 0; then status=1; fi
}
check tests bin/rails db:prepare test
check native-tests bin/rails test test/agent_native
check system bin/rails test:system
check security bin/brakeman
check style bin/rubocop
check portable ruby -Itest -e 'Dir["test/standalone/*_test.rb"].sort.each { |f| require_relative f }'
python3 -m venv /tmp/contracts
/tmp/contracts/bin/pip install -r docs/agent-native/contracts/requirements.txt >tmp/agent-stack/contract-install.log 2>&1
check contracts /tmp/contracts/bin/python script/ci/validate-contracts.py
if test -d clients/python/tests; then
  check python env PYTHONPATH=clients/python python3 -m unittest discover -s clients/python/tests -v
fi
# Emit reviewable formatting suggestions, never modify the submitted branch.
bin/rubocop -a >tmp/agent-stack/style-suggestions.log 2>&1 || true
git diff -- '*.rb' >tmp/agent-stack/style.patch
cp db/structure.sql tmp/agent-stack/structure.sql 2>/dev/null || true
exit "$status"
