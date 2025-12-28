import Foundation

enum HTMLTemplate {
    static func render(title: String, mermaid: String, reportJSON: String, summary: ReportRenderer.ReportSummary, issues: [ScenarioIssue], mermaidScript: String) -> String {
        let escapedJSON = reportJSON.replacingOccurrences(of: "</script>", with: "<\\/script>")
        let validationSection: String
        if issues.isEmpty {
            validationSection = "<p class=\"muted\">No validation issues.</p>"
        } else {
            let body = issues.map { issue -> String in
                let icon = issue.severity == .error ? "✖" : "⚠︎"
                return "<li>\(icon) \(escapeHTML(issue.message))</li>"
            }.joined()
            validationSection = "<ul>\(body)</ul>"
        }

        let topDeps = summary.topDependencies.map { "<li>\(escapeHTML($0.name)) (\($0.count))</li>" }.joined()
        let topDependents = summary.topDependents.map { "<li>\(escapeHTML($0.name)) (\($0.count))</li>" }.joined()

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(escapeHTML(title))</title>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f7f8fa;color:#111827;margin:0;padding:20px;}
        h1{margin:0 0 10px 0;}
        .card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:16px;margin-bottom:12px;box-shadow:0 8px 18px rgba(0,0,0,0.05);}
        .muted{color:#6b7280;}
        ul{padding-left:18px;}
        .pill{display:inline-block;padding:4px 10px;border-radius:999px;border:1px solid #d1d5db;color:#374151;background:#f9fafb;margin-right:6px;font-size:13px;}
        .mermaid{border:1px solid #e5e7eb;border-radius:12px;padding:12px;background:#f9fafb;overflow:auto;}
        </style>
        </head>
        <body>
        <div class="card">
          <h1>\(escapeHTML(title))</h1>
          <div class="pill">Services: \(summary.topDependencies.count + summary.topDependents.count)</div>
        </div>
        <div class="card">
          <h2>Validation</h2>
          \(validationSection)
        </div>
        <div class="card">
          <h2>Top dependencies</h2>
          <ul>\(topDeps)</ul>
          <h2>Top dependents</h2>
          <ul>\(topDependents)</ul>
        </div>
        <div class="card">
          <h2>Dependency graph</h2>
          <div class="mermaid">\(escapeHTML(mermaid))</div>
        </div>
        <script>\(mermaidScript)</script>
        <script id="story-data" type="application/json">\(escapedJSON)</script>
        <script>
        const graphDef = `\(escapeJS(mermaid))`;
        if (window.mermaid && mermaid.render){
          mermaid.render("graph", graphDef, (svg) => {
            document.querySelector(".mermaid").innerHTML = svg;
          });
        }
        </script>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
    }
}
