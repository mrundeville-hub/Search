# Search × Yab — feature gap

What Yab has that this fork of Search does not, what Search already has under another name, and
where the missing parts live in Yab's source so they can be ported.

**Pinned versions**

| | |
|---|---|
| Search (upstream) | `driceroland/Search` @ `859c951`, `VERSION` 1.0.15, MIT |
| This fork | `mrundeville-hub/Search`, `upstream` remote points at the line above |
| Yab (source) | `yetanotherbrowser/yab` @ `f204408`, Apache-2.0, 3013 Swift files |
| Yab (shipped) | `/Applications/yab.app`, `dev.serafim.fast`, 0.50.0 |

**Key fact.** `yab-repo/NOTICE` says: *"Yab began as a fork of Search by Office Commun, MIT
License."* Both trees are Swift + WebKit + AppKit on macOS with the same architecture, so this is
a source-to-source port **back** along a shared lineage, not a reimplementation from screenshots.
Ported files keep Yab's Apache-2.0 notice; `TRADEMARKS.md` means no Yab name, logo or icon comes
along.

**How each line was checked.** `craft-anything` triaged and inventoried the shipped bundle
(evidence `ev_c232a252…`, `ev_acc8e51d…` in `../runde/investigation-yab.cany`); every row below is
backed by files in both trees — file names plus `grep` — and by each project's own docs
(`README.md`, `ROADMAP.md`, `CHANGELOG.md`, `docs/keyboard.md`). Rows marked ❓ are guesses from
names only and need a run before anyone claims them.

Legend: ✅ have · 🟡 have, different mechanism · ❌ absent · ❓ unverified

## A. UI / Arc layer

| Feature | Search 1.0.15 | Yab 0.50 | Evidence | Phase |
|---|---|---|---|---|
| Peek at a link (⇧-click) | ✅ `Peek.swift`, Settings › "Peek at a link" | ✅ `LinkPeek.swift` | `SettingsIndex.swift:477` | — |
| Open a link **beside** (⌥-click → split) | ❌ tab click ignores ⌥ (`TabBar.swift:863`); Split View opens from the menu only | ✅ `Browser.swift`, `Split.swift`, `DoorList.swift` | grep `besidePage`/`inSplit` | 1A |
| Pins, folders, spaces | 🟡 `Pins.swift`, `PinFolders.swift`, `Spaces.swift`, `SpaceGradient.swift` | ✅ plus `SharedPins.swift`, `SpaceIconArt.swift` (Ionicons), folder-from-⌘-click, "New Tab in Folder", drag tab into another space | `Sources/Fast/Space*.swift` | 1A |
| Keep folders up to date, check at 9 | 🟡 `LiveFolders.swift` | ✅ `LiveFolderSettings.swift`, scheduled check | both trees | 1A |
| Link cards (preview before opening) | ❌ | ✅ `LinkCard.swift`, `LinkCardLoad.swift`, `LinkCardScript.swift` (3 files, 940 lines) | file listing | 1A |
| Tidy (clear the tab row) | ❌ | ✅ `Tidy.swift`, `TidyTabs.swift` (2 files, 700 lines) | file listing | 1A |
| Snippets (text expansion, Raycast/Alfred) | 🟡 `Substitutions.swift` — verify scope | ✅ `Snippet*` (3 files, 1450 lines) | grep both | 1A ❓ |
| Call window for Zoom/Slack, PiP on leaving | ❌ (only `NativePiP.swift`, `DownloadsFloat.swift`) | ✅ `FloatCall.swift` (1 file, 1075 lines), `Float*.swift` | file listing | later |
| Wrapped (year in review) | ❌ | ✅ `Wrapped*` (10 files, 2729 lines) | file listing | later |
| Smart ⌘T ("what's next": meeting, mail, last tab) | 🟡 `Omnibox.swift`, `Fuzzy.swift`, `Recall.swift` — no calendar/mail sources | ✅ field + mail + calendar sources | file listing | later |
| Tabs across the top / down the left | ✅ `TabBar.swift` (⇧⌘S) | ✅ | READMEs | — |
| Split View, pinned splits | ✅ `SplitView.swift`, `Split.swift` | ✅ plus pinning a split | both trees | — |
| PDF fill & sign | ❌ | ✅ `PDFDesk*` (10 files) | file listing | later |
| Translate | ✅ `Translate.swift` | ❌ | file listing | — (Search ahead) |

## B. Agents and MCP

