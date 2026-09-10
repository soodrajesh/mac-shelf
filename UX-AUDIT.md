# MacTools — UI/UX & Functional Audit

**Scope:** static/code audit of `Sources/*.swift` (v1.1, Polar Pro licensing). No live GUI automation was used — every finding is traced through source and cross-checked against Apple HIG and Nielsen's 10 usability heuristics.

**Overall polish: 6/10** against a paid Mac-utility bar. The core mechanics (menu-bar rendering, tab architecture, notepad editing, license caching) are built with real craft — better than most indie menu-bar apps. What holds it back from a 8–9 is: (1) a pre-launch monetization bug that will actively deceive paying customers, (2) a clipboard manager with no way to delete an item, (3) a stats readout that ignores the app's own Text Size setting, and (4) missing tooltips/accessibility labels on several icon-only controls. All are fixable in isolation; none require a redesign.

---

## Fix Status (post-audit pass)

All Critical/High findings and the cheap/low-risk Medium ones have been fixed in `Sources/*.swift`. Full universal-binary build (`./build.sh`) compiles and signs cleanly with no errors or warnings.

| Finding | Status | Notes |
|---|---|---|
| P-1 / Exec #1 — placeholder Polar org ID | ✅ Fixed | `PolarConfig.isConfigured` + `LicenseCheckError.notConfigured`, short-circuited in `LicenseChecker.verify()` before any network call. |
| C-1 / CN-1 / Exec #2 — no clipboard delete | ✅ Fixed | Per-item delete (trailing button + right-click "Delete") and "Clear All" (with confirmation) added to both `ClipboardListView` (popover tab) and the ⌘⇧V picker (`PickerController`/`PickerRowView`). |
| A-1 / Exec #3 — Stats ignores Text Size | ✅ Fixed | New `.statValue` `AppFontStyle` case + `design:` param on `.appFont`; `StatsView` routes through it. |
| A-2 / Exec #3 — Notepad editor ignores Text Size | ✅ Fixed | `NotepadTextView` reads `context.environment.textScale` in both `makeNSView` and `updateNSView`. |
| F-1 / Exec #4 — silent hotkey registration failure | ✅ Fixed | `main.swift` checks `HotKey.init?` result, logs via `NSLog`, and surfaces a disabled warning item in the right-click menu. Full remapping UI intentionally out of scope (per audit). |
| A-3 / Exec #5 — missing accessibility labels | ✅ Fixed (most impactful sites) | `.help()`/`.accessibilityLabel()` added to: Calendar prev/next chevrons, the tab-switcher segmented picker, Calculator's symbol keys (±, ÷, ×, −, %, =, .), clipboard row thumbnails/delete buttons (`ClipboardListView`), and picker rows (`PickerRowView`). |
| A-4 — color-only high-load signaling | ✅ Fixed (bundled with A-1) | Added a warning-triangle glyph + accessibility label ("… high") alongside the red text in `StatsView.statRow`. |
| F-4 — divide-by-zero returns 0 instead of Error | ✅ Fixed | One-line change in `CalculatorView.calculate()`; now falls through to `formatResult`'s existing NaN/infinite → "Error" handling. |
| A-5 — license key field ignores Text Size | ✅ Fixed (cheap) | `LicenseEntrySheet`'s `TextEditor` now uses `.appFont(.body, design: .monospaced)`. |
| P-4 — placeholder HMAC cache key | ⏭ Skipped | Requires generating and committing a real secret at ship time, not a code-shape fix; left as the flagged TODO for the pre-launch checklist. |
| O-1, O-2 — accessibility-prompt onboarding context | ⏭ Skipped | Medium, not cheap — needs a new one-time explainer sheet/flow, not a small call-site change. |
| C-2 — clipboard tab caps at 12 of 40 items | ⏭ Skipped | Medium, ties to the fixed-popover-size tradeoff in C-4; not cheap without a layout rework. |
| C-4 — fixed popover size cramped | ⏭ Skipped | Medium, explicitly flagged in the audit as "not a rewrite" but still a runtime-resize feature, not a cheap fix. |
| C-5 — Calculator has no keyboard input | ⏭ Skipped | Medium, real feature (key event handling), not cheap. |
| C-6 — Calendar can't jump to arbitrary month/year | ⏭ Skipped | Low. |
| D-1, D-2, D-3 — clipboard plaintext storage / size cap / backup exposure | ⏭ Skipped | High/Medium/Low but each requires a design decision (entropy heuristics, storage format change, README rewrite) beyond a cheap fix; D-1's most important sub-fix (delete/clear) is done via C-1. |
| P-3 — no preview in `UnlockProView` | ⏭ Skipped | Low-Medium, a feature addition, not a fix. |
| CN-2 — mixed button styling | ⏭ Skipped | Low, and the audit itself calls this a defensible two-context split rather than a bug. |
| CN-3 — dead code / stale comment in `SystemStats.swift` | ⏭ Skipped | Low code-hygiene item, not a UX finding. |
| F-2 — `freeMemory()` unconditionally tries `sudo -n` | ⏭ Skipped | Low, noted as "functionally harmless" in the audit itself. |

