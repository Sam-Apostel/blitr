# Interaction scripts and animation capture

`blitr` can drive a screen with a script of steps and capture what happens: a PNG per
step, a filmstrip, or an animated file whose in-between frames are interpolated the way SwiftUI
animates (not a cross-fade of screenshots).

```
blitr render Todo.swift -o out/todo.png \
    --steps 'type "New task" "Water the plants" submit; tap "Buy milk"; swipe "Call the dentist" left' \
    --frames out/todo --frames-every-step --filmstrip out/todo-strip.png --animated out/todo.gif

blitr render Card.swift --animated out/card.gif --steps 'tap "Trip to Lisbon"'
blitr render Loading.swift --animated out/loading.apng --duration 2
```

`Examples/Interactions.swift` has one preview per feature with the exact command lines in its header.
`Tests/Interaction/run.sh` (run in CI) checks frame counts and that two runs give identical bytes.

Without any of these flags nothing changes: a still render records nothing and draws exactly what it
drew before.

## Steps

Steps run in order after the first frame has settled. After each one the normal resolve/layout pass loop
runs, so state changes, `onChange`, `.task`, presentations and navigation take effect. The `-o` PNG shows
the state after the last step. Each step logs one line on stderr:

```
tap "Toggle card" -> activated button "Toggle card"; state changed, 25 frames (spring(response: 0.5, damping: 0.6), 0.81s), 1 pass
```

On the command line separate steps with `;`; in a `--steps-file` write one per line. `# ` starts a
comment (`#3` is a selector). Strings are quoted with `"` or `'` and may contain `\"`, `\\`, `\n`.
Unknown steps, bad arguments and selectors that match nothing (or more than one thing) are errors that
list the candidates.

