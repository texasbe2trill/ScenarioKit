# ScenarioKit
ScenarioKit is a SwiftPM CLI for working with scenario manifests and storyboards: validate YAML, analyze dependencies, and generate polished HTML briefings that work entirely offline.

## Requirements
- macOS with Swift 6 (Xcode 15.3 or later)
- No external services; everything runs locally

## Install and build
```sh
swift build
```

## Quick start
Validate a scenario manifest:
```sh
swift run scenariokit validate examples/basic.yaml
```

Analyze dependencies (text):
```sh
swift run scenariokit analyze examples/basic.yaml
```

Analyze dependencies (JSON to file):
```sh
swift run scenariokit analyze --format json --output /tmp/analysis.json examples/basic.yaml
```

Generate an HTML dependency report:
```sh
swift run scenariokit report examples/enterprise.yaml --out report.html
```

Render a storyboard from a storyboard YAML (light theme by default):
```sh
swift run scenariokit storyboard render examples/storyboard_macos.yaml --out storyboard.html
```

Import raw events and render as a storyboard:
```sh
swift run scenariokit storyboard import-events examples/events_only.yaml --name "Imported Demo" --out storyboard-events.html
```

Open the generated HTML (macOS):
```sh
open storyboard.html
```

## CLI summary
- `validate <path>`: Load and validate a scenario YAML (`--strict` to treat warnings as errors).
- `analyze <path>`: Decode scenario YAML, summarize services, output text or JSON (`--format text|json`, `--output <file>`).
- `report <path>`: Dependency report HTML or JSON (`--format html|json`, `--out <file>`, `--open`).
- `storyboard render <path>`: Render storyboard HTML (`--theme light|dark`, `--out <file>`, `--open`).
- `storyboard import-events <path>`: Convert events YAML to a storyboard and render (`--name <scenario>`, `--theme light|dark`, `--out <file>`, `--open`).

## Examples
- Basic scenario: `examples/basic.yaml`
- Enterprise scenario: `examples/enterprise.yaml`
- macOS storyboard: `examples/storyboard_macos.yaml`
- Events-only import: `examples/events_only.yaml`

## Notes
- Outputs are single-file HTML with inline CSS/JS; no network required.
- Mermaid JS is bundled for dependency graphs.
- Lists and tables are sorted for deterministic output.

## Development
- Build: `swift build`
- Tests: `swift test`
- Linting/formatting: use SwiftFormat or swift-format if desired (not required to run the CLI).

Generate a report:

```sh
swift run scenariokit report examples/enterprise.yaml --out report.html --open
```
