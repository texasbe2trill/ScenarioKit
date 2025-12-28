import Foundation

enum StoryboardHTMLRenderer {
    enum Theme {
        case light
        case dark
    }

    enum RenderKind {
        case native
        case draft(String)

        var label: String {
            switch self {
            case .native: return "Native Scenario"
            case .draft(let note): return "Draft (\(note))"
            }
        }
    }

    static func render(storyboard: StoryboardDocument, theme: Theme, kind: RenderKind) throws -> String {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let computedSeverity = effectiveSeverity(for: storyboard)

        let storyData = StoryData(
            version: storyboard.version ?? 1,
            build: storyboard.build,
            generatedAt: generatedAt,
            scenario: ScenarioData(
                name: storyboard.scenario.name,
                description: storyboard.scenario.description ?? "",
                owner: storyboard.scenario.owner,
                tags: (storyboard.scenario.tags ?? []).sorted()
            ),
            severity: storyboard.severity?.rawValue,
            computedSeverity: computedSeverity.rawValue,
            badge: kind.label,
            signals: storyboard.signals
                .sorted { $0.label < $1.label }
                .map { SignalData(id: $0.id, label: $0.label) },
            rules: storyboard.rules
                .sorted { $0.id < $1.id }
                .map {
                    RuleData(
                        id: $0.id,
                        title: $0.title,
                        severity: $0.severity.rawValue,
                        techniques: ($0.techniques ?? []).sorted(),
                        match: ($0.match ?? []).map { MatchData(ok: $0.ok ?? false, text: $0.text ?? "") },
                        explanation: $0.explanation
                    )
                },
            actions: storyboard.actions
                .sorted { $0.id < $1.id }
                .map {
                    ActionData(
                        id: $0.id,
                        title: $0.title,
                        steps: $0.steps,
                        notes: $0.notes
                    )
                },
            timeline: storyboard.timeline.map {
                TimelineData(time: $0.time ?? "", headline: $0.headline, detail: $0.detail ?? "", severity: $0.severity?.rawValue)
            },
            fixtures: storyboard.fixtures
                .sorted { $0.id < $1.id }
                .map { FixtureData(id: $0.id, expected: $0.expected ?? [], result: $0.result, event: $0.event) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(storyData)
        guard var json = String(data: data, encoding: .utf8) else {
            throw ScenarioKitError.jsonEncodingFailed(underlying: CocoaError(.coderInvalidValue))
        }
        json = json.replacingOccurrences(of: "</script>", with: "<\\/script>")

        let base = template(for: theme)
        let html = base
            .replacingOccurrences(of: "__STORY_DATA__", with: json)
            .replacingOccurrences(of: "__SCRIPT__", with: commonScript)

        return html
    }

    private static func effectiveSeverity(for storyboard: StoryboardDocument) -> StoryboardDocument.Severity {
        if let explicit = storyboard.severity {
            return explicit
        }
        let rank: [StoryboardDocument.Severity: Int] = [.low: 1, .medium: 2, .high: 3, .critical: 4]
        return storyboard.rules.reduce(StoryboardDocument.Severity.medium) { current, rule in
            return (rank[rule.severity] ?? 1) > (rank[current] ?? 1) ? rule.severity : current
        }
    }

    private static func template(for theme: Theme) -> String {
        switch theme {
        case .light: return lightTemplate
        case .dark: return darkTemplate
        }
    }
}

private struct StoryData: Codable {
    let version: Int
    let build: String?
    let generatedAt: String
    let scenario: ScenarioData
    let severity: String?
    let computedSeverity: String
    let badge: String
    let signals: [SignalData]
    let rules: [RuleData]
    let actions: [ActionData]
    let timeline: [TimelineData]
    let fixtures: [FixtureData]
}

private struct ScenarioData: Codable {
    let name: String
    let description: String
    let owner: String?
    let tags: [String]
}

private struct RuleData: Codable {
    let id: String
    let title: String
    let severity: String
    let techniques: [String]
    let match: [MatchData]
    let explanation: String?
}

private struct ActionData: Codable {
    let id: String
    let title: String
    let steps: [String]
    let notes: String?
}

private struct IssueData: Codable {
    let severity: String
    let message: String
}

private struct SignalData: Codable {
    let id: String
    let label: String
}

private struct MatchData: Codable {
    let ok: Bool
    let text: String
}

private struct TimelineData: Codable {
    let time: String
    let headline: String
    let detail: String
    let severity: String?
}

private struct FixtureData: Codable {
    let id: String
    let expected: [String]
    let result: String?
    let event: YAMLValue?
}

private extension ScenarioIssue {
    var severityText: String {
        switch severity {
        case .error: return "error"
        case .warning: return "warning"
        }
    }
}

private let commonScript = #"""
const STORY = JSON.parse(document.getElementById("story-data").textContent || "{}");
const $ = (sel) => document.querySelector(sel);

function render(){
  const scenario = STORY.scenario || {};
  const severity = (STORY.computedSeverity || "medium").toUpperCase();
  const fixtures = STORY.fixtures || [];

  $("#scenarioName").textContent = scenario.name || "Untitled scenario";
  $("#scenarioDesc").textContent = scenario.description || "";
  $("#purposeBox").textContent = scenario.description || "Purpose statement goes here.";
  $("#scenarioBadge").textContent = STORY.badge || "Native Scenario";
  const firstNotes = (STORY.actions || []).map(a => a.notes).find(n => n && n.length) || "";
  $("#notesBox").textContent = firstNotes || "—";
  $("#schemaVer").textContent = `schema v${STORY.version || "1"}`;
  $("#severityPill").textContent = `Severity: ${severity}`;
  const passCount = passingFixtures(fixtures);
  const unknownCount = (fixtures||[]).filter(f => !f.result || f.result.toLowerCase() === "unknown").length;
  $("#coveragePill").textContent = `Fixtures: ${passCount}/${fixtures.length} passing (${unknownCount} unknown)`;

  const tags = $("#tagChips");
  tags.innerHTML = "";
  (scenario.tags || []).forEach(t=>{
    const s = document.createElement("span");
    s.className = "chip";
    s.textContent = t;
    tags.appendChild(s);
  });

  const sig = $("#signalsList"); sig.innerHTML = "";
  (STORY.signals || []).forEach(s=>{
    const li = document.createElement("li");
    li.textContent = s.label;
    sig.appendChild(li);
  });

  const rc = $("#rulesListCompact"); rc.innerHTML = "";
  (STORY.rules || []).forEach(r=>{
    const li = document.createElement("li");
    li.innerHTML = `<span class="mono">${escapeHtml(r.id)}</span> — ${escapeHtml(r.title)} <span class="badge">${(r.severity||"").toUpperCase()}</span>`;
    rc.appendChild(li);
  });

  const ac = $("#actionsListCompact"); ac.innerHTML = "";
  (STORY.actions || []).forEach(a=>{
    const li = document.createElement("li");
    li.innerHTML = `<span class="mono">${escapeHtml(a.id)}</span> — ${escapeHtml(a.title)}`;
    ac.appendChild(li);
  });

  $("#ownerField").textContent = scenario.owner || "—";
  $("#severityField").textContent = severity;
  $("#techniquesField").textContent = uniqueTechniques(STORY.rules).join(", ") || "—";
  $("#fixturesField").textContent = `${passingFixtures(fixtures)}/${fixtures.length} passing`;
  $("#buildField").textContent = STORY.build || "—";
  $("#generatedAt").textContent = `generatedAt: ${STORY.generatedAt || ""}`;

  const tl = $("#timelineList"); tl.innerHTML = "";
  (STORY.timeline || []).forEach(t=>{
    const item = document.createElement("div");
    item.className = "item";
    item.innerHTML = `
      <div class="itemhead">
        <div><strong>${escapeHtml(t.headline || "")}</strong><div class="subtitle">${escapeHtml(t.detail || "")}</div></div>
        <div class="time">${escapeHtml(t.time || "")}</div>
      </div>
      <div class="row" style="margin-top:8px;">
        <span class="badge">severity: ${(t.severity||"info").toUpperCase()}</span>
      </div>
    `;
    tl.appendChild(item);
  });

  const rf = $("#rulesFull"); rf.innerHTML = "";
  (STORY.rules || []).forEach(r=>{
    const box = document.createElement("div");
    box.className = "item";
    box.innerHTML = `
      <div class="itemhead">
        <div>
          <div><strong>${escapeHtml(r.title)}</strong></div>
          <div class="subtitle mono">${escapeHtml(r.id)}</div>
        </div>
        <div class="badge">${(r.severity||"").toUpperCase()}</div>
      </div>
      <div class="row" style="margin-top:10px;">
        <span class="badge">techniques: ${(r.techniques||[]).join(", ") || "—"}</span>
      </div>
      <div style="margin-top:10px;">
        <div class="subtitle"><strong>Match logic</strong></div>
        <ul style="margin-top:6px;">
          ${(r.match||[]).map(m=>`<li>${m.ok ? "✓" : "×"} ${escapeHtml(m.text || "")}</li>`).join("")}
        </ul>
      </div>
      <div style="margin-top:10px;">
        <div class="subtitle"><strong>Explanation</strong></div>
        <div class="box" style="margin-top:6px;">${escapeHtml(r.explanation || "—")}</div>
      </div>
    `;
    rf.appendChild(box);
  });

  const af = $("#actionsFull"); af.innerHTML = "";
  (STORY.actions || []).forEach(a=>{
    const box = document.createElement("div");
    box.className = "item";
    box.innerHTML = `
      <div class="itemhead">
        <div>
          <div><strong>${escapeHtml(a.title)}</strong></div>
          <div class="subtitle mono">${escapeHtml(a.id)}</div>
        </div>
        <div class="badge">checklist</div>
      </div>
      <div style="margin-top:10px;">
        ${(a.steps||[]).map(s=>`
          <div class="row" style="margin:8px 0;">
            <input type="checkbox" />
            <div>${escapeHtml(s)}</div>
          </div>
        `).join("")}
      </div>
      <div class="box" style="margin-top:10px;">${escapeHtml(a.notes || "")}</div>
    `;
    af.appendChild(box);
  });

  const ff = $("#fixturesFull"); ff.innerHTML = "";
  fixtures.forEach(f=>{
    const eventJSON = JSON.stringify(f.event||{}, null, 2);
    const box = document.createElement("div");
    box.className = "item";
    box.dataset.search = `${f.id} ${(f.expected||[]).join(" ")} ${eventJSON}`.toLowerCase();
    box.innerHTML = `
      <div class="itemhead">
        <div>
          <div><strong>Fixture ${escapeHtml(f.id)}</strong></div>
          <div class="subtitle mono">Expected: ${(f.expected||[]).join(", ") || "none"}</div>
        </div>
        <div class="badge">${(f.result||"").toUpperCase()}</div>
      </div>
      <div class="code">${escapeHtml(eventJSON)}</div>
    `;
    ff.appendChild(box);
  });

  attachFixtureSearch();
}

function escapeHtml(s){
  return String(s)
    .replaceAll("&","&amp;")
    .replaceAll("<","&lt;")
    .replaceAll(">","&gt;")
    .replaceAll("\"","&quot;")
    .replaceAll("'","&#39;");
}

function uniqueTechniques(rules){
  const set = new Set();
  (rules||[]).forEach(r => (r.techniques||[]).forEach(t => set.add(t)));
  return Array.from(set);
}

function passingFixtures(fixtures){
  return (fixtures||[]).filter(f => (f.result||"").toLowerCase() === "pass").length;
}

function showTab(tabName){
  ["overview","timeline","rules","actions","tests"].forEach(v=>{
    const sec = document.getElementById(`view-${v}`);
    sec.classList.toggle("hidden", v !== tabName);
  });
  document.querySelectorAll(".tab").forEach(t=>{
    t.setAttribute("aria-selected", t.dataset.tab === tabName ? "true" : "false");
  });
}

function attachFixtureSearch(){
  const input = document.getElementById("fixtureSearch");
  if (!input) return;
  input.addEventListener("input", ()=>{
    const term = (input.value || "").toLowerCase();
    document.querySelectorAll("#fixturesFull .item").forEach(el=>{
      const match = (el.dataset.search || "").includes(term);
      el.style.display = match ? "" : "none";
    });
  });
}

document.querySelectorAll(".tab").forEach(t=>{
  t.addEventListener("click", ()=>showTab(t.dataset.tab));
  t.tabIndex = 0;
  t.addEventListener("keydown",(e)=>{
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); showTab(t.dataset.tab); }
  });
});

