name: AC1 uses the three-leg processed denominator and confirms only when every denominator leg is exact
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  DOC="$ROOT/agents/orchestrator.md"
  grep -Fq '.delegate_tokens.tokens.processed' "$DOC" || exit 1
  grep -Fq '.specialist_spawns[].tokens.processed.value' "$DOC" || exit 1
  grep -Fq 'specialist_spawns[].tokens.processed.confidence' "$DOC" || exit 1
  primary_block=$(sed -n '/^\*\*Primary metric (AC 1):\*\*/,/^\*\*Secondary metric (AC 2):\*\*/p' "$DOC")
  printf '%s' "$primary_block" | grep -Fq 'processed_total' && exit 1
  exact=$(jq -cn '
    {
      conductor_tokens:{tokens:{processed:40},confidence:"exact"},
      delegate_tokens:{tokens:{processed:30},confidence:"exact"},
      specialist_spawns:[
        {tokens:{processed:{value:20,confidence:"exact"}}},
        {tokens:{processed:{value:10,confidence:"exact"}}}
      ],
      tokens:{processed_total:{value:1,confidence:"exact"}}
    }
  ')
  share=$(printf '%s' "$exact" | jq '
    .conductor_tokens.tokens.processed /
    (.conductor_tokens.tokens.processed + .delegate_tokens.tokens.processed +
     ([.specialist_spawns[].tokens.processed.value] | add // 0))
  ')
  confirmatory=$(printf '%s' "$exact" | jq '
    (.conductor_tokens.confidence == "exact") and
    (.delegate_tokens.confidence == "exact") and
    all(.specialist_spawns[]; .tokens.processed.confidence == "exact")
  ')
  [ "$share" = "0.4" ] && [ "$confirmatory" = "true" ] || exit 1
  partial=$(printf '%s' "$exact" | jq '.delegate_tokens.confidence = "partial"')
  partial_share=$(printf '%s' "$partial" | jq '
    .conductor_tokens.tokens.processed /
    (.conductor_tokens.tokens.processed + .delegate_tokens.tokens.processed +
     ([.specialist_spawns[].tokens.processed.value] | add // 0))
  ')
  partial_confirmatory=$(printf '%s' "$partial" | jq '
    (.conductor_tokens.confidence == "exact") and
    (.delegate_tokens.confidence == "exact") and
    all(.specialist_spawns[]; .tokens.processed.confidence == "exact")
  ')
  [ "$partial_share" = "0.4" ] && [ "$partial_confirmatory" = "false" ] || exit 1
  echo "PASS"
  # Mutations: using processed_total yields 40, not 0.4; dropping the Delegate
  # confidence arm makes the partial example falsely confirmatory.
expected: exit 0; stdout "PASS"; exact three-leg share is 0.4 (<45%), while the same partial reading only corroborates
phase: 03 · execute-plan
owner: Prompt 03 / AC1 three-leg metric and confidence gate
