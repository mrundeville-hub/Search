# Building and shipping this fork

This is a fork of [Search](https://github.com/driceroland/Search) that ports features from
[Yab](https://github.com/yetanotherbrowser/yab) — which is itself a fork of Search, Apache-2.0.
What was ported, what Search already had, and what is deliberately not here is in
[GAP.md](GAP.md); the order it was done in, and the rules each port followed, are in
[PLAN.md](PLAN.md).

## Build it on this Mac

Needs Xcode 26 and Swift 6.2 or newer.

```sh
./build.sh                    # release build, ad-hoc signed, runs here
SEARCH_DEV=1 ./build.sh       # the same, named for the branch, yellow icon
```

The app lands at `build/Search.app`. Note that upstream as of `859c951` does not compile with
Xcode 26.3 / Swift 6.2.4 — three expressions were split or renamed for it in this fork
(`8223cf6`), so a plain `git checkout upstream/main && ./build.sh` fails while this branch builds.

## A disk image

```sh
./build.sh release dmg        # build/Search.dmg, build/Search.zip, build/appcast.json
```

`dmgbuild` is installed into `.build/` the first time, which needs Python 3 and a network once.

**What the signature means.** With no Developer ID certificate in the login keychain the build
says so — *"no Developer ID certificate found — the DMG will only open on this Mac"* — and signs
ad-hoc. That is enough for this Mac (the app launches, `codesign --verify --deep --strict` passes)
and not enough to give anyone else: Gatekeeper refuses an ad-hoc build that arrived from the
network. To hand it over, a Developer ID Application certificate and a `notarytool` profile are
needed (see the top of `build.sh`); then:

```sh
./build.sh release ship
```

`build/` is git-ignored: the artifacts are local, built from the branch, not committed.

## Install it here

```sh
cp -R build/Search.app /Applications/
open -a /Applications/Search.app
```

The first launch of a copy from another Mac needs System Settings › Privacy & Security ›
"Open Anyway" — an ad-hoc signature, again.

## What is in it

Everything upstream has, plus the ports listed in [GAP.md](GAP.md): userscripts (`search://userscripts`,
`GM_*`, `@require`), link cards, boosts (CSS, script, colours/type/spacing, sharing as `.boost`,
hidden blocks), snippets (`search://snippets`), agents that reach bookmarks, history, spaces and
their own notebook, one-click setup for Claude Code and Codex with a bundled MCP server and skill,
and a call window. `Craft Anything` was used to establish which of these Yab really has — the
matrix says where each was checked and where the first reading was wrong.

## Check it

```sh
swift test --filter UserscriptsTests      # and the other suites: BoostLook, BoostFile, Boost,
                                          # BoostHidden, LinkCards, Snippets, DeveloperSetup,
                                          # AgentMemory
```

The behaviour tests drive the built app through its own bench socket, one per feature:

```sh
./build.sh                                # they need build/Search.app
python3 -u Tests/userscripts.py           # 6 checks
python3 -u Tests/link_cards.py            # 7
python3 -u Tests/boosts.py                # 18
python3 -u Tests/snippets.py              # 7
python3 -u Tests/agent_wide.py            # 18
python3 -u Tests/developers.py            # 17
python3 -u Tests/call_window.py           # 11
```

Each kills and wipes its own test world (`~/Library/Application Support/Search (<world>)`) and
touches nothing of yours. Two need the building Mac's pretend devices (`call_window.py`) or a
temporary home (`developers.py`); neither writes to the real one.

`Tests/agent_control.py` is upstream's and long: 89 of its checks pass here, and it then stops in
its own "Always allow" section, which compiles a tiny C launcher — `cc` cannot link on this Mac
(CommandLineTools' `libSystem.tbd` is malformed for this clang). That is the environment, not the
fork.
