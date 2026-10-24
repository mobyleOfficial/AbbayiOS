# Spike: can iOS 26's tab bar accessory host a finger-tracked expansion?

Date: 2026-10-23 · Task 1 of `docs/superpowers/plans/2026-10-23-tabs-mini-player.md`
Toolchain: Xcode 26.4 (17E192), iPhone 17 simulator, iOS 26.4.

## Verdict

**`ACCESSORY_HOSTS_EXPANSION = yes`**

On iOS 26 the mini player bar can be the `.tabViewBottomAccessory` content. A `DragGesture` on that
content gets a continuous stream of touches. A sibling overlay above the `TabView` can start at the
accessory's frame, read with `onGeometryChange(... .frame(in: .global))`, and grow over the tab bar to
full screen while tracking the finger. It settles open or closed on release. The tab bar can be hidden
with `.toolbar(.hidden, for: .tabBar)`, and dragging the overlay down collapses it the same way.

This holds only under one condition, which is the main gotcha: **nothing that re-evaluates the view
which builds the accessory may change during the drag** (see Gotcha 1).

## How it was tested

The spike was a throwaway XcodeGen app in `/tmp`, outside the repo, now deleted. Its source, logs,
frames and result bundles are kept, git-ignored, under
`.superpowers/sdd/2026-10-23-tabs-mini-player/spike/`.

- **The app:** a `TabView` with `Tab("A")` and `Tab(role: .search)`, each holding a `NavigationStack` with a
  60-row `List`. It used `.tabViewBottomAccessory { bar }`.
  - The bar carried `DragGesture(minimumDistance: 8, coordinateSpace: .global)`.
  - That gesture drove `progress = -dy / accessoryFrame.minY`, clamped to 0…1.
  - A sibling overlay in a `ZStack` above the `TabView` interpolated its frame from the accessory frame to
    the full screen, and its corner radius from capsule to 40.
- **Settle rule:** open if p > 0.3 or a flick faster than 800 pt/s, as in the spec.
- **Collapse:** a `DragGesture` on the open overlay.
- **Launch arguments:** `-hide during|settled|never` (when the tab bar hides), `-minimize`
  (`.tabBarMinimizeBehavior(.onScrollDown)`), `-zoom` (the native zoom variant).
- **How it was driven:** an XCUITest using
  `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` for slow drags at 120 pt/s with a
  1.5 s hold while the finger stays down, and for fast flicks at 2500 pt/s.
- **Evidence collected three ways:**
  - a timestamped in-app log of every `onChanged` / `onEnded` and of each accessory frame and placement change
  - an on-screen probe label read by the test
  - a background `xcrun simctl io <udid> screenshot` loop, about 1 frame every 0.3–0.6 s

## Answers, with evidence

| Question | Answer | Evidence |
|---|---|---|
| Does a `DragGesture` inside the accessory get touches? | **Yes**, continuously, once Gotcha 1 is respected: 145 `onChanged` events at about 60 Hz for a 300 pt slow drag, then `onEnded` with velocity. With the drag state in the root view's `@State`, it got exactly **one** `onChanged` and then nothing, not even `onEnded`. | `run2-app.log`, `run1-app.log`; tests t1/t2 |
| Can the expansion visually start at the accessory and grow over the tab bar? | **Yes.** The `.global` frame of the accessory content, (21,743 360×32) on iPhone 17, matches the screen. A sibling overlay drawn from that rect covers the accessory and the Liquid Glass tab bar, and tracks the finger: p = 0.08 → 0.23 → 0.36 → 0.37 while held, then animates to 1.0. | `sheet-t1-slow-drag-hide-during.jpg`, `sheet-t2-hide-settled-and-collapse.jpg` |
| Does a slow drag animate slowly, and does release settle open or closed? | **Yes.** A short slow drag (p = 0.108) settled closed. A fast flick (p = 0.202, vy = −2275) settled open. A 300 pt slow drag (p ≈ 0.37–0.40) settled open. | `run3-app.log`, t3 |
| Can the tab bar be hidden while expanded? | **Yes.** `.toolbar(.hidden, for: .tabBar)` on each tab's root slides the tab bar out, and **the accessory moves down with it** (minY 743 → 813). Hiding it *during* the drag did **not** cancel the gesture. | t1 (`-hide during`), `run2-app.log` |
| Does dragging down collapse it, also tracking the finger? | **Yes.** Frames show p = 0.80 → 0.63 with the finger held. On release at p = 0.63 it settled closed, and the tab bar and accessory came back. | `sheet-t2-…jpg` frames 6–10 |
| Do minimize-on-scroll / inline placements interfere? | **No for the gesture, yes for the geometry.** After a scroll, the placement goes `.expanded` → `.inline` and the accessory shrinks to (84,806 234×32), sitting between the tab item and the search button. Dragging from inline still tracked (139 events) and opened. The overlay simply starts from the smaller inline rect. | `sheet-t4-inline.jpg`, `run3-app.log` |
| Is there a native API for this? (`matchedTransitionSource` + `navigationTransition(.zoom)`) | **Only partly.** A `fullScreenCover` with `.navigationTransition(.zoom(sourceID:in:))` from the accessory opens with a zoom out of the bar on **tap only**. **Dismissal is interactive**: a slow drag down shrinks the cover toward the bar under the finger. Opening cannot be finger-driven. A drag gesture can only *trigger* the cover once (discrete), and then the system animation plays. That does not meet goal 5 ("a slow drag animates slowly"). | `sheet-t5-zoom.jpg`, t5 |

