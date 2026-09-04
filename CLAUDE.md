# Shelf — macOS Clipboard History Manager

> Rename freely — "Shelf" is just a default. One find-replace across the repo swaps it.

## What this is
A **personal-use, native macOS menu bar app** that keeps a history of what you copy
(text, images, files) so you can quickly recall and reuse earlier clipboard items —
by copying them back or dragging them out into any app. **Local-only. No account, no
server, no cloud.**

The owner is a frontend developer (React/TypeScript, ~7 yrs), new to Swift/AppKit.
Explain native-specific concepts briefly as you go; don't assume macOS-dev fluency.

---

## Context & decisions (why this shape)

- **Inspired by, not ported from, Edge Drop.** Edge Drop is a Windows app built in
  Electron + React. We deliberately are NOT forking or porting it — this is a clean
  native Swift rebuild. No shared code, no Windows baggage, no license entanglement.
- **The real need is history, not friction.** The owner has no problem with basic
  copy-paste. The actual want: recall/reuse *earlier* clipboard items (text, images,
  files). So the center of gravity is the **history + easy retrieval**, not any
  particular fancy interaction.
- **No custom cross-device sync needed.** Apple's Universal Clipboard already mirrors
  the *latest* copied item across the owner's iPhone / iPad / Mac. This app captures
  *history on the Mac*, which therefore automatically absorbs items copied on the other
  Apple devices too. Building our own sync would duplicate what Apple already does.
  Do not build sync.
- **Personal use only.** No code signing / notarization / App Store needed. Running
  unsigned locally is fine. Don't spend effort on distribution concerns.
- **Native Swift chosen over Electron** because a clipboard-history app's core
  (pasteboard polling, menu bar residency, global hotkey, native drag-out) is all
  first-class in AppKit/SwiftUI, whereas Electron would just add weight around it.

---

## Scope

### Phase 1 — build now (local Mac menu bar history)
- Capture **text, images, and files** as they're copied.
- Open the history via **menu bar icon** AND a **global shortcut (⌘⇧V)**.
- Show items **most-recent-first**; **dedupe** on re-copy (re-copying an existing item
  moves it to the top rather than duplicating).
- **Click an item** → copies it back to the system pasteboard.
- **Drag an item out** → drops into any app (Finder, Slack, Figma, etc.) as a real
  file/image, not fake paste.