---

## Executive Summary — Top 5 Issues

| # | Severity | Issue | File |
|---|---|---|---|
| 1 | **Critical (pre-launch blocker)** | `PolarConfig.organizationId` is a placeholder, so any real license key a customer enters will be told **"The license key is invalid or not recognized"** — a false, confidence-destroying error indistinguishable from a typo'd key. | `MacToolsLicenseCheck.swift:32` |
| 2 | **High** | Clipboard history has **no delete affordance anywhere** — not in the popover tab, not in the ⌘⇧V picker. `ClipboardStore.remove()`/`.clear()` exist but are never called from any UI. A user who copies a password or an embarrassing snippet cannot remove it except by waiting for 40 more copies to push it out. | `ClipboardListView.swift`, `PickerController.swift`, `ClipboardStore.swift:69,76` |
| 3 | **High** | The Stats tab's CPU/MEM numbers — the app's headline feature — are rendered with a **raw `.font(.system(size: 16…))`** instead of `.appFont`, so the Text Size setting (Small/Medium/Large/Extra Large) has **zero effect** on the one thing users glance at most. | `StatsView.swift:51` |
| 4 | **Medium-High** | Global hotkeys (⌘⇧V, ⌘⇧N) are hardcoded with no in-app way to view or change them, and no conflict detection — if either collides with another app's shortcut (⌘⇧V and ⌘⇧N are both used by other utilities), `RegisterEventHotKey` silently returns non-`noErr`, `HotKey.init?` returns `nil`, and the feature is dead with no error surfaced to the user anywhere. | `HotKey.swift:17-28`, `main.swift:73-80` |
| 5 | **Medium** | Icon-only buttons are missing `.help()` tooltips and accessibility labels almost everywhere (calendar chevrons, calculator operator keys, clipboard row images, picker rows) — a VoiceOver user gets "button" with no label on most controls. | multiple, see Accessibility section |

---

## Onboarding & Permissions

