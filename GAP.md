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
| Open a link **beside** (⌥-click → split) | ✅ `Browser.openLinkBeside(_:from:)` — *"A link ⌥-clicked: in a tab of its own beside the page it came from"* (`Browser.swift:6229`), `openInSplit` (`:6221`, `:4277`) | ✅ same lineage | `Sources/Search/Browser.swift:6229` | — |
| Pins, folders, spaces | 🟡 `Pins.swift`, `PinFolders.swift`, `Spaces.swift`, `SpaceGradient.swift` | ✅ plus `SharedPins.swift`, `SpaceIconArt.swift` (Ionicons), folder-from-⌘-click, "New Tab in Folder", drag tab into another space | `Sources/Fast/Space*.swift` | 1A |
| Keep folders up to date, check at 9 | 🟡 `LiveFolders.swift` | ✅ `LiveFolderSettings.swift`, scheduled check | both trees | 1A |
| Link cards (preview before opening) | ✅ **ported** (this fork): `LinkCards.swift` — title, description and icon of the link under the pointer, asked for once the pointer rests, off unless Settings › Links turns it on. **Smaller than Yab's**: Yab loads the page itself in a hidden tab, signed in as you; this reads the page's head with one cookie-less request and runs nothing | ✅ `LinkCard.swift`, `LinkCardLoad.swift`, `LinkCardScript.swift` (3 files, 940 lines) | `Sources/Search/LinkCards.swift`, `StatusLine.swift` | done |
| Tidy: tabs close themselves after being left alone | ✅ **same feature, different name** — `Closing.swift` ("Tabs that close themselves, as in Arc": 12 h / day / week / month, keeps on-screen, pinned, named, grouped, busy; archives for a month, ⇧⌘T brings back) | ✅ `Tidy.swift`, `TidyTabs.swift` (2 files, 700 lines) | `Sources/Search/Closing.swift:1-26` | — |
| Snippets (text expansion) | ✅ **ported, plain half** (this fork): `Snippets.swift` — a list of names in `snippets.json`, `;name` + space or Tab in any page box takes the text in, never in a password or one-code box, off with its setting, `search://snippets` and View › Snippets… to keep the list. Search's own `Substitutions.swift` is macOS's Text Replacements inside pages, not a library of its own. **Missing vs Yab:** the list under the caret, bringing in Text Replacements/Alfred/espanso/Raycast, mail snippets, and the address field | ✅ `Snippet*` (3 files, 1450 lines) + `MailSnippets` | `Sources/Search/Snippets.swift`, `Tab.swift` | 1A done |
| Call window for Zoom/Slack | ✅ **ported** (this fork): `CallWindow.swift` + `Browser.floatCall`/`landCall`, Tabs › Float This Call — the page on a call lifted into a plain resizable window that stays above everything, the same page still running (Search already knew a tab was on a call: `StageView.onCall`). **And by itself:** with Settings › Browsing › Pages › "Float a call when it starts" on, the tab in front is looked at once a second and a call goes out into the window as it begins, coming back when the call ends. The call window still has no controls of its own | ✅ `FloatCall.swift` (1 file, 1075 lines), `Float*.swift` | `Sources/Search/CallWindow.swift` | 1A done |
| Wrapped (year in review) | ❌ | ✅ `Wrapped*` (10 files, 2729 lines) | file listing | later |
| Smart ⌘T ("what's next": meeting, mail, last tab) | 🟡 `Omnibox.swift`, `Fuzzy.swift`, `Recall.swift` — no calendar/mail sources | ✅ field + mail + calendar sources | file listing | later |
| Tabs across the top / down the left | ✅ `TabBar.swift` (⇧⌘S) | ✅ | READMEs | — |
| Split View, pinned splits | ✅ `SplitView.swift`, `Split.swift` | ✅ plus pinning a split | both trees | — |
| PDF fill & sign | ❌ `Snap.swift` only rasterises a PDF page; no form fields | ✅ `PDFDesk*` (10 files) | grep both | later |
| Translate | ✅ `Translate.swift` | ❌ | file listing | — (Search ahead) |

