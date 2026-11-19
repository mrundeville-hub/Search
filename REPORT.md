# What this fork added, and how it was checked

A port of Yab's features into Search, done along the shared lineage both browsers come from
(Yab's `NOTICE` says it began as a fork of Search). The matrix of what was missing, what Search
already had and what is deliberately not here is [GAP.md](GAP.md); the order and the rules are
[PLAN.md](PLAN.md); building and shipping are [RELEASE.md](RELEASE.md).

Branch `port/plan` holds the documents and three build fixes; `port/phase-1` holds the features, one
commit each: **23 commits, 45 files, ~5,500 lines**, on top of upstream `859c951` (Search 1.0.15).

## The features

| Feature | Where it is | Commits | Unit tests | Behaviour test |
|---|---|---|---|---|
| Userscripts: `==UserScript==` reader, `@match`/`@include`/`@exclude`, store, injection; `search://userscripts` page; `GM_*` values; `@require` pinned by SHA-256 | `Userscripts.swift`, `UserscriptViews.swift` | `ffaf18f`, `d3845fe`, `2de42b1`, `6433187` | `UserscriptsTests` 18 | `Tests/userscripts.py` 6 |
| Link cards: title, description, icon of the link under the pointer, asked once, off by default | `LinkCards.swift` | `53c1ff5` | `LinkCardsTests` 8 | `Tests/link_cards.py` 7 |
| Boosts: a site's CSS and its script, the Look (ground, text, font, size, line height, paragraph spacing), sharing as a `.boost` file, hidden blocks carried too | `SiteStyles.swift`, `BoostFile.swift`, `BoostLook.swift` | `caf01a1`, `6d7412a`, `e7a9daf`, `ada3e15`, `825fcb5` | `BoostTests` 6, `BoostFileTests` 5, `BoostLookTests` 8, `BoostHiddenTests` 3 | `Tests/boosts.py` 18 |
| Snippets: `;name` and a space or Tab in any page box, never in a password or code box | `Snippets.swift` | `835bfbe` | `SnippetsTests` 6 | `Tests/snippets.py` 7 |
| Agents beyond the page: `bookmarks`, `bookmark_add`, `history`, `spaces`, `space_switch`, `approval_status`, `close_my_tabs` | `AgentWide.swift` | `0b0df37`, `4e9ba77` | — | `Tests/agent_wide.py` 24 |
| The agent's notebook: `memory_write`/`read`/`search`/`forget`, kept between sessions, emptied from Settings | `AgentMemory.swift` | `a1720ea` | `AgentMemoryTests` 6 | `Tests/agent_wide.py` 24 |
| One-click setup into Claude Code and Codex with a bundled skill, and a Remove that takes back only what it wrote | `DeveloperSetup.swift`, `build.sh` | `19fb6d7`, `c576557` | `DeveloperSetupTests` 12 | `Tests/developers.py` 17 |
| Call window: the page on a call lifted into a window of its own, by menu, and by itself when a call starts | `CallWindow.swift` | `586e9e2`, `8ebd1b3` | — | `Tests/call_window.py` 11 |
| Three build fixes, without which upstream does not compile on Xcode 26.3 / Swift 6.2.4 | `App.swift`, `Recall.swift`, `Fold.swift` | `8223cf6` | — | the build itself |

Every behaviour test drives the built app through its own bench socket, in a world of its own, and
the numbers above are what `./verify.sh` prints.

## Refused, with the reason

- **`keep_password` / `keep_address`** — a password is not something one “Allow” hands over for a
  whole session. It wants a consent per call, and that is a design decision, not a port.
- **`lay_out_tabs`** — it arranges the person's whole window. `close_my_tabs` takes back only the
  agent's own tabs, which is the part that is the agent's business.
- **The boost catalog and `BoostAI`** — both need a server, and Search's stated position is that
  there is none: no sync, no account, no cloud.
- **Chromium/CEF, the iPhone and Android apps, the mail subsystem, the PDF desk, Wrapped** — separate
  projects or separate applications, out of this phase by decision, not by omission.

## Checking it yourself

```sh
./verify.sh              # the unit tests, then one behaviour test per feature
./verify.sh units        # the unit tests alone
./verify.sh behaviour    # against build/Search.app (built if missing)
```

Last full run: **all nine unit suites green (72 tests), all seven behaviour tests green (90 checks)**.
The one upstream test that does not finish here — `Tests/agent_control.py` — passes 89 of its checks
and then stops compiling a small C launcher with `cc`, which cannot link on this Mac
(CommandLineTools' `libSystem.tbd` is malformed for this clang). That is the environment, not the
port; it is written down in [RELEASE.md](RELEASE.md) too.