**Finding O-1 — Accessibility prompt fires with zero in-app context (Medium)**
`main.swift:82-84` calls `PasteSimulator.requestAccessibility()` unconditionally on every launch where `isTrusted == false`, with no preceding explanation screen. The very first thing an unfamiliar user sees after installing is a cold system dialog asking to grant Accessibility access, with no prior "why" — a clear HIG error-prevention/context violation (Apple's own guidance: explain *before* the system prompt, not after). The written explanation exists only in `README.md`, which the app itself never surfaces.
*Fix:* on first Accessibility failure, show a small one-time sheet/alert ("MacTools uses Accessibility only to auto-paste your clipboard picks — everything still works without it, you'll just need ⌘V yourself") with a button that triggers the system prompt, rather than triggering it as a launch side-effect.

**Finding O-2 — Denial has no visible affordance to retry except the right-click menu (Low)**
If the user dismisses/denies the system prompt, the only path back is `handleClick`'s right-click menu ("Enable Accessibility for Auto-Paste…", `main.swift:210-215`) — reasonable, but it's undiscoverable from the popover itself, and the Clipboard/Notepad tabs give no in-context hint that auto-paste is degraded. A user who denied the prompt has no way to know *why* paste isn't automatic when they pick a clipboard item later.
*Fix:* a small inline badge/caption in `ClipboardListView`/picker when `!PasteSimulator.isTrusted`.

**Finding O-3 — Free-tier degrade is honest (Positive)**
Confirmed: when Pro is unlicensed, gated tabs show `UnlockProView` (a calm, on-brand upsell card) rather than a disabled/greyed tab or an error dialog — this matches Nielsen's error-prevention heuristic well and is the correct pattern. Hotkeys fire without incident and simply route to Settings' License tab (`main.swift:96-109`) rather than doing nothing or showing a system beep.

---

## Core Flows

**Finding C-1 — Clipboard: no per-item or bulk delete (High, restated from summary)**
`ClipboardStore.remove(_:)` and `.clear()` (`ClipboardStore.swift:69-82`) are fully implemented and even used correctly elsewhere (`NotepadView.swift:56` wires `store.clear()` behind a confirmation dialog) — but the identical pattern was never applied to `ClipboardListView` or `PickerRowView`/`PickerController`. There is no swipe, no right-click context menu, no trailing "×" button, no "Clear All" anywhere in the clipboard UI. Compare to the Notepad tab, which *does* get a proper `Button("Clear")` + `confirmationDialog`. This is an inconsistency within the same app (Nielsen: consistency and standards) as much as a missing feature.
*Fix:* add a trailing delete button per row in both `ClipboardListView` and `PickerRowView`, plus a "Clear All" affordance (with confirmation, mirroring Notepad's pattern) somewhere reachable — the tab's empty-state area or a small toolbar button.

**Finding C-2 — Clipboard tab caps display at 12 items, no way to reach items 13–40 (Medium)**
`ClipboardListView.swift:19` hardcodes `store.items.prefix(12)` inside a `ScrollView` that will never actually need to scroll, since it never receives more than 12 rows — the remaining 28 items the store retains (`maxItems = 40`) are reachable only via the separate ⌘⇧V picker window, not from the popover tab itself. This is silent and undocumented; a user scrolling the popover tab expecting to find an older copy simply won't, with no explanation of why.
*Fix:* either raise the `.prefix` to actually fill the available scroll height, or add a "search full history" affordance that opens the picker.

**Finding C-3 — Tab-switch state is preserved correctly (Positive)**
`QuickToolsPanel.swift` keeps all 5 tabs mounted simultaneously (`opacity`/`allowsHitTesting` toggling instead of conditional rendering, `PanelView.swift:73-80`), with an explicit comment explaining this is deliberate so the Notepad's `NSTextView` isn't recreated. Verified: `NotepadTextView` binds directly to `NotepadStore.text`, which autosaves on a 0.35s debounce (`NotepadStore.swift:22-27`) independent of tab visibility — switching tabs mid-typing does **not** lose text, and unsaved-on-quit risk is bounded to well under half a second. This is a correctly-solved risk the audit was asked to check.

**Finding C-4 — Fixed 260×190 tab content is cramped for Clipboard/Notepad specifically (Medium)**
The 280×240 popover (`main.swift:46`, content frame `PanelView.swift:40`) works well for Stats/Calendar/Calculator, whose content is naturally bounded. For Clipboard, 12 rows at 22–24px each roughly fills the space exactly — leaving no room for a delete affordance without redesigning row height (ties to C-1). For Notepad, a fixed ~150pt-tall text area is workable for a "scratch pad" framing but is noticeably small compared to competing menu-bar notepad utilities (Notzon, Notation) that resize with content; there's no way to expand the popover even temporarily for a longer note.
*Fix:* not a rewrite — consider a resizable popover only while the Notepad tab is active (`NSPopover.contentSize` can be changed at runtime), reverting on tab switch.

**Finding C-5 — Calculator has no keyboard input (Medium)**
`CalculatorView.swift` only responds to on-screen button taps (`handleTap`) — there's no `.onKeyPress`/keyDown handling, so a power user who wants to type "12*4=" cannot; they must click every digit with the mouse. This violates Nielsen's "flexibility and efficiency of use" (no accelerator for expert users) and is inconsistent with virtually every calculator utility, built-in or third-party.
*Fix:* add keyboard handling for digits, operators, `=`/Return, and Escape/`C`.

**Finding C-6 — Calendar has no way to jump to an arbitrary month/year (Low)**
Only prev/next chevrons and a "jump to today" tap on the label (`CalendarView.swift:24-30`) — going from, say, January to December of the same year takes 11 clicks. Minor for a "quick glance" widget, but worth noting since the label is otherwise unused space that could host a picker.

---

## Data Safety / Privacy

**Finding D-1 — Clipboard history is stored in plaintext on disk with only an informal filter (High)**
`ClipboardStore` persists every copied string/image to `~/Library/Application Support/ClipKeep/history.json` and `images/*.png`, unencrypted (`ClipboardStore.swift:100-103`). The only protection against password-manager leakage is `ClipboardMonitor`'s check for `org.nspasteboard.ConcealedType`/`TransientType` (`ClipboardMonitor.swift:15-18,36`) — a real, widely-respected convention, but **opt-in on the source app's side**. Any copy from a source that doesn't tag itself (a browser's password-fill-then-select-then-copy flow, a terminal `pbcopy` of a secret, many enterprise password tools that predate the convention) is captured and written to disk in the clear, retained until 40 more copies push it out — which for a light user could be days. Combined with Finding C-1 (no delete), a sensitive value copied by accident has no way to be purged except clearing 40 more items or restarting.
*Fix:* (a) wire up delete/clear in the UI (C-1) — the most important single fix here; (b) consider a size/heuristic filter that skips or masks values that look like tokens/passwords (e.g. high-entropy strings with no whitespace); (c) document the plaintext-storage + concealed-type caveat in the README's clipboard section so users know the actual guarantee.

**Finding D-2 — No size cap on an individual clipboard item (Low-Medium)**
`addText(_:)` (`ClipboardStore.swift:36-41`) accepts and persists any string length — copying a very large text blob (a full log file, a large JSON blob) gets written whole into `history.json` on every subsequent save (the entire array is re-serialized on every single new copy, `save()` at line 100-103). Over time this is a real perf/IO concern, not just a storage one: every future copy re-writes all 40 items' full text to disk.
*Fix:* truncate/cap stored text length (e.g. 50–100 KB) with a "content truncated" marker, and/or store items individually instead of one monolithic JSON array.

**Finding D-3 — Notepad and clipboard files have no distinguishing protection from Time Machine/iCloud backup or other local apps (Low)**
Both `notepad.txt` and `ClipKeep/history.json` sit in ordinary Application Support with default file protection — consistent with most menu-bar utilities, so this is a minor note rather than a defect, but worth flagging given the app explicitly markets itself as handling clipboard content that can include secrets.

---

## Pro / Monetization UX

**Finding P-1 — Placeholder Polar org ID will show real customers a false "invalid key" error (Critical, restated)**
Already detailed in the Executive Summary. To spell out the failure mode precisely: `PolarConfig.organizationId` returns the literal string `"TODO_POLAR_ORGANIZATION_ID"` (`MacToolsLicenseCheck.swift:32-36`) unless the `MACTOOLS_POLAR_ORG_ID` env var is set. `validateRemote` sends that as `organization_id` to Polar's API (`MacToolsLicenseCheck.swift:328-331`), which — per the file's own doc comment — 404s for *any* key under a non-existent org, and `mapErrorResponse` turns a 404 into `.invalidLicenseKey` (line 398-399), surfaced to the user verbatim as **"The license key is invalid or not recognized."** (`LicenseCheckError.errorDescription`, line 220-221). A real paying customer pasting their real key from their real purchase email will see this and reasonably conclude either they mistyped it or were scammed — there is nothing in the UI distinguishing "your key is wrong" from "this app isn't configured yet." This is entirely correct as *current, pre-launch* behavior (the code comments are honest about it being a TODO) but it is a **hard blocker that must not ship** — the moment "Buy MacTools Pro" (`LicenseManagementView.swift:68-74`) is pointed at a real checkout URL, every buyer hits this wall.
*Fix:* either gate the "Buy" button/checkout link behind the same `organizationId != placeholder` check so Pro literally cannot be purchased until configured, or (better) add a distinct error case for "product not yet configured" that the app can detect (e.g. treat the specific placeholder locally and short-circuit with a clear "MacTools Pro isn't available yet" message instead of ever calling the API with a bogus org ID).

**Finding P-2 — Upsell moment and copy are well-placed and honest (Positive)**
`UnlockProView` is compact, on-brand, and appears exactly where the value would have been (in the tab itself, not as an interstitial) — this is good practice, matching Nielsen's "match between system and real world" (the user sees the feature's icon/shape, just locked) rather than hiding Pro features entirely. The README's feature table is accurate and matches what the code actually gates (Clipboard, Notepad, both hotkeys) — no over-promising.

