# RepliCore Gap-Analyse: Vom Package zum Flutter-Standard für Sync

## Kurzfazit
RepliCore hat einen guten Kern (lokale Dirty-Flag-Logik, Pull/Push, Konfliktstrategien), ist aber noch **ein early-stage package** und kein vollwertiges Sync Framework.

Der größte Hebel ist nicht ein einzelnes Feature, sondern ein "Production-Grade Sync Contract":
- korrektes Cursoring,
- Idempotenz,
- robuste Konflikt- und Tombstone-Strategien,
- garantierte Reihenfolge und Replays,
- starke Testmatrix,
- Telemetrie + DX.

## Kritische Schwachstellen (Must-Fix)

### 1) Cursoring ist potenziell inkorrekt bei gleichen `updated_at` Werten
Aktuell wird beim Pull nur über `updated_at > cursor.updatedAt` paginiert. Bei mehreren Datensätzen mit identischem Zeitstempel können Einträge zwischen Batches übersprungen werden.

**Verbesserung:**
- Stabile Cursor-Semantik mit `(updated_at, primary_key)` als zusammengesetztem Cursor.
- Query-Bedingung: `updated_at > lastUpdatedAt OR (updated_at = lastUpdatedAt AND pk > lastPk)`.
- Immer deterministische Sortierung auf beiden Feldern.

### 2) Primärschlüssel wird im SupabaseAdapter teilweise hart auf `id` angenommen
`nextCursor.primaryKey` und `softDelete(...).eq('id', id)` sind nicht generisch für Tabellen mit anderem PK-Namen.

**Verbesserung:**
- PK explizit im PullRequest/Adapter überall mitführen.
- SoftDelete/Upsert strikt nach `TableConfig.primaryKey` ausführen.
- Contract-Tests für Tabellen mit `uuid`, `slug`, zusammengesetzten Schlüsseln (letzteres ggf. explizit nicht unterstützt, aber dokumentiert).

### 3) Lokale Konflikterkennung ist zu grob
`localWins`/`lastWriteWins` nutzen keine Feldhistorie oder Versionsnummern. Nur Zeitstempel-basiertes LWW kann in verteilten Systemen zu stillen Datenverlusten führen (Clock drift, nicht-monotone Uhren).

**Verbesserung:**
- Optionale `version` Spalte (inkrementell serverseitig) als authoritative Order.
- Hybrid-Policy: `version` bevorzugen, `updated_at` nur Fallback.
- Konflikte als Events exponieren (Hook + Stream), damit Apps UX-Entscheidungen treffen können.

### 4) Keine echte Idempotenz-/Replay-Garantie beim Push
Nach einem Netzwerkfehler ist unklar, ob ein Upsert serverseitig schon angenommen wurde. Bei Retry fehlen dedizierte Idempotency-Keys.

**Verbesserung:**
- Client-side Operation IDs (`op_id`) pro Mutation.
- Serverseitig deduplizierbare Upsert/Delete-Endpunkte (oder RPC), die `op_id` beachten.
- At-least-once bewusst designen und durch Idempotenz sicher machen.

### 5) Fehlende End-to-End-Tests für harte Sync-Szenarien
Es gibt aktuell faktisch keine belastbaren Tests, die Konflikte, Pagination-Ränder, Offline-Recovery und Retry-Verhalten absichern.

**Verbesserung:**
- Testpyramide:
  - Unit (Resolver, Retry, Cursor-Transitions),
  - Integration (Sqflite + mock Remote),
  - E2E (lokal/CI gegen Supabase Test-Stack).
- Property-based Tests für Merge- und Cursor-Invarianten.

## Wichtige Verbesserungen (Should-Fix)

### 6) Delta-Strategie und Change Feed fehlen
Polling via `updated_at` reicht für viele Apps, aber nicht für niedrige Latenz oder große Datenmengen.

**Verbesserung:**
- Optionaler Realtime-Mode (Supabase Realtime) mit lokalem Apply-Log.
- Backfill + Catch-up über Cursor, damit Realtime-Ausfälle robust überbrückt werden.

