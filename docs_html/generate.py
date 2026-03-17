#!/usr/bin/env python3
"""Generate syncitron HTML documentation site."""
import os, html as H

OUT = os.path.dirname(os.path.abspath(__file__))

# ── Navigation structure ─────────────────────────────────────────────────────
NAV = [
    ("GETTING STARTED", [
        ("index.html",       "🏠", "Home"),
        ("getting-started.html","🚀", "Quick Start"),
        ("architecture.html","🏗️", "Architecture"),
    ]),
    ("CORE CONCEPTS", [
        ("sync-engine.html", "⚙️", "Sync Engine"),
        ("sync-conflicts.html","🔀", "Conflict Resolution"),
        ("configuration.html","🎛️", "Configuration"),
        ("error-handling.html","🛡️", "Error Handling"),
        ("metrics-logging.html","📊", "Metrics & Logging"),
    ]),
    ("REMOTE BACKENDS", [
        ("backend-supabase.html","💜", "Supabase"),
        ("backend-firebase.html","🔶", "Firebase Firestore"),
        ("backend-appwrite.html","🌍", "Appwrite"),
        ("backend-graphql.html","◼️", "GraphQL"),
    ]),
    ("LOCAL STORAGE", [
        ("storage-sqflite.html","🗄️", "SQLite (sqflite)"),
        ("storage-drift.html","🔐", "Drift"),
        ("storage-hive.html","📦", "Hive"),
        ("storage-isar.html","⚡", "Isar"),
    ]),
    ("ADVANCED", [
        ("orchestration.html","🎭", "Sync Orchestration"),
        ("realtime.html",    "📡", "Real-Time Sync"),
        ("widgets.html",     "🎨", "UI Widgets"),
        ("multi-engine.html","🔗", "Multi-Engine"),
        ("diagnostics.html", "🔍", "Health & Diagnostics"),
        ("testing.html",     "🧪", "Testing"),
    ]),
    ("REFERENCE", [
        ("api-reference.html","📖", "API Reference"),
        ("changelog.html",  "📋", "Changelog"),
    ]),
]

FLAT = []
for _, items in NAV:
    for href, _, title in items:
        FLAT.append((href, title))

def sidebar_html(active_href):
    s = ""
    for section, items in NAV:
        s += '<div class="section-title">' + section + '</div>\n'
        for href, icon, title in items:
            cls = ' class="active"' if href == active_href else ""
            s += '<a href="' + href + '"' + cls + '><span class="icon">' + icon + '</span>' + title + '</a>\n'
    return s

def prev_next(href):
    idx = next((i for i,(h,_) in enumerate(FLAT) if h==href), -1)
    p = FLAT[idx-1] if idx>0 else None
    n = FLAT[idx+1] if idx<len(FLAT)-1 else None
    h = '<div class="page-nav">'
    if p:
        h += '<a href="' + p[0] + '"><div class="label">← Previous</div><div class="title">' + p[1] + '</div></a>'
    else:
        h += '<span></span>'
    if n:
        h += '<a href="' + n[0] + '" class="next"><div class="label">Next →</div><div class="title">' + n[1] + '</div></a>'
    h += '</div>'
    return h

def page(filename, title, body, subtitle=""):
    sub = '<p style="opacity:.75;font-size:.9rem;margin-top:-.5rem">' + subtitle + '</p>' if subtitle else ""
    return (
        '<!DOCTYPE html>\n<html lang="en">\n<head>\n'
        '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">\n'
        '<title>' + title + ' — syncitron Docs</title>\n'
        '<link rel="stylesheet" href="assets/style.css">\n'
        '<script src="assets/app.js"></script>\n'
        '<script src="assets/search.js"></script>\n'
        '</head>\n<body>\n'
        '<div class="topbar">\n'
        '  <button class="hamburger" onclick="toggleSidebar()">☰</button>\n'
        '  <div class="logo">syncitron <span>v0.5.1 Docs</span></div>\n'
        '  <div class="spacer"></div>\n'
        '  <button class="search-trigger" onclick="openSearch()">🔍 Search <kbd>⌘K</kbd></button>\n'
        '  <button id="theme-btn" onclick="toggleDark()">🌙 Dark</button>\n'
        '</div>\n'
        '<div id="search-overlay">\n'
        '  <div class="search-modal">\n'
        '    <div class="search-header">\n'
        '      <input id="search-input" type="text" placeholder="Search docs…" autocomplete="off">\n'
        '      <button id="search-close">Esc</button>\n'
        '    </div>\n'
        '    <div id="search-results"></div>\n'
        '  </div>\n'
        '</div>\n'
        '<div class="page">\n'
        '<nav class="sidebar">' + sidebar_html(filename) + '</nav>\n'
        '<main class="content">\n'
        '<h1>' + title + '</h1>\n'
        + sub +
        body +
        prev_next(filename) + '\n'
        '<div class="footer">syncitron v0.5.1 — Enterprise Local-First Sync for Flutter &middot; MIT License</div>\n'
        '</main>\n</div>\n</body></html>'
    )

def code(lang, src):
    return '<pre><code class="language-' + lang + '">' + H.escape(src.strip()) + '</code></pre>'

def dart(src): return code("dart", src)
def yaml(src): return code("yaml", src)
def sql(src):  return code("sql", src)
def bash(src): return code("bash", src)

def callout(kind, text):
    icons = {"info":"ℹ️","warn":"⚠️","danger":"🚫","success":"✅"}
    ic = icons.get(kind, "💡")
    return '<div class="callout callout-' + kind + '"><span class="icon">' + ic + '</span><div>' + text + '</div></div>'

def tbl(headers, rows):
    h = '<table><thead><tr>' + ''.join('<th>' + c + '</th>' for c in headers) + '</tr></thead><tbody>'
    for row in rows:
        h += '<tr>' + ''.join('<td>' + c + '</td>' for c in row) + '</tr>'
    h += '</tbody></table>'
    return h

def write(filename, title, body, subtitle=""):
    with open(os.path.join(OUT, filename), "w") as f:
        f.write(page(filename, title, body, subtitle))
    print("  ✓ " + filename)

# ═══════════════════════════════════════════════════════════════════════════════
print("Generating syncitron documentation…")

# ── 1. HOME ──────────────────────────────────────────────────────────────────
write("index.html", "syncitron Documentation",
'<p style="font-size:1.15rem;color:var(--c-text-muted);margin-bottom:2rem">'
'Enterprise-grade local-first synchronization framework for Flutter.<br>'
'Build offline-capable apps with automatic sync, conflict resolution, and comprehensive monitoring.'
'</p>'

'<div class="feature-grid">'
'<div class="feature"><div class="emoji">🔌</div><h4>Pluggable Backends</h4><p>Supabase, Firebase, Appwrite, or any GraphQL server</p></div>'
'<div class="feature"><div class="emoji">📱</div><h4>True Offline-First</h4><p>Full functionality offline, seamless sync when connected</p></div>'
'<div class="feature"><div class="emoji">🧠</div><h4>Smart Conflicts</h4><p>ServerWins, LocalWins, LastWriteWins, or Custom strategies</p></div>'
'<div class="feature"><div class="emoji">⚡</div><h4>Batch Operations</h4><p>50-100× faster syncs — eliminates the N+1 problem</p></div>'
'<div class="feature"><div class="emoji">📊</div><h4>Observability</h4><p>Structured logging, metrics, and health checks</p></div>'
'<div class="feature"><div class="emoji">🛡️</div><h4>Error Recovery</h4><p>Sealed exception hierarchy with retry and backoff</p></div>'
'<div class="feature"><div class="emoji">🎨</div><h4>Ready-made Widgets</h4><p>6 Flutter widgets for sync status, errors, and metrics</p></div>'
'<div class="feature"><div class="emoji">📡</div><h4>Real-Time</h4><p>Event-driven sync with all four backends</p></div>'
'</div>'

'<h2>Quick Install</h2>'
+ bash("flutter pub add syncitron") +

'<h2>Minimal Example</h2>'
+ dart(
"import 'package:syncitron/syncitron.dart';\n"
"import 'package:sqflite/sqflite.dart';\n"
"import 'package:supabase_flutter/supabase_flutter.dart';\n\n"
"final engine = SyncEngine(\n"
"  localStore:    SqfliteStore(database, conflictAlgorithm: ConflictAlgorithm.replace),\n"
"  remoteAdapter: SupabaseAdapter(\n"
"    client: supabaseClient,\n"
"    localStore: sqfliteStore,\n"
"    postgresChangeEventAll: PostgresChangeEvent.all,\n"
"  ),\n"
"  config:        syncitronConfig.production(),\n"
"  logger:        ConsoleLogger(),\n"
");\n\n"
"engine.registerTable(TableConfig(\n"
"  name: 'todos',\n"
"  columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],\n"
"  strategy: SyncStrategy.lastWriteWins,\n"
"));\n\n"
"await engine.init();\n"
"final metrics = await engine.syncAll();\n"
"print(metrics.overallSuccess); // true"
) +

'<h2>Documentation Map</h2>'
+ tbl(["Section","Contents"], [
  ["<a href='getting-started.html'>Quick Start</a>", "Install, configure, sync in 5 minutes"],
  ["<a href='architecture.html'>Architecture</a>", "Engine, stores, adapters, data flow"],
  ["<a href='sync-engine.html'>Sync Engine</a>", "Core API: init, syncAll, syncTable, registerTable"],
  ["<a href='sync-conflicts.html'>Conflict Resolution</a>", "4 strategies with examples"],
  ["<a href='configuration.html'>Configuration</a>", "syncitronConfig presets and custom tuning"],
  ["<a href='error-handling.html'>Error Handling</a>", "Sealed exception hierarchy"],
  ["<a href='metrics-logging.html'>Metrics &amp; Logging</a>", "SyncMetrics, Loggers, MetricsCollector"],
  ["Backends", "<a href='backend-supabase.html'>Supabase</a> · <a href='backend-firebase.html'>Firebase</a> · <a href='backend-appwrite.html'>Appwrite</a> · <a href='backend-graphql.html'>GraphQL</a>"],
  ["Storage", "<a href='storage-sqflite.html'>SQLite</a> · <a href='storage-drift.html'>Drift</a> · <a href='storage-hive.html'>Hive</a> · <a href='storage-isar.html'>Isar</a>"],
  ["<a href='orchestration.html'>Orchestration</a>", "5 built-in sync strategies for advanced flows"],
  ["<a href='realtime.html'>Real-Time</a>", "Event-driven sync with auto-reconnect"],
  ["<a href='widgets.html'>UI Widgets</a>", "6 ready-made Flutter widgets"],
  ["<a href='api-reference.html'>API Reference</a>", "Complete class/method reference"],
])
)