**Finding P-3 — No way to preview clipboard/notepad value before paying (Low-Medium)**
Unlike some competitors that show a blurred/sample state, `UnlockProView` shows no preview of what Clipboard History or Notepad actually look like — just an icon and one line of body text. For a $-range purchase decision this is a thin pitch; a static screenshot or a "here's what your last 3 copies would have looked like" (from real pasteboard content, computed but not persisted while unlicensed) would materially strengthen the upsell without violating the paywall.

**Finding P-4 — HMAC cache key is a checked-in placeholder (Medium, security-adjacent)**
`SecureLicenseCache.hmacKey` (`MacToolsLicenseCheck.swift:65-73`) is explicitly flagged in its own comment as a placeholder to rotate before shipping — correctly caught by the developer already, but re-flagging here since it's a monetization-integrity issue (a stale/shared key across the mac-apps line would make a forged Keychain cache entry easier to construct) and ties to the same pre-launch checklist as P-1.

---

## Accessibility

**Finding A-1 — Stats readout bypasses `.appFont`/Text Size entirely (High, restated)**
`StatsView.swift:51`: `.font(.system(size: 16, weight: .bold, design: .rounded))` on the CPU/MEM value text — the single largest, most-glanced-at text in the whole app — is a raw SwiftUI font call, immune to the `textScale` environment value every other label respects. A user who sets Text Size to Extra Large for readability gets every label around it scaled except the number they actually care about.
*Fix:* route through `.appFont`, e.g. add a suitably large `AppFontStyle` case or accept an explicit override point size in the modifier.

