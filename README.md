# ScenarioKit
ScenarioKit is a SwiftPM CLI for macOS security storyboards: validate YAML, analyze dependencies, and generate polished offline HTML briefings from curated scenarios or raw macOS event data.

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

## Quickstart: macOS logs → YAML → storyboard
Assumes `jq` and `yq` installed (brew install jq yq).

TCC-focused events:
```sh
log show --last 30m --style json \
  --predicate 'subsystem == "com.apple.TCC"' \
| jq -c '{ timestamp, process, subsystem, category, eventMessage, senderImagePath, user: (user // null) }' \
| yq -P > macos_events.yaml

swift run scenariokit storyboard import-events macos_events.yaml --open
```

LaunchAgents / persistence keywords:
```sh
log show --last 2h --style json \
| jq -c 'select(.eventMessage? | test("LaunchAgents|LaunchDaemons|launchd|plist"; "i")) |
        { timestamp, process, subsystem, category, eventMessage, senderImagePath }' \
| yq -P > persistence_events.yaml

swift run scenariokit storyboard import-events persistence_events.yaml --open
```

Curated storyboard (reviewed, shareable):
```sh
swift run scenariokit storyboard render examples/storyboard_macos.yaml --open
```

Dependency analysis (non-storyboard):
```sh
swift run scenariokit analyze examples/basic.yaml
swift run scenariokit report examples/enterprise.yaml --out report.html
```

## CLI summary
- `validate <path>`: Load and validate a scenario YAML (`--strict` to treat warnings as errors).
- `analyze <path>`: Decode scenario YAML, summarize services, output text or JSON (`--format text|json`, `--output <file>`).
- `report <path>`: Dependency report HTML or JSON (`--format html|json`, `--out <file>`, `--open`).
- `storyboard render <path>`: Render storyboard HTML (`--theme light|dark`, `--out <file>`, `--open`).
- `storyboard import-events <path>`: Convert macOS events YAML to a storyboard draft and render (`--name <scenario>`, `--theme light|dark`, `--out <file>`, `--open`).

## Examples
- Basic scenario: `examples/basic.yaml`
- Enterprise scenario: `examples/enterprise.yaml`
- macOS storyboard (curated): `examples/storyboard_macos.yaml`
- macOS events import: `examples/macos_events.yaml`

## Output philosophy
- Single-file HTML (inline CSS/JS), offline, Safari-friendly
- Deterministic ordering for repeatable runs
- No external services or network fetches

## Development
- Build: `swift build`
- Tests: `swift test`

Generate a report:

```sh
swift run scenariokit report examples/enterprise.yaml --out report.html --open
```
