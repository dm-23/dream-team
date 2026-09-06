# HTML Output Template — Agent Team Reports

All user-facing outputs (plans, specs, analysis reports, explanations) are self-contained HTML files.
Internal artifacts (`status.md`, `draft-plan.md`, `task-*.md`, `*-exploration.md`) stay as Markdown.

**Never publish these HTML reports via the Artifact tool.** Write the file locally to the path in the
table below and give the user that file path/link in chat — nothing more. The user explicitly rejected
cloud Artifact publishing for this project: it costs the same or more (an extra tool call on top of the
`Write`), and it pushes content off the local machine onto claude.ai hosting, which matters here because
reports can contain NDA-covered third-party material and internal architecture detail. Because local
files aren't run under Artifact's CSP, CDN-hosted JS libraries (Mermaid, Chart.js — see below) work
normally when the user opens the file in a real browser; no need to hand-roll diagrams in CSS to dodge
CSP restrictions that don't apply here.

## When to Produce HTML

| Output type | Format | Location |
|-------------|--------|----------|
| Analysis report | HTML | `.claude-tracking/{context_id}/reports/{topic}.html` |
| Detailed plan presentation | HTML | `.claude-tracking/{context_id}/reports/plan-{feature}.html` |
| Architecture explanation | HTML | `.claude-tracking/{context_id}/reports/{topic}.html` |
| Simple status / yes-no question | Chat text | — |
| Internal agent coordination | Markdown | `.claude-tracking/{context_id}/` |

## JS Libraries (CDN — no install)

### Mermaid.js — Diagrams & Flowcharts
```html
<script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
<script>mermaid.initialize({ startOnLoad: true, theme: 'dark' });</script>
```

Usage:
```html
<pre class="mermaid">
graph TD
    A[Controller] --> B[Service]
    B --> C[DAL / DbContext]
    B --> D[External API]
</pre>
```

Supports: flowchart, sequence, class, ER, state, Gantt, pie, mindmap, timeline.

### Chart.js — Data Charts
```html
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
```

Usage:
```html
<canvas id="myChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('myChart'), {
    type: 'bar', // bar, line, pie, doughnut, radar, polarArea
    data: {
        labels: ['Label1', 'Label2', 'Label3'],
        datasets: [{
            label: 'Dataset',
            data: [12, 19, 3],
            backgroundColor: ['rgba(88,166,255,0.6)', 'rgba(63,185,80,0.6)', 'rgba(188,140,255,0.6)']
        }]
    },
    options: {
        plugins: { legend: { labels: { color: '#e6edf3' } } },
        scales: { y: { ticks: { color: '#8b949e' }, grid: { color: '#2d3a47' } }, x: { ticks: { color: '#8b949e' }, grid: { color: '#2d3a47' } } }
    }
});
</script>
```

## HTML Boilerplate

```html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{Report Title}</title>
    <style>
        :root {
            --bg: #0f1419;
            --surface: #1a2028;
            --surface2: #242d38;
            --border: #2d3a47;
            --text: #e6edf3;
            --text-muted: #8b949e;
            --accent: #58a6ff;
            --accent2: #3fb950;
            --warning: #d29922;
            --danger: #f85149;
            --purple: #bc8cff;
            --cyan: #39c5cf;
            --orange: #f0883e;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.6;
            padding: 2rem;
        }

        .container { max-width: 1200px; margin: 0 auto; }

        h1 {
            font-size: 2rem;
            margin-bottom: 0.5rem;
            background: linear-gradient(135deg, var(--accent), var(--purple));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }

        .subtitle { color: var(--text-muted); font-size: 0.95rem; margin-bottom: 2rem; }

        .card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 1.5rem;
            margin-bottom: 1.5rem;
        }

        .card:hover { border-color: var(--accent); }

        .card-header {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            margin-bottom: 1rem;
        }

        .card-header h2 { font-size: 1.25rem; }

        table { width: 100%; border-collapse: collapse; font-size: 0.88rem; }
        th, td { padding: 0.6rem 1rem; text-align: left; border-bottom: 1px solid var(--border); }
        th { background: var(--surface2); color: var(--text-muted); font-weight: 600; font-size: 0.78rem; text-transform: uppercase; }

        code { background: var(--surface2); padding: 0.15rem 0.4rem; border-radius: 4px; font-size: 0.82rem; color: var(--cyan); }

        .badge {
            display: inline-block; padding: 0.2rem 0.6rem; border-radius: 6px;
            font-size: 0.7rem; font-weight: 600; text-transform: uppercase;
        }
        .badge-blue { background: rgba(88,166,255,0.15); color: var(--accent); }
        .badge-green { background: rgba(63,185,80,0.15); color: var(--accent2); }
        .badge-yellow { background: rgba(210,153,34,0.15); color: var(--warning); }
        .badge-red { background: rgba(248,81,73,0.15); color: var(--danger); }
        .badge-purple { background: rgba(188,140,255,0.15); color: var(--purple); }

        /* Collapsible */
        .collapsible { cursor: pointer; user-select: none; display: flex; align-items: center; gap: 0.5rem; }
        .collapsible::before { content: '▶'; font-size: 0.7rem; transition: transform 0.2s; color: var(--text-muted); }
        .collapsible.open::before { transform: rotate(90deg); }
        .collapse-content { display: none; padding-top: 0.75rem; }
        .collapse-content.open { display: block; }

        /* Grid */
        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; }
        @media (max-width: 900px) { .grid-2 { grid-template-columns: 1fr; } }

        /* Mermaid dark background */
        .mermaid { background: var(--surface2); padding: 1rem; border-radius: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>{Icon} {Title}</h1>
        <p class="subtitle">{Context description} — {Date}</p>

        <!-- Content cards here -->
        <div class="card">
            <div class="card-header">
                <h2>{Section Title}</h2>
            </div>
            <!-- Content: tables, lists, Mermaid diagrams, Chart.js canvases -->
        </div>

        <!-- Mermaid diagram example -->
        <div class="card">
            <div class="card-header"><h2>Architecture</h2></div>
            <pre class="mermaid">
graph TD
    A[User Request] --> B[Controller]
    B --> C[Service Layer]
    C --> D[DbContext]
            </pre>
        </div>
    </div>

    <!-- Libraries -->
    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
    <script>mermaid.initialize({ startOnLoad: true, theme: 'dark' });</script>
    <!-- <script src="https://cdn.jsdelivr.net/npm/chart.js"></script> --><!-- uncomment if charts needed -->

    <script>
        // Collapsible toggle
        function toggleCollapse(el) {
            el.classList.toggle('open');
            el.nextElementSibling.classList.toggle('open');
        }
    </script>
</body>
</html>
```

## Design Rules

1. **Self-contained** — single `.html` file, no external CSS, all styles in `<style>`
2. **Dark theme** — use CSS variables from boilerplate (matches team aesthetic)
3. **Interactive** — collapsible sections for detailed content, tabs for multiple views if 3+ sections
4. **Diagrams** — use Mermaid for architecture, flow, sequence; Chart.js only if numeric data
5. **Responsive** — grid-2 for desktop, single column for mobile
6. **Accessible** — proper headings, table headers, sufficient contrast
7. **No frameworks** — vanilla JS only (no React, no Vue in reports)