# ── 2. GETTING STARTED ───────────────────────────────────────────────────────
write("getting-started.html", "Quick Start",
'<p>Get your first offline-first sync running in under 5 minutes.</p>'

'<div class="toc"><h4>On this page</h4><ul>'
'<li><a href="#install">1. Installation</a></li>'
'<li><a href="#setup-db">2. Set Up Local Database</a></li>'
'<li><a href="#create-engine">3. Create Sync Engine</a></li>'
'<li><a href="#register">4. Register Tables</a></li>'
'<li><a href="#sync">5. Sync</a></li>'
'<li><a href="#whats-next">What\'s Next</a></li>'
'</ul></div>'

'<h2 id="install">1. Installation</h2>'
+ bash("flutter pub add syncitron") +
'<p>Or add manually to <code>pubspec.yaml</code>:</p>'
+ yaml(
"dependencies:\n"
"  syncitron: ^0.5.1\n"
"  sqflite: ^2.4.2            # local store (user dependency)\n"
"  supabase_flutter: ^2.12.0  # remote backend (user dependency)"
) +
callout("info", "syncitron has <strong>zero third-party dependencies</strong>. All backend packages (Supabase, Firebase, Appwrite, GraphQL) and local stores (sqflite, Drift, Hive, Isar) are optional — add only the ones you actually use to your own <code>pubspec.yaml</code>.") +

'<h2 id="setup-db">2. Set Up Local Database</h2>'
+ dart(
"import 'package:sqflite/sqflite.dart';\n"
"import 'package:path/path.dart';\n\n"
"final db = await openDatabase(\n"
"  join(await getDatabasesPath(), 'myapp.db'),\n"
"  version: 1,\n"
"  onCreate: (db, version) async {\n"
"    await db.execute(\n"
"      'CREATE TABLE todos ('\n"
"      '  id TEXT PRIMARY KEY,'\n"
"      '  title TEXT NOT NULL,'\n"
"      '  completed INTEGER DEFAULT 0,'\n"
"      '  updated_at TEXT,'\n"
"      '  deleted_at TEXT'\n"
"      ')'\n"
"    );\n"
"  },\n"
");"
) +
callout("info", "syncitron automatically adds <code>is_synced</code> and <code>op_id</code> columns via <code>ensureSyncColumns()</code> during <code>engine.init()</code>. You do not need to create them manually.") +

'<h2 id="create-engine">3. Create the Sync Engine</h2>'
+ dart(
"import 'package:syncitron/syncitron.dart';\n"
"import 'package:sqflite/sqflite.dart';\n"
"import 'package:supabase_flutter/supabase_flutter.dart';\n\n"
"final localStore = SqfliteStore(db, conflictAlgorithm: ConflictAlgorithm.replace);\n\n"
"final remoteAdapter = SupabaseAdapter(\n"
"  client: Supabase.instance.client,\n"
"  localStore: localStore,\n"
"  postgresChangeEventAll: PostgresChangeEvent.all,\n"
"  isAuthException: (e) => e is AuthException,\n"
");\n\n"
"final engine = SyncEngine(\n"
"  localStore:       localStore,\n"
"  remoteAdapter:    remoteAdapter,\n"
"  config:           syncitronConfig.production(),\n"
"  logger:           ConsoleLogger(minLevel: LogLevel.info),\n"
"  metricsCollector: InMemoryMetricsCollector(),\n"
");"
) +

'<h2 id="register">4. Register Tables</h2>'
+ dart(
"engine\n"
"  .registerTable(TableConfig(\n"
"    name: 'todos',\n"
"    columns: ['id', 'title', 'completed', 'updated_at', 'deleted_at'],\n"
"    strategy: SyncStrategy.lastWriteWins,\n"
"  ))\n"
"  .registerTable(TableConfig(\n"
"    name: 'projects',\n"
"    columns: ['id', 'name', 'updated_at', 'deleted_at'],\n"
"    strategy: SyncStrategy.serverWins,\n"
"  ));"
) +
callout("warn", "<code>registerTable()</code> must be called <strong>before</strong> <code>engine.init()</code>. The method returns the engine so you can chain calls.") +

'<h2 id="sync">5. Sync!</h2>'
+ dart(
"await engine.init();                    // idempotent — safe to call multiple times\n"
"final metrics = await engine.syncAll(); // pull + push all registered tables\n\n"
"print('Success: ${metrics.overallSuccess}');\n"
"print('Pulled:  ${metrics.totalRecordsPulled}');\n"
"print('Pushed:  ${metrics.totalRecordsPushed}');"
) +

'<h2 id="whats-next">What\'s Next</h2>'
'<ul>'
'<li><a href="architecture.html">Architecture Overview</a> — understand the data flow</li>'
'<li><a href="sync-conflicts.html">Conflict Resolution</a> — pick the right strategy</li>'
'<li><a href="configuration.html">Configuration</a> — tune batch size, retries, timeouts</li>'
'<li><a href="widgets.html">UI Widgets</a> — drop-in sync status &amp; error widgets</li>'
'</ul>',
subtitle="Your first offline-first sync in 5 minutes"
)

# ── 3. ARCHITECTURE ──────────────────────────────────────────────────────────
write("architecture.html", "Architecture",
'<p>syncitron follows a clean, layered architecture with dependency injection throughout.</p>'

'<h2>High-Level Data Flow</h2>'
'<pre><code>'
'┌─────────────────────────────────────────────────────────┐\n'
'│                     Your Flutter App                     │\n'
'│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │\n'
'│  │ UI Widgets   │  │  Your Code   │  │  State Mgmt   │  │\n'
'│  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘  │\n'
'│         └─────────────────┼──────────────────┘           │\n'
'│                           ▼                              │\n'
'│  ┌─────────────────── SyncEngine ───────────────────┐    │\n'
'│  │  registerTable() · syncAll() · syncTable()       │    │\n'
'│  │  statusStream · conflict resolution · retry      │    │\n'
'│  └────────────┬────────────────────┬────────────────┘    │\n'
'│               ▼                    ▼                     │\n'
'│  ┌────────────────┐   ┌─────────────────────┐           │\n'
'│  │   LocalStore   │   │   RemoteAdapter     │           │\n'
'│  │ (sqflite/drift │   │ (supabase/firebase/ │           │\n'
'│  │  hive/isar)    │   │  appwrite/graphql)  │           │\n'
'│  └────────┬───────┘   └──────────┬──────────┘           │\n'
'│           ▼                      ▼                      │\n'
'│     Local SQLite/NoSQL      Remote Backend              │\n'
'└─────────────────────────────────────────────────────────┘'
'</code></pre>'

'<h2>Core Components</h2>'

'<h3>SyncEngine</h3>'
'<p>The central orchestrator. It coordinates pulling data from the remote backend, pushing local changes, resolving conflicts, and emitting status updates. All sync operations go through the engine.</p>'

'<h3>LocalStore (Abstract)</h3>'
'<p>Handles all local persistence: reading/writing sync cursors, querying dirty (unsynced) records, upserting batches, and marking records as synced. Four implementations are provided:</p>'
+ tbl(["Store","Backing","Best For"], [
  ["<code>SqfliteStore</code>","SQLite","Production — battle-tested, 100K+ records"],
  ["<code>DriftStore</code>","SQLite (typed)","Type safety, reactive streams, code gen"],
  ["<code>HiveStore</code>","Hive (NoSQL)","Fast prototyping, small datasets"],
  ["<code>IsarStore</code>","Isar (NoSQL)","High-performance mobile, encryption"],
]) +

'<h3>RemoteAdapter (Abstract)</h3>'
'<p>Handles all remote communication: pulling pages of records, upserting, and soft deleting. Each adapter also provides optional real-time subscription support.</p>'
+ tbl(["Adapter","Backend","Real-Time"], [
  ["<code>SupabaseAdapter</code>","Supabase (PostgreSQL)","✅ via WebSocket LISTEN/NOTIFY"],
  ["<code>FirebaseFirestoreAdapter</code>","Cloud Firestore","✅ via Snapshot listeners"],
  ["<code>AppwriteAdapter</code>","Appwrite","✅ via RealtimeService"],
  ["<code>GraphQLAdapter</code>","Any GraphQL server","✅ via Subscriptions"],
]) +

'<h3>syncitronConfig</h3>'
'<p>Immutable configuration controlling batch sizes, retry policies, timeouts, and feature flags. Three presets: <code>production()</code>, <code>development()</code>, <code>testing()</code>.</p>'

'<h3>TableConfig</h3>'
'<p>Per-table configuration specifying column mappings, sync strategy, and optional custom conflict resolver.</p>'

'<h2>Sync Cycle</h2>'
'<ol>'
'<li><strong>Init</strong> — <code>engine.init()</code> ensures sync columns (<code>is_synced</code>, <code>op_id</code>) exist in the local database.</li>'
'<li><strong>Pull</strong> — Fetches remote records modified since the last cursor, using keyset pagination. Conflicts are detected and resolved per the table\'s strategy.</li>'
'<li><strong>Push</strong> — Queries local dirty records (<code>is_synced = 0</code>), assigns idempotent operation IDs, then batch-upserts/deletes to the remote backend.</li>'
'<li><strong>Mark Synced</strong> — Successfully pushed records are marked <code>is_synced = 1</code> locally.</li>'
'<li><strong>Cursor Update</strong> — The sync cursor is advanced to the latest <code>updated_at</code> timestamp.</li>'
'</ol>'
+ callout("success", "All sync operations are <strong>idempotent</strong>. The operation ID (<code>op_id</code>) prevents duplicate writes even if the network fails mid-push and the engine retries.") +

'<h2>Dependency Graph</h2>'
'<pre><code>'
'SyncEngine\n'
'  ├── LocalStore          (required)\n'
'  ├── RemoteAdapter       (required)\n'
'  ├── syncitronConfig     (optional — defaults to syncitronConfig())\n'
'  ├── Logger              (optional — defaults to ConsoleLogger())\n'
'  └── MetricsCollector    (optional — defaults to InMemoryMetricsCollector())'
'</code></pre>',
subtitle="How syncitron is structured"
)

# ── 4. SYNC ENGINE ───────────────────────────────────────────────────────────
write("sync-engine.html", "Sync Engine",
'<p>The <code>SyncEngine</code> is the central class of syncitron. It orchestrates pulling, pushing, conflict resolution, metrics, and status updates.</p>'

'<h2>Constructor</h2>'
+ dart(
"SyncEngine({\n"
"  required LocalStore localStore,\n"
"  required RemoteAdapter remoteAdapter,\n"
"  syncitronConfig? config,            // default: syncitronConfig()\n"
"  Logger? logger,                     // default: ConsoleLogger()\n"
"  MetricsCollector? metricsCollector,  // default: InMemoryMetricsCollector()\n"
"})"
) +

'<h2>Public API</h2>'
+ tbl(["Method","Returns","Description"], [
  ["<code>init()</code>","<code>Future&lt;void&gt;</code>","Ensures sync columns exist. Idempotent — safe to call repeatedly."],
  ["<code>registerTable(TableConfig)</code>","<code>SyncEngine</code>","Registers a table. Returns <code>this</code> for chaining. Must be called before <code>init()</code>."],
  ["<code>syncAll()</code>","<code>Future&lt;SyncSessionMetrics&gt;</code>","Pull + push all registered tables. Skips if sync is already running."],
  ["<code>syncTable(TableConfig)</code>","<code>Future&lt;SyncMetrics&gt;</code>","Sync a single table by config. Skips if sync is already running."],
  ["<code>syncTableByName(String)</code>","<code>Future&lt;SyncMetrics&gt;</code>","Sync a single table by name. Looks up the registered TableConfig."],
  ["<code>syncWithOrchestration(strategy)</code>","<code>Future&lt;SyncSessionMetrics&gt;</code>","Execute a custom <a href='orchestration.html'>SyncOrchestrationStrategy</a>."],
  ["<code>dispose()</code>","<code>void</code>","Closes the status stream controller. Call on app shutdown."],
]) +

'<h3>statusStream</h3>'
'<p>A broadcast <code>Stream&lt;String&gt;</code> emitting human-readable status messages during sync. Wire it to <a href="widgets.html">SyncStatusWidget</a> or listen directly:</p>'
+ dart(
"engine.statusStream.listen((msg) => print('Sync: $msg'));\n"
'// "Starting Full Sync..."\n'
'// "Downloading todos..."\n'
'// "Uploading todos..."\n'
'// "Sync completed successfully."'
) +

'<h2>Overlap Protection</h2>'
'<p>If <code>syncAll()</code> or <code>syncTable()</code> is called while a sync is already in progress, the call returns immediately with empty metrics and a warning is logged. This prevents concurrent writes to the local database.</p>'

'<h2>Error Tolerance</h2>'
'<p><code>syncAll()</code> does not abort on a single table failure. If table A fails, table B is still synced. Errors are captured in <code>SyncSessionMetrics.totalErrors</code>.</p>'
+ dart(
"final metrics = await engine.syncAll();\n"
"if (!metrics.overallSuccess) {\n"
"  for (final tm in metrics.tableMetrics) {\n"
"    if (!tm.success) print('Failed: ${tm.tableName} — ${tm.errorMessages}');\n"
"  }\n"
"}"
),
subtitle="Core orchestrator for all sync operations"
)

