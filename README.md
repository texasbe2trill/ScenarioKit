# ScenarioKit
ScenarioKit is a SwiftPM CLI for macOS security storyboards: take macOS logs (Unified Logs JSON, EDR exports), turn them into an offline HTML briefing with timeline, starter rules, actions, and fixtures.

## Requirements
- macOS with Swift 6 (Xcode 15.3 or later)
- No external services; everything runs locally

## Install and build
```sh
swift build
```

## What ScenarioKit is
- macOS security storyboard generator (offline HTML)
- Works with curated storyboard YAML and with raw macOS event exports (filtered + Sigma-matched)
- Single-file HTML output ready for tickets, briefs, or postmortems

## Quickstart: macOS logs → storyboard
Assumes `jq` installed (`brew install jq`).

Targeted curl/wget, DNS, and plist signals:
```sh
log show --last 20m --style json \
  --predicate 'process == "curl" || process == "wget" || eventMessage CONTAINS "http" || eventMessage CONTAINS ".plist" || subsystem CONTAINS "dns"' \
| jq '[.[] | {
  timestamp,
  process,
  processID,
  processImagePath: .imagePath,
  subsystem,
  category,
  eventMessage,
  composedMessage,
  senderImagePath,
  senderImageUUID,
  traceID,
  bootUUID,
  machTimestamp
}]' > macos_signals.json

swift run scenariokit storyboard import-events macos_signals.json --open
# Notes: import-events keeps only Sigma-matched events; curl/wget/DNS/plist hits should render fixtures with rule IDs.
```

High-signal TCC example:
```sh
log show --last 60m --style json --predicate 'subsystem == "com.apple.TCC"' \
| jq '[.[] | {
  timestamp,
  process,
  processID,
  processImagePath: .imagePath,
  subsystem,
  category,
  eventMessage,
  composedMessage,
  messageType,
  senderImagePath,
  senderImageUUID,
  threadID,
  activityIdentifier,
  machTimestamp,
  traceID,
  bootUUID,
  timezoneName
}]' \
> tcc_events.json

swift run scenariokit storyboard import-events tcc_events.json --open
# Notes: if no Sigma rule matches, the HTML will be sparse/empty; TCC churn alone may be filtered as background noise.
```

General Unified Logs (no predicate; noisy):
```sh
log show --last 10m --style json \
| jq '[.[] | {
  timestamp,
  process,
  subsystem,
  category,
  eventMessage,
  composedMessage,
  senderImagePath,
  senderImageUUID
}]' > macos_events.json

swift run scenariokit storyboard import-events macos_events.json --open
# Notes: large exports can be mostly noise; prefer predicates above for clearer output.
```

Curated storyboard (reviewed, shareable):
```sh
swift run scenariokit storyboard render examples/storyboard_macos_example.yaml --open
```

## CLI usage
`swift run scenariokit storyboard render <path>`
- `path` (required): storyboard YAML or JSON
- `--out <file>`: output HTML path (default `storyboard.html`)
- `--theme light|dark`: theme (default dark)
- `--max-events <N>`: cap embedded fixtures (default 200)
- `--open`: open the generated HTML on macOS

`swift run scenariokit storyboard import-events <path>`
- `path` (required): events YAML/JSON (top-level array or `events`/`items` array)
- `--name <string>`: override scenario name
- `--out <file>`: output HTML path (default `storyboard.html`)
- `--theme light|dark`: theme (default dark)
- `--max-events <N>`: cap embedded fixtures (default 200)
- `--open`: open the generated HTML on macOS

Notes:
- Event import applies noise filtering to drop chatty macOS background subsystems and keep security-relevant signals (curl/TCC/persistence/credential hints).
- Bundled macOS Sigma rules are applied during `import-events`; only events that match at least one Sigma rule are kept and annotated in the HTML (fixtures show “Sigma: <rule ids>”).
- Coverage treats Sigma matches as “passing”; expect coverage to drop to 0 if nothing matches.
- Large Unified Log exports can be very noisy; prefer predicates (e.g., `subsystem == "com.apple.TCC"`) before import, and include the richer fields above to improve matching.
 
## Examples
- macOS storyboard (curated): `examples/storyboard_macos_example.yaml`
- macOS events import (YAML/JSON): `examples/macos_events_example.yaml`, `examples/macos_events_example.json`
- TCC-focused events (JSON): `examples/tcc_events.json`

## Output philosophy
- Single-file HTML (inline CSS/JS), offline, Safari-friendly
- Deterministic ordering for repeatable runs
- No external services or network fetches

> Generated storyboard HTML (e.g., `storyboard.html` or `*.storyboard.html`) is a build artifact—do not commit it.

## Development
- Build: `swift build`
- Tests: `swift test`