- **Cap history at 50 items** (make this a constant that's easy to change later).
- **Respect privacy flags** from day one (see below) — skip password-manager /
  transient / sensitive copies.
- **Persist across app restarts.**

### Phase 2 — later, DO NOT build yet
- **Edge-hover panel** (open by moving the cursor to the left/right screen edge), the
  way the Edge Drop reference works. Deferred on purpose: global mouse tracking +
  a non-activating always-on-top panel + multi-monitor edge logic is the fiddly part,
  and it can needlessly eat the whole first build. Ship the core retrieval loop first;
  add edge-hover as an *additional* way to open once Phase 1 is solid.
- Any custom device sync (probably never — Universal Clipboard covers it).

---

## Architecture (Phase 1 — as built)

- **SwiftUI + AppKit app**, `LSUIElement = true` → agent app: lives in the menu bar,
  **no Dock icon**, no main window. Entry point is a plain `NSApplication` run loop
  (`ShelfApp.swift`) with `.accessory` activation policy.
- **`NSStatusItem` + a non-activating `NSPanel`** (`ShelfPanel.swift`) — *not*
  `MenuBarExtra`, and *not* `NSPopover`. See "Deviations" below for why.
  The panel hosts the SwiftUI list through `NSHostingView`. It is positioned three
  ways depending on how it was opened: under the status item, beside the mouse
  cursor (the hotkey), or flush against a screen edge (edge hover).
- **`EdgeHoverMonitor`** — polls `NSEvent.mouseLocation` and runs a small state
  machine: rest within 2pt of a chosen screen edge and the shelf itself slides a
  30pt strip in from off-screen; from there either pull inward or keep holding and
  it comes the rest of the way. Two stages rather than one because an edge that
  opens the moment you touch it fires constantly while you are just moving around
  the screen, and there is no warning before it does.

  The thing you grab is the panel, not a separate handle. An earlier version drew a
  small tinted tab that vanished the instant the pull committed, and the pull and
  the result never looked like one motion. Now the window sits mostly off-screen and
  `revealedWidth` says how much of it is in - 1pt while hidden, 30pt at rest, the
  full width once committed - so pulling literally drags the panel out and the
  commit is a spring past the resting position. Never 0pt: a window entirely off
  every screen risks being repositioned by the system.

  Move the window with `animator().setFrame(_:display:)`. `setFrameOrigin` through
  the animator proxy is silently ignored on `NSWindow` - it neither animates nor
  moves - which is worth knowing because the failure is invisible: the window simply
  stays where it was put, and every symptom points at the positioning maths instead. Holding is safe as a second route because nobody parks a cursor
  against a screen edge for half a second by accident. Only the middle half of each
  edge is live: the top of the left edge is where browsers put back buttons and
  sidebars and the cursor goes there constantly, while the corners are where people
  park the mouse and where macOS puts Hot Corners. A held mouse button normally suppresses the whole thing, since that means a window
  is being dragged to the edge - but `EdgeOpenMode.drag` lets the user require a
  press-and-pull instead, and that stays distinguishable from window tiling by only
  honouring a press that *began* at the edge. A window drag begins on a title bar
  and merely arrives there.

  Drag mode brings its own hazard: the shelf travels *under* the cursor while the
  button is still down, so releasing lands a click on whichever row happens to be
  there - copying something the user never pointed at. Row activation is therefore
  locked from the moment an edge drag commits until the button is actually observed
  to release, with a timeout so a missed release cannot lock it forever.
- **`PanelAnimationStyle`** — six named recipes chosen in the settings menu. A recipe
  is the collapsed scale per opening direction plus one `Animation` for each of size,
  corner radius and opacity, and a `Flourish` describing the gesture on arrival: tilt,
  squash, hinge angle, and how much the rows stagger.

  Landing more than once needs `WobbleEffect`. SwiftUI interpolates straight between
  the start and end of an animated value, so animating scale can overshoot once and
  no more - a ball bouncing three times cannot be expressed that way. The effect
  animates a 0-to-1 phase instead and computes the scale from a damped cosine each
  frame, which is what `bounce` and `rubber` are built on.

  Rotation costs window margin. A 340x460 card tilted 9 degrees and stretched to 1.22
  vertically pushes 68pt past its own bounds top and bottom, so `shadowMargin` has to
  exceed that or the corners are simply cut off - which is how the clipping bug
  arrived. Departure squash is declared separately rather than inverting the arrival
  values, because inverting a vertical stretch produces a horizontal one, and that
  plus tilt sent the card 73pt out each side. Keeping those on
  separate clocks is what makes the styles distinguishable; drive them from one
  animation and every style collapses back into "it gets bigger".
  Polling beats a global mouse monitor here: the monitor wakes on every mouse move
  system-wide, while the question being asked is "has it *stayed* here", and neither
  needs Accessibility permission. Off by default (`Preferences`), since a shelf that
  appears when you brush the screen edge is worse than one you have to ask for.
  Only an edge-opened panel closes itself when the pointer wanders off, and never
  while a mouse button is down, so dragging an item out still works. An edge that
  abuts another display is ignored: that boundary is the corridor the cursor crosses
  between screens, so opening there is pure obstruction. The probe is a point one
  point beyond the edge at the cursor's own height, so displays of different heights
  still trigger along the stretch where nothing adjoins.
- **Panel animation** — `PanelPresentation` drives a SwiftUI `scaleEffect` anchored
  at the side the panel was summoned from, with a spring that slightly overshoots, so
  the card grows out of that edge rather than sliding as a rigid block. The window
  frame never animates: the window is deliberately `shadowMargin` larger than the
  visible card on every side, giving the growth and the (SwiftUI-drawn) shadow room
  to live inside a stationary window. `hasShadow` is off for the same reason - a
  window shadow is computed from the window, not the scaled content, so it would sit
  still while the card moved. `animationBehavior = .none` keeps the system's own
  window animation out of the way.

  Two consequences worth remembering. The window outlives the closing animation, so
  `isVisible` does not answer "is the panel open" - `AppDelegate.isPanelPresented`
  does. And the window is bigger than what the user sees, so anything geometric -
  the outside-click test, the edge-hover auto-close - must use `panel.cardFrame`,
  never `panel.frame`.
- **`ClipboardMonitor`** — a `Timer` (~0.4s) that polls
  `NSPasteboard.general.changeCount`. macOS has **no** "clipboard changed"
  notification, so polling changeCount is the standard, correct approach. When the
  count changes, read the current pasteboard, classify the type, apply privacy rules,
  dedupe, and prepend to the store.
- **Dropping onto the panel** — `HistoryView` accepts file URLs, PNG/TIFF and plain
  text dropped on the card, so things can be collected without going through the
  clipboard. One provider usually advertises several types at once, so the handler
  takes the most specific match and stops; checking them all files the same thing
  twice. Dropping requires the panel to already be open: edge detection deliberately
  ignores everything while a mouse button is held, which is what makes dragging a
  window to the screen edge safe, and telling that apart from dragging a file there
  needs a separate mechanism.
- **Keep open** — `Preferences.keepsPanelOpen` suspends every automatic dismissal:
  pointer-leave, outside clicks, and closing after a copy. Collecting several files
  means walking to Finder and back repeatedly, and each of those trips is an outside
  click, so a shelf that dismisses on any of them cannot be filled. Deliberately not
  persisted - it is a mode for a task, not a preference, and a forgotten one would
  quietly disable dismissal forever.
- **`ClipboardItem`** — model: stable `id`, `kind` (`.text` / `.image` / `.file`),
  text payload, blob path, original path, `timestamp`, preview, a content
  fingerprint used for dedupe, `isPinned`, and which app was frontmost at capture. It decodes by hand rather than by
  synthesis, so that a field added after people already have history on disk reads
  as its default instead of failing the whole file.
- **`HistoryStore`** — `ObservableObject`: ordered list, **capped at 50**, dedupe on
  re-copy (existing match moves to top), persists to disk, loads on launch.
  Pinned items sort ahead of the rest and are excluded from the cap and from
  "clear all" - a pin that the cap can still evict is not a pin. `finderURL(for:)`
  resolves a file item to where it actually lives rather than to the archived copy;
  reopening a folder is the whole point, and the copy is useless for that.
  Files over 50 MB are recorded by original path only, with no blob copy.
- **`LocalizationManager`** — the UI ships in Korean and English, switchable from a
  globe button in the panel header and persisted in `UserDefaults`. Strings live in
  `Resources/<code>.lproj/Localizable.strings`; `build.sh` copies every `.lproj`
  folder into the bundle, so adding a language needs no build changes. Keys go
  through the `StringKey` enum rather than raw strings, so a typo fails to compile.
  Anything derived from the user's own clipboard content is never translated.
- **Global hotkey (⌘⇧V)** — `GlobalHotkey.swift`, a thin wrapper over Carbon's
  `RegisterEventHotKey`. No third-party dependency; the project has **zero** SPM
  dependencies. The combination lives in two constants at the bottom of that file.
- **Drag-out** — SwiftUI `.onDrag` returning an `NSItemProvider`: a file URL for
  images and files, a plain string for text. Because every image is written to
  `blobs/` as a real PNG when captured, an image drag vends an actual on-disk URL, so
  no `NSFilePromiseProvider` is needed.

---

## Privacy rules (implement in Phase 1, not later)
When reading the pasteboard, **skip** the item entirely if any of these types are
present (these are set by password managers and sensitive tools):
- `org.nspasteboard.TransientType`
- `org.nspasteboard.ConcealedType`
- `org.nspasteboard.AutoGeneratedType`

Match case-insensitively. Never persist a skipped item.

---

## Persistence
- Directory: `~/Library/Application Support/Shelf/`
- Text + item metadata → `history.json`
- Images / files → saved as blobs in a `blobs/` subfolder, referenced by filename in
  the JSON.
- Load on launch; enforce the 50-item cap on every write (drop oldest, delete its blob).

---

## Tech & conventions
- Swift 5.9 tools version, built with Swift 6.2. Deployment target **macOS 14**.
- **No third-party dependencies.** If one ever seems necessary, first check that it
  compiles without Xcode (see "Deviations" below).
- Source comments are written in Korean, matching the owner's language. UI strings are
  **not** hardcoded — they go through `LocalizationManager` (see Architecture).
- Anything shown in the list that depends on language must be computed at display time,
  never baked into the stored model. `ClipboardItem` therefore keeps an image's
  `byteCount` as a number, and the "Image · 4 kB" label is built when the row renders.
- Menu bar / agent app only — no Dock icon, no main window.
- No telemetry, no network calls. This app never talks to a server.
- Keep commits small and logical; explain each native concept the first time it shows up.

---

## Build & run (no Xcode required)

The owner's machine has **Command Line Tools only — Xcode is not installed.** The
project is therefore a plain **Swift Package Manager** package, and `build.sh`
assembles the compiled binary into a `Shelf.app` bundle and ad-hoc signs it.

```bash
./build.sh              # release build for this machine's architecture → ./Shelf.app
./build.sh --run        # build, kill any running instance, and launch
./build.sh --debug      # debug build
./build.sh --universal  # arm64 + x86_64, for handing the app to another Mac
```

`--universal` cannot use SwiftPM's `--arch` flag, which needs Xcode's `xcbuild`. It
builds the second architecture into a separate scratch path with an explicit target
triple and joins the two with `lipo`. If that second build fails it warns and falls
back to a native-only bundle rather than aborting.

Installation on another machine is documented for the owner in `INSTALL.md`. The one
thing to remember when changing distribution: the app is ad-hoc signed, so `spctl`
rejects it and a quarantined copy (AirDrop, download) will not open until
`xattr -dr com.apple.quarantine` is run on it.

`swift build` alone is enough to type-check; the bundle step only matters for running.
If Xcode is installed later, `Package.swift` opens directly in it with no conversion.

Verified working environment: macOS 26.2 (arm64), Swift 6.2.3, deployment target
macOS 14.

Ask the owner before anything that depends on their machine's specifics (paths, macOS
version choices, signing team). Otherwise proceed autonomously.