# ── 5. CONFLICT RESOLUTION ───────────────────────────────────────────────────
write("sync-conflicts.html", "Conflict Resolution",
'<p>A conflict occurs when a record was modified both locally and remotely since the last sync. syncitron supports four strategies, configured per table.</p>'

'<h2>SyncStrategy Enum</h2>'
+ tbl(["Strategy","Behaviour","Use Case"], [
  ["<code>serverWins</code>","Remote record overwrites local. <strong>Default.</strong>","Reference data, admin settings"],
  ["<code>localWins</code>","Local record is kept; remote update ignored.","Drafts, user preferences"],
  ["<code>lastWriteWins</code>","Record with the latest <code>updated_at</code> wins.","Collaborative content"],
  ["<code>custom</code>","Your custom resolver function runs.","Complex merge logic"],
]) +

'<h2>Setting the Strategy</h2>'
+ dart(
"// Per table\n"
"engine.registerTable(TableConfig(\n"
"  name: 'settings',\n"
"  columns: ['id', 'key', 'value', 'updated_at', 'deleted_at'],\n"
"  strategy: SyncStrategy.serverWins,\n"
"));"
) +

'<h2>Custom Conflict Resolver</h2>'
'<p>When <code>SyncStrategy.custom</code> is selected, you <strong>must</strong> provide a <code>customResolver</code>. The resolver receives both records and returns a <code>ConflictResolution</code>.</p>'
+ dart(
"engine.registerTable(TableConfig(\n"
"  name: 'documents',\n"
"  columns: ['id', 'title', 'body', 'version', 'updated_at', 'deleted_at'],\n"
"  strategy: SyncStrategy.custom,\n"
"  customResolver: (local, remote) async {\n"
"    // Keep the one with the higher version\n"
"    if ((local['version'] as int) >= (remote['version'] as int)) {\n"
"      return const UseLocal();\n"
"    }\n"
"    return UseRemote(remote);\n"
"  },\n"
"));"
) +

'<h3>ConflictResolution Types</h3>'
+ tbl(["Type","Meaning"], [
  ["<code>UseLocal()</code>","Keep the local dirty record as-is."],
  ["<code>UseRemote(data)</code>","Overwrite local with the remote record data."],
  ["<code>UseMerged(data)</code>","Save a manually merged map combining both versions."],
]) +
callout("danger", "Using <code>SyncStrategy.custom</code> without providing a <code>customResolver</code> will throw an <code>EngineConfigurationException</code> at registration time.") +

'<h2>How Conflicts Are Detected</h2>'
'<p>During the <strong>pull</strong> phase, for each incoming remote record, the engine checks if a local record with the same primary key exists and has <code>is_synced = 0</code> (dirty). If so, it\'s a conflict. If the local record is already synced, the remote version is simply upserted.</p>',
subtitle="ServerWins · LocalWins · LastWriteWins · Custom"
)

# ── 6. CONFIGURATION ─────────────────────────────────────────────────────────
write("configuration.html", "Configuration",
'<p><code>syncitronConfig</code> is an immutable class controlling engine behaviour. Three factory constructors provide sensible presets.</p>'

'<h2>Presets</h2>'
+ dart(
"syncitronConfig.production()   // large batches, aggressive retries\n"
"syncitronConfig.development()  // small batches, detailed logging\n"
"syncitronConfig.testing()      // minimal overhead, no logging/metrics"
) +

'<h2>All Parameters</h2>'
+ tbl(["Parameter","Type","Default","Description"], [
  ["<code>batchSize</code>","<code>int</code>","500","Max records per pull page / push batch"],
  ["<code>maxConcurrentSyncs</code>","<code>int</code>","1","Reserved for future parallel sync"],
  ["<code>operationTimeout</code>","<code>Duration</code>","30 s","Timeout per remote operation"],
  ["<code>maxRetries</code>","<code>int</code>","3","Max retry attempts on failure"],
  ["<code>initialRetryDelay</code>","<code>Duration</code>","300 ms","First retry wait time"],
  ["<code>maxRetryDelay</code>","<code>Duration</code>","30 s","Cap for exponential backoff"],
  ["<code>isSyncedColumn</code>","<code>String</code>","<code>'is_synced'</code>","Local column tracking sync status"],
  ["<code>operationIdColumn</code>","<code>String</code>","<code>'op_id'</code>","Local column for idempotency keys"],
  ["<code>autoSyncOnStartup</code>","<code>bool</code>","false","Auto-trigger syncAll after init"],
  ["<code>periodicSyncInterval</code>","<code>Duration?</code>","null","If set, enables periodic sync timer"],
  ["<code>enableDetailedLogging</code>","<code>bool</code>","false","Log individual record operations"],
  ["<code>collectMetrics</code>","<code>bool</code>","true","Whether to record sync metrics"],
  ["<code>validateOnCreation</code>","<code>bool</code>","true","Run <code>validate()</code> in constructor"],
]) +

'<h2>Custom Configuration</h2>'
+ dart(
"final config = syncitronConfig(\n"
"  batchSize: 1000,\n"
"  maxRetries: 5,\n"
"  initialRetryDelay: Duration(seconds: 1),\n"
"  maxRetryDelay: Duration(minutes: 5),\n"
"  enableDetailedLogging: false,\n"
"  periodicSyncInterval: Duration(minutes: 10),\n"
");"
) +

'<h2>copyWith</h2>'
'<p>Create a modified copy without mutating the original:</p>'
+ dart(
"final custom = syncitronConfig.production().copyWith(\n"
"  batchSize: 2000,\n"
"  enableDetailedLogging: true,\n"
");"
) +

'<h2>Validation</h2>'
'<p><code>validate()</code> is called automatically during construction (unless <code>validateOnCreation: false</code>). It checks:</p>'
'<ul>'
'<li><code>batchSize</code> &gt; 0</li>'
'<li><code>maxRetries</code> &gt;= 0</li>'
'<li><code>initialRetryDelay</code> &gt; 0</li>'
'<li><code>maxRetryDelay</code> &gt;= <code>initialRetryDelay</code></li>'
'</ul>',
subtitle="syncitronConfig — presets and tuning"
)

# ── 7. ERROR HANDLING ─────────────────────────────────────────────────────────
write("error-handling.html", "Error Handling",
'<p>syncitron uses a <strong>sealed exception hierarchy</strong> rooted at <code>syncitronException</code>. You can pattern-match on specific types for granular error handling.</p>'

'<h2>Exception Hierarchy</h2>'
'<pre><code>'
'syncitronException  (sealed)\n'
'  ├── SyncNetworkException       — network / timeout / server error\n'
'  ├── SyncAuthException          — 401/403, session expired\n'
'  ├── ConflictResolutionException — custom resolver threw\n'
'  ├── SchemaMigrationException   — ALTER TABLE failed\n'
'  ├── LocalStoreException        — local DB read/write error\n'
'  ├── UnregisteredTableException — table not registered\n'
'  └── EngineConfigurationException — invalid config'
'</code></pre>'

'<h2>Pattern Matching</h2>'
+ dart(
"try {\n"
"  await engine.syncAll();\n"
"} on SyncNetworkException catch (e) {\n"
"  if (e.isOffline) showOfflineBanner();\n"
"  else showError('Server error: ${e.statusCode}');\n"
"} on SyncAuthException catch (e) {\n"
"  redirectToLogin();\n"
"} on ConflictResolutionException catch (e) {\n"
"  log('Conflict on ${e.table} pk=${e.primaryKey}');\n"
"} on SchemaMigrationException catch (e) {\n"
"  reportFatalError(e);\n"
"} on LocalStoreException catch (e) {\n"
"  showError('Database error: ${e.message}');\n"
"} on syncitronException catch (e) {\n"
"  // catch-all for any syncitron error\n"
"  showError('Sync error: ${e.message}');\n"
"}"
) +

'<h2>Exception Details</h2>'

'<h3>SyncNetworkException</h3>'
+ tbl(["Field","Type","Description"], [
  ["<code>table</code>","<code>String</code>","The table being synced"],
  ["<code>statusCode</code>","<code>int?</code>","HTTP status code, <code>null</code> if offline"],
  ["<code>isOffline</code>","<code>bool</code>","Getter — <code>true</code> when statusCode is null"],
  ["<code>cause</code>","<code>Object?</code>","Original underlying exception"],
]) +

'<h3>SyncAuthException</h3>'
+ tbl(["Field","Type","Description"], [
  ["<code>table</code>","<code>String</code>","The table being synced"],
  ["<code>message</code>","<code>String</code>","Default: \'Unauthorized. Session may have expired.\'"],
]) +

'<h3>ConflictResolutionException</h3>'
+ tbl(["Field","Type","Description"], [
  ["<code>table</code>","<code>String</code>","Table where conflict occurred"],
  ["<code>primaryKey</code>","<code>dynamic</code>","Primary key of the conflicting record"],
  ["<code>cause</code>","<code>Object?</code>","The error thrown by the custom resolver"],
]) +

'<h3>SchemaMigrationException</h3>'
+ tbl(["Field","Type","Description"], [
  ["<code>table</code>","<code>String</code>","Table being migrated"],
  ["<code>column</code>","<code>String</code>","Column that failed to add"],
]) +

'<h3>LocalStoreException</h3>'
+ tbl(["Field","Type","Description"], [
  ["<code>table</code>","<code>String</code>","Table with the local DB error"],
  ["<code>message</code>","<code>String</code>","Error description"],
]) +

'<h3>UnregisteredTableException</h3>'
'<p>Thrown when you attempt to sync a table that hasn\'t been registered via <code>registerTable()</code>.</p>'

'<h3>EngineConfigurationException</h3>'
'<p>Thrown at setup time, e.g. using <code>SyncStrategy.custom</code> without a <code>customResolver</code>, or invalid config values.</p>'

+ callout("info", "All exceptions include a <code>cause</code> field for chaining the original underlying error."),
subtitle="Sealed exception hierarchy"
)

# ── 8. METRICS & LOGGING ─────────────────────────────────────────────────────
write("metrics-logging.html", "Metrics & Logging",
'<h2>Sync Metrics</h2>'
'<p>Every <code>syncAll()</code> returns a <code>SyncSessionMetrics</code> containing per-table <code>SyncMetrics</code>.</p>'

'<h3>SyncSessionMetrics</h3>'
+ tbl(["Property","Type","Description"], [
  ["<code>totalDuration</code>","<code>Duration</code>","Total wall time for the session"],
  ["<code>totalTablesSynced</code>","<code>int</code>","Number of tables processed"],
  ["<code>totalRecordsPulled</code>","<code>int</code>","Sum of all pulled records"],
  ["<code>totalRecordsPushed</code>","<code>int</code>","Sum of all pushed records"],
  ["<code>totalConflicts</code>","<code>int</code>","Sum of conflicts encountered"],
  ["<code>totalErrors</code>","<code>int</code>","Number of failed table syncs"],
  ["<code>overallSuccess</code>","<code>bool</code>","<code>true</code> if all tables synced without errors"],
  ["<code>tableMetrics</code>","<code>List&lt;SyncMetrics&gt;</code>","Per-table breakdown"],
]) +

'<h3>SyncMetrics (per table)</h3>'
+ tbl(["Property","Type"], [
  ["<code>tableName</code>","<code>String</code>"],
  ["<code>duration</code>","<code>Duration</code>"],
  ["<code>recordsPulled</code>","<code>int</code>"],
  ["<code>recordsPushed</code>","<code>int</code>"],
  ["<code>recordsWithConflicts</code>","<code>int</code>"],
  ["<code>conflictsResolved</code>","<code>int</code>"],
  ["<code>errors</code>","<code>int</code>"],
  ["<code>success</code>","<code>bool</code>"],
]) +

'<h3>Usage</h3>'
+ dart(
"final metrics = await engine.syncAll();\n\n"
"print(metrics);                        // pretty-printed summary\n"
"print(metrics.toJson());               // structured JSON\n\n"
"for (final tm in metrics.tableMetrics) {\n"
"  if (!tm.success) {\n"
"    print('${tm.tableName} failed: ${tm.errorMessages}');\n"
"  }\n"
"}"
) +

'<h2>MetricsCollector</h2>'
+ tbl(["Implementation","Behaviour"], [
  ["<code>InMemoryMetricsCollector</code>","Stores all sessions and table metrics in memory. Useful for dashboards."],
  ["<code>NoOpMetricsCollector</code>","Discards all metrics. Zero overhead for production."],
]) +

'<h2>Logging</h2>'
'<p>syncitron provides a pluggable <code>Logger</code> interface with three built-in implementations.</p>'

'<h3>Logger Implementations</h3>'
+ tbl(["Class","Behaviour"], [
  ["<code>ConsoleLogger</code>","Prints to <code>stdout</code>. Accepts <code>minLevel</code> to filter."],
  ["<code>NoOpLogger</code>","Discards all log output. Zero overhead."],
  ["<code>MultiLogger</code>","Fan-out: delegates to a list of loggers."],
]) +

'<h3>Log Levels</h3>'
+ tbl(["Level","Severity"], [
  ["<code>LogLevel.debug</code>","0 — Verbose debugging"],
  ["<code>LogLevel.info</code>","1 — Normal operations"],
  ["<code>LogLevel.warning</code>","2 — Potential issues"],
  ["<code>LogLevel.error</code>","3 — Errors requiring attention"],
  ["<code>LogLevel.critical</code>","4 — Fatal errors"],
]) +

'<h3>Custom Logger Integration</h3>'
+ dart(
"class SentryLogger implements Logger {\n"
"  @override\n"
"  void error(String msg, {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) {\n"
"    Sentry.captureException(error, stackTrace: stackTrace);\n"
"  }\n"
"  // ... implement other methods\n"
"}\n\n"
"final engine = SyncEngine(\n"
"  localStore: store,\n"
"  remoteAdapter: adapter,\n"
"  logger: MultiLogger([ConsoleLogger(), SentryLogger()]),\n"
");"
) +

'<h3>LogEntry</h3>'
'<p>Structured log entries can be serialized to JSON for export:</p>'
+ dart(
"final entry = LogEntry(\n"
"  level: LogLevel.error,\n"
"  message: 'Sync failed',\n"
"  error: exception,\n"
"  context: {'table': 'todos', 'records': 42},\n"
");\n"
"print(entry.toJson());"
),
subtitle="Track performance and debug sync flows"
)

