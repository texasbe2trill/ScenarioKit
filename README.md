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
- Works with curated storyboard YAML and with raw macOS event exports
- Single-file HTML output ready for tickets, briefs, or postmortems

## Quickstart: macOS logs → storyboard
Assumes `jq` installed (`brew install jq`).

General Unified Logs to storyboard:
```sh
log show --last 15m --style json \
| jq '[.[] | {
  timestamp: .timestamp,
  process: .process,
  subsystem: .subsystem,
  category: .category,
  eventMessage: .eventMessage,
  senderImagePath: .senderImagePath
}]' > macos_events.json

swift run scenariokit storyboard import-events macos_events.json --open
```

High-signal TCC example:
```sh
log show --last 60m --style json --predicate 'subsystem == "com.apple.TCC"' \
| jq '[.[] | { timestamp, process, subsystem, category, eventMessage, senderImagePath }]' \
> tcc_events.json

swift run scenariokit storyboard import-events tcc_events.json --open
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
- No “enterprise/basic” YAML profiles are used; the inputs are either event exports or full storyboard docs.
- Event import applies light noise filtering to drop chatty macOS background subsystems and keep security-relevant signals (curl/TCC/persistence/credential hints).
 
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
