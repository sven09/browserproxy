# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Picker rows have **Domain** and **App** toggle buttons (text instead of the 📌 / ▢ icons). A green ✓ shows which browser holds the binding; clicking switches it on or off (`enabled: false`) without closing the picker. ⌥-click Domain binds the exact host (shown as ✓ Host)
- `⌘R` in the picker opens `rules.json` (or reveals the folder if it doesn't exist yet) to remove or pause a binding

### Changed

- Picker footer now has hint lines for navigation, the Domain / App toggles, the bind-and-open shortcuts (`⌘P`, `⌘⇧P`), `⌘R`, and `⇧`-click to get the picker back for a bound link
- Button tooltips name the target browser and explain what a click switches

### Docs

- Add a "bind, change, remove" cheat sheet to the README

## [2.0.0] - 2026-07-15

### Added

- Route links by the **source application** they were opened from — e.g. "every link from Cursor opens in Chrome"
- App pin in the picker (`⌘⇧P` or the ▢ icon) to bind every link from the current app to a browser
- Combined app + URL rules (a URL pattern that only applies when opened from a given app)
- Show the source app as `from <app>` in the picker so the App pin's target is visible

### Changed

- Split the picker's single pin into a URL pin (`⌘P`, `⌥` for the exact host) and an App pin (`⌘⇧P`)
- Rank app rules above URL rules when both match; combined rules outrank plain app rules; numeric `priority` still overrides everything
- Bump `rules.json` to schema version 2: `pattern`/`matchType` are now optional and `sourceAppBundleID` is added (version 1 files still load unchanged)
- Bump app version to 2.0

### Docs

- Document app rules, the two pin actions, precedence, and the version 2 schema in the README

## [1.0.0] - 2026-07-14

### Added

- Initial BrowserProxy: an accessory "default browser" that intercepts links and routes them to the real browser
- Floating picker at the mouse position with number keys, arrow keys, hover, and click selection
- URL rules (`domain`, `domainSuffix`, `glob`, `regex`, `exact`) with priority, specificity, and age ordering
- Learning: pin a domain (or exact host with `⌥`) to a browser from the picker
- Bypass modifier (Shift by default) to force the picker even for a domain a rule owns
- `--set-default` to request becoming the macOS default browser
- `make-app.sh` to build, sign, install, and register the `.app` bundle