# ── 9. BACKEND: SUPABASE ─────────────────────────────────────────────────────
write("backend-supabase.html", "Supabase Backend",
'<p><code>SupabaseAdapter</code> connects syncitron to a Supabase PostgreSQL backend. It supports cursor-based pagination, native batch upserts, and real-time subscriptions via WebSocket.</p>'

'<h2>Setup</h2>'
+ yaml(
"dependencies:\n"
"  syncitron: ^0.5.1\n"
"  supabase_flutter: ^2.12.0\n"
"  sqflite: ^2.4.2"
) +
dart(
"import 'package:syncitron/syncitron.dart';\n"
"import 'package:supabase_flutter/supabase_flutter.dart';\n\n"
"final adapter = SupabaseAdapter(\n"
"  client: Supabase.instance.client,\n"
"  localStore: sqfliteStore,\n"
"  postgresChangeEventAll: PostgresChangeEvent.all,\n"
"  isAuthException: (e) => e is AuthException,\n"
"  updatedAtColumn: 'updated_at',  // default\n"
");"
) +

'<h2>Required Database Schema</h2>'
'<p>Every table synced with syncitron must have these columns on Supabase:</p>'
+ sql(
"CREATE TABLE todos (\n"
"  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),\n"
"  title TEXT NOT NULL,\n"
"  completed BOOLEAN DEFAULT false,\n"
"  -- Required by syncitron:\n"
"  updated_at TIMESTAMPTZ DEFAULT now(),\n"
"  deleted_at TIMESTAMPTZ NULL\n"
");\n\n"
"-- Recommended: index for keyset pagination performance\n"
"CREATE INDEX idx_todos_updated_at ON todos(updated_at);"
) +
callout("warn", "The <code>updated_at</code> column must be auto-updated on every write. Use a Supabase trigger or set it in your application code.") +

'<h2>Real-Time Subscriptions</h2>'
+ dart(
"final realtimeProvider = SupabaseRealtimeProvider(\n"
"  client: Supabase.instance.client,\n"
"  postgresChangeEventAll: PostgresChangeEvent.all,\n"
"  connectionTimeout: Duration(seconds: 30),\n"
");\n\n"
"final manager = RealtimeSubscriptionManager(\n"
"  config: RealtimeSubscriptionConfig.production(),\n"
"  provider: realtimeProvider,\n"
"  engine: engine,\n"
"  logger: ConsoleLogger(),\n"
");\n\n"
"await manager.initialize(['todos', 'projects']);"
) +

'<h2>Batch Operations</h2>'
'<p>SupabaseAdapter uses native PostgreSQL <code>UPSERT</code> for batch operations — true atomic writes for maximum throughput.</p>'

'<h2>Security</h2>'
'<ul>'
'<li>Enable <strong>Row-Level Security (RLS)</strong> on all synced tables</li>'
'<li>Handle session expiry: catch <code>SyncAuthException</code> and re-authenticate</li>'
'<li>Never log auth tokens — use <code>NoOpLogger</code> in production if needed</li>'
'</ul>',
subtitle="PostgreSQL via Supabase + real-time WebSocket sync"
)

# ── 10. BACKEND: FIREBASE ────────────────────────────────────────────────────
write("backend-firebase.html", "Firebase Firestore Backend",
'<p><code>FirebaseFirestoreAdapter</code> connects to Cloud Firestore. Uses dynamic typing to avoid hard dependencies — add <code>cloud_firestore</code> to your pubspec.</p>'

'<h2>Setup</h2>'
+ yaml(
"dependencies:\n"
"  syncitron: ^0.5.1\n"
"  firebase_core: ^2.24.0\n"
"  cloud_firestore: ^4.13.0"
) +
dart(
"import 'package:cloud_firestore/cloud_firestore.dart';\n"
"import 'package:syncitron/syncitron.dart';\n\n"
"final adapter = FirebaseFirestoreAdapter(\n"
"  firestore: FirebaseFirestore.instance,\n"
"  localStore: sqfliteStore,\n"
"  timeout: Duration(seconds: 30),\n"
"  enableOfflinePersistence: true,\n"
");"
) +

'<h2>Constructor</h2>'
+ tbl(["Parameter","Type","Default","Description"], [
  ["<code>firestore</code>","<code>dynamic</code>","required","<code>FirebaseFirestore</code> instance"],
  ["<code>localStore</code>","<code>dynamic</code>","required","Your LocalStore"],
  ["<code>timeout</code>","<code>Duration</code>","30 s","Per-operation timeout"],
  ["<code>enableOfflinePersistence</code>","<code>bool</code>","true","Enable Firestore offline cache"],
]) +

'<h2>Additional Methods</h2>'
+ tbl(["Method","Description"], [
  ["<code>watchCollection(table)</code>","Returns a <code>Stream</code> of live collection snapshots"],
  ["<code>batchWrite(operations)</code>","Execute multiple writes as a Firestore batch"],
  ["<code>runTransaction(callback)</code>","Execute inside a Firestore transaction"],
]) +

'<h2>Real-Time</h2>'
+ dart(
"final realtimeProvider = FirebaseFirestoreRealtimeProvider(\n"
"  firestore: FirebaseFirestore.instance,\n"
");"
) +

'<h2>Batch Writes</h2>'
'<p>Uses Firestore\'s native batch API (up to 500 operations per batch). Automatically chunks larger batches.</p>',
subtitle="Cloud Firestore with real-time snapshot listeners"
)

# ── 11. BACKEND: APPWRITE ────────────────────────────────────────────────────
write("backend-appwrite.html", "Appwrite Backend",
'<p><code>AppwriteAdapter</code> connects to self-hosted or cloud Appwrite. Uses dynamic typing — add the <code>appwrite</code> package.</p>'

'<h2>Setup</h2>'
+ yaml(
"dependencies:\n"
"  syncitron: ^0.5.1\n"
"  appwrite: ^11.0.0"
) +
dart(
"import 'package:appwrite/appwrite.dart';\n"
"import 'package:syncitron/syncitron.dart';\n\n"
"final client = Client()\n"
"  ..setEndpoint('https://cloud.appwrite.io/v1')\n"
"  ..setProject('your-project-id');\n\n"
"final adapter = AppwriteAdapter(\n"
"  client: client,\n"
"  database: Databases(client),\n"
"  localStore: sqfliteStore,\n"
"  databaseId: 'your-database-id',\n"
");"
) +

'<h2>Constructor</h2>'
+ tbl(["Parameter","Type","Default","Description"], [
  ["<code>client</code>","<code>dynamic</code>","required","Appwrite Client"],
  ["<code>database</code>","<code>dynamic</code>","required","Appwrite Databases instance"],
  ["<code>localStore</code>","<code>dynamic</code>","required","Your LocalStore"],
  ["<code>databaseId</code>","<code>String</code>","required","Appwrite database ID"],
  ["<code>timeout</code>","<code>Duration</code>","30 s","Per-operation timeout"],
]) +

'<h2>Additional Methods</h2>'
+ tbl(["Method","Description"], [
  ["<code>executeFunction(functionId, data)</code>","Execute an Appwrite Cloud Function"],
  ["<code>batchWrite(table, creates, updates, deletes)</code>","Parallel batch operations"],
  ["<code>watchCollection(table)</code>","Stream of live document changes"],
]) +

'<h2>Real-Time</h2>'
+ dart(
"final realtimeProvider = AppwriteRealtimeProvider(\n"
"  client: client,\n"
"  databaseId: 'your-database-id',\n"
");"
),
subtitle="Self-hosted BaaS with WebSocket real-time"
)

# ── 12. BACKEND: GRAPHQL ─────────────────────────────────────────────────────
write("backend-graphql.html", "GraphQL Backend",
'<p><code>GraphQLAdapter</code> works with any GraphQL server (Hasura, Apollo, Supabase GraphQL, custom). You provide query/mutation builders; syncitron handles the sync logic.</p>'

'<h2>Setup</h2>'
+ yaml(
"dependencies:\n"
"  syncitron: ^0.5.1\n"
"  graphql: ^5.1.0"
) +
dart(
"import 'package:graphql/client.dart';\n"
"import 'package:syncitron/syncitron.dart';\n\n"
"final graphqlClient = GraphQLClient(\n"
"  link: HttpLink('https://your-server.com/graphql'),\n"
"  cache: GraphQLCache(),\n"
");\n\n"
"final adapter = GraphQLAdapter(\n"
"  graphqlClient: graphqlClient,\n"
"  localStore: sqfliteStore,\n"
"  queryBuilder: (request) {\n"
"    return '''\n"
"      query Pull(\\$cursor: timestamptz, \\$limit: Int!) {\n"
"        ${request.table}(\n"
"          where: {updated_at: {_gte: \\$cursor}}\n"
"          order_by: {updated_at: asc}\n"
"          limit: \\$limit\n"
"        ) { ${request.columns.join(' ')} }\n"
"      }\n"
"    ''';\n"
"  },\n"
"  mutationBuilder: (table, data) {\n"
"    return '''\n"
"      mutation Upsert(\\$object: ${table}_insert_input!) {\n"
"        insert_${table}_one(\n"
"          object: \\$object\n"
"          on_conflict: {constraint: ${table}_pkey, update_columns: [${data.keys.join(', ')}]}\n"
"        ) { id }\n"
"      }\n"
"    ''';\n"
"  },\n"
");"
) +

'<h2>Constructor</h2>'
+ tbl(["Parameter","Type","Description"], [
  ["<code>graphqlClient</code>","<code>dynamic</code>","GraphQL client instance"],
  ["<code>localStore</code>","<code>dynamic</code>","Your LocalStore"],
  ["<code>queryBuilder</code>","<code>Function(PullRequest) → String</code>","Builds the pull query"],
  ["<code>mutationBuilder</code>","<code>Function(String, Map) → String</code>","Builds upsert mutations"],
  ["<code>softDeleteMutationBuilder</code>","<code>Function(String, String) → String</code>","Builds soft-delete mutations"],
  ["<code>timeout</code>","<code>Duration</code>","Per-operation timeout (default 30s)"],
]) +

'<h2>Real-Time via Subscriptions</h2>'
+ dart(
"final realtimeProvider = GraphQLRealtimeProvider(\n"
"  graphqlClient: graphqlClient,\n"
"  subscriptionQueryBuilder: (table) {\n"
"    return '''\n"
"      subscription Watch {\n"
"        $table(order_by: {updated_at: desc}, limit: 1) {\n"
"          id updated_at\n"
"        }\n"
"      }\n"
"    ''';\n"
"  },\n"
");"
),
subtitle="Works with Hasura, Apollo, or any GraphQL server"
)