render();
showTab("overview");
"""#

private let lightTemplate = #"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>ScenarioKit • Storyboard</title>
  <style>
    :root{
      --bg:#ffffff;
      --ink:#111111;
      --muted:#555555;
      --line:#cfcfcf;
      --panel:#f6f6f6;
      --chip:#ededed;
      --radius:10px;
      --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
    }
    *{box-sizing:border-box}
    body{margin:0; background:var(--bg); color:var(--ink); font-family:var(--sans); line-height:1.35}
    .wrap{max-width:1100px; margin:0 auto; padding:18px 16px 60px}
    header{
      border:2px solid var(--line);
      border-radius:var(--radius);
      padding:14px;
      background:var(--panel);
      position:sticky;
      top:10px;
      z-index:10;
    }
    .top{display:flex; gap:12px; flex-wrap:wrap; justify-content:space-between; align-items:flex-start}
    h1{margin:0; font-size:20px}
    .subtitle{color:var(--muted); font-size:13px; margin-top:4px}
    .chips{display:flex; gap:8px; flex-wrap:wrap; margin-top:10px}
    .chip{padding:6px 10px; background:var(--chip); border:1px solid var(--line); border-radius:999px; font-size:12px; color:var(--muted)}
    .meta{display:flex; gap:10px; flex-wrap:wrap; justify-content:flex-end}
    .pill{
      padding:8px 10px;
      border:2px dashed var(--line);
      border-radius:999px;
      font-size:12px;
      color:var(--muted);
      background:#fff;
      min-width:150px;
      text-align:center;
    }
    nav{
      margin-top:12px;
      display:flex;
      gap:8px;
      flex-wrap:wrap;
      border-top:2px solid var(--line);
      padding-top:10px;
    }
    .tab{
      padding:10px 12px;
      border:2px solid var(--line);
      border-radius:10px;
      background:#fff;
      color:var(--muted);
      font-size:13px;
      cursor:pointer;
      user-select:none;
    }
    .input{padding:8px 10px; border-radius:10px; border:2px solid var(--line); background:#fff; color:var(--ink); font-size:13px;}
    .tab[aria-selected="true"]{background:var(--chip); color:var(--ink)}
    main{margin-top:14px}
    .grid{display:grid; grid-template-columns:1fr; gap:12px}
    @media (min-width: 900px){
      .grid.two{grid-template-columns:1.3fr .7fr; align-items:start}
    }
    .card{
      border:2px solid var(--line);
      border-radius:var(--radius);
      padding:14px;
      background:#fff;
    }
    .card h2{margin:0 0 8px 0; font-size:15px}
    .card h3{margin:14px 0 6px 0; font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.08em}
    .box{
      border:2px dashed var(--line);
      border-radius:12px;
      padding:12px;
      background:var(--panel);
      color:var(--muted);
      font-size:13px;
    }
    ul{margin:6px 0 0 0; padding-left:18px}
    li{margin:6px 0}
    .kvs{display:grid; grid-template-columns:140px 1fr; gap:8px 12px; font-size:13px}
    .k{color:var(--muted)}
    .v{color:var(--ink)}
    .mono{font-family:var(--mono)}
    .hidden{display:none !important}
    .row{display:flex; gap:10px; flex-wrap:wrap; align-items:center}
    .badge{
      padding:6px 10px;
      border:2px solid var(--line);
      border-radius:999px;
      font-size:12px;
      color:var(--muted);
      background:#fff;
    }
    .item{
      border:2px solid var(--line);
      border-radius:12px;
      padding:12px;
      background:#fff;
    }
    .itemhead{display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap; align-items:baseline}
    .time{font-family:var(--mono); color:var(--muted); font-size:12px}
    .footer{margin-top:14px; color:var(--muted); font-size:12px; display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap}
    .code{
      margin-top:10px;
      border:2px dashed var(--line);
      border-radius:12px;
      padding:10px;
      background:var(--panel);
      font-family:var(--mono);
      font-size:12px;
      color:var(--muted);
      white-space:pre;
      overflow:auto;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="top">
        <div>
          <div class="row" style="align-items:baseline; gap:8px;">
            <h1 id="scenarioName">Scenario Name</h1><span class="badge" id="scenarioBadge">Native Scenario</span>
          </div>
          <div class="subtitle" id="scenarioDesc">One-line description of the scenario. Keep it calm and readable.</div>
          <div class="chips" id="tagChips"></div>
        </div>
        <div class="meta">
          <div class="pill" id="severityPill">Severity: HIGH</div>
          <div class="pill" id="coveragePill">Fixtures: 2/2 passing</div>
          <div class="pill mono" id="schemaVer">schema v1</div>
        </div>
      </div>

      <nav role="tablist" aria-label="Storyboard Tabs">
        <div class="tab" role="tab" aria-selected="true" data-tab="overview">Overview</div>
        <div class="tab" role="tab" aria-selected="false" data-tab="timeline">Timeline</div>
        <div class="tab" role="tab" aria-selected="false" data-tab="rules">Rules</div>
        <div class="tab" role="tab" aria-selected="false" data-tab="actions">Actions</div>
        <div class="tab" role="tab" aria-selected="false" data-tab="tests">Tests</div>
      </nav>
    </header>

    <main>
      <!-- OVERVIEW -->
      <section id="view-overview" class="grid two">
        <div class="card">
          <h2>Overview</h2>
          <div class="box" id="purposeBox">
            Purpose statement goes here: explain what this scenario is, why it matters, and what the user should do next.
          </div>

          <h3>Signals</h3>
          <ul id="signalsList"></ul>

          <h3>Rules evaluated</h3>
          <ul id="rulesListCompact"></ul>

          <h3>Recommended actions</h3>
          <ul id="actionsListCompact"></ul>
        </div>

        <div class="card">
          <h2>Summary</h2>
          <div class="kvs">
            <div class="k">Owner</div><div class="v" id="ownerField"></div>
            <div class="k">Severity</div><div class="v" id="severityField"></div>
            <div class="k">Techniques</div><div class="v" id="techniquesField"></div>
            <div class="k">Fixtures</div><div class="v" id="fixturesField"></div>
            <div class="k">Build</div><div class="v mono" id="buildField"></div>
          </div>

          <h3>Notes</h3>
          <div class="box" id="notesBox">
            This panel is ideal for constraints, assumptions, and “what good looks like”.
          </div>
        </div>
      </section>

      <!-- TIMELINE -->
      <section id="view-timeline" class="grid hidden">
        <div class="card">
          <h2>Timeline</h2>
          <div class="box">A chronological narrative: what was observed, in what order, with brief explanations.</div>
          <div id="timelineList" style="margin-top:12px; display:flex; flex-direction:column; gap:10px;"></div>
        </div>
      </section>

      <!-- RULES -->
      <section id="view-rules" class="grid hidden">
        <div class="card">
          <h2>Rules</h2>
          <div class="box">Each rule should be readable without YAML. Show match logic + plain-English explanation.</div>
          <div id="rulesFull" style="margin-top:12px; display:flex; flex-direction:column; gap:10px;"></div>
        </div>
      </section>

      <!-- ACTIONS -->
      <section id="view-actions" class="grid hidden">
        <div class="card">
          <h2>Actions</h2>
          <div class="box">Step-by-step checklists, calm wording, platform-neutral.</div>
          <div id="actionsFull" style="margin-top:12px; display:flex; flex-direction:column; gap:10px;"></div>
        </div>
      </section>

      <!-- TESTS -->
      <section id="view-tests" class="grid hidden">
        <div class="card">
          <h2>Tests</h2>
          <div class="box">Fixtures validate intent. They prevent regressions and build trust in community contributions.</div>
          <input id="fixtureSearch" class="input" placeholder="Search fixtures..." style="margin-top:10px; width:100%; padding:8px; border-radius:10px; border:2px solid var(--line);" />
          <div id="fixturesFull" style="margin-top:12px; display:flex; flex-direction:column; gap:10px;"></div>
        </div>
      </section>

      <div class="footer">
        <div>ScenarioKit • storyboard</div>
        <div class="mono" id="generatedAt"></div>
      </div>
    </main>
  </div>

  <script id="story-data" type="application/json">__STORY_DATA__</script>
  <script>__SCRIPT__</script>
</body>
</html>
"""#

