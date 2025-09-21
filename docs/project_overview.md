# Why this matters

> We’re building a local-first, App-Store-compliant file finder that feels instantaneous. The Rust core gives us Lucene-grade speed with tiny resource use; SwiftUI delivers a clean, keyboard-first Mac experience. Our immediate goal is a lovable MVP that indexes user-selected folders, searches as you type in under 150 ms, and opens or previews files with zero fuss. Background indexing, Spotlight text, and saved searches land next. /// Now: * You skipped every file as unchanged (good), **but still read ~1.2 GB** of content. That means content is being read **before** your dedup/skip decision. Fixing that will massively reduce indexing time and I/O load.

---

Below is a focused, **do-this-next** plan for your assistant—first a quick perf patch to the CLI/indexer, then FFI + SwiftUI MVP.

## Project Overview (one-pager)

### 1) Elevator pitch

Build a **blazing-fast, privacy-preserving macOS file finder** with a **Rust core** (Tantivy index, glob/wildcard filters) and a **SwiftUI** shell. Users pick folders (App-Store compliant), we index filenames + text (when available), and deliver **as-you-type** search with sub-200 ms latency—even on large home directories. iOS later via shared Rust core.

### 2) Target users & jobs-to-be-done

* Power users, developers, clinicians, researchers with large local/cloud-synced folders.
* Jobs: “Find any file instantly by name/wildcard/content,” “Open or preview quickly,” “Respect privacy; stay local.”

### 3) Success metrics & SLOs (MVP)

* **Latency:** P95 ≤ **150 ms** (name/content queries, 10k–50k docs).
* **Index throughput:** ≥ **5k docs/min** for small text files on a typical dev Mac.
* **Resource use:** peak RSS < **500 MB** during indexing of 50k docs; UI remains responsive while typing.
* **UX:** ≤ 2 clicks from query to opened file; full keyboard control (⌘F, ⌘K, ⏎, ␣ Quick Look).

### 4) Scope (v0.2) & Non-goals (for now)

**In:** user-picked folders; filename + plain-text content; wildcards/globs; snippets & highlights; Quick Look; No background agent.

**Out (later):** FSEvents incremental updates; Spotlight `kMDItemTextContent`; OCR/Office deep extraction; Login Item; saved searches/regex.

### 5) Current status (baseline numbers)

* Rust core online with scanner, extractor, Tantivy schema (name + name_raw, inode/dev, fast fields on mtime/size), dedup, query API.
* CLI smoke tool: 12,587 files scanned in **1.51 s** (metadata); example queries P95 **1–3 ms** (name/content).
* Observation: content bytes were being read **before** dedup (now slated for fix); expect big I/O drop after patch.

### 6) Architecture (at a glance)

* **Rust engine:** `walkdir + ignore + rayon` (scan), **binary sniff** + size caps (extract), **Tantivy** (index/search), `globset` (wildcards), Aho-Corasick for fast literals.
* **FFI:** C-ABI (`cbindgen`) to Swift Package `FinderCoreFFI`.
* **macOS app:** SwiftUI; security-scoped bookmarks; `NSOpenPanel` to add roots; Quick Look; Finder reveal.
* **Privacy:** local-only indexing; no telemetry by default.

```mermaid
flowchart LR
  A[User picks folder] --> B[Swift Security-Scoped URL]
  B --> C[Swift enumerator (metadata-only filters)]
  C -->|changed/new| D[Rust read (sniff + size cap)]
  D --> E[Tantivy Index]
  F[Search query] --> G[FFI -> Rust search]
  G --> H[SwiftUI results + Quick Look]
```

### 7) Key decisions (and why)

* **Security-scoped bookmarks** (App Store-safe broad access).
* **Tantivy** for Lucene-class speed, incremental commits.
* **C-ABI** first (simple, stable); UniFFI later if needed.
* **No background agent (yet)**—ship a lovable interactive MVP first.

### 8) Performance playbook

* Pre-dedup **before reading** any bytes (inode/dev + mtime/size map).
* Batch commits (every 1k docs or 2 s), then refresh reader.
* Prefix-boost `name_raw`, mild recency boost via `mtime`.
* Bounded stage queues: Scan → Filter → Read → Index (backpressure).

### 9) Security & privacy

* On-device only; user-selected roots; clear settings to pause/delete index.
* Respect skip lists (system/hidden dirs), size caps, binary sniff—don’t ingest sensitive binaries inadvertently.

### 10) Repo & environment

* **/finder-core (Rust lib + bin/smoke)**
* **/mac-app (SwiftUI app + Packages/FinderCoreFFI)**
* Tooling: Rust 1.7x (edition 2021), Swift 5.x, Xcode 15+, VSCode (Rust Analyzer).
* CI: macOS runner builds Rust + Swift; style checks (`rustfmt`, `clippy`, SwiftFormat optional).

### 11) Dev workflow & quality bar

* Small PRs (<300 lines); tests required for core code paths; keep CLI perf harness results in PR description.
* Benchmarks: report docs/min, query P50/P95 on 10k–50k corpus.
* Crash-free promise: errors log + skip; never panic UI.