# ── 13. STORAGE: SQFLITE ─────────────────────────────────────────────────────
write("storage-sqflite.html", "SQLite Storage (sqflite)",
'<p><code>SqfliteStore</code> is the recommended local store. Battle-tested, suitable for 100K+ records, lowest memory footprint.</p>'

'<h2>Setup</h2>'
+ dart(
"import 'package:sqflite/sqflite.dart';\n"
"import 'package:syncitron/syncitron.dart';\n\n"
"final db = await openDatabase('myapp.db', version: 1, onCreate: (db, v) async {\n"
"  await db.execute('CREATE TABLE todos (id TEXT PRIMARY KEY, title TEXT, ...)');\n"
"});\n\n"
"final store = SqfliteStore(\n"
"  db,\n"
"  conflictAlgorithm: ConflictAlgorithm.replace, // required\n"
"  isSyncedColumn: 'is_synced',      // default\n"
"  operationIdColumn: 'op_id',       // default\n"
");"
) +

'<h2>Automatic Column Migration</h2>'
'<p><code>ensureSyncColumns()</code> (called during <code>engine.init()</code>) checks if <code>is_synced</code> and <code>op_id</code> columns exist and adds them via <code>ALTER TABLE</code> if missing.</p>'

'<h2>Cursor Persistence</h2>'
'<p>Sync cursors are stored in a private <code>_syncitron_meta</code> table, created automatically. This table maps table names to their last-synced <code>updated_at</code> + <code>primaryKey</code> pair.</p>'

'<h2>Batch Optimisations</h2>'
'<ul>'
'<li>SQL parameter chunking: batches are split into chunks of 999 parameters to respect SQLite\'s <code>SQLITE_MAX_VARIABLE_NUMBER</code> limit.</li>'
'<li><code>markManyAsSynced()</code> uses <code>UPDATE … WHERE pk IN (...)</code> instead of N individual updates.</li>'
'<li><code>upsertBatch()</code> uses <code>INSERT OR REPLACE</code> inside a single transaction.</li>'
'</ul>',
subtitle="Recommended — production-proven SQLite storage"
)

# ── 14. STORAGE: DRIFT ───────────────────────────────────────────────────────
write("storage-drift.html", "Drift Storage",
'<p><code>DriftStore</code> wraps a Drift (typed SQL) database. Schema management is compile-time, so <code>ensureSyncColumns()</code> is a no-op — ensure your Drift schema includes <code>is_synced</code> and <code>op_id</code> columns.</p>'

'<h2>Setup</h2>'
+ yaml(
"dependencies:\n"
"  syncitron: ^0.5.1\n"
"  drift: ^2.14.0\n"
"  sqlite3_flutter_libs: ^0.5.0"
) +
dart(
"import 'package:syncitron/syncitron.dart';\n\n"
"final store = DriftStore(\n"
"  tables: {'todos': todosTable, 'projects': projectsTable},\n"
"  readMetadataQuery: (table) => metadataDao.read(table),\n"
"  writeMetadataQuery: (table, json) => metadataDao.write(table, json),\n"
"  deleteMetadataQuery: (table) => metadataDao.delete(table),\n"
");"
) +

'<h2>Constructor</h2>'
+ tbl(["Parameter","Type","Description"], [
  ["<code>tables</code>","<code>Map&lt;String, dynamic&gt;</code>","Map of table name → Drift table reference"],
  ["<code>readMetadataQuery</code>","<code>Function(String)</code>","Reads sync cursor JSON for a table"],
  ["<code>writeMetadataQuery</code>","<code>Function(String, String)</code>","Writes sync cursor JSON"],
  ["<code>deleteMetadataQuery</code>","<code>Function(String)</code>","Deletes sync cursor"],
  ["<code>isSyncedColumn</code>","<code>String</code>","Column name (default: <code>'is_synced'</code>)"],
  ["<code>operationIdColumn</code>","<code>String</code>","Column name (default: <code>'op_id'</code>)"],
]) +
callout("warn", "Your Drift schema <strong>must</strong> include <code>is_synced</code> (int) and <code>op_id</code> (text) columns. syncitron cannot add them at runtime."),
subtitle="Type-safe SQL with compile-time safety"
)

# ── 15. STORAGE: HIVE ────────────────────────────────────────────────────────
write("storage-hive.html", "Hive Storage",
'<p><code>HiveStore</code> uses Hive boxes for lightweight NoSQL storage. Schema-less — great for rapid prototyping.</p>'

'<h2>Setup</h2>'
+ yaml(
"dependencies:\n"
"  syncitron: ^0.5.1\n"
"  hive_flutter: ^1.1.0"
) +
dart(
"import 'package:hive_flutter/hive_flutter.dart';\n"
"import 'package:syncitron/syncitron.dart';\n\n"
"await Hive.initFlutter();\n"
"final metadataBox = await Hive.openBox('syncitron_meta');\n\n"
"final store = HiveStore(\n"
"  metadataBox: metadataBox,\n"
"  dataBoxFactory: (table) => Hive.openBox(table),\n"
");"
) +

'<h2>Constructor</h2>'
+ tbl(["Parameter","Type","Description"], [
  ["<code>metadataBox</code>","<code>dynamic</code>","Hive box for sync cursor storage"],
  ["<code>dataBoxFactory</code>","<code>Function(String)</code>","Factory returning the Hive box for a table name"],
  ["<code>isSyncedColumn</code>","<code>String</code>","Key name (default: <code>'is_synced'</code>)"],
  ["<code>operationIdColumn</code>","<code>String</code>","Key name (default: <code>'op_id'</code>)"],
]) +
callout("info", "Hive is schema-less: <code>ensureSyncColumns()</code> is a no-op. The <code>is_synced</code> and <code>op_id</code> fields are simply added as keys in each record map."),
subtitle="Lightweight NoSQL — zero native dependencies"
)

# ── 16. STORAGE: ISAR ────────────────────────────────────────────────────────
write("storage-isar.html", "Isar Storage",
'<p><code>IsarStore</code> uses Isar, a high-performance embedded NoSQL database backed by Rust. Ideal for mobile with encryption and indexing support.</p>'

'<h2>Setup</h2>'
+ yaml(
"dependencies:\n"
"  syncitron: ^0.5.1\n"
"  isar: ^3.1.0\n"
"  isar_flutter_libs: ^3.1.0"
) +
dart(
"import 'package:isar/isar.dart';\n"
"import 'package:syncitron/syncitron.dart';\n\n"
"final isar = await Isar.open([TodoSchema, ProjectSchema]);\n\n"
"final store = IsarStore(\n"
"  isar: isar,\n"
"  collectionFactory: (table) => isar.collection<dynamic>(table),\n"
");"
) +

'<h2>Constructor</h2>'
+ tbl(["Parameter","Type","Description"], [
  ["<code>isar</code>","<code>dynamic</code>","Isar database instance"],
  ["<code>collectionFactory</code>","<code>Function(String)</code>","Returns the Isar collection for a table name"],
  ["<code>isSyncedColumn</code>","<code>String</code>","Property name (default: <code>'is_synced'</code>)"],
  ["<code>operationIdColumn</code>","<code>String</code>","Property name (default: <code>'op_id'</code>)"],
]) +
callout("warn", "Isar schemas are defined at compile time. Ensure your <code>@collection</code> classes include <code>isSynced</code> and <code>opId</code> properties."),
subtitle="Rust-backed high-performance embedded database"
)

# ── 17. ORCHESTRATION ─────────────────────────────────────────────────────────
write("orchestration.html", "Sync Orchestration",
'<p>For advanced sync flows beyond the default pull-push pattern, syncitron provides <code>SyncOrchestrationStrategy</code> — a pluggable lifecycle for custom sync orchestrations.</p>'

'<h2>How It Works</h2>'
+ dart(
"final metrics = await engine.syncWithOrchestration(\n"
"  OfflineFirstSyncOrchestration(),\n"
");"
) +
'<p>The engine creates a <code>SyncOrchestrationContext</code> and calls:</p>'
'<ol>'
'<li><code>strategy.beforeSync(context)</code> — setup, logging, pre-checks</li>'
'<li><code>strategy.execute(context)</code> — the actual sync logic (must return <code>SyncSessionMetrics</code>)</li>'
'<li><code>strategy.afterSync(context, metrics)</code> — cleanup, notifications</li>'
'</ol>'

'<h2>SyncOrchestrationContext</h2>'
'<p>The context provides controlled access to engine internals:</p>'
+ tbl(["Member","Description"], [
  ["<code>logger</code>","The engine's Logger"],
  ["<code>metricsCollector</code>","The engine's MetricsCollector"],
  ["<code>tableNames</code>","List of registered table names"],
  ["<code>startTime</code>","When the sync started"],
  ["<code>managedSyncTable(name)</code>","Sync a single table by name, returns SyncMetrics"],
  ["<code>managedSyncAll()</code>","Sync all tables, returns SyncSessionMetrics"],
  ["<code>shouldContinue()</code>","Returns false if cancelled"],
  ["<code>cancel()</code>","Cancels the orchestration"],
]) +

'<h2>Built-in Strategies</h2>'

'<h3>StandardSyncOrchestration</h3>'
'<p>Default pull-push for all tables. Same as <code>syncAll()</code>.</p>'

'<h3>OfflineFirstSyncOrchestration</h3>'
'<p>Graceful degradation: continues syncing remaining tables even after network errors. Stops after <code>maxNetworkErrors</code> consecutive failures.</p>'
+ dart("OfflineFirstSyncOrchestration(maxNetworkErrors: 3)") +

'<h3>StrictManualOrchestration</h3>'
'<p>Strict error handling — aborts on first failure. Useful for critical data.</p>'

'<h3>PrioritySyncOrchestration</h3>'
'<p>Syncs tables in priority order (higher number = synced first).</p>'
+ dart(
"PrioritySyncOrchestration({\n"
"  'user_settings': 100,   // synced first\n"
"  'todos': 50,\n"
"  'analytics': 10,        // synced last\n"
"})"
) +

'<h3>CompositeSyncOrchestration</h3>'
'<p>Chains multiple strategies sequentially.</p>'
+ dart(
"CompositeSyncOrchestration([\n"
"  PrioritySyncOrchestration({'settings': 100}),\n"
"  StandardSyncOrchestration(),\n"
"])"
) +

'<h2>Custom Strategy</h2>'
+ dart(
"class MyStrategy extends SyncOrchestrationStrategy {\n"
"  @override\n"
"  Future<SyncSessionMetrics> execute(SyncOrchestrationContext ctx) async {\n"
"    final session = SyncSessionMetrics();\n\n"
"    // Sync critical tables first\n"
"    for (final table in ['users', 'settings']) {\n"
"      final m = await ctx.managedSyncTable(table);\n"
"      session.addTableMetrics(m);\n"
"      if (!ctx.shouldContinue()) break;\n"
"    }\n\n"
"    // Then sync the rest\n"
"    for (final table in ctx.tableNames) {\n"
"      if (['users', 'settings'].contains(table)) continue;\n"
"      final m = await ctx.managedSyncTable(table);\n"
"      session.addTableMetrics(m);\n"
"    }\n\n"
"    session.endTime = DateTime.now().toUtc();\n"
"    return session;\n"
"  }\n"
"}"
),
subtitle="5 built-in strategies + custom orchestration"
)