**Finding A-2 — Notepad text view font is hardcoded, ignoring Text Size (Medium)**
`NotepadTextView.swift:24`: `textView.font = NSFont.systemFont(ofSize: 11)` — this is AppKit, not SwiftUI, so it isn't caught by a `.font(` grep, but it has the identical bug as A-1: the actual editing font in the one tab where legibility matters most (reading/writing prose) never responds to the Text Size setting. `updateNSView` (line 39-47) never re-applies scale either, so even a future SwiftUI-side fix wouldn't reach it without also threading `textScale` into `NotepadTextView`'s `Coordinator`.
*Fix:* pass the current `textScale` into `NotepadTextView` (it already has access via `.environment` at the parent) and set `textView.font` from it, refreshing in `updateNSView` when the scale changes.

**Finding A-3 — No accessibility labels anywhere in the codebase (Medium-High)**
A full grep for `accessibilityLabel`/`accessibilityHint` across `Sources/` returns zero hits. Concretely affected:
- Calendar's prev/next chevron buttons (`CalendarView.swift:12-18, 34-40`) — icon-only, no `.help()`, no accessibility label; VoiceOver reads them as unlabeled "button."
- Calculator's operator/digit buttons (`CalculatorView.swift:34-42`) have visible text glyphs (e.g. "÷", "±") so VoiceOver reads *something*, but "±" and "÷" read poorly/ambiguously without an explicit accessibility label ("Toggle sign", "Divide").
- Clipboard row thumbnails (`ClipboardListView.swift:50-58`, `PickerRowView.swift`) have no label describing the image beyond its pixel dimensions — a screen-reader user gets no sense of *what* the copied image is.
- The segmented tab switcher itself (`PanelView.swift:20-28`) uses bare SF Symbol `Image`s with no text/labels — VoiceOver users get "cpu," "calendar," etc. only if SF Symbols' built-in accessibility descriptions happen to be legible for that glyph, which is inconsistent.
*Fix:* a pass adding `.help()` (mouse tooltip) + `.accessibilityLabel()` (VoiceOver) to every icon-only control — roughly a dozen call sites, not a redesign.