## Recommended architecture for Tasks 6–8 (the "yes" branch)

- **iOS 26:**
  - `TabView` with `Tab("Library")` and `Tab(role: .search)`.
  - The mini player bar is the `.tabViewBottomAccessory` content.
  - The bar reports its frame with `onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }` into an
    `@Observable` presentation model, which holds the frame, progress and the open/closed state.
- **The expansion:** a single overlay in a `ZStack` *above* the `TabView`, at the root (`AppRootView`). It
  interpolates frame, corner radius, cover size and content opacity on `progress`, from the stored
  accessory frame to the full screen. The details screen (`PlayerView`) lives inside it.
- **The drag:** the bar's `DragGesture` writes `progress` to the model. The overlay's own drag, from the
  header or grabber, or the list when scrolled to the top, writes it back down. Settling uses the
  `ExpansionMath` pure functions (0.30, 800 pt/s).
- **The tab bar:** hide it with `.toolbar(.hidden, for: .tabBar)` on each tab's root, driven by a small
  modifier that reads only the model's "hidden" flag (see Gotcha 2 for when to flip it).
- **Content insets:** the system is expected to inset tab content for the tab bar and its accessory, so
  no manual `safeAreaInset` should be needed on iOS 26. The spike did not verify this with a
  last-row-visible check, so T6/T7 must confirm it.
- **iOS 17–25 (unchanged by this spike):** a hand-drawn tab bar plus a docked bar via
  `safeAreaInset(edge: .bottom)`, with the same overlay and model. Only where the bar lives differs.
  Read the frame from the docked bar the same way.

## Gotchas (each one observed)

1. **Keep drag-driven state out of the view that builds the accessory.**
   - In run 1, `progress` lived in the root view's `@State`. Setting it on the first `onChanged` re-ran the
     root `body`, which rebuilt the `.tabViewBottomAccessory` closure. The gesture died after one event,
     with no `onEnded`, so the overlay stuck at p = 0.01.
   - In run 2, the state was moved into an `@Observable` model. It was read only by small leaf views (the
     overlay, the probe, a tab bar visibility modifier) and written by the gesture. The root and accessory
     `body` were never re-evaluated during the drag, and tracking was continuous.
   - Rule for T6–T8: the root that owns the `TabView` must not read `progress`, `dragging` or the
     accessory frame in its `body`, and the accessory view must not read `progress` either. The ticking
     `PlaybackClock` read by the bar is fine: it re-renders the bar's leaf, not the root. Verify this
     during T7.
2. **Hiding the tab bar moves the accessory.**
   - With `-hide during`, the accessory jumped from minY 743 to 813 as soon as p > 0. The overlay's start
     rect and travel moved by 70 pt mid-drag.
   - Either snapshot the start frame and travel when the drag begins, or hide the tab bar only once the
     overlay covers it (p ≥ about 0.15) or after settling open (`-hide settled` looked clean).
   - Collapsing: show the tab bar again before p reaches 0, so the bar is back in place when the overlay
     lands.
3. **The inline placement changes the start rect.** In `.inline` the bar is 234 pt wide at x = 84. Read
   the frame live (as above) instead of assuming full width. Adjust the bar's layout for inline using
   `@Environment(\.tabViewBottomAccessoryPlacement)`, for example cover + title + play only. Or pass
   `.tabBarMinimizeBehavior(.never)` (the spike's non-`-minimize` runs used `.never` and stayed `.expanded`;
   the `.automatic` default was not tested).
4. **Spurious frames.** In run 1 the accessory content also reported a `.global` frame of (0,8 234×32)
   alternating with the real one, which suggests the system hosts the content more than once around
   placement changes. Ignore frames whose `minY` is not near the bottom (for example `minY < screen
   height / 2`), and assign only when the value changes.
5. **Availability.** `.tabViewBottomAccessory { }` and `tabViewBottomAccessoryPlacement` are iOS 26.0.
   The `isEnabled:` overload, needed to hide the accessory when no book is loaded, is **iOS 26.1**. On
   26.0, either always attach it and render an empty or zero-height bar (untested), or gate on
   `#available(iOS 26.1, *)` and fall back to the iOS 17–25 path. Deployment target stays 17.0, and the
   whole branch goes behind `if #available(iOS 26, *)`.
6. **The bar stays mounted under the open overlay.** While open, the accessory is still mounted, slid
   down with the hidden tab bar, so its gesture and the overlay's gesture never overlap in practice. Turn
   off overlay hit testing while closed (as the spike did) so it never steals bar touches.
7. **Native zoom is not enough.** `navigationTransition(.zoom)` is still a reasonable fallback for "tap
   opens", and its interactive dismiss is good. But it cannot do a finger-driven open, so it is not the
   main mechanism.

## Not determinable in the simulator

- Real-device feel: frame pacing at 120 Hz, touch latency, and how the Liquid Glass material looks under
  a moving opaque overlay.
- Real-finger behavior is untested. The drags were synthesized by XCUITest at fixed velocities, though
  the gesture got real touch events.
- VoiceOver interaction with the accessory, and whether accessibility actions on accessory content are
  exposed. Not tested.
- Interrupting a settle mid-animation (grabbing during the spring) was not exercised. SwiftUI animates
  the model value, so the presentation value must be tracked separately in T8. This is a known design
  item, not spike-specific.