# ── 18. REAL-TIME ─────────────────────────────────────────────────────────────
write("realtime.html", "Real-Time Sync",
'<p>syncitron supports event-driven real-time synchronization for all four backends. When data changes on the server, the client syncs automatically — no polling needed.</p>'

'<h2>Architecture</h2>'
'<pre><code>'
'Remote Backend  ──▶  RealtimeSubscriptionProvider  ──▶  RealtimeSubscriptionManager\n'
'                         (per backend)                     (debounce → engine.syncTableByName())'
'</code></pre>'

'<h2>Setup</h2>'
+ dart(
"final manager = RealtimeSubscriptionManager(\n"
"  config: RealtimeSubscriptionConfig.production(),\n"
"  provider: SupabaseRealtimeProvider(\n"
"    client: supabaseClient,\n"
"    postgresChangeEventAll: PostgresChangeEvent.all,\n"
"  ),\n"
"  engine: engine,\n"
"  logger: ConsoleLogger(),\n"
");\n\n"
"await manager.initialize(['todos', 'projects']);"
) +

'<h2>RealtimeSubscriptionConfig</h2>'
+ tbl(["Parameter","Type","Default","Description"], [
  ["<code>enabled</code>","<code>bool</code>","true","Master switch"],
  ["<code>autoSync</code>","<code>bool</code>","true","Auto-sync when changes detected"],
  ["<code>debounce</code>","<code>Duration</code>","2 s","Debounce window to coalesce rapid changes"],
  ["<code>connectionTimeout</code>","<code>Duration</code>","30 s","Connection timeout"],
  ["<code>autoReconnect</code>","<code>bool</code>","true","Auto-reconnect on disconnect"],
  ["<code>maxReconnectAttempts</code>","<code>int</code>","5","Max reconnect tries"],
  ["<code>backoffMultiplier</code>","<code>double</code>","2.0","Exponential backoff factor"],
]) +

'<h3>Presets</h3>'
+ dart(
"RealtimeSubscriptionConfig.production()    // 2s debounce, 5 retries, 2× backoff\n"
"RealtimeSubscriptionConfig.development()   // 1s debounce, 10 retries, 1.5× backoff\n"
"RealtimeSubscriptionConfig.disabled()      // everything off"
) +

'<h2>RealtimeSubscriptionManager API</h2>'
+ tbl(["Method","Description"], [
  ["<code>initialize(tables)</code>","Subscribe to listed tables, start listening"],
  ["<code>syncTable(table)</code>","Manually queue a table for debounced sync"],
  ["<code>syncPendingTables()</code>","Immediately sync all pending tables"],
  ["<code>isConnected</code>","Getter — current connection status"],
  ["<code>activeSubscriptionCount</code>","Number of active subscriptions"],
  ["<code>subscribedTables</code>","List of subscribed table names"],
  ["<code>close()</code>","Cancel all subscriptions and close connection"],
]) +

'<h2>Backend Support Matrix</h2>'
+ tbl(["Backend","Provider Class","Protocol"], [
  ["Supabase","<code>SupabaseRealtimeProvider</code>","PostgreSQL LISTEN/NOTIFY via WebSocket"],
  ["Firebase","<code>FirebaseFirestoreRealtimeProvider</code>","Firestore snapshot listeners"],
  ["Appwrite","<code>AppwriteRealtimeProvider</code>","WebSocket real-time service"],
  ["GraphQL","<code>GraphQLRealtimeProvider</code>","GraphQL subscriptions over WebSocket"],
]) +

'<h2>How It Works</h2>'
'<ol>'
'<li>The provider subscribes to the backend\'s real-time channel for each table.</li>'
'<li>When a <code>RealtimeChangeEvent</code> arrives (insert/update/delete), the table is added to the pending set.</li>'
'<li>A debounce timer coalesces rapid changes (default 2 seconds).</li>'
'<li>After the debounce window, <code>engine.syncTableByName(table)</code> is called for each pending table.</li>'
'<li>On disconnect, auto-reconnect kicks in with exponential backoff.</li>'
'</ol>',
subtitle="Event-driven sync with auto-reconnect"
)

# ── 19. UI WIDGETS ────────────────────────────────────────────────────────────
write("widgets.html", "UI Widgets",
'<p>syncitron ships 6 ready-made Flutter widgets for displaying sync status, errors, and metrics.</p>'

'<h2>SyncStatusWidget</h2>'
'<p>Displays sync status from the engine\'s <code>statusStream</code>.</p>'
+ dart(
"SyncStatusWidget(\n"
"  statusStream: engine.statusStream,\n"
"  onSync: () => engine.syncAll(),\n"
"  showProgress: true,\n"
"  builder: (context, status) => Text(status),  // optional custom builder\n"
")"
) +
tbl(["Prop","Type","Default","Description"], [
  ["<code>statusStream</code>","<code>Stream&lt;String&gt;</code>","required","Status messages from engine"],
  ["<code>onSync</code>","<code>VoidCallback</code>","required","Sync trigger callback"],
  ["<code>builder</code>","<code>Widget Function(…)?</code>","null","Custom builder, overrides default UI"],
  ["<code>showProgress</code>","<code>bool</code>","true","Show spinner during sync"],
  ["<code>textColor</code>","<code>Color?</code>","null","Override text color"],
]) +

'<h2>SyncMetricsCard</h2>'
'<p>Shows sync performance metrics in a card layout.</p>'
+ dart(
"SyncMetricsCard(\n"
"  metrics: sessionMetrics,\n"
"  elevation: 2,\n"
"  backgroundColor: Colors.white,\n"
")"
) +
tbl(["Prop","Type","Default"], [
  ["<code>metrics</code>","<code>SyncSessionMetrics</code>","required"],
  ["<code>elevation</code>","<code>double</code>","1"],
  ["<code>backgroundColor</code>","<code>Color?</code>","null"],
  ["<code>showWhenEmpty</code>","<code>bool</code>","true"],
]) +

'<h2>SyncErrorBanner</h2>'
'<p>Context-aware error banner using Dart 3 pattern matching on the sealed <code>syncitronException</code> hierarchy.</p>'
+ dart(
"SyncErrorBanner(\n"
"  error: currentError,   // syncitronException?\n"
"  onRetry: () => engine.syncAll(),\n"
"  onDismiss: () => setState(() => currentError = null),\n"
"  customMessage: null,   // optional override text\n"
")"
) +
tbl(["Prop","Type","Default"], [
  ["<code>error</code>","<code>syncitronException?</code>","required"],
  ["<code>onRetry</code>","<code>VoidCallback?</code>","null"],
  ["<code>onDismiss</code>","<code>VoidCallback?</code>","null"],
  ["<code>customMessage</code>","<code>String?</code>","null"],
]) +
'<p>When <code>error</code> is <code>null</code>, the banner is hidden (renders <code>SizedBox.shrink()</code>).</p>'

'<h2>OfflineIndicator</h2>'
'<p>Small chip showing online/offline state.</p>'
+ dart(
"OfflineIndicator(\n"
"  isOnline: connectivityStatus,\n"
"  offlineIcon: Icons.cloud_off,\n"
"  onlineIcon: Icons.cloud_done,\n"
"  offlineLabel: 'Offline',\n"
")"
) +

'<h2>SyncButton</h2>'
'<p>A <code>FilledButton.icon</code> that auto-disables and shows a spinner while syncing.</p>'
+ dart(
"SyncButton(\n"
"  onPressed: () => engine.syncAll(),\n"
"  isSyncing: isSyncInProgress,\n"
"  label: 'Sync Now',\n"
"  icon: Icons.sync,\n"
")"
) +
tbl(["Prop","Type","Default"], [
  ["<code>onPressed</code>","<code>VoidCallback</code>","required"],
  ["<code>isSyncing</code>","<code>bool</code>","required"],
  ["<code>label</code>","<code>String</code>","'Sync'"],
  ["<code>icon</code>","<code>IconData</code>","Icons.sync"],
]) +

'<h2>SyncStatusPanel</h2>'
'<p>All-in-one dashboard combining status, metrics, errors, and sync button.</p>'
+ dart(
"SyncStatusPanel(\n"
"  statusStream: engine.statusStream,\n"
"  onSync: () => engine.syncAll(),\n"
"  metrics: lastSessionMetrics,\n"
"  error: currentError,\n"
"  onErrorDismiss: () => setState(() => currentError = null),\n"
"  showMetrics: true,\n"
"  showButton: true,\n"
"  showStatus: true,\n"
")"
) +
tbl(["Prop","Type","Default"], [
  ["<code>statusStream</code>","<code>Stream&lt;String&gt;</code>","required"],
  ["<code>onSync</code>","<code>VoidCallback</code>","required"],
  ["<code>metrics</code>","<code>SyncSessionMetrics?</code>","null"],
  ["<code>error</code>","<code>syncitronException?</code>","null"],
  ["<code>onErrorDismiss</code>","<code>VoidCallback?</code>","null"],
  ["<code>showMetrics</code>","<code>bool</code>","true"],
  ["<code>showButton</code>","<code>bool</code>","true"],
  ["<code>showStatus</code>","<code>bool</code>","true"],
]),
subtitle="6 ready-made Flutter widgets for sync UX"
)

# ── 20. MULTI-ENGINE ──────────────────────────────────────────────────────────
write("multi-engine.html", "Multi-Engine (SyncManager)",
'<p><code>SyncManager</code> coordinates multiple <code>SyncEngine</code> instances — useful for multi-tenant apps, workspaces, or isolated sync contexts.</p>'

'<h2>Setup</h2>'
+ dart(
"final manager = SyncManager(\n"
"  logger: ConsoleLogger(),\n"
"  metricsCollector: InMemoryMetricsCollector(),\n"
");\n\n"
"manager.registerEngine('workspace-a', engineA);\n"
"manager.registerEngine('workspace-b', engineB);\n\n"
"await manager.initializeAll();"
) +

'<h2>API</h2>'
+ tbl(["Method","Returns","Description"], [
  ["<code>registerEngine(id, engine)</code>","<code>void</code>","Register an engine with a unique ID"],
  ["<code>getEngine(id)</code>","<code>SyncEngine?</code>","Retrieve an engine by ID"],
  ["<code>getAllEngines()</code>","<code>List&lt;SyncEngine&gt;</code>","All registered engines"],
  ["<code>initializeAll()</code>","<code>Future&lt;void&gt;</code>","Init all engines"],
  ["<code>syncAll()</code>","<code>Future&lt;Map&lt;String, SyncSessionMetrics&gt;&gt;</code>","Sync all engines, returns metrics keyed by ID"],
  ["<code>syncEngine(id)</code>","<code>Future&lt;SyncSessionMetrics&gt;</code>","Sync a specific engine by ID"],
  ["<code>startPeriodicSync(interval:)</code>","<code>void</code>","Start a periodic timer syncing all engines"],
  ["<code>stopPeriodicSync()</code>","<code>void</code>","Stop the periodic timer"],
  ["<code>checkAllHealth()</code>","<code>Future&lt;Map&lt;String, HealthCheckResult&gt;&gt;</code>","Health check all engines"],
  ["<code>dispose()</code>","<code>Future&lt;void&gt;</code>","Stop timers, dispose all engines"],
]) +

'<h2>Usage Pattern</h2>'
+ dart(
"// Sync all engines\n"
"final results = await manager.syncAll();\n"
"for (final entry in results.entries) {\n"
"  print('${entry.key}: ${entry.value.overallSuccess}');\n"
"}\n\n"
"// Periodic sync every 5 minutes\n"
"manager.startPeriodicSync(interval: Duration(minutes: 5));\n\n"
"// Cleanup\n"
"await manager.dispose();"
),
subtitle="Coordinate multiple SyncEngine instances"
)

