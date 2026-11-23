# Buddy UI design spec

A small dark "screen" creature that sits in a screen corner. It stays quiet, nudges softly, and only grows into a surface when there is something to say or pick. Black, white and grey only. The one hue is amber, and it appears only as the "needs you" ring.

Code: `Sources/BuddyUI`. Review every state: `Sources/BuddyUIGallery` (see the end of this file).

## Palette tokens (`Theme.swift`)

| Token | Dark appearance | Light appearance | Use |
| --- | --- | --- | --- |
| ink | white 96% | white 7% (near-black) | primary text, icons, working dot, primary button fill |
| ink2 | ink at 66% (84% at high contrast) | same | secondary text (meeting time, toast text) |
| ink3 | ink at 46% (68%) | same | labels, paths, ages, hints |
| onInk | near-black | near-white | text on the inverted primary button |
| hairline | white 15% | black 11% | surface border, dividers (1 px) |
| fillHover / fillSelected / fillField | white 7 / 13 / 7% | black 5 / 8 / 5% | row hover, selected row, compose field |
| glassTint | black 50% | white 62% | over the blurred material, keeps contrast on any desktop |
| solidSurface | white 10% | white 97% | replaces glass under Reduce Transparency / Increase Contrast |
| amber | #E8A640 | #B37519 | "needs you" ring only |
| screen / face / bezel | #0E0E0E / white 95% / white 16% | same | the character, identical in both appearances |

**Status dots.** working is a solid ink dot with a soft sonar ping (1.8 s). idle is a grey dot (ink at 36%). needs you is a hollow amber ring. Recent, not-live sessions get a grey dash. Each status differs in shape as well as tone, so none depends on colour alone. The working dot is white in dark mode and black in light mode: a white dot vanishes on light glass.

**Why the needs-you state is an amber ring and not a white one.** It is the only state that asks for action, so it gets the only hue and the only hollow shape. A white ring would sit too close to the white working dot when glanced at from the corner of the eye. Amber is used nowhere else, so it never turns into decoration. The text "needs you" sits next to it in rows and toasts for redundancy. Light-mode amber is darker so it passes 3:1 against the light glass.

## Type

System font for UI, SF Mono for anything machine-ish (paths, ages, transcripts, labels).
- title 13 semibold; row title 13 medium; body 13
- meta 11 mono (paths, ages, meeting time)
- label 10 mono medium, uppercase, tracking +0.6 (section labels, toast kind)
- transcript 12 mono, line spacing 2

## Character anatomy (56 pt)

- Head: rounded rect, radius 16 continuous, `screen` fill. Faint scanlines (0.5 pt lines every 3 pt at 4.5% white), drawn once by a Canvas. Inner bezel at 16% white, 0.5 pt dark outline so it reads on white desktops, shadow r9 y4.
- Eyes: two block rects, 7x11, radius 2, 11 pt apart, 3 pt above centre. Blinks scale the height toward a line.
- Mouth: none, except a 10x2.5 terminal-cursor underscore while listening.
- Badge: a 16 pt knockout at the top-trailing corner holding a status dot. It shows an amber ring if any live session needs you (or the mood is needs-you), otherwise a static white dot if anything is working, otherwise nothing. It is static so idle CPU stays at zero.
- Hover: scale 1.04. Press: scale 0.93, anchored bottom. Click: toggles the panel. While choosing a target, click dismisses. While listening, click does nothing.

## Moods

| Mood | Character | Surface (collapsed) |
| --- | --- | --- |
| idle | block eyes; every ~4.2 s slot does one of: blink, double blink, 1.6 s glance left or right, 2.4 s breath (eyes rise 1.2 pt), or nothing | none |
| meetingSoon | eyes look toward the bubble; bezel pulse (opacity only) most slots, rare after 60 s | banner: title, "in 4 min · 10:30–11:00" (refreshes every minute), Join (primary, only with a joinURL), dismiss |
| listening | taller eyes (8x12); cursor mouth blinking at 1 Hz | "LISTENING · RELEASE TO SEND", live transcript in mono with a blinking block caret. Only the newest ~130 characters are kept, so the tail is always visible |
| choosingTarget | eyes look toward the picker | target picker (below) |
| sessionFinished | happy carets `^ ^`, one hop on arrival | toast: grey dot, "FINISHED", title, Open, dismiss |
| sessionNeedsYou | wide eyes (8x13) looking at the toast, amber badge, one hop, bezel pulse (rare after 45 s) | toast: amber ring, "NEEDS YOU", title, Open (primary), dismiss |
| sent | happy carets, one hop | check glyph + the mood's string verbatim, dismiss |
| error | `x x` eyes, short horizontal shake | "!" glyph + message (up to 3 lines), dismiss |

The UI never dismisses on its own. The app owns timeouts for toasts (`onDismiss` / setting `mood = .idle`).

## Precedence

1. listening and choosingTarget always own the surface.
2. Otherwise `model.expanded` shows the panel. An active toast (finished / needs you / sent / error) then appears inside the panel as a notice row, and the meeting Join drops to secondary so the surface has one primary action.
3. Otherwise the mood's bubble. Idle shows the character only.