private let darkTemplate = #"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>ScenarioKit • Storyboard</title>
  <style>
    :root{
      --bg:#0f172a;
      --ink:#e5e7eb;
      --muted:#9ca3af;
      --line:#1f2937;
      --panel:#111827;
      --chip:#1f2937;
      --radius:10px;
      --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
    }
    *{box-sizing:border-box}
    body{margin:0; background:var(--bg); color:var(--ink); font-family:var(--sans); line-height:1.35}
    .wrap{max-width:1100px; margin:0 auto; padding:18px 16px 60px}
    header{
      border:2px solid var(--line);
      border-radius:var(--radius);
      padding:14px;
      background:var(--panel);
      position:sticky;
      top:10px;
      z-index:10;
    }
    .top{display:flex; gap:12px; flex-wrap:wrap; justify-content:space-between; align-items:flex-start}
    h1{margin:0; font-size:20px}
    .subtitle{color:var(--muted); font-size:13px; margin-top:4px}
    .chips{display:flex; gap:8px; flex-wrap:wrap; margin-top:10px}
    .chip{padding:6px 10px; background:var(--chip); border:1px solid var(--line); border-radius:999px; font-size:12px; color:var(--muted)}
    .meta{display:flex; gap:10px; flex-wrap:wrap; justify-content:flex-end}
    .pill{
      padding:8px 10px;
      border:2px dashed var(--line);
      border-radius:999px;
      font-size:12px;
      color:var(--muted);
      background:#0b1220;
      min-width:150px;
      text-align:center;
    }
    nav{
      margin-top:12px;
      display:flex;
      gap:8px;
      flex-wrap:wrap;
      border-top:2px solid var(--line);
      padding-top:10px;
    }
    .tab{
      padding:10px 12px;
      border:2px solid var(--line);
      border-radius:10px;
      background:#0b1220;
      color:var(--muted);
      font-size:13px;
      cursor:pointer;
      user-select:none;
    }
    .input{padding:8px 10px; border-radius:10px; border:2px solid var(--line); background:#0b1220; color:var(--ink); font-size:13px;}
    .tab[aria-selected="true"]{background:var(--chip); color:var(--ink)}
    main{margin-top:14px}
    .grid{display:grid; grid-template-columns:1fr; gap:12px}
    @media (min-width: 900px){
      .grid.two{grid-template-columns:1.3fr .7fr; align-items:start}
    }
    .card{
      border:2px solid var(--line);
      border-radius:var(--radius);
      padding:14px;
      background:var(--panel);
    }
    .card h2{margin:0 0 8px 0; font-size:15px}
    .card h3{margin:14px 0 6px 0; font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.08em}
    .box{
      border:2px dashed var(--line);
      border-radius:12px;
      padding:12px;
      background:#0b1220;
      color:var(--muted);
      font-size:13px;
    }
    ul{margin:6px 0 0 0; padding-left:18px}
    li{margin:6px 0}
    .kvs{display:grid; grid-template-columns:140px 1fr; gap:8px 12px; font-size:13px}
    .k{color:var(--muted)}
    .v{color:var(--ink)}
    .mono{font-family:var(--mono)}
    .hidden{display:none !important}
    .row{display:flex; gap:10px; flex-wrap:wrap; align-items:center}
    .badge{
      padding:6px 10px;
      border:2px solid var(--line);
      border-radius:999px;
      font-size:12px;
      color:var(--muted);
      background:#0b1220;
    }
    .item{
      border:2px solid var(--line);
      border-radius:12px;
      padding:12px;
      background:#0b1220;
    }
    .itemhead{display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap; align-items:baseline}
    .time{font-family:var(--mono); color:var(--muted); font-size:12px}
    .footer{margin-top:14px; color:var(--muted); font-size:12px; display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap}
    .code{
      margin-top:10px;
      border:2px dashed var(--line);
      border-radius:12px;
      padding:10px;
      background:#0b1220;
      font-family:var(--mono);
      font-size:12px;
      color:var(--muted);
      white-space:pre;
      overflow:auto;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="top">
        <div>
          <h1 id="scenarioName">Scenario Name</h1>
          <div class="subtitle" id="scenarioDesc">One-line description of the scenario. Keep it calm and readable.</div>
          <div class="chips" id="tagChips"></div>
        </div>
        <div class="meta">
          <div class="pill" id="severityPill">Severity: HIGH</div>
          <div class="pill" id="coveragePill">Fixtures: 2/2 passing</div>
          <div class="pill mono" id="schemaVer">schema v1</div>
        </div>
      </div>

      <nav role="tablist" aria-label="Storyboard Tabs">
        <div class="tab" role="tab" aria-selected="true" data-tab="overview">Overview</div>
        <div class="tab" role="tab" aria-selected="false" data-tab="timeline">Timeline</div>
        <div class="tab" role="tab" aria-selected="false" data-tab="rules">Rules</div>
        <div class="tab" role="tab" aria-selected="false" data-tab="actions">Actions</div>
        <div class="tab" role="tab" aria-selected="false" data-tab="tests">Tests</div>
      </nav>
    </header>

    <main>
      <!-- OVERVIEW -->
      <section id="view-overview" class="grid two">
        <div class="card">
          <h2>Overview</h2>
          <div class="box" id="purposeBox">
            Purpose statement goes here: explain what this scenario is, why it matters, and what the user should do next.
          </div>

          <h3>Signals</h3>
          <ul id="signalsList"></ul>

          <h3>Rules evaluated</h3>
          <ul id="rulesListCompact"></ul>

          <h3>Recommended actions</h3>
          <ul id="actionsListCompact"></ul>
        </div>

        <div class="card">
          <h2>Summary</h2>
          <div class="kvs">
            <div class="k">Owner</div><div class="v" id="ownerField"></div>
            <div class="k">Severity</div><div class="v" id="severityField"></div>
            <div class="k">Techniques</div><div class="v" id="techniquesField"></div>
            <div class="k">Fixtures</div><div class="v" id="fixturesField"></div>
            <div class="k">Build</div><div class="v mono" id="buildField"></div>
          </div>

          <h3>Notes</h3>
          <div class="box" id="notesBox">
            This panel is ideal for constraints, assumptions, and “what good looks like”.
          </div>
        </div>
      </section>

      <!-- TIMELINE -->
      <section id="view-timeline" class="grid hidden">
        <div class="card">
          <h2>Timeline</h2>
          <div class="box">A chronological narrative: what was observed, in what order, with brief explanations.</div>
          <div id="timelineList" style="margin-top:12px; display:flex; flex-direction:column; gap:10px;"></div>
        </div>
      </section>

      <!-- RULES -->
      <section id="view-rules" class="grid hidden">
        <div class="card">
          <h2>Rules</h2>
          <div class="box">Each rule should be readable without YAML. Show match logic + plain-English explanation.</div>
          <div id="rulesFull" style="margin-top:12px; display:flex; flex-direction:column; gap:10px;"></div>
        </div>
      </section>

      <!-- ACTIONS -->
      <section id="view-actions" class="grid hidden">
        <div class="card">
          <h2>Actions</h2>
          <div class="box">Step-by-step checklists, calm wording, platform-neutral.</div>
          <div id="actionsFull" style="margin-top:12px; display:flex; flex-direction:column; gap:10px;"></div>
        </div>
      </section>

      <!-- TESTS -->
      <section id="view-tests" class="grid hidden">
        <div class="card">
          <h2>Tests</h2>
          <div class="box">Fixtures validate intent. They prevent regressions and build trust in community contributions.</div>
          <input id="fixtureSearch" class="input" placeholder="Search fixtures..." style="margin-top:10px; width:100%; padding:8px; border-radius:10px; border:2px solid var(--line);" />
          <div id="fixturesFull" style="margin-top:12px; display:flex; flex-direction:column; gap:10px;"></div>
        </div>
      </section>

      <div class="footer">
        <div>ScenarioKit • storyboard</div>
        <div class="mono" id="generatedAt"></div>
      </div>
    </main>
  </div>

  <script id="story-data" type="application/json">__STORY_DATA__</script>
  <script>__SCRIPT__</script>
</body>
</html>
"""#