---

## Definition of done (Phase 1)
- Copying **text / image / file** adds it to the history.
- History **survives an app restart**.
- **Clicking** an item re-copies it to the pasteboard.
- **Dragging** an item drops it into another app as a real file/image.
- **⌘⇧V** and the **menu bar icon** both open the list.
- **Password-manager / transient** copies are ignored.
- History **never exceeds 50** items.

---

## Deviations from the original plan, and why

These three changes were forced by things discovered while building. Do not revert
them without re-testing the specific failure described.

1. **SwiftPM package instead of an Xcode project.** Xcode is not installed on the
   owner's machine, so `xcodebuild` and `.xcodeproj` are unavailable. The Command
   Line Tools SDK does ship SwiftUI and AppKit, so a package plus a bundling script
   builds a fully working app.

2. **No `KeyboardShortcuts` package; Carbon `RegisterEventHotKey` instead.**
   `KeyboardShortcuts` 2.4.0 uses the `#Preview` macro, whose implementation plugin
   (`PreviewsMacros`) ships only with Xcode. Without Xcode the dependency fails to
   compile outright. The Carbon API is what such packages wrap anyway, needs no
   Accessibility permission, and cost about 90 lines.

   Note for the handler: install the Carbon event handler on
   `GetEventDispatcherTarget()`, **not** `GetApplicationEventTarget()`. With the
   latter the hotkey registers successfully but the handler never fires.