## Target picker (320 pt wide)

Header "Send to" + close. Below it, the transcript as a mono quote (4 lines max, with a 2 pt rule on the leading edge) and "Screenshot attached" when there is one. Then the list:
- live sessions: LIVE label, sessions in model order, then New session
- no live sessions: NO LIVE SESSIONS label, New session, RECENT label, recent sessions (dash marker)

Rows are 40 pt: dot, title, path (head-truncated), and on the trailing side the age, "needs you", or a return keycap on the selected row. New session uses the cwd of the most recent live (else recent) session, else home. The list scrolls past 6 rows. Footer hint: up/down move, return send, 1-9 pick, esc close. Hovering moves the selection and clicking sends. Calls `model.onPick` and `model.onDismiss`.

## Expanded panel (320 pt wide, at most ~470 pt tall)

From top to bottom:
1. Optional notice row.
2. NEXT: meeting title, countdown and time range, Join. With no meeting: "No meetings soon".
3. SESSIONS (with "N live") or RECENT. Rows open the session (`onOpenSession`). Scrolls past 5 rows.
4. Compose: a 1-4 line "Ask Claude" field, a "to <target>" native pop-up menu (live or recent sessions plus New session), and a send button. Return sends and Esc collapses. The default target is the most recent live session, else New session.

## Sizes (`BuddyMetrics`)

characterSize 56, outerPadding 16, stackSpacing 10, bubbleMaxWidth 320, panelWidth 320, panelMaxHeight 470. collapsedSize is 88x88. expandedMaxSize is 352x568. The root view is self-sizing with a transparent background. If the window is larger than the content, the content stays pinned to `corner` (default bottomTrailing). Surfaces stack above the character for bottom corners and below it for top corners.

## Motion

- Surfaces: spring response 0.34, damping 1.0 (no overshoot). They scale from 0.94 at the character's corner, with a 6 pt offset and a fade, and leave along the same path. All transitions are interruptible because they are SwiftUI springs keyed on the surface kind.
- Expression morphs: spring 0.30 / 0.78. Press: 0.16 / 1.0. Hover: 0.28 / 0.72.
- Hop: 70 ms anticipation squash, rise of 7 pt, landing spring (damping 0.55).
- Shake: -5, 5, -3, 2, 0 over about 0.5 s.
- Idle choreography (`Choreography.swift`): poses are a pure function of absolute time. A custom `TimelineSchedule` emits frames only while an action plays, capped at 30 fps, and nothing in between. An idle buddy renders a few frames every few seconds. Listening adds 2 ticks per second for the caret. The working-dot ping uses `TimelineView(.animation(minimumInterval: 1/30))` and only runs while a list is on screen.
- Visibility: `WindowVisibilityReader` watches the window's occlusion state. When the window is covered, ordered out, or the display is asleep, the choreography, the dot pings and the caret stop.

## Accessibility

- Reduce Motion: surfaces cross-fade (0.18 s ease). No glance, breath, hop, shake or hover scale. Blinks, the opacity-only bezel pulse and the caret remain, and a press dims instead of scaling.
- Reduce Transparency and Increase Contrast: surfaces switch to solid fills. Increase Contrast also raises ink2, ink3, the hairline and the bezel.
- VoiceOver: the character is a button labelled "Buddy" whose value is the mood. Toasts and meetings are announced on arrival (`AccessibilityNotification.Announcement`). Rows read "title, status, path". Status is never conveyed by colour alone.
- Keyboard: the picker is fully keyboard-driven. The panel's compose field supports Return and Esc.

## Integration notes

- Host it in a borderless `NSPanel` with `isOpaque = false`, `backgroundColor = .clear` and `hasShadow = false` (the UI draws its own shadows). Size the panel to the hosting view's fitting size, keep it anchored to the corner, and use the `BuddyCorner` you pass to `BuddyRootView(model:composeBridge:corner:)`.
- Glass uses `NSVisualEffectView` with `.behindWindow` blending, so it blurs the desktop. Galleries and previews that draw their own backdrop call `.buddyMaterialBlending(.withinWindow)`.
- The picker and the compose field need the panel to become key (`canBecomeKey = true`, then make it key when the picker or panel appears). Otherwise the arrow, return, number and Esc keys and typing do nothing.
- Compose: `BuddyComposeBridge.onCompose(text, target)` is called on the main actor, and the draft clears after it. Dispatch it with `SessionProviding.dispatch(prompt:screenshot: nil, to:)`.

## Gallery

`swift build --product BuddyUIGallery --scratch-path .build-ui && .build-ui/debug/BuddyUIGallery`

The gallery shows every state in dark appearance on a dark desktop, dark appearance on a light desktop, and light appearance on a light desktop. It has a sidebar, a scripted live demo and a cycle toggle. `--shoot DIR` writes one PNG per state (see `docs/shots/`). `--film DIR` captures frame bursts of the demo's transitions. `--state <rawValue>` opens on a single state.
