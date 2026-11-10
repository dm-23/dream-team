# HTML Output Template — Agent Team Reports

## When This Template Applies

**Whenever the user asks for a report, in any language and any phrasing.** "Generate a report", "make a
report", "I need a report on X", "write up the findings" — each of those is a request for the file described here, by
default and without further qualification. The user does not have to say "shareable", the findings do not
have to be long, and the workflow does not matter. The only thing that changes the outcome is the same
message naming a different form outright ("a short report in chat", "in Markdown", "put it in {path}"), which
overrides the format and the location while still owing the user a report.

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

## Where Each Output Goes

| Output type | Format | Location |
|-------------|--------|----------|
| Analysis report | HTML | `.dream-team-tracking/{context_id}/reports/{topic}.html` |
| Detailed plan presentation | HTML | `.dream-team-tracking/{context_id}/reports/plan-{slug}.html` |
| UX audit (Analyze) | HTML | `.dream-team-tracking/{context_id}/reports/ux-audit.html` |
| Architecture explanation | HTML | `.dream-team-tracking/{context_id}/reports/{topic}.html` |
| Review page (Review Changes) | HTML | `.dream-team-tracking/{context_id}/reports/review-{slug}.html` |
| Simple status / yes-no question | Chat text | — |
| Internal agent coordination | Markdown | `.dream-team-tracking/{context_id}/` |

**Plan page (Full Feature).** `reports/plan-{slug}.html` is a rendering of `plans/detailed-plan.md` and `tasks/*.md`, never a second source of truth; regenerate it whenever those files change before approval. Order of sections: overview and the decisions needed from the user; Public API Surface; batches, each task a collapsible card (description, files, contract, criteria, test cases, verify by hand); documentation obligations; simplicity justification; the audit's findings and the `## Audit response`; the plan path and the task paths. Dark theme, collapsibles, no frameworks, as every report.

**UX audit page (Analyze).** `reports/ux-audit.html` is a rendering of `reports/ux-audit.md`, never a second source of truth. Order of sections: the surface and the user tasks walked; the findings as one table, blocking first, with the evidence column kept; the state matrix; the order of work, each batch a collapsible card listing its findings and pages; out of scope; the audit path. Dark theme, collapsibles, no frameworks, as every report.

**Review page (Review Changes).** `reports/review-{slug}.html` is a rendering of `reports/review-findings.md` (or the merged `review-findings-{part}.md` files) written by the ChangeReviewer, never a second source of truth; the page is written in the task's language, the `Comment (EN)` text stays English. Use the tabs, findings table, detail and copy classes of the boilerplate. Order of sections:
1. Header: the title; the range (`base..head`) and the file and line counts from the run's `status.md → **Range:**` line, never from one part's pointer block; the branch names, the pull request link and the work item link when known, the date and the review focus from the run's `status.md` (its `**Range:**` line and the task) or the handoff.
2. Summary card: one stat tile per severity from the `Findings:` line (`.grid-3` and `.stat`), the requirements covered from `Intent coverage:`, the `Recommendation:` line, the `## Summary` paragraph as the assessment, the `Verification:` line (what ran, what did not and why), the knowledge used and what could not be assessed (from `Unverified:`).
3. Intent coverage: one table, requirement / status / evidence, from the `Intent coverage:` line and the findings that name a requirement.
4. Key changes: the `## Key changes` bullets, five to fifteen, with the main files; a Mermaid diagram only when the flow earns one.
5. Existing review threads, only when a pull request has any: thread / topic / its severity / status / our check / the finding it maps to, from the `Thread:` fields and the open threads in the handoff.
6. Findings: one tab per severity with its count (`.tabs`, `.tab`, `.cnt`), Critical first, empty severities left out, and the "expand all" and "collapse all" buttons (`.tab-x`). Each severity is a `.tabpane` holding a `table.findings`; each finding is a `tr.main` row (id `F-<n>`, severity badge, area from `Section`, the location, the `Issue` in one line with the `Why` under it as `.why`) followed by a `tr.det` row. The location is up to two links: on a GitHub remote, the host link `<https remote>/blob/<sha>/<path>#L<n>`, `<https remote>` the https form of `git config --get remote.origin.url` and `<sha>` the head of `**Range:**` (omitted when there is no remote or no head sha); on any other host, no host link; and an editor link `vscode://file/<absolute path>:<line>` only when the Decisions log says `Head checked out: yes`. With neither link, the location is a bare `path:line`. Before writing the page the orchestrator records the Verifier's vote on each voted finding as `verified: yes` or `verified: no — <the Verifier's reason>`. The row shows a `verified` badge for `yes`; for `no` it shows a `not verified` badge and the first detail block starts with the Verifier's reason, so a rejected finding stays visible; a finding the Verifier did not vote on (Medium and below, unless the focus asked) carries no badge. An `already raised` badge is shown when the `Thread:` field names a thread. The detail row (`.detail`) holds three `.blk` blocks: **Story and what happens** (`Story`, then `Explanation` with its lines; when a `Decision:` line exists, the quoted decision first), **Comment for the PR (EN)** (`Comment (EN)` in a `.prtext` element after a `button.copy`, and the location to attach it to) and **Required change** (`Required change`, with a `button.copy` when the finding carries a snippet, coloured with `.da`, `.dd` and `.dh` when it is a diff).
   Markup contract of the Findings section, which the script depends on: each tab is `<button class="tab" onclick="showTab('critical', this)">Critical <span class="cnt">2</span></button>` and its pane is `<div class="tabpane" data-tab="critical">`, where the `data-tab` value is the lowercase severity and equals the first argument of `showTab`; the two `.tab-x` buttons are `onclick="expandAll(true)"` and `onclick="expandAll(false)"`; every finding is `<tr class="main" onclick="toggleRow(this)">` with its `<tr class="det"><td colspan="N"><div class="detail">...</div></td></tr>` directly after it, nothing between the two rows; a `button.copy` carries `onclick="copyNext(this)"` and sits immediately before the element whose text it copies. Initial state: the first tab (Critical, or the first severity that has findings) carries `class="tab active"`, its pane shows, and every other `.tabpane` starts with `style="display:none"`.
7. Order of work: the blocking findings first, that is every Critical and High whatever the vote (a rejected one keeps its `not verified` badge), then Medium, then Low grouped by file, each as an ordered list item with the finding ids.
8. Tests: the `## Tests` paragraph.
9. Out of scope: the `Out of scope:` line, candidates for a separate run.
10. Unverified: the `Unverified:` line in full.
11. The paths of the findings files, as `<code>` elements.