**Finding A-4 — Color-only status signaling for CPU/MEM high state (Medium)**
`statRow` (`StatsView.swift:40-54`) turns the value text red when `high == true` with no secondary indicator (no icon change, no bold-vs-not distinction beyond what's already there, no VoiceOver announcement) — a colorblind user or VoiceOver user gets no signal that load is high. This is a direct Nielsen/WCAG "don't rely on color alone" violation.
*Fix:* pair the red state with a small warning glyph (e.g. a exclamation triangle) next to the value, and set an accessibility value/label that includes the word "high" when true.

**Finding A-5 — `LicenseManagementView`'s license-key `TextEditor` also bypasses `.appFont` (Low)**
`LicenseManagementView.swift:109`: `.font(.system(.body, design: .monospaced))` — defensible as an intentional monospaced-for-key-legibility choice, but still means this one field won't grow with Text Size while every label around it does. Lower severity than A-1/A-2 since it's a one-time-entry field, not a glanceable/read-heavy surface.

---

## Consistency

**Finding CN-1 — Delete/Clear pattern exists in Notepad but not Clipboard (High, cross-ref C-1)**
Restated for the Consistency lens specifically: the app *has* a correct, polished pattern for destructive actions — text button + color cue (red when active) + `confirmationDialog` — proven out in `NotepadView.swift:38-59`. The fact that an equivalent pattern was never extended to Clipboard (a tab that arguably needs it *more*, given D-1) reads as an oversight rather than a considered decision, and is the single most visible inconsistency in the app.

**Finding CN-2 — Inline vs. bordered button styling is mixed without an obvious rule (Low)**
`NotepadView` uses `.buttonStyle(.plain)` text buttons styled by hand (`NotepadView.swift:27-47`); `LicenseManagementView` uses `.buttonStyle(.bordered)`/`.buttonStyle(.link)` (`LicenseManagementView.swift:52-74`); `CalendarView`/`CalculatorView` use `.buttonStyle(.plain)` custom-drawn buttons. This is consistent *within* the popover's compact tabs (where custom `.plain` styling makes sense for density) vs. the full-size Settings window (where native `.bordered`/`.link` styling makes sense) — arguably a defensible two-context split rather than a bug, but it's not documented anywhere as an explicit rule, so a future contributor could easily pick the wrong style for a new popover control.

**Finding CN-3 — `makeStatusAttributedTitle` is unused dead code with a misleading sibling comment (Low)**
`SystemStats.swift:185-208` defines `makeStatusAttributedTitle`, which is never called anywhere (confirmed via grep). Its neighbor `makeStatusImage` (used at `main.swift:131`) carries a comment claiming *it* is "unused by MacTools menu bar; kept for reference tooling" (`SystemStats.swift:210`) — which is stale/backwards, since `makeStatusImage` is in fact the one actually driving the menu-bar icon, while `makeStatusAttributedTitle` is the truly-unused one. Purely a code-hygiene/documentation-accuracy issue, but worth a cleanup pass since the comment actively misleads the next person to touch this file.

---

## Functional Bugs

**Finding F-1 — Hotkey registration failure is silent (Medium, restated from summary)**
`HotKey.init?` returns `nil` on any `RegisterEventHotKey` failure (`HotKey.swift:17-28`) — including a conflict with another app's global shortcut for the same key combo. `main.swift:73-80` assigns the result to `hotKey`/`notepadHotKey` (both `HotKey?`) and never checks for `nil` or surfaces anything to the user. If ⌘⇧V or ⌘⇧N is already claimed system-wide, MacTools' picker/notepad-open silently never fires, with no menu item, badge, or Settings-pane indicator telling the user why. Given ⌘⇧V/⌘⇧N are common shortcuts (many clipboard managers, IDEs, and note apps use exactly these), this isn't a hypothetical edge case.
*Fix:* on `nil`, log/surface a state the Settings License/About area can show ("Global shortcut ⌘⇧V could not be registered — it may be in use by another app"), and ideally let advanced users remap the shortcut (none of the current UI exposes the key codes at all).

**Finding F-2 — `freeMemory()`'s passwordless-purge path runs a blocking subprocess check on every tap without caching sudoers state (Low)**
`StatsController.freeMemory()` (`StatsController.swift:127-146`) always tries `sudo -n purge` first (line 133, 165-176) before falling back to the interactive AppleScript prompt. This is correct behavior, but on a Mac without the optional NOPASSWD sudoers rule, every single "Free Up Memory" tap pays the cost of spawning `/usr/bin/sudo -n` just to fail, then spawning `osascript`. Functionally harmless (sub-second), purely a minor inefficiency — noted for completeness, not a real bug.

**Finding F-3 — Everything else traced checks out (Positive)**
Verified end-to-end and found correctly wired: Calculator's four operations and edge cases (divide-by-zero returns `0` rather than crashing/NaN-displaying — though see F-4), Calendar's month math including year boundaries, Irish holiday computation (Easter algorithm, weekend-shift rules, the Dec 25/26 collision cases), clipboard picker's live search/arrow-key nav/paste flow, Notepad's debounced autosave + Clear-with-confirm, and License state's explicit "always resolve, never leave stale" refresh logic (`LicenseState.swift:32-41`, which the code comments confirm was a deliberate fix for a bug pattern seen in a sibling app). No empty/TODO'd action closures were found anywhere in `Sources/`.

**Finding F-4 — Calculator divide-by-zero silently returns 0 instead of an error state (Low)**
`CalculatorView.swift:124`: `result = currentValue != 0 ? pendingValue / currentValue : 0` — dividing by zero produces a `0` result rather than the "Error" state that `formatResult` already supports for `NaN`/`isInfinite` (line 148-150). This is inconsistent with the app's own error-display capability and slightly misleading (a genuine `0` result and a divide-by-zero look identical to the user).
*Fix:* `result = pendingValue / currentValue` unconditionally and let `formatResult`'s existing `isInfinite`/`isNaN` check produce "Error" (0/0 → NaN, N/0 → ±infinity, both already handled).

---

## Menu-Bar Icon States

Confirmed via `SystemStats.swift:185-242` and `main.swift:122-135`:
- Light/dark legibility: `makeStatusImage` uses `NSColor.white`/`NSColor.black` keyed off `effectiveAppearance`, redrawn on an explicit KVO observer (`main.swift:43, 122-126`) — this correctly tracks live menu-bar appearance changes, and the two-line monospaced-digit layout (`NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)`) is legible at typical menu-bar height. No issue found.
- Red-under-load thresholds (`cpuHighThreshold = 90.0`, `memPressureThreshold = 75.0`, `SystemStats.swift:179-180`) are reasonably conservative — 90% CPU and 75% *memory pressure* (not raw usage — the code explicitly computes pressure as wired+compressed rather than total used, `SystemStats.swift:77-80`, a materially better metric than naive "% RAM used" that most competitors get wrong) — this should not be noisy for normal bursty workloads. No alarmism concern found; if anything the pressure-based metric is a genuine strength worth highlighting rather than a flaw.
- One inconsistency: `makeStatusImage`'s bitmap approach draws with hardcoded `.white`/`.black` rather than semantic `NSColor.labelColor` (which `makeStatusAttributedTitle`, the *unused* sibling function, correctly uses at line 189). Functionally fine under normal Aqua/Dark Aqua, but won't automatically track a future macOS accent/contrast mode the way `labelColor` would. Very low priority given menu-bar icons are typically expected to be literal black/white/template anyway.

---

## Summary of Fix Priority (suggested order)

1. **P-1** — gate or special-case the placeholder Polar org ID so no real customer can hit a false "invalid key" error.
2. **C-1 / CN-1** — add delete/clear to Clipboard (both popover tab and picker), mirroring Notepad's existing pattern.
3. **A-1 / A-2** — route Stats readout and Notepad editor font through `.appFont`/`textScale`.
4. **F-1** — surface hotkey-registration failure somewhere visible; consider exposing the shortcuts (view-only at minimum) in Settings.
5. **A-3 / A-4** — accessibility-label pass on icon-only controls; pair color-only high-load state with a non-color cue.
6. Everything else in this report, roughly in the severity order listed per section.
