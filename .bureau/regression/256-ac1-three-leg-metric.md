name: AC1 uses the three-leg processed denominator and confirms only when every denominator leg is exact
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  DOC="$ROOT/agents/orchestrator.md"
  uncommented=$(awk '
    BEGIN { in_comment=0 }
    {
      line=$0
      while (1) {
        if (in_comment) {
          end=index(line,"-->")
          if (!end) { line=""; break }
          line=substr(line,end+3); in_comment=0
        }
        start=index(line,"<!--")
        if (!start) break
        before=substr(line,1,start-1); rest=substr(line,start+4)
        end=index(rest,"-->")
        if (end) { line=before substr(rest,end+3); continue }
        line=before; in_comment=1; break
      }
      if (length(line)) print line
    }
  ' "$DOC")
  primary_block=$(printf '%s\n' "$uncommented" | sed -n '/^\*\*Primary metric (AC 1):\*\*/,/^\*\*Secondary metric (AC 2):\*\*/p')
  [ -n "$primary_block" ] || exit 1
  printf '%s' "$primary_block" | grep -Fq '.delegate_tokens.tokens.processed' || exit 1
  printf '%s' "$primary_block" | grep -Fq '.specialist_spawns[].tokens.processed.value' || exit 1
  printf '%s' "$primary_block" | grep -Fq 'specialist_spawns[].tokens.processed.confidence' || exit 1
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
  # Mutations: moving a required path outside Primary, hiding it in an HTML
  # comment, using processed_total, or dropping the Delegate confidence arm fails.
expected: exit 0; stdout "PASS"; synthetic exact three-leg share is 0.4 (<45%), while the same partial reading only corroborates
phase: 03 · execute-plan
owner: Prompt 03 / AC1 three-leg metric and confidence gate