| Step | |
|---|---|
| `tap <selector> [+\|-]` | Activates an element: buttons, toggles, navigation links, tab items, list rows and views with `onTapGesture`, segmented / inline picker options, alert and dialog buttons, links (warns: URLs are not opened), the back button. `+` / `-` tap a stepper's halves (or step a slider); `tap @x,y` on a stepper picks the half under the point. Tapping a text field focuses it (the keyboard is not drawn). Tapping a menu picker or a date picker is an error that points to `set`. |
| `type <selector> "text" [submit]` | Sets a `TextField` / `SecureField` / `TextEditor` binding. `submit` then runs the `onSubmit` actions around the field. |
| `submit <selector>` | Runs `onSubmit`. |
| `set <selector> <value>` | Slider (number in its range, or `80%`), stepper (number, clamped to its range), picker (an option's title, exact then case-insensitive then a unique part; or `#n`), toggle (`on`/`off`/`toggle`), date picker (ISO 8601: `2025-03-01`, `2025-03-01T09:30`, `2025-03-01T09:30:00Z`). |
| `select-tab <name\|index>` | Selects a tab of the visible tab bar by title or 1-based index. |
| `scroll <selector\|first> <dy> [dx]` | Scrolls the innermost scroll view / `List` / `Form` around the element (or the first one) by points, clamped to the content. Positive `dy` moves the content up. |
| `scroll-to <selector>` | Scrolls the least amount that shows the element with a 16pt margin. |
| `swipe <selector> left\|right [action]` | Runs a row's swipe action (`.swipeActions`, `ForEach.onDelete`): left uses the trailing actions, right the leading ones; the first by default, or the one named. Inside a paging `TabView` it turns the page. |
| `long-press <selector>` | Runs `onLongPressGesture`. |
| `dismiss` | Dismisses the topmost sheet, cover, alert or dialog; otherwise goes back. |
| `back` | Pops the top screen of the innermost navigation stack (screens pushed by steps, and `NavigationStack(path:)` bindings). |
| `shake` | Shakes the device: UIKit's `motionBegan` and `motionEnded` with `.motionShake` on the key window, so an app's `extension UIWindow { override func motionEnded(...) }` runs (see docs/FRAMEWORKS.md, overrides in extensions). |
| `press up\|down\|left\|right\|select\|menu\|playpause` | A Siri Remote press (docs/FOCUS.md). |
| `wait <seconds>` | Lets time pass: time-driven content keeps moving; animated outputs hold the frame. `Task.sleep` calls that end by then return, and what they change shows after the wait. |
| `snapshot [name]` | Emits a frame here (`--frames`, `--filmstrip`). |

### Selectors

- `"Add"` or `Add`: an accessibility identifier, else an exact label, else a case-insensitive part of a
  label. Interactive elements are searched first; `scroll-to`, `swipe` and `long-press` also find static
  text and images (a row by its text). An element on screen wins over one scrolled out of view.
- `id:addButton`: an identifier (also matched without the prefix).
- `"Delete"[2]`: the second match.
- `#3`: the third interactive element in reading order (the error listing shows the numbers).
- `@120,400`: the topmost interactive element at a point, in points (the smallest hit area containing it).

Elements come from the accessibility tree of the current frame (`--accessibility-tree` shows the same
labels, roles and frames). What a tap does comes from the element's default action, the focus engine's
activation registry (`Runtime.activations`), or a control's recorded handlers
(`Interaction/InteractionRegistry.swift`).

### What steps cannot do

- Context menus are not drawn: `long-press` on a view with only a `.contextMenu` is an error.
- Menus (menu pickers, `Menu`) do not open; use `set` to choose an option.
- Revealed swipe-action buttons are not drawn: `swipe` runs the action directly.
- Gestures attached with `.gesture(...)`, drags and custom controls have no action to run.
- The keyboard is not drawn.
- `@Environment(\.dismiss)` during a capture dismisses the topmost presentation (else pops), which is
  right when the button that calls it is on the topmost screen.

## Outputs

| Flag | |
|---|---|
| `--frames <dir>` | A PNG per `snapshot` step, named `<nnn>-<step>.png`. |
| `--frames-every-step` | ...and one after the start and after every step. |
| `--frames-all` | ...and every in-between frame. |
| `--filmstrip <file.png>` | The frames side by side with a caption under each (the step, or the snapshot's name). With only time-driven content, or with `--filmstrip-frames <n>`, n evenly spaced moments of the animation, captioned with their time. `--filmstrip-scale <f>` sizes the cells (default 2 pixels per point). |
| `--animated <file>` | The whole capture: `.gif`, `.png` / `.apng` (lossless APNG), `.webp` (lossless, Skia's animated encoder), `.mp4` / `.mov` (frames piped to `ffmpeg` on `PATH`; a clear error otherwise). `--animated-scale <f>` (default 1 pixel per point). |
| `--fps <n>` | Frames per second of animations (default 30). |
| `--hold <s>` | How long each settled state is shown in animated outputs (default 0.6). |
| `--duration <s>` | Seconds of time-driven content captured at the start. |
| `--full-content <file.png>` | The first vertical scroll view's whole content in one tall image (see Scrolling). |
| `--gif-palette global\|local`, `--gif-dither` | GIF options. |

The runner's JSON line reports `frameCount`, `captureDuration`, `frames`, `animated`, `animatedFrames`.

With `--frame` or `--frame-dir` (README, "Device frames") the frames, the animated output and the filmstrip
cells carry the device frame; the filmstrip then draws no outline of its own. Taps and other steps still address
the bare screen. GIF has only on-off transparency, so the frame's anti-aliased edge is hard there; APNG and WebP
keep it smooth. `--full-content` is not framed.

### Encoders

- **GIF** (`Interaction/GIFEncoder.swift`): median-cut palette (255 colors, perceptually weighted, one
  for the whole capture by default), optional ordered dithering (Bayer 4x4, stable between frames),
  frame differencing (each frame stores only the changed rectangle, with unchanged pixels transparent),
  identical frames merged into longer delays, LZW. Delays are hundredths of a second with the rounding
  carried over, so the total length is right. A 393x852 capture of a few seconds is 60-800 KB.
- **APNG** (`Interaction/AnimatedEncoders.swift`): Skia encodes each frame's changed rectangle as a PNG;
  the encoder takes its IDAT chunks and writes `acTL`, `fcTL` and `fdAT` itself. Lossless.
- **WebP**: Skia's `sk_webpencoder_encode_animated`, lossless (large; prefer GIF or APNG).
- **MP4 / MOV**: raw RGBA frames piped to `ffmpeg` (H.264, yuv420p, bit-exact flags), constant frame rate.

## Animation between states

When a step changes state, the tree before the step and the settled tree after it are compared, node by
node, and frames in between are drawn by the tweener (`Animation/Tweener.swift`):

- **Matching** is by structural identity: the resolve path of the view that produced each node (the same
  identity `@State` uses; `ForEach` ids are part of it), plus the node's class and occurrence. Container
  nodes the engine creates (list rows, wrappers) take the identity of their first stamped descendant.
- **Matched nodes interpolate** their frame (position and size, relative to the parent so containers
  carry their children; scroll offsets follow from that), opacity, `scaleEffect`, `rotationEffect`,
  `offset`, blur, shadow (color, radius, offset), shape geometry through `animatableData` (corner radius
  of `RoundedRectangle` / `UnevenRoundedRectangle`, `trim`, custom `Shape`s with `Double`/`CGFloat`
  `AnimatablePair` data), and paints: colors (premultiplied), linear / radial / angular gradients with the
  same number of stops, color to gradient. Text and images keep their final layout and move; when their
  content changes (string, font, color, symbol) they cross-fade, which is SwiftUI's default `.opacity`
  content transition. `contentTransition(.numericText())` and symbol replacements also cross-fade.
- **Unmatched nodes** are insertions and removals, drawn in their place among their siblings through
  their `.transition`: `.opacity` (default), `.move(edge:)` (by the view's own size), `.offset`, `.scale`
  (with anchor), `.slide`, `.push(from:)`, `.blurReplace`, `.identity`, `.asymmetric`, `.combined`,
  `AnyTransition.animation(_:)`. Custom `Transition` types and `AnyTransition.modifier` fade instead
  (with a warning).
- **`matchedGeometryEffect`**: a removed and an inserted view with the same id and namespace form a pair;
  the inserted one flies from the removed one's frame to its own above the rest of the screen, the two
  cross-fading (shapes simply take the in-between frame).
- **Which animation**: the step's transaction (`withAnimation`, `withTransaction`, `Binding.animation`),
  overridden inside `.animation(_:value:)` when its value changed (`animation(nil)` disables), and by
  `.transaction` modifiers; `disablesAnimations` turns implicit animations off. With `--animate-all` a
  step without a transaction animates with `.default`. Changes without an animation snap. Every change
  made during a step that recorded a `withAnimation` animates with it (the capture cannot tell which
  state change a transaction made). `withAnimation(completion:)` runs the completion after the frames.
- A `withAnimation` in `onAppear` / `.task` of the first frame animates from the state before it.
- The last frame of every animation is drawn by the plain renderer, so it is pixel-identical to a still
  render of the end state, and the `-o` PNG equals the last frame.

### Curves

`Animation` keeps Apple's parameters (`Animation/Animation.swift`):

| | |
|---|---|
| `.linear`, `.easeIn`, `.easeOut`, `.easeInOut` | cubic Béziers (0.42,0,1,1 / 0,0,0.58,1 / 0.42,0,0.58,1), 0.35 s by default |
| `timingCurve(_:_:_:_:duration:)`, `timingCurve(UnitCurve, duration:)` | Bézier / circular curves |
| `.spring(response:dampingFraction:)` | ω = 2π / response, ζ = dampingFraction (defaults 0.5, 0.825; also `.spring`) |
| `.spring(duration:bounce:)`, `.interpolatingSpring(duration:bounce:)` | response = duration, ζ = 1 - bounce (1 / (1 + bounce) when negative) |
| `.smooth`, `.snappy`, `.bouncy` | bounce 0, 0.15, 0.3 (+ `extraBounce`), duration 0.5 |
| `.interactiveSpring` | response 0.15, ζ 0.86 |
| `.interpolatingSpring(mass:stiffness:damping:initialVelocity:)`, `.spring(Spring)` | as given |
| `.default` | the `.smooth` spring (iOS 17 and later, the only looks rendered); easeInOut 0.35 s before |
| `CustomAnimation` | sampled through its `animate(value:time:context:)` |

Springs are solved in closed form (under-, critically and over-damped, with initial velocity), so they
overshoot. A spring runs until its displacement stays below 0.1% of the distance. `delay`, `speed`,
`repeatCount(_:autoreverses:)` (after the last repeat the value jumps to the end, as in SwiftUI) and
`repeatForever` (one cycle is captured: forward and back when autoreversing) are applied. Animations are
capped at 10 s.

### System transitions

`Animation/SystemTransitions.swift` holds them with named durations and curves so they can be calibrated:

| | |
|---|---|
| Sheet | slides up from the bottom (critically damped spring, response 0.5; dismissal 0.42); the presenter scales back and dims as the card comes up; partial sheets fade their dimming |
| Full-screen cover | slides up |
| Alert | fades in while scaling from 1.15 to 1 (ease-out 0.3 s); fades out (ease-in 0.2 s) |
| Confirmation dialog | slides up, the backdrop fades |
| Navigation push / pop | the new screen slides in from the trailing edge over the old one, which moves a third of the way and dims 10%; reversed on pop (spring, response 0.5); bar titles cross-fade |
| Tab switch | none (immediate, as on iOS) |
| Keyboard | not drawn |

## Time-driven content

A capture has its own clock. It only advances by the frame interval, never from the wall clock:

- `--duration <s>` captures that span at the start (also after the first frame's animations).
- `TimelineView` gets `start + clock` as its date (`.animation`, `.periodic`, `.everyMinute`...).
- `Text(date, style: .timer / .relative)`, `Text(timerInterval:)`, timer progress views read the same "now".
- `PhaseAnimator` (view and modifier) cycles through its phases with each phase's animation and the
  tweener interpolates between consecutive phases; with a trigger it runs once when the trigger changes
  during the capture. A phase is considered done when a spring is within 1% of its target.
- `KeyframeAnimator` / `keyframeAnimator` / `KeyframeTimeline`: tracks are evaluated for real (`LinearKeyframe`
  with its timing curve, `SpringKeyframe`, `CubicKeyframe` as Hermite splines with Catmull-Rom tangents
  unless velocities are given, `MoveKeyframe`); repeating ones loop, triggered ones play when the trigger
  changes.
- Indeterminate `ProgressView`: the eight ticks step round once a second.
- Indefinite `symbolEffect`: `.pulse` and `.variableColor` (as a pulse: symbols have one layer) fade,
  `.breathe` scales, `.rotate` turns, `.wiggle` rocks. Discrete effects (`.bounce` with `value:`) and
  transition effects are not animated.

**`--date <ISO8601>`** fixes "now" (`Runtime.referenceDate`) for all of the above. A capture without
`--date` uses a fixed date (2025-06-09T09:41:00Z), so the same input gives the same bytes. User code that
calls `Date()` or `Date.now` itself is not affected and stays non-deterministic. `.task` work still runs
within `--task-timeout` of real time, as in a still render, with `Task.sleep` on the virtual clock
(docs/ARCHITECTURE.md, "Tasks, time and network"); each `wait` step moves that clock on. Times are shown in
`--time-zone` (UTC unless given).

## Scrolling

`scroll` and `scroll-to` animate with UIScrollView's deceleration curve (rate 0.998/ms, settling in
0.8 s). Unlike state changes, every frame is a full layout at that offset, so:

- **modelled**: content moving under the navigation and tab bars and the safe area; lazy stacks and lists
  realizing rows as they come into view; whatever the engine draws at an offset (pinned section headers,
  scroll edge effects as far as the still renderer draws them).
- **not modelled**: rubber-banding, scroll indicators, large navigation titles collapsing to inline (the
  title keeps its still-frame layout), `scrollTargetBehavior` paging, animating
  `ScrollViewReader.scrollTo` and `scrollPosition` from code (both jump to the end position).

`--full-content <file.png>` captures the first vertical scroll view at successive offsets and stacks the
visible slices; what is above the scroll view (status and navigation bar) is taken from the first capture
and what is below it (tab bar, home indicator) from the last, so bars appear once.

## Limitations

- Frames keep the size of the first frame; `--layout fit` views that change size warn.
- Re-parented views (other than matched-geometry pairs) move in absolute coordinates.
- Several state changes in one step share one animation (see above).
- A view whose identity changes (an `if`/`else` with different branches, `.id()`) is a removal plus an
  insertion, as in SwiftUI.