3. **A non-activating `NSPanel` instead of `MenuBarExtra` / `NSPopover`.** Two
   separate problems ruled the popover out:
   - `MenuBarExtra` has no public API to open its window programmatically, so the
     ⌘⇧V requirement could not be met with it.
   - Since macOS 14's cooperative activation model, `NSApp.activate` triggered from a
     global hotkey does **not** make an accessory app active. An `NSPopover` shown by
     an inactive app reports `isShown == true` while the window server never puts it
     on screen (`CGWindowListCopyWindowInfo` shows `onscreen = false`). A
     `.nonactivatingPanel` displays without requiring activation.

   This also turns out to be better behaviour: the app you are dragging into keeps
   focus the whole time, and it is the same window type Phase 2's edge-hover panel
   will need.

---

## Verified against the definition of done

Everything below was exercised on the real machine, not just reasoned about.

| Item | Result |
| --- | --- |
| Text / image / file capture | Pass — one history entry per copied file; file keeps its original name |
| Dedupe on re-copy | Pass — re-copying an existing item moves it to the top instead of duplicating |
| Survives restart | Pass — 50 items reloaded from `history.json` |
| Click to re-copy | Pass — verified with synthetic clicks and `pbpaste`; panel closes afterwards |
| **Drag out to another app** | Pass — an image item dropped into Finder produced a real PNG whose SHA-1 matched the stored blob exactly |
| ⌘⇧V and menu bar icon | Pass — both toggle the panel |
| Privacy markers ignored | Pass — a pasteboard write carrying `org.nspasteboard.ConcealedType` was not stored |
| 50-item cap | Pass — 60 copies left exactly 50 entries, and the dropped items' blob folders were deleted |

| Language switching | Pass — the globe menu switches Korean/English live, persists to `UserDefaults`, and survives a restart |

One caveat worth repeating to the owner: the drop was verified into Finder. Dropping
into a specific creative app (Figma, Photoshop) is worth a manual sanity check.

### One more trap found while adding the language menu

The global "click outside to dismiss" monitor also fires for clicks on the app's own
**menu** windows, because menu tracking runs its own event loop and the click never
reaches the app the ordinary way. Picking a language therefore dismissed the whole
panel. `AppDelegate.isPointOverOwnWindow(_:)` now checks the click location against
every on-screen window owned by this process — `NSApp.windows` is not enough, since
menu windows do not appear there.