# ── 21. DIAGNOSTICS ───────────────────────────────────────────────────────────
write("diagnostics.html", "Health & Diagnostics",
'<p>syncitron provides a diagnostics subsystem for monitoring the health of your sync infrastructure.</p>'

'<h2>HealthCheckResult</h2>'
+ dart(
"HealthCheckResult(\n"
"  component: 'Database',\n"
"  status: HealthStatus.healthy,\n"
"  message: 'Connection is alive',\n"
"  details: {'tables': 5, 'total_rows': 1234},\n"
")"
) +
tbl(["Field","Type","Description"], [
  ["<code>component</code>","<code>String</code>","Name of the component"],
  ["<code>status</code>","<code>HealthStatus</code>","healthy / degraded / unhealthy"],
  ["<code>message</code>","<code>String</code>","Human-readable status message"],
  ["<code>details</code>","<code>Map?</code>","Optional structured data"],
  ["<code>timestamp</code>","<code>DateTime</code>","Auto-set to UTC now"],
]) +

'<h2>HealthStatus Enum</h2>'
+ tbl(["Value","Meaning"], [
  ["<code>healthy</code>","All systems operational"],
  ["<code>degraded</code>","Partial issues (e.g. slow sync, outdated data)"],
  ["<code>unhealthy</code>","Critical failure"],
]) +

'<h2>SystemHealth</h2>'
'<p>Aggregates multiple <code>HealthCheckResult</code>s:</p>'
+ dart(
"final health = SystemHealth(results: {\n"
"  'db': dbCheck,\n"
"  'sync': syncCheck,\n"
"});\n\n"
"print(health.isHealthy);       // true if ALL healthy\n"
"print(health.overallStatus);   // worst status among all checks\n"
"print(health.toJson());        // structured JSON"
) +

'<h2>Built-in Providers</h2>'

'<h3>DatabaseDiagnosticsProvider</h3>'
'<p>Checks SQLite connectivity and returns table/row counts.</p>'
+ dart(
"final dbDiag = DatabaseDiagnosticsProvider(database);\n"
"final result = await dbDiag.checkHealth();\n"
"final info = await dbDiag.getDiagnostics();\n"
"// {'database_type': 'SQLite', 'tables': 5, 'total_rows': 1234, ...}"
) +

'<h3>SyncDiagnosticsProvider</h3>'
'<p>Reports on the last sync status (time, success, metrics).</p>'
+ dart(
"final syncDiag = SyncDiagnosticsProvider(\n"
"  lastSyncSuccessful: true,\n"
"  lastSyncTime: DateTime.now(),\n"
"  lastSyncMetrics: metrics.toJson(),\n"
");"
) +

'<h3>SystemDiagnosticsProvider</h3>'
'<p>Combines multiple providers into a single health check:</p>'
+ dart(
"final systemDiag = SystemDiagnosticsProvider([dbDiag, syncDiag]);\n"
"final health = await systemDiag.checkHealth();\n"
"// Overall status: worst of all sub-checks"
),
subtitle="Monitor sync infrastructure health"
)

# ── 22. TESTING ───────────────────────────────────────────────────────────────
write("testing.html", "Testing",
'<p>syncitron\'s architecture is fully testable via dependency injection. All core interfaces have in-memory or mock implementations.</p>'

'<h2>Test Configuration</h2>'
+ dart(
"final config = syncitronConfig.testing();\n"
"// Minimal overhead: no logging, no metrics, fast timeouts"
) +

'<h2>Test Doubles Strategy</h2>'
+ tbl(["Interface","Test Double"], [
  ["<code>LocalStore</code>","In-memory map-based implementation"],
  ["<code>RemoteAdapter</code>","Fake with configurable responses"],
  ["<code>Logger</code>","<code>NoOpLogger()</code> or mock that captures calls"],
  ["<code>MetricsCollector</code>","<code>InMemoryMetricsCollector</code> or <code>NoOpMetricsCollector</code>"],
]) +

'<h2>Example: In-Memory Local Store</h2>'
+ dart(
"class InMemoryLocalStore implements LocalStore {\n"
"  final Map<String, List<Map<String, dynamic>>> _tables = {};\n"
"  final Map<String, String> _cursors = {};\n\n"
"  List<Map<String, dynamic>> table(String name) =>\n"
"    _tables.putIfAbsent(name, () => []);\n\n"
"  @override\n"
"  Future<List<Map<String, dynamic>>> queryDirty(String table) async =>\n"
"    this.table(table).where((r) => r['is_synced'] == 0).toList();\n\n"
"  @override\n"
"  Future<void> upsertBatch(String table, List<Map<String, dynamic>> records) async {\n"
"    for (final record in records) {\n"
"      final idx = this.table(table).indexWhere((r) => r['id'] == record['id']);\n"
"      if (idx >= 0) this.table(table)[idx] = record;\n"
"      else this.table(table).add(record);\n"
"    }\n"
"  }\n"
"  // ... implement remaining LocalStore methods\n"
"}"
) +

'<h2>Example: Fake Remote Adapter</h2>'
+ dart(
"class FakeRemoteAdapter extends RemoteAdapter {\n"
"  final Map<String, List<Map<String, dynamic>>> remoteTables = {};\n"
"  final List<Map<String, dynamic>> upserts = [];\n\n"
"  @override\n"
"  Future<PullResult> pull(PullRequest request) async {\n"
"    final records = remoteTables[request.table] ?? [];\n"
"    return PullResult(records: records, nextCursor: null);\n"
"  }\n\n"
"  @override\n"
"  Future<void> upsert({\n"
"    required String table,\n"
"    required Map<String, dynamic> data,\n"
"    String? idempotencyKey,\n"
"  }) async {\n"
"    upserts.add({'table': table, 'data': data, 'op_id': idempotencyKey});\n"
"  }\n\n"
"  // ... implement remaining RemoteAdapter methods\n"
"}"
) +

'<h2>Integration Test</h2>'
+ dart(
"test('full sync cycle', () async {\n"
"  final local = InMemoryLocalStore();\n"
"  final remote = FakeRemoteAdapter();\n"
"  final engine = SyncEngine(\n"
"    localStore: local,\n"
"    remoteAdapter: remote,\n"
"    config: syncitronConfig.testing(),\n"
"    logger: NoOpLogger(),\n"
"  );\n\n"
"  engine.registerTable(TableConfig(\n"
"    name: 'todos',\n"
"    columns: ['id', 'title', 'updated_at', 'deleted_at'],\n"
"  ));\n\n"
"  await engine.init();\n"
"  final metrics = await engine.syncAll();\n"
"  expect(metrics.overallSuccess, isTrue);\n"
"});"
),
subtitle="Dependency injection for fully testable sync"
)