**Several parts.** When the review ran in parts, the page shows each part's `## Summary`, `## Key changes` and `## Tests` under the part's name, in the parts' logged order (sections 2, 4 and 8). The per-severity counts and `Intent coverage` are summed across the parts' pointer blocks: a copy marked `- Merged into:` is not counted again, so the counts are those of the Decisions log's `Consolidated:` line, and a requirement covered in any part counts once as covered.

Dark theme, collapsibles, no frameworks, as every report.

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

        /* Review page: stat tiles */
        .grid-3 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; }
        @media (max-width: 900px) { .grid-3 { grid-template-columns: 1fr 1fr; } }
        .stat { background: var(--surface2); border-radius: 10px; padding: 1rem; text-align: center; }
        .stat .n { font-size: 2rem; font-weight: 700; }
        .why { color: var(--text-muted); margin-top: 0.35rem; font-size: 0.82rem; }
        .nowrap { white-space: nowrap; }

        /* Review page: severity tabs */
        .tabs { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-bottom: 0.75rem; align-items: center; }
        .tabs .tab { background: var(--surface2); color: var(--text); border: 1px solid var(--border); border-radius: 8px 8px 0 0; padding: 0.45rem 1rem; cursor: pointer; font-weight: 600; }
        .tabs .tab.active { border-color: var(--accent); color: var(--accent); background: var(--surface); }
        .tabs .cnt { display: inline-block; min-width: 1.4rem; padding: 0 0.35rem; margin-left: 0.3rem; border-radius: 10px; background: var(--bg); color: var(--text-muted); font-size: 0.75rem; }
        .tabs .tab-x { margin-left: auto; background: none; border: 1px solid var(--border); color: var(--text-muted); border-radius: 6px; padding: 0.25rem 0.6rem; cursor: pointer; font-size: 0.75rem; }
        .tabs .tab-x + .tab-x { margin-left: 0; }

        /* Review page: expandable findings */
        table.findings tr.main { cursor: pointer; }
        table.findings tr.main:hover td { background: rgba(88,166,255,0.05); }
        .chev { display: inline-block; font-size: 0.65rem; color: var(--text-muted); transition: transform 0.15s; }
        tr.main.open .chev { transform: rotate(90deg); }
        tr.det { display: none; }
        tr.det.open { display: table-row; }
        tr.det > td { background: var(--bg); padding: 0; }
        .detail { padding: 1rem 1.25rem 1.25rem 2.2rem; display: grid; gap: 1rem; }
        .blk h4 { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--cyan); margin-bottom: 0.4rem; }
        .prtext { white-space: pre-wrap; font-size: 0.8rem; background: var(--surface2); border: 1px solid var(--border); border-radius: 6px; padding: 0.5rem; }
        button.copy { float: right; background: var(--surface2); color: var(--text-muted); border: 1px solid var(--border); border-radius: 5px; font-size: 0.7rem; padding: 0.1rem 0.45rem; cursor: pointer; margin: 0 0 0.25rem 0.4rem; }
        button.copy:hover { color: var(--accent); border-color: var(--accent); }
        pre.code { white-space: pre; overflow-x: auto; font-size: 0.74rem; line-height: 1.45; background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 0.5rem; max-height: 420px; }
        .da { color: var(--accent2); background: rgba(63,185,80,0.08); display: inline-block; width: 100%; }
        .dd { color: var(--danger); background: rgba(248,81,73,0.08); display: inline-block; width: 100%; }
        .dh { color: var(--purple); }
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

        // Review page: findings rows, severity tabs, copy buttons
        function toggleRow(tr) { tr.classList.toggle('open'); tr.nextElementSibling.classList.toggle('open'); }
        function showTab(name, btn) {
            document.querySelectorAll('.tabs .tab').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            document.querySelectorAll('.tabpane').forEach(p => p.style.display = p.dataset.tab === name ? '' : 'none');
        }
        function expandAll(open) {
            document.querySelectorAll('.tabpane').forEach(p => {
                if (p.style.display === 'none') return;
                p.querySelectorAll('tr.main').forEach(tr => {
                    tr.classList.toggle('open', open);
                    tr.nextElementSibling.classList.toggle('open', open);
                });
            });
        }
        function copyNext(btn) {
            const t = btn.nextElementSibling;
            navigator.clipboard.writeText(t.innerText).then(() => {
                const o = btn.textContent; btn.textContent = 'copied';
                setTimeout(() => btn.textContent = o, 1200);
            });
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