| Feature | Search 1.0.15 | Yab 0.50 | Evidence | Phase |
|---|---|---|---|---|
| MCP server for coding agents | 🟡 `search-mcp` (Python, stdio → app's `agent.sock`), tools are page automation: tabs, navigate, read_page, click, type, screenshot, wait — asked in-window, Allow/Don't Allow, handles expire | ✅ in-app `Mcp.swift`, `McpRun.swift`, `McpTool.swift` (10 files, 3052 lines) + `yab` CLI | `search-mcp` header, `Sources/Fast/Mcp*.swift` | 1B |
| Tool *domains* | pages only | pages + `bookmark_*`, `mail_*` (17), `calendar_*`, `devtools_*`, `files_*`, `memory_*`, `keep_password`/`keep_address`, `know_report`, `lay_out_tabs`, `sign_in`, `approval_status` | grep tool names | 1B |
| Agent in its own tabs, your sessions, approval before send/pay | 🟡 `AgentControl.swift` (1518), `AgentTrust.swift` (465), `AgentBanner.swift`, consent in-window | ✅ plus `Approvals.swift`, `AssistantApprovals.swift`, `ApprovalDetails.swift` | file listing | 1B |
| One-click setup into Claude Code / Codex / Cursor + skill | ❌ (README documents `claude mcp add` by hand) | ✅ Settings › Developers, `yab setup`, bundled `Skills/` | yab site `/developers` | 1B |
| Chat column with the assistant | ❌ (inline `AIAssist.swift`, `AIPage.swift`, `PageQuestions.swift`) | ✅ `Chat*` (29 files) | file listing | 1B |
| Mail as an agent surface (inbox, triage, send, snippets, codes) | 🟡 `Webmail.swift` only | ✅ `MailCore/` + `Mail*` (48 files) | file listing | later |

## C. Customisation: boosts, userscripts, extensions

| Feature | Search 1.0.15 | Yab 0.50 | Evidence | Phase |
|---|---|---|---|---|
| Boosts (per-site CSS/JS, colors, fonts, hidden blocks, share/import) | ❌ `SiteStyles.swift` only reaches what the site ships; no user editor | ✅ `Boost*.swift` (34 files, 6450 lines), `ArcBoosts.swift`, `BoostCLI.swift`, `BoostEditor*` | file listing | 1C |
| Userscripts (Tampermonkey-style managers) | ❌ `Scripting.swift` (102 lines) is internal injection only | ✅ `Userscript*.swift` (6 files, 2938 lines), `UserscriptRuntime.swift` | file listing | 1C |
| Chrome extensions (WebKit + shims) | ✅ `Extensions*.swift` (18 files), `Crx.swift`, `ExtensionShims*` | ✅ (61 files, incl. Chromium) | both trees | — |
| Chrome DevTools | 🟡 `Inspector.swift` (WebKit Web Inspector) | ✅ `ChromiumDevTools.swift`, `DevTools*` | file listing | with Chromium |

## D. Explicitly out of scope for phase 1

- **Chromium engine** (CEF) — 103 files in `Sources/Fast`, plus `YabCore/` CEF build (`CMakeLists.txt`, `cef-patches/`, `ext/`) and per-tab engine switching. A project of its own, needs Xcode 26 **and** a CEF build pipeline.
- **iPhone app** (`Phone/`, 598 Swift files) and **Android** — separate applications.
- **Sync-server** (`sync-server/`) — Yab's E2EE sync service; Search's folder-based sync (`Sync.swift`, the 17 Nov 2026 decision) stays unless asked otherwise.
- **Yab trademarks, logo, icons, store branding** — `TRADEMARKS.md`.

## Port order (small, self-contained first)

| # | Item | Yab source | Size | Why first |
|---|---|---|---|---|
| 1 | Tidy | `Tidy.swift`, `TidyTabs.swift` | 700 lines | teaches the port workflow on UI-only code |
| 2 | Open a link beside (⌥-click) | `Browser.swift` + `Split.swift` + `DoorList.swift` | small, spread | most visible missing everyday gesture |
| 3 | Link cards | `LinkCard*.swift` | 940 lines | self-contained view + one script |
| 4 | Snippets | `Snippet*` | 1450 lines | shares `Substitutions.swift` ground |
| 5 | MCP server inside the app + tool domains | `Mcp*.swift`, `McpTools*.swift` | 3052 lines | flagship: agents drive the fork, adapters over `AgentControl.swift` |
| 6 | Userscripts | `Userscript*.swift` | 2938 lines | needs `Scripting.swift` |
| 7 | Boosts | `Boost*.swift` | 6450 lines | biggest; needs editor, catalog, sharing |
