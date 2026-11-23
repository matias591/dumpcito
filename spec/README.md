# Scenario format

Each `scenarios/*.json` is replayed by both apps' test suites through the real normalizer, state-file writer and detector.

```json
{
  "name": "...",
  "preseed": [ { ...state file content... } ],   // optional: files that exist before the app starts
  "steps": [
    { "t": 0,                                    // seconds since scenario start (injected clock)
      "tool": "claude",                          // value of --tool
      "payload": { ...hook stdin JSON... },
      "expectEvents": [ {"kind":"needsAttention","tool":"claude","session":"s1"} ],   // events detected right after this step; omit = none
      "expectState": { "claude__s1": "waiting" } // optional; "absent" = file does not exist
    }
  ]
}
```

Harness: (1) write `preseed` files, run one detector poll (priming, never alerts); (2) for each step: set clock to `t`, apply the hook payload, run one detector poll at that time, compare emitted events (order-insensitive) and states.
`preseed` times (`at`, `workingSince`, `touched`) are milliseconds relative to scenario start (negative = before).
A step with `"noPoll": true` applies its hook event but skips the detector poll (simulates a missed poll).
A step with `"tool": null` and `"payload": null` only advances the clock and polls (used for staleness).
Detector settings in tests: finished threshold 20 s, attention cooldown 30 s.

`expectState` is the state the app *displays* (file state after the 15-minute staleness rule), not necessarily the raw file content.