### 12) Near-term roadmap

* **v0.2 (current):** FFI + SwiftUI MVP with progress/cancel, snippets, keyboard flow.
* **v0.3:** FSEvents incremental updates; Spotlight text; Login Item; saved searches & filters.

### 13) Risks & mitigations

* **Sandbox friction:** solved with bookmarks + user education screen.
* **Index bloat:** fast fields only where needed; prune policies per root.
* **I/O spikes:** pre-dedup + binary sniff + bounded queues.

---

## One-week onboarding checklist (give this to the new assistant)

### Day 1–2: Understand & run

* Clone & build both targets; run CLI on 10k–50k corpus; capture baseline: docs/min, bytes_read, P50/P95.
* Verify tests (`cargo test -p finder-core`, `xcodebuild test`).
* Read `schema.rs`, `indexer.rs`, `query.rs`; sketch data flow.

### Day 2–3: Ship the I/O fix

* Implement **pre-dedup before read** and **binary sniff**; add metrics (`skipped_binary`).
* Re-run CLI; confirm bytes_read ≈ 0 on unchanged runs; record new timings.

### Day 3–4: FFI + SwiftPM

* Add C-ABI (init, add_or_update, commit_and_refresh, search, free).
* Generate header with `cbindgen`; create `FinderCoreFFI` SwiftPM wrapper.
* Swift unit test: index 3 files → search → free (Instruments: no leaks).

### Day 4–5: SwiftUI MVP

* Entitlements; add/manage locations (bookmarks).
* Index Now: enumerate → filter → read (background) → FFI; progress + cancel; toast after commit.
* Search: debounce 120 ms; Name/Content/Both; results table; ⏎ open; ␣ Quick Look.

### Deliverables by EOW

* Short screen recording: add folder → index → search → Quick Look → open.
* CLI perf table before/after I/O fix.
* Notes on edge cases hit (emojis, long paths, permissions) and how handled.

---

## 0) Quick Perf Patch (same day)

### 0.1 Pre-dedup before any content read

**Goal:** Never read bytes for files we’ll skip.

**Tasks**

* Build an in-memory **seen map** at startup: `(inode, dev) -> {mtime, size, doc_id}` by scanning the current index once.
* In the scan loop, do this order:
  1. `skip_ext / skip_dir / size_cap` checks using **metadata only**.
  2. **Dedup/unchanged check** against the seen map using `(inode, dev, mtime, size)`.
  3. Only if changed/new → read content (subject to size cap & sniffing below) → index.

**Acceptance**

* Re-running the same root shows `bytes_read` near **0 KB** (aside from directory stats).
* `skipped_dedup` remains high; wall time drops materially vs prior run.

### 0.2 Binary sniff before decode

**Goal:** Don’t waste time decoding binaries.

**Tasks**

* Read only the **first 4–8 KB** and test:
  * If NUL byte present or >10% non-printable bytes ⇒ treat as binary ⇒ **content = None** (filename-only).
* Add `--sniff-bytes <N>` flag (default 8192).

**Acceptance**

* `skipped_binary` metric appears in CLI summary.
* Content decode never runs for obvious binaries; `bytes_read` falls further.

### 0.3 Tighten metrics & knobs

**Goal:** Make perf visible and tunable.

**Tasks**

* Track and print: `files_seen, added, updated, skipped_dedup, skipped_large, skipped_ext, skipped_zero, skipped_binary, bytes_read, commits, total`.
* Add flags already echoed in your config plus:
  * `--sniff-bytes`, `--max-open-fds` (optional), `--io-workers <N>` (content read pool), `--index-workers <N>` (tantivy writer threads override).

**Acceptance**

* CLI prints the new counters and they change as expected when flags change.

---

## 1) Pipeline Architecture Hardening (still CLI; 0.5–1 day)

### 1.1 Stage pipeline with backpressure

**Goal:** Avoid RAM spikes, keep CPU busy, reduce tail latency.

**Tasks**

* Split into stages with bounded channels:
  * **Scan → Filter** (metadata only) → **Read** (I/O pool) → **Index** (tantivy writer).
* Use a bounded queue (e.g., 1024 items) between stages to create backpressure.
* Commit policy: commit every **N=1000** or **T=2000 ms**, then `refresh()`.

**Acceptance**

* Memory stays stable during large runs (doesn’t grow linearly with corpus).
* Throughput (docs/min) holds or improves vs previous run.

### 1.2 Prefix boosting & ranking polish

**Goal:** Results feel “smart” instantly.

**Tasks**

* Keep `name_raw` for exact/prefix matches; boost `(name_raw prefix)` > `(name token)` > `(content BM25)`.
* Add a mild recency boost using `mtime` fast field (e.g., score += f(mtime) with a gentle half-life).

**Acceptance**

* For queries like `README` or project names, top hits are the nearest, newest files.

---

## 2) FFI Surface (C-ABI) + Swift Package (0.5–1 day)

### 2.1 C-ABI (Rust → header via cbindgen)

**Export**

