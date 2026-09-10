# MacTools Audit — 2026-09-10

Scope: build + audit only (no UI/theme refactor — that's a later stage).

## Build

- No `Tests/` directory or Swift test target exists — test step skipped.
- Built via `swiftc -O -o /tmp/mt-build/MacTools Sources/*.swift` (host-arch
  compile, equivalent to the per-arch slices `build.sh` produces). Did not
  run the full `build.sh` (it code-signs and installs to `/Applications`,
  out of scope for a compile check).
- **Before fixes**: 1 warning (deprecated API), 0 errors.
- **After fixes**: 0 warnings, 0 errors. Clean build.

## Fixes made

1. **`Sources/PanelView.swift`** — `onChange(of:perform:)` is deprecated as
   of macOS 14.0, but the app's deployment target is 13.0 (`LSMinimumSystemVersion`
   in `build.sh`), so switching straight to the new two-parameter `onChange`
   would have broken macOS 13 support. Added a small `ViewModifier`
   (`SelectedTabChangeHandler`) that branches on `#available(macOS 14.0, *)`:
   the new non-deprecated API on 14+, the old one (still fully functional)
   on 13. Silences the warning without dropping 13.0 support.

2. **`Sources/PickerController.swift`** — `(panel.contentLayoutGuide as! NSLayoutGuide)`
   was a force-cast on a property Apple types as `Any` (bridged from an
   Objective-C protocol). In practice it always succeeds, but there's no
   reason to crash the app if a future macOS release changes that. Changed
   to `as?` with a fallback to `content.topAnchor`.

## Audit findings

- **Force-unwraps / crashes**: only one `as!` in the whole codebase (fixed
  above, see #2). No `try!`, no other force-unwraps found via pattern scan.
- **TODO / FIXME**: none in `Sources/`.
- **App icon**: no static icon assets to go stale — `build.sh` renders
  `AppIcon.icns` from an SF Symbol (`square.grid.2x2.fill`) at build time,
  so there's no placeholder-icon risk.
- **SF Symbols vs custom assets**: consistent — the app uses SF Symbols
  exclusively (13 `systemName:` usages across the UI); no `NSImage(named:)`
  or custom image assets anywhere, so there's nothing to be inconsistent
  with.
- **Entitlements**: `MacTools.entitlements` exists, matches the app's
  actual needs. The app is unsandboxed by design (documented in the
  entitlements file's own comment — distributed as a signed/notarized DMG,
  needs unrestricted user-folder/system-API access) with every
  hardened-runtime exemption explicitly set to `false`. Runtime permissions
  used (Accessibility, via `AXIsProcessTrusted`/`CGEvent` in
  `PasteSimulator.swift`, and the administrator-privileges prompt in
  `PrivilegedPurge.swift`) are OS-level TCC/authorization prompts, not
  entitlement keys, and need no corresponding entitlement given no sandbox.
  Nothing missing or mismatched.
- **Dead code / unused files**: none found. Cross-referenced every source
  file's primary type against the rest of the tree — all are wired in from
  `main.swift` or a caller. No stray/orphaned files.
- **Version currency**: `CFBundleShortVersionString` in `build.sh`'s
  generated `Info.plist` is `1.0` (`CFBundleVersion` `1`), matching the
  already-built `MacTools.app/Contents/Info.plist` in the tree and the
  `MacTools-1.0.dmg` filename at the repo root. No git tags exist in this
  repo. Version is consistent across all three; nothing stale.

## Still open

- No test suite exists at all — nothing to fix, but there's no regression
  safety net either. Worth adding at least a few unit tests around the
  non-UI logic (`SystemStats`, `IrishHolidays`, `ClipboardStore` dedup) in a
  future pass.
- `build.sh` installs straight to `/Applications` (with a `sudo` fallback)
  as part of every build — fine for local dev-loop use, but means there's
  no separate "just compile and check" mode; this audit worked around that
  by compiling `Sources/*.swift` directly rather than invoking `build.sh`.

## Current version

**1.0** (`CFBundleShortVersionString` / `MacTools-1.0.dmg`, consistent
across `build.sh`, the built app bundle, and the DMG filename).