# ── 23. API REFERENCE ─────────────────────────────────────────────────────────
write("api-reference.html", "API Reference",
'<p>Complete class and method reference for syncitron v0.5.1. Organized by module.</p>'

'<div class="toc"><h4>Modules</h4><ul>'
'<li><a href="#core">Core</a> — SyncEngine, syncitronConfig, TableConfig, Models</li>'
'<li><a href="#strategy">Strategy &amp; Conflict</a> — SyncStrategy, ConflictResolution, Orchestration</li>'
'<li><a href="#exceptions">Exceptions</a> — Sealed exception hierarchy</li>'
'<li><a href="#logging">Logging &amp; Metrics</a> — Logger, MetricsCollector, LogEntry</li>'
'<li><a href="#adapters">Remote Adapters</a> — Supabase, Firebase, Appwrite, GraphQL</li>'
'<li><a href="#storage">Local Stores</a> — Sqflite, Drift, Hive, Isar</li>'
'<li><a href="#realtime-ref">Real-Time</a> — Subscription config, providers, manager</li>'
'<li><a href="#widgets-ref">UI Widgets</a> — 6 Flutter widgets</li>'
'<li><a href="#manager">Multi-Engine</a> — SyncManager</li>'
'<li><a href="#diag">Diagnostics</a> — Health checks</li>'
'<li><a href="#utils">Utilities</a> — retry()</li>'
'</ul></div>'

'<h2 id="core">Core</h2>'

'<h3>SyncEngine</h3>'
+ dart(
"SyncEngine({\n"
"  required LocalStore localStore,\n"
"  required RemoteAdapter remoteAdapter,\n"
"  syncitronConfig? config,\n"
"  Logger? logger,\n"
"  MetricsCollector? metricsCollector,\n"
"})"
) +
tbl(["Method","Signature"], [
  ["init","<code>Future&lt;void&gt; init()</code>"],
  ["registerTable","<code>SyncEngine registerTable(TableConfig config)</code>"],
  ["syncAll","<code>Future&lt;SyncSessionMetrics&gt; syncAll()</code>"],
  ["syncTable","<code>Future&lt;SyncMetrics&gt; syncTable(TableConfig config)</code>"],
  ["syncTableByName","<code>Future&lt;SyncMetrics&gt; syncTableByName(String name)</code>"],
  ["syncWithOrchestration","<code>Future&lt;SyncSessionMetrics&gt; syncWithOrchestration(SyncOrchestrationStrategy)</code>"],
  ["dispose","<code>void dispose()</code>"],
  ["statusStream","<code>Stream&lt;String&gt; get statusStream</code>"],
]) +

'<h3>syncitronConfig</h3>'
+ dart(
"const syncitronConfig({\n"
"  int batchSize = 500,\n"
"  int maxConcurrentSyncs = 1,\n"
"  Duration operationTimeout = const Duration(seconds: 30),\n"
"  int maxRetries = 3,\n"
"  Duration initialRetryDelay = const Duration(milliseconds: 300),\n"
"  Duration maxRetryDelay = const Duration(seconds: 30),\n"
"  String isSyncedColumn = 'is_synced',\n"
"  String operationIdColumn = 'op_id',\n"
"  bool autoSyncOnStartup = false,\n"
"  Duration? periodicSyncInterval,\n"
"  bool enableDetailedLogging = false,\n"
"  bool collectMetrics = true,\n"
"  bool validateOnCreation = true,\n"
"})\n\n"
"factory syncitronConfig.production()\n"
"factory syncitronConfig.development()\n"
"factory syncitronConfig.testing()\n\n"
"void validate()\n"
"syncitronConfig copyWith({...})\n"
"Map<String, dynamic> toJson()"
) +

'<h3>TableConfig</h3>'
+ dart(
"const TableConfig({\n"
"  required String name,\n"
"  required List<String> columns,\n"
"  String primaryKey = 'id',\n"
"  String updatedAtColumn = 'updated_at',\n"
"  String deletedAtColumn = 'deleted_at',\n"
"  String isSyncedColumn = 'is_synced',\n"
"  String operationIdColumn = 'op_id',\n"
"  SyncStrategy strategy = SyncStrategy.serverWins,\n"
"  ConflictResolver? customResolver,\n"
"})\n\n"
"void validate()"
) +

'<h3>SyncCursor</h3>'
+ dart(
"const SyncCursor({required DateTime updatedAt, required dynamic primaryKey})\n"
"factory SyncCursor.fromJson(Map<String, dynamic> json)\n"
"Map<String, dynamic> toJson()"
) +

'<h3>PullRequest / PullResult</h3>'
+ dart(
"const PullRequest({\n"
"  required String table,\n"
"  required List<String> columns,\n"
"  required String primaryKey,\n"
"  required String updatedAtColumn,\n"
"  SyncCursor? cursor,\n"
"  required int limit,\n"
"})\n\n"
"const PullResult({\n"
"  required List<Map<String, dynamic>> records,\n"
"  SyncCursor? nextCursor,\n"
"})"
) +

'<h2 id="strategy">Strategy &amp; Conflict Resolution</h2>'

'<h3>SyncStrategy</h3>'
'<p>Enum: <code>serverWins</code> · <code>localWins</code> · <code>lastWriteWins</code> · <code>custom</code></p>'

'<h3>ConflictResolution (sealed)</h3>'
+ tbl(["Class","Constructor","Description"], [
  ["<code>UseLocal</code>","<code>const UseLocal()</code>","Keep local record"],
  ["<code>UseRemote</code>","<code>const UseRemote(Map data)</code>","Use remote record"],
  ["<code>UseMerged</code>","<code>const UseMerged(Map data)</code>","Use merged record"],
]) +

'<h3>ConflictResolver typedef</h3>'
+ dart(
"typedef ConflictResolver = Future<ConflictResolution> Function(\n"
"  Map<String, dynamic> local,\n"
"  Map<String, dynamic> remote,\n"
");"
) +

'<h3>SyncOrchestrationStrategy (abstract)</h3>'
+ tbl(["Method","Description"], [
  ["<code>execute(context)</code>","Core sync logic — returns SyncSessionMetrics"],
  ["<code>beforeSync(context)</code>","Lifecycle hook (default: no-op)"],
  ["<code>afterSync(context, metrics)</code>","Lifecycle hook (default: no-op)"],
]) +
'<p>Built-in: <code>StandardSyncOrchestration</code> · <code>OfflineFirstSyncOrchestration</code> · <code>StrictManualOrchestration</code> · <code>PrioritySyncOrchestration</code> · <code>CompositeSyncOrchestration</code></p>'

'<h2 id="exceptions">Exceptions</h2>'
+ tbl(["Exception","Key Fields"], [
  ["<code>syncitronException</code> (sealed)","message, cause"],
  ["<code>SyncNetworkException</code>","table, statusCode, isOffline"],
  ["<code>SyncAuthException</code>","table"],
  ["<code>ConflictResolutionException</code>","table, primaryKey"],
  ["<code>SchemaMigrationException</code>","table, column"],
  ["<code>LocalStoreException</code>","table"],
  ["<code>UnregisteredTableException</code>","table"],
  ["<code>EngineConfigurationException</code>","message"],
]) +

'<h2 id="logging">Logging &amp; Metrics</h2>'

'<h3>Logger (abstract)</h3>'
+ tbl(["Method","Signature"], [
  ["debug","<code>void debug(String msg, {Map? context})</code>"],
  ["info","<code>void info(String msg, {Map? context})</code>"],
  ["warning","<code>void warning(String msg, {Map? context, Object? error})</code>"],
  ["error","<code>void error(String msg, {Object? error, StackTrace? st, Map? context})</code>"],
  ["critical","<code>void critical(String msg, {Object? error, StackTrace? st})</code>"],
  ["log","<code>void log(LogEntry entry)</code>"],
]) +
'<p>Implementations: <code>ConsoleLogger</code> · <code>NoOpLogger</code> · <code>MultiLogger</code></p>'

'<h3>LogLevel enum</h3>'
'<p><code>debug(0)</code> · <code>info(1)</code> · <code>warning(2)</code> · <code>error(3)</code> · <code>critical(4)</code></p>'

'<h3>MetricsCollector (abstract)</h3>'
+ tbl(["Method","Signature"], [
  ["recordTableMetrics","<code>void recordTableMetrics(SyncMetrics)</code>"],
  ["recordSessionMetrics","<code>void recordSessionMetrics(SyncSessionMetrics)</code>"],
  ["getLastSessionMetrics","<code>SyncSessionMetrics? getLastSessionMetrics()</code>"],
]) +
'<p>Implementations: <code>InMemoryMetricsCollector</code> · <code>NoOpMetricsCollector</code></p>'

'<h2 id="adapters">Remote Adapters</h2>'

'<h3>RemoteAdapter (abstract)</h3>'
+ tbl(["Method","Description"], [
  ["<code>pull(PullRequest)</code>","Fetch remote records since cursor"],
  ["<code>upsert(table, data, idempotencyKey?)</code>","Insert or update a single record"],
  ["<code>softDelete(table, pkColumn, id, payload, idempotencyKey?)</code>","Soft-delete a record"],
  ["<code>batchUpsert(table, records, pkColumn, idempotencyKeys?)</code>","Batch upsert (default: individual fallback)"],
  ["<code>batchSoftDelete(table, pkColumn, records, ...)</code>","Batch soft-delete (default: individual fallback)"],
  ["<code>getRealtimeProvider()</code>","Returns RealtimeSubscriptionProvider? (default: null)"],
]) +
'<p>Implementations: <code>SupabaseAdapter</code> · <code>FirebaseFirestoreAdapter</code> · <code>AppwriteAdapter</code> · <code>GraphQLAdapter</code></p>'

'<h2 id="storage">Local Stores</h2>'

'<h3>LocalStore (abstract)</h3>'
+ tbl(["Method","Description"], [
  ["<code>ensureSyncColumns(table, updatedAt, deletedAt)</code>","Add is_synced/op_id columns if missing"],
  ["<code>readCursor(table)</code>","Read last sync cursor"],
  ["<code>writeCursor(table, cursor)</code>","Write sync cursor"],
  ["<code>clearCursor(table)</code>","Clear sync cursor"],
  ["<code>queryDirty(table)</code>","Get records with is_synced = 0"],
  ["<code>upsertBatch(table, records)</code>","Batch insert/update records"],
  ["<code>markAsSynced(table, pkColumn, pk)</code>","Set is_synced = 1"],
  ["<code>setOperationId(table, pkColumn, pk, opId)</code>","Set op_id for idempotency"],
  ["<code>markManyAsSynced(table, pkColumn, pks)</code>","Batch mark synced"],
  ["<code>setOperationIds(table, pkColumn, opIds)</code>","Batch set op_ids"],
  ["<code>findById(table, pkColumn, id)</code>","Lookup single record"],
  ["<code>findManyByIds(table, pkColumn, ids)</code>","Lookup multiple records"],
]) +
'<p>Implementations: <code>SqfliteStore</code> · <code>DriftStore</code> · <code>HiveStore</code> · <code>IsarStore</code></p>'

'<h2 id="realtime-ref">Real-Time</h2>'

'<h3>RealtimeSubscriptionProvider (abstract)</h3>'
+ tbl(["Member","Signature"], [
  ["subscribe","<code>Stream&lt;RealtimeChangeEvent&gt; subscribe(String table)</code>"],
  ["isConnected","<code>bool get isConnected</code>"],
  ["connectionStatusStream","<code>Stream&lt;bool&gt; get connectionStatusStream</code>"],
  ["close","<code>Future&lt;void&gt; close()</code>"],
]) +
'<p>Implementations: <code>SupabaseRealtimeProvider</code> · <code>FirebaseFirestoreRealtimeProvider</code> · <code>AppwriteRealtimeProvider</code> · <code>GraphQLRealtimeProvider</code></p>'

'<h3>RealtimeChangeEvent</h3>'
+ dart(
"const RealtimeChangeEvent({\n"
"  required String table,\n"
"  required RealtimeOperation operation,  // insert, update, delete\n"
"  Map<String, dynamic>? record,\n"
"  Map<String, dynamic> metadata = const {},\n"
"  required DateTime timestamp,\n"
"})"
) +

'<h2 id="widgets-ref">UI Widgets</h2>'
'<p>See <a href="widgets.html">UI Widgets</a> page for full parameter tables.</p>'
+ tbl(["Widget","Purpose"], [
  ["<code>SyncStatusWidget</code>","Display sync status from statusStream"],
  ["<code>SyncMetricsCard</code>","Metrics card showing pull/push/conflict stats"],
  ["<code>SyncErrorBanner</code>","Context-aware error banner with retry/dismiss"],
  ["<code>OfflineIndicator</code>","Online/offline chip"],
  ["<code>SyncButton</code>","Sync button with loading state"],
  ["<code>SyncStatusPanel</code>","All-in-one dashboard"],
]) +

'<h2 id="manager">Multi-Engine</h2>'
'<p>See <a href="multi-engine.html">SyncManager</a> for full API.</p>'

'<h2 id="diag">Diagnostics</h2>'
'<p>See <a href="diagnostics.html">Health &amp; Diagnostics</a> for full API.</p>'

'<h2 id="utils">Utilities</h2>'

'<h3>retry&lt;T&gt;</h3>'
+ dart(
"Future<T> retry<T>(\n"
"  Future<T> Function() action, {\n"
"  int retries = 3,\n"
"  Duration initialDelay = const Duration(milliseconds: 300),\n"
"  Duration maxDelay = const Duration(seconds: 30),\n"
"  Logger? logger,\n"
"})"
) +
'<p>Retries the given <code>action</code> with exponential backoff. Used internally by SyncEngine for all remote operations.</p>',
subtitle="Complete class and method reference"
)

# ── 24. CHANGELOG ─────────────────────────────────────────────────────────────
write("changelog.html", "Changelog",
'<h2>v0.5.1</h2>'
'<ul>'
'<li>Added <code>syncTableByName(String)</code> to SyncEngine for convenience</li>'
'<li>Removed duplicate <code>HealthCheckResult</code>/<code>HealthStatus</code> from sync_manager.dart</li>'
'<li>Exported <code>sync_manager.dart</code> in barrel file</li>'
'<li>Replaced custom <code>pow()</code> with <code>dart:math</code> in realtime_subscription.dart</li>'
'<li>Fixed <code>RealtimeSubscriptionManager</code> to use <code>syncTableByName</code></li>'
'<li>Fixed <code>InMemoryMetricsCollector.recordTableMetrics()</code> double-counting bug</li>'
'<li>Fixed <code>SyncManager.syncEngine()</code> using wrong exception type</li>'
'<li>Removed unused <code>clock.dart</code></li>'
'<li>Fixed README widget API examples to match actual constructors</li>'
'</ul>'

'<h2>v0.5.0</h2>'
'<ul>'
'<li><strong>Batch Operations</strong> — 50-100× faster syncs via <code>batchUpsert</code>/<code>batchSoftDelete</code></li>'
'<li><strong>Sync Orchestration Strategies</strong> — 5 built-in strategies (Standard, OfflineFirst, StrictManual, Priority, Composite)</li>'
'<li><strong>Sealed Exception Hierarchy</strong> — <code>syncitronException</code> root with 7 specific subtypes</li>'
'<li><strong>Real-Time Subscriptions</strong> — All 4 backends (Supabase, Firebase, Appwrite, GraphQL)</li>'
'<li><strong>Multiple Storage Backends</strong> — SqfliteStore, DriftStore, HiveStore, IsarStore</li>'
'<li><strong>Multiple Remote Adapters</strong> — Supabase, Firebase Firestore, Appwrite, GraphQL</li>'
'<li><strong>SyncManager</strong> — Multi-engine coordination</li>'
'<li><strong>Diagnostics</strong> — HealthCheckResult, SystemHealth, DiagnosticsProviders</li>'
'<li><strong>UI Widgets</strong> — 6 ready-made Flutter widgets</li>'
'<li><strong>Metrics &amp; Logging</strong> — SyncMetrics, SyncSessionMetrics, structured LogEntry</li>'
'</ul>'

'<h2>v0.4.0</h2>'
'<ul>'
'<li>Supabase adapter with cursor-based pagination</li>'
'<li>Conflict resolution strategies (ServerWins, LocalWins, LastWriteWins, Custom)</li>'
'<li>Configurable retry with exponential backoff</li>'
'<li>SqfliteStore with sync column auto-migration</li>'
'</ul>',
subtitle="Version history"
)

print("\n✅ Generated " + str(len(FLAT)) + " documentation pages in docs_html/")

# ── SEARCH INDEX ──────────────────────────────────────────────────────────────
import re, json

def strip_tags(html_str):
    """Remove HTML tags and collapse whitespace."""
    text = re.sub(r'<[^>]+>', ' ', html_str)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

def extract_sections(html_str):
    """Extract h2/h3 heading text from HTML body."""
    return [strip_tags(m) for m in re.findall(r'<h[23][^>]*>(.*?)</h[23]>', html_str, re.DOTALL)]

search_index = []
for href, title in FLAT:
    filepath = os.path.join(OUT, href)
    if not os.path.exists(filepath):
        continue
    with open(filepath, "r") as f:
        html_content = f.read()
    # Extract the <main> body to avoid indexing sidebar/nav
    main_match = re.search(r'<main[^>]*>(.*?)</main>', html_content, re.DOTALL)
    body_html = main_match.group(1) if main_match else html_content
    sections = extract_sections(body_html)
    content_text = strip_tags(body_html)
    search_index.append({
        "title": title,
        "url": href,
        "sections": sections,
        "content": content_text,
    })

index_path = os.path.join(OUT, "search-index.json")
with open(index_path, "w") as f:
    json.dump(search_index, f, ensure_ascii=False)

print("🔍 Generated search-index.json (" + str(len(search_index)) + " pages indexed)")