## B. Agents and MCP

| Feature | Search 1.0.15 | Yab 0.50 | Evidence | Phase |
|---|---|---|---|---|
| MCP server for coding agents | 🟡 `search-mcp` (Python, stdio → app's `agent.sock`), tools are page automation: tabs, navigate, read_page, click, type, screenshot, wait — asked in-window, Allow/Don't Allow, handles expire | ✅ in-app `Mcp.swift`, `McpRun.swift`, `McpTool.swift` (10 files, 3052 lines) + `yab` CLI | `search-mcp` header, `Sources/Fast/Mcp*.swift` | 1B |
| Tool *domains* | 🟡 **wider now** (this fork): pages plus `bookmarks`, `bookmark_add`, `history`, `spaces`, `space_switch` (`AgentWide.swift`) and `memory_write`/`memory_read`/`memory_search`/`memory_forget` (`AgentMemory.swift`), and the question says what they reach. **Still missing vs Yab:** mail, calendar, devtools, files, `keep_password`, `lay_out_tabs`, `sign_in` | pages + `bookmark_*`, `mail_*` (17), `calendar_*`, `devtools_*`, `files_*`, `memory_*`, `keep_password`/`keep_address`, `know_report`, `lay_out_tabs`, `sign_in`, `approval_status` | grep tool names | 1B partly |
| Agent in its own tabs, your sessions, approval before send/pay | 🟡 `AgentControl.swift` (1518), `AgentTrust.swift` (465), `AgentBanner.swift`, consent in-window | ✅ plus `Approvals.swift`, `AssistantApprovals.swift`, `ApprovalDetails.swift` | file listing | 1B |
| One-click setup into Claude Code / Codex / Cursor + skill | ✅ **ported** (this fork): Settings › About › Developer — "Set up Claude Code" and "Set up Codex" write the entry into `~/.claude.json` / `~/.codex/config.toml` (with a backup), write a skill to `~/.claude/skills/search` / `~/.agents/skills/search`, "Remove what Search set up" takes back only what it wrote (another copy's entry, or an edited skill, is left and said so), "Copy the agent config" for Cursor, Zed, Windsurf and Claude Desktop, and the MCP server itself now ships inside the app | ✅ Settings › Developers, `yab setup`, bundled `Skills/` | `Sources/Search/DeveloperSetup.swift`, `build.sh` | 1B done |
| Chat column with the assistant | ❌ (inline `AIAssist.swift`, `AIPage.swift`, `PageQuestions.swift`) | ✅ `Chat*` (29 files) | file listing | 1B |
| Mail as an agent surface (inbox, triage, send, snippets, codes) | 🟡 `Webmail.swift` only | ✅ `MailCore/` + `Mail*` (48 files) | file listing | later |

## C. Customisation: boosts, userscripts, extensions

| Feature | Search 1.0.15 | Yab 0.50 | Evidence | Phase |
|---|---|---|---|---|
| Boosts | ✅ **both halves now** (this fork): `SiteStyles.swift` keeps a site's CSS *and* its script in `styles.json` (v2, old files still read), the editor in View › Edit Site Style… switches between CSS and Script, the CSS goes in before first paint, the script runs wrapped once the document is there and is off with the switch. **Sharing done too:** a boost is a `.boost` file (format `search-boost`, both halves, its site) — Share… and Copy in the editor, Bring in… in Settings. **Colours and type too:** `BoostLook.swift` — ground, text, font and text size, written as one rule on the root ahead of your own CSS, kept per site (`styles.json` v3, older files still read) and carried in a `.boost` file. **And the spacing:** line height and the room around paragraphs, as two more switches. **And hidden blocks:** a `.boost` file carries the site's hidden selectors (⇧⌘H's work) and brings them when it comes in, applied to the pages already open. **Still missing vs Yab:** the catalog and `BoostAI` (both want a server Search hasn't got) | ✅ `Boost*.swift` (34 files, 6450 lines), `ArcBoosts.swift`, `BoostEditor*`, `BoostAI`, `BoostCLI` | `Sources/Search/SiteStyles.swift`, `Tab.swift:1252` | 1C done |
| Userscripts (Tampermonkey-style managers) | ❌ `Scripting.swift` (102 lines) is internal injection only | ✅ `Userscript*.swift` (6 files, 2938 lines), `UserscriptRuntime.swift` | file listing | 1C |
| Chrome extensions (WebKit + shims) | ✅ `Extensions*.swift` (18 files), `Crx.swift`, `ExtensionShims*` | ✅ (61 files, incl. Chromium) | both trees | — |
| Chrome DevTools | 🟡 `Inspector.swift` (WebKit Web Inspector) | ✅ `ChromiumDevTools.swift`, `DevTools*` | file listing | with Chromium |

## D. Explicitly out of scope for phase 1

- **Chromium engine** (CEF) — 103 files in `Sources/Fast`, plus `YabCore/` CEF build (`CMakeLists.txt`, `cef-patches/`, `ext/`) and per-tab engine switching. A project of its own, needs Xcode 26 **and** a CEF build pipeline.
- **iPhone app** (`Phone/`, 598 Swift files) and **Android** — separate applications.
- **Sync-server** (`sync-server/`) — Yab's E2EE sync service; Search's folder-based sync (`Sync.swift`, the 17 Nov 2026 decision) stays unless asked otherwise.
- **Yab trademarks, logo, icons, store branding** — `TRADEMARKS.md`.

## Port order (small, self-contained first)

Corrected after checking the port order against Search's own source: Tidy (`Closing.swift`) and
⌥-click open-beside (`Browser.openLinkBeside`) are already there, and Boosts exist in CSS-only
form, so the first port is userscripts.

| # | Item | Yab source | Size | Why first |
|---|---|---|---|---|
| 1 | Userscripts: install from URL, manage, run per site | `Userscript.swift`, `Userscripts.swift`, `UserscriptRuntime.swift`, `UserscriptViews.swift`, `UserscriptMove.swift` | 2938 lines, 6 files | genuinely absent; `Tab.swift` already builds `WKUserScript`s, so the hook exists |
| 2 | Boosts, the rest: JS in a boost, the editor's colours/fonts/hidden blocks, sharing | `Boost*.swift` | 6450 lines, 34 files | builds on `SiteStyles.swift` |
| 3 | Link cards (preview on hover) | `LinkCard*.swift` | 940 lines | self-contained view + one script; `HoveredLink` already reports the destination |
| 4 | Chat column with the assistant | `Chat*.swift` | 29 files | sits beside `AIAssist.swift` |
| 5 | In-app MCP server + wider tool domains | `Mcp*.swift`, `McpTools*.swift` | 3052 lines | extends `search-mcp`/`AgentControl.swift` |

## Building the fork

Upstream `859c951` **does not compile** with this machine's toolchain (Xcode 26.3, Swift 6.2.4):
`App.body` exceeds the type checker's patience, `Recall.swift`'s gradient opacity is ambiguous, and
`Fold.shownPages` shadows `Browser.tabs` with the name it declares. The fork carries three
behaviour-preserving fixes first (`8223cf6`), then the ports. `swift build` and `swift test` both
work from there; `./build.sh` assembles the app.

## Corrections to this document

2026-11-20, after the first port attempt: three rows above were wrong because the first pass went
by file names instead of behaviour — `Closing.swift` is Tidy, `Browser.openLinkBeside` is ⌥-click
open-beside, and `SiteStyles.swift` is Boosts (CSS only). Every remaining ❌ was then re-checked
with a behaviour `grep`, not a file-name match.
