# Plan — closing the gap with Yab

Phases and their first commits. Feature truth and evidence live in [GAP.md](GAP.md); Yab's source
is the reference for each port (`git clone https://github.com/yetanotherbrowser/yab` — Apache-2.0,
not included in this repo).

## Rules for every port

0. **Where the work lives:** `port/plan` is the documents (this file, GAP.md) and the build fixes;
   `port/phase-1` is the phase-1 code on top of it, one commit per feature — userscripts
   (`ffaf18f`, `d3845fe`, `2de42b1`, `6433187`) then link cards (`53c1ff5`).
1. **One feature per branch, one commit per feature.** Branch `port/<feature>`, message
   `Port <feature> from Yab (Apache-2.0)`, and the ported files keep a header:
   `// Ported from Yab (github.com/yetanotherbrowser/yab), Apache-2.0, Copyright 2026 Serafim Korablev`.
2. **Adapt, do not transplant.** Yab files lean on `SharedContracts`, `YabCore`, `SyncKit` and a
   different `Browser`/`Tab`/`Prefs` shape. Port the behaviour onto Search's types; a file that
   pulls in a Yab subsystem goes back to the plan.
3. **Build and test before the commit.** `SEARCH_DEV=1 ./build.sh` must exit 0, and the feature
   needs a `Tests/<feature>.py` in Search's existing style where the behaviour is observable.
4. **No Yab names, icons, strings, or curated art** (TRADEMARKS.md). Ionicons glyphs are MIT —
   keep their notice if space icons are ported.

## Phase 1A — UI / Arc layer

| Order | Work | Source in Yab | Done when |
|---|---|---|---|
| 1 | Tidy: close/group the tab row in one go | `Tidy.swift`, `TidyTabs.swift` | menu item + shortcut, tabs close as asked, `Tests/tidy.py` passes |
| 2 | ⌥-click a link opens it beside the page (⌥⇧-click for the other side) | `Browser.swift`, `Split.swift` | link click with ⌥ yields a split, ⇧-peek still wins where both are on, `Tests/open_beside.py` |
| 3 | Link cards: preview on hover/peek without opening | `LinkCard*.swift` | card shows title, address, icon; dismisses on move; no network until asked |
| 4 | Snippets: expand a trigger in the field and in page text | `Snippet*`, `Substitutions.swift` | round trip through Settings, Raycast/Alfred URL scheme optional |
| 5 | Call window — **done**: `CallWindow.swift`, Tabs › Float This Call, `Browser.floatCall`/`landCall`; the page on a call moves window and keeps running. Automatic floating is in too, behind its own setting (the tab in front, once a second, only while it is on) | `FloatCall.swift` | a call can be watched in a window of its own while you work elsewhere |
| 6 | Spaces: per-space colour + icon, folder from ⌘-click, drag tab into a space | `SpaceIconArt.swift`, `SpaceSettings.swift`, `SpaceDrop.swift` | colour and icon persist; drag-in works on the same data as `Spaces.swift` |

## Phase 1B — agents and MCP

| Order | Work | Source in Yab | Done when |
|---|---|---|---|
| 1 | MCP server inside the app (no Python bridge): a loopback socket the app serves, JSON-RPC over stdio through a small `search` CLI | `Mcp.swift`, `McpRun.swift`, `McpTool.swift` | `search` CLI speaks `initialize`/`tools/list`/`tools/call`; existing `search-mcp` keeps working |
| 2 | Tool domains beyond pages — **half done**: `bookmarks`, `bookmark_add`, `history`, `spaces`, `space_switch` (`AgentWide.swift` + `search-mcp`), the ask card says what they reach. Left: `memory_*`, `keep_password`/`keep_address`, `lay_out_tabs`, `approval_status` (and mail, which needs the mail subsystem first) | `McpToolsShelf.swift`, `McpToolsKnowing.swift`, `McpToolsPerson.swift` | every tool maps onto an existing verb in `AgentControl.swift`; nothing new gets reach it did not have |
| 3 | Approvals parity: send, pay, delete ask first and show what will happen | `Approvals.swift`, `AssistantApprovals.swift` | an agent action that spends or sends is blocked until answered in-window |
| 4 | One-click setup into Claude Code / Codex + bundled skill — **done**: `DeveloperSetup.swift` writes `~/.claude.json` and `~/.codex/config.toml` with a backup, writes the skill, copies the entry for other clients, and `build.sh` ships `search-mcp` inside the app. Both a Set Up and a **Remove that takes back only what it wrote** (done): an entry pointing at another copy, or a skill someone has edited, is left and said so | `Skills/`, `SkillInstall` in Yab's settings | Settings › Developers writes the entries and can remove only what it added |
| 5 | Chat column with the assistant, per space | `Chat*.swift` | the column opens beside the page; `PageQuestions.swift` still answers inline asks |

## Phase 1C — customisation

| Order | Work | Source in Yab | Done when |
|---|---|---|---|
| 1 | Userscripts: install from a URL, manage, run per site | `Userscript*.swift` | a user script mutates a page after load, off/on per site, `Tests/userscript.py` |
| 2 | Boosts: per-site CSS/JS editor with colours, fonts, hidden blocks | `Boost*.swift` | a boost survives relaunch, applies before first paint, shares as a link/file |
| 3 | Boost catalog and AI-assisted creation | `BoostCatalog.swift`, `BoostAI.swift` | optional; comes after the editor works |

## After phase 1 (needs a decision from the user)

- Mail as an agent surface (`MailCore/`), PDF desk, Float call window, Wrapped, smart ⌘T.
- Chromium engine (CEF) — separate project, separate build pipeline.
- iPhone / Android companions — separate applications.