### 7) Keine dedizierte Queue/Backpressure-Steuerung
Push läuft sequentiell pro Datensatz. Bei vielen Änderungen fehlen priorisierte Queues, Parallelität mit Limits, Pause/Resume.

**Verbesserung:**
- Persistente Mutations-Queue (SQLite-Tabelle) mit Zuständen: pending/running/succeeded/failed.
- Config: maxConcurrency, retryBudget, dead-letter handling.

### 8) Schema- und Migrationserkennung ist nützlich, aber begrenzt
Auto-Add von Sync-Spalten ist gut, aber ohne tiefere Schema-Validierung kann es zu stillen Problemen kommen.

**Verbesserung:**
- Schema-Checks mit klaren Fehlern (Typen, NOT NULL, PK-Existenz).
- `preflight()` API: liefert diagnosefähigen Report vor erstem Sync.

### 9) Observability zu schwach für Production
String-Statusstream allein reicht nicht für Operations.

**Verbesserung:**
- Strukturierte Events/Metriken: sync duration, throughput, retries, conflict count, lag.
- Optionales Logger/Telemetry Interface (OpenTelemetry/Sentry Hooks).

### 10) Sicherheits- und RLS-Guidance fehlt
Für Community-Standard braucht es klare Sicherheitsvorgaben für Supabase RLS und Multi-tenant Trennung.

**Verbesserung:**
- Security-Playbook in Doku:
  - empfohlene RLS-Policies,
  - Tenant-Isolation,
  - PII/Encryption-at-rest Optionen lokal.

## Produkt- und DX-Hebel (Could-Fix mit hoher Wirkung)

### 11) Klare API-Layer für Adapter-Ökosystem
Der Adapter-Ansatz ist gut; als Framework braucht es stabile Schnittstellen und Versionierung.

**Verbesserung:**
- `RemoteAdapter` Capabilities deklarieren (pull cursor, transactional batch, realtime, server timestamps).
- Adapter-Compliance-Testkit veröffentlichen.

### 12) Developer Experience: "it just works"
Der Weg zur Adoption in Flutter hängt stark von Defaults + Docs + Beispielen ab.

**Verbesserung:**
- Opinionated Starter (`Replicore.bootstrap(...)`) mit Best-Practice Defaults.
- Referenz-Apps (Todo, Chat, CRM lite) inkl. Konflikt-UI.
- Migrations-Guide von online-only Supabase zu offline-first.

### 13) Stabilitäts- und Release-Disziplin
Version `0.1.0` signalisiert frühe Phase.

**Verbesserung:**
- Öffentliche Roadmap + RFC Prozess.
- SemVer streng einhalten, Breaking Changes klar kennzeichnen.
- CI-Matrix (Flutter stable/beta, Android/iOS/macOS/Linux).

## Vorschlag: 90-Tage Roadmap

### Phase 1 (0-30 Tage): Korrektheit
- Cursor-Fix `(updated_at, pk)` + PK-Verallgemeinerung.
- Idempotente Push-Basis mit `op_id` Design.
- 20+ harte Integrations-Tests für Konflikte/Pagination.

### Phase 2 (31-60 Tage): Robustheit
- Persistente Mutations-Queue + Retry/Backoff Policies.
- Strukturierte Sync-Events + Metriken.
- Preflight/Schema-Validation API.

### Phase 3 (61-90 Tage): Adoption
- Realtime-Hybridmodus (optional).
- Adapter-Compliance-Testkit.
- Exzellente Docs + 2-3 Showcase-Apps.

## Messbare Kriterien für "Community-Standard"
- **Reliability:** <0.1% irrecoverable sync failures in soak tests.
- **Correctness:** keine Datenverluste in deterministischen Conflict-Suites.
- **Performance:** >10k records sync in vertretbarer Zeit auf Mid-range Geräten.
- **DX:** Setup <15 Minuten bis erster erfolgreicher Offline/Online Roundtrip.
- **Trust:** klare Security/RLS Doku + reproduzierbare CI-Badges.