```c
bool fc_init_index(const char* index_dir);
void fc_close_index(void);

typedef struct {
  const char* path; const char* name; const char* ext;
  long long mtime; unsigned long long size;
  unsigned long long inode; unsigned long long dev;
} FCFileMeta;

bool fc_add_or_update(const FCFileMeta* meta, const char* utf8_content_or_null);
bool fc_commit_and_refresh(void);

typedef struct {
  const char* q;        // "foo" | "name:foo" | "content:foo"
  const char* glob;     // NULL or pattern
  int scope;            // 0=name,1=content,2=both
  int limit;            // e.g., 200
} FCQuery;

typedef struct {
  const char* path; const char* name;
  long long mtime; unsigned long long size; float score;
} FCHit;

typedef struct { FCHit* hits; int count; } FCResults;

FCResults fc_search(const FCQuery* query);
void fc_free_results(FCResults* results);
```

**Acceptance**

* Minimal Swift test target links, indexes 3 files, searches 1 query, frees results (Instruments: no leaks).

### 2.2 SwiftPM wrapper `FinderCoreFFI`

**Tasks**

* Wrap C calls in small Swift types; ensure safe UTF-8 conversion both ways.
* Add a tiny “E2E” Swift test: init temp index → add 3 meta+content → search → assert hits.

**Acceptance**

* `xcodebuild test` green on clean checkout.

---

## 3) SwiftUI MVP (1–2 days)

### 3.1 Permissions, locations, and indexing

**Tasks**

* Enable App Sandbox; use **NSOpenPanel** (directories only) to get a root; save a **security-scoped bookmark**.
* “Manage Locations…” view to list/remove roots.
* “Index Now”:
  * Enumerate files within each root using security-scoped URLs.
  * Apply your **metadata-only filters** first (ext/size/dedup).
  * For changed/new files under size cap, read **on a background queue**, pass to FFI.
  * Commit every N/T and show live counts.

**Acceptance**

* Add a large folder; indexing proceeds with visible progress; relaunch persists locations; no sandbox errors.

### 3.2 Search UX that feels instant

**Tasks**

* Search field + scope (Name | Content | Both).
* **Debounce ~120 ms**, run on a background queue; modern List/Table with two-line cells:
  * **Name** (bold), **…/parent/dir** (monospaced tail-truncated), **“2d ago”**, size.
* Keyboard flows: ⌘F focus, ⌘K clear, ↑/↓ select, ⏎ open, **␣ Quick Look**.
* Double-click/⏎: reveal in Finder (`NSWorkspace.shared.activateFileViewerSelecting([url])`).

**Acceptance**

* Typing never blocks UI; P95 query time ≤ **150 ms** on ~10k–50k docs; opening files works.

### 3.3 Snippets & highlights (quick win)

**Tasks**

* If `content` exists, use Tantivy `SnippetGenerator` to return up to 2 fragments with highlights; otherwise filename-only row.
* Gray ellipses between fragments; bold the matched term.

**Acceptance**

* Query “patient” shows readable context on text files; binaries show filename-only.

### 3.4 Progress, cancel, and resilience

**Tasks**

* Per-location progress with **Cancel** that flips an atomic flag the reader checks between items.
* After each commit, small toast: “Indexed 12,431 files (9.2s)”.
* If a file read fails, log & continue; never crash.

**Acceptance**

* Cancel leaves index consistent; re-index resumes without full rebuild.

---

## 4) What to hand back after this pass

1. **CLI perf table** (same corpus as before) after 0.1–1.2 patches:
   * Expect `bytes_read` near **0 KB** on unchanged runs; total time ↓ sharply; docs/min reported for changed files.
2. **Swift demo clip**: add folder → index → live search → Quick Look → open in Finder.
3. **Resource snapshot**: RAM & CPU during index and rapid typing; flag anything >500 MB or UI jank.
4. **Edge-case log**: emojis/diacritics, very long paths, permission errors, zero-byte files—no crashes.

---

## Optional quick stubs (paste-ready)

### Binary sniff (Rust)

```rust
fn looks_binary(head: &[u8]) -> bool {
    if head.iter().any(|&b| b == 0) { return true; }
    let non_printable = head.iter().filter(|&&b| b < 9 || (b > 13 && b < 32)).count();
    non_printable as f32 / head.len().max(1) as f32 > 0.10
}
```

### Stage channels (Rust)

```rust
let (tx_meta, rx_meta) = crossbeam_channel::bounded(1024);
let (tx_read, rx_read) = crossbeam_channel::bounded(1024);
// scan -> tx_meta; filter/dedup -> tx_read; io pool consumes rx_read; writer consumes io outputs
```

### Quick Look (Swift)

```swift
import QuickLook

final class PreviewCtrl: NSObject, QLPreviewPanelDataSource {
    var urls: [URL] = []
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt i: Int) -> QLPreviewItem { urls[i] as NSURL }
}

let previewCtrl = PreviewCtrl()
func quickLook(_ url: URL) {
    previewCtrl.urls = [url]
    QLPreviewPanel.shared()?.dataSource = previewCtrl
    QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
}
```
