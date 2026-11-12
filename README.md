# HandTrack – Intelligent Virtual Mouse (Team 1)

Control your computer's mouse with hand gestures in front of a webcam.
Built with **Python, OpenCV, MediaPipe Hand Landmarker and PyAutoGUI**.

| Requirement | How HandTrack does it |
|---|---|
| Move cursor with index finger | Only index finger up → cursor follows the index fingertip |
| Click with thumb–index pinch | Quick pinch and release → left click |
| Double-click **or** drag | **Both**: thumb–middle pinch = double click, pinch and hold = drag & drop |
| Gesture to enable/disable mouse | Hold an open palm for 1 s → mouse control ON / OFF |
| Show recognised gesture | Gesture banner + side panel with the matched rule and live measurements |
| No hand / unclear gesture | "No hand detected" message, "Unclear gesture" with the reason; no mouse action in both cases |
| Bonus | Scroll (index + middle up), fist = pause, two-hand support, light boost, emergency stop |

---

## 1. Setup

You need Python 3.9 or newer and a webcam.

**Easiest (macOS):** double-click **`Start HandTrack.command`** in Finder, or run
`./run.sh` in Terminal from this folder. On first run it creates the Python
environment and installs everything automatically.

Manual setup (any OS):

```bash
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

> On macOS the command is `python3`, not `python`, unless the `.venv` is activated.
> `./run.sh` avoids this problem.

The hand model `handtrack/models/hand_landmarker.task` is included. If it's missing, download it:

```bash
curl -L -o handtrack/models/hand_landmarker.task https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
```

**macOS permissions** (one time): System Settings → Privacy & Security →
**Camera** *and* **Accessibility** → allow your terminal app (Terminal / iTerm / VS Code).
Without Accessibility the app runs but the mouse won't move.

## 2. Run

```bash
./run.sh                            # same as below, works without activating .venv
python -m handtrack                 # mouse control starts OFF: hold open palm 1 s
python -m handtrack --dry-run       # recognise gestures but never touch the mouse
python -m handtrack --start-on      # start with mouse control ON
python -m handtrack --hand right    # with two hands visible, only the right one controls
python -m handtrack --enhance       # contrast boost for dim rooms
python -m unittest discover tests -v   # 16 automated tests, no webcam needed
```

Keys (with the HandTrack window focused): **Q**/Esc quit · **M** mouse on/off ·
**Space** emergency stop · **E** light boost · **H** show/hide gesture help ·
**C** switch camera.

## 3. Gestures

| Gesture | Hand shape | Action |
|---|---|---|
| **MOVE** | Only index finger up | Cursor follows index fingertip |
| **PINCH** (tap) | Thumb tip touches index tip, then release | Left click |
| **PINCH** (hold > 0.45 s) | Keep thumb & index together and move | Drag; open fingers to drop |
| **DOUBLE CLICK** | Index up, thumb touches **middle** fingertip | Double click (once per gesture) |
| **SCROLL** | Index + middle up | Move hand up/down from the start point to scroll |
| **OPEN PALM** (hold 1 s) | All 5 fingers spread | Toggle mouse control ON/OFF |
| **FIST** | All fingers curled | Pause: reposition your hand without moving the cursor |
| **UNCLEAR** | Anything else | No action, reason shown on screen |

**Tips:** sit 50–80 cm from the camera with your hand inside the pink "control
area" box. That box maps to the whole screen, so small hand movements reach every
screen edge.

## 4. How it works

```
Webcam ─► OpenCV (flip, resize, optional CLAHE) ─► MediaPipe Hand Landmarker (21 points)
       ─► gestures.py  measurements → rules → stabiliser
       ─► controller.py  gesture → mouse state machine → PyAutoGUI
       ─► hud.py  skeleton, measurements and matched rule on screen
```

| File | Role |
|---|---|
| `handtrack/main.py` | Webcam loop, hand selection, keyboard, error handling |
| `handtrack/tracker.py` | MediaPipe Hand Landmarker wrapper (21 landmarks + left/right) |
| `handtrack/gestures.py` | **Gesture recognition logic** (measurements + rules + stabiliser) |
| `handtrack/controller.py` | Click / drag / scroll / toggle state machine |
| `handtrack/filters.py` | One-Euro filter for smooth cursor movement |
| `handtrack/hud.py` | Explainability overlay and side panel |
| `handtrack/config.py` | All thresholds in one place |
| `tests/test_handtrack.py` | 16 tests using synthetic hands |

### 4.1 Gesture recognition logic (what to explain to judges)

MediaPipe returns 21 landmarks per hand (0 = wrist, 4 = thumb tip, 8 = index tip,
12 = middle tip, …). We compute **three kinds of measurements**:

1. **Hand size** = distance from wrist (0) to the middle-finger knuckle (9).
   Every other distance is divided by this, so the rules work whether the hand is
   30 cm or 1 m from the camera.

2. **Is a finger up?** For index/middle/ring/pinky:

   `extension = dist(tip, wrist) / dist(PIP joint, wrist)`

   A straight finger's tip is much farther from the wrist than its middle joint
   (≈ 1.3). A curled finger folds back (≈ 0.6). **Up if > 1.15.**
   Because this compares distances and not "is the tip above the knuckle", it
   still works when the hand is tilted or rotated (a test checks ±60°).

   Thumb: `dist(thumb tip, index knuckle) / hand size`, **up if > 0.60**.

3. **Pinch distance** = `dist(thumb tip, index tip) / hand size`
   (and the same for the middle finger).
   **Pinch starts below 0.25 and only ends above 0.35.** This gap is called
   *hysteresis*: a distance hovering around one threshold can't make the pinch
   flicker on and off and fire several clicks.

**Rules, checked in this order (first match wins):**

| # | Rule | Gesture |
|---|---|---|
| 1 | All 5 fingers up | OPEN PALM |
| 2 | Thumb–index pinch **and** index not fully curled (extension > 0.85) | PINCH |
| 3 | Thumb–middle pinch **and** middle not fully curled **and** index up | DOUBLE CLICK |
| 4 | Index + middle up, ring + pinky down | SCROLL |
| 5 | Only index up (thumb ignored) | MOVE |
| 6 | No long finger up | FIST |
| – | Nothing matched | UNCLEAR (shows the finger pattern, e.g. `T- I- M- R- P+`) |

The "not fully curled" checks in rules 2 and 3 stop false clicks: in a fist, or
just while pointing, the thumb rests on the curled fingers, so the thumb–finger
distance is small. Our automated tests caught this bug (pointing was detected as
a double click) and this check fixes it.

### 4.2 From gesture to mouse action

* **Stabiliser:** a new gesture is only accepted after **3 consecutive frames**
  (~0.1 s). A one-frame glitch can't click.
* **Click vs drag:** when a pinch starts we record the time. Released before
  0.45 s → click. Held longer → mouse button down, cursor follows the hand
  (macOS-style drag events), release → drop.
* **Click rollback:** closing your fingers to pinch moves the index tip a little,
  which would make you miss small buttons. On pinch start we move the cursor
  back to where it was 0.2 s earlier, before the pinch motion began.
* **Smoothing:** a **One-Euro filter** (Casiez et al., 2012) smooths heavily when
  the hand is almost still (no jitter) and lightly when it moves fast (no lag).
* **Scroll** works like a joystick: the start height is the zero point; moving
  further up or down scrolls faster. A small dead zone ignores tiny movements.
* **Toggle:** the palm must be held for a full second (a ring fills up on screen),
  and it toggles only once per hold.

### 4.3 Robustness and edge cases

| Situation | Behaviour |
|---|---|
| No hand in frame | "No hand detected" message; after 5 missed frames everything resets and any drag is released (button never stuck down) |
| Brief tracking drop-out | Up to 5 frames tolerated without changing state |
| Unclear hand shape | Shown as UNCLEAR with the reason; no mouse action |
| Two hands | Both are tracked; one controls (sticky, or chosen with `--hand`), the other is drawn grey as "ignored" |
| Dim lighting | `E` key or `--enhance` applies CLAHE contrast boost |
| Emergency | Space key, or slam the real mouse into a screen corner (PyAutoGUI fail-safe) → mouse control OFF and button released |
| Several cameras / black camera | Each camera is tested at startup and black ones are skipped; if the camera goes black or disconnects while running, the app switches camera instead of closing |
| No camera at all | Window stays open with a "Waiting for camera" message and keeps retrying |

### 4.4 Explainability (on screen)

* Fingertips are **green = up, red = down**.
* The **thumb–index line** shows the live pinch distance and turns green when engaged.
* The side panel shows each **finger's measured extension next to its threshold**
  (yellow tick), both **pinch distances with the engage/release ticks**, the
  **rule that matched**, the controlling hand and confidence, FPS and the last actions.
* While a new gesture is being confirmed the panel shows "confirming …".

## 5. Surprise-challenge readiness

| Possible challenge | Already in HandTrack / how to adapt |
|---|---|
| Add a custom gesture | Add a rule in `GestureClassifier.classify` and an action in `MouseController._act`. Example: right-click with thumb–ring pinch (same as rule 3, using landmark 16) → `pyautogui.rightClick()` |
| Start/stop or emergency stop | Open-palm toggle, Space key, corner fail-safe |
| Two-hand detection | `max_hands=2`, control-hand selection, `--hand` option |
| Reduce accidental activation | 3-frame stabiliser, pinch hysteresis, curl guards, 1 s palm hold, starts OFF; raise `stable_frames` in `config.py` for stricter behaviour |
| Simple GUI | Side panel with status, meters and action log |
| Different positions / lighting | Rotation- and scale-invariant ratios, CLAHE light boost, adjustable confidence in `config.py` |
| Explain why a gesture was recognised | "Rule:" line + threshold meters (section 4.4) |

## 6. How AI tools supported development

> Edit this section so it describes what your team actually did.

We used an AI coding assistant (Claude) as a pair programmer:

* **Design:** discussed which gestures would be reliable and non-conflicting
  (e.g. double-click on a separate thumb–middle pinch instead of timing two
  pinches, fist as a "clutch").
* **API help:** the installed MediaPipe version (1.x) no longer has the old
  `mp.solutions.hands` API, so the assistant helped us move to the newer
  **Tasks `HandLandmarker` API**.
* **Code:** generated a first version of the modules, which we reviewed, ran and tuned.
* **Testing:** wrote synthetic-hand unit tests. These found a real bug (pointing
  was detected as a double click because the thumb rests on the curled middle
  finger), which we fixed with the "not fully curled" check.
* **Our own work:** testing with the real webcam, tuning thresholds for our
  hands and lighting, and understanding/explaining every rule.

## 7. Tuning and troubleshooting

All numbers are in `handtrack/config.py`. Watch the side panel while doing a
gesture to see the measured values, then adjust:

* Clicks too hard to trigger → raise `pinch_on` (e.g. 0.30) and `pinch_off`.
* Cursor jittery → lower `filter_min_cutoff`; cursor laggy → raise `filter_beta`.
* Can't reach screen edges → shrink the control region (`region_*`).
* A finger shows "down" when straight → lower `finger_up_ratio` (e.g. 1.10).
* Mouse doesn't move on macOS → Accessibility permission (section 1).
* Black picture / wrong camera → the app tests every camera at startup and skips
  black ones (e.g. an iPhone Continuity Camera). Press **C** to switch camera,
  or run `./run.sh --list-cameras` to see which ones work.

## 8. Demo script (≈ 3 minutes)

1. Start `python -m handtrack`. Point out the side panel: **mouse is OFF**.
2. Hide your hand → "No hand detected". Show a random shape → "UNCLEAR" + reason.
3. **Open palm 1 s** → ring fills → MOUSE ON.
4. **Index up** → move the cursor around; show the smoothing.
5. **Quick pinch** on a folder → click. **Thumb–middle** → double click opens it.
6. **Pinch and hold** a file/window → drag and drop.
7. **Index + middle** → scroll a web page up and down.
8. **Fist** → move hand, cursor stays (clutch).
9. Show a second hand → drawn grey as "ignored".
10. Point at the panel: explain one rule using the live numbers
    (e.g. "pinch is 0.12, below the 0.25 threshold → PINCH").
11. **Open palm 1 s** → MOUSE OFF. Mention Space = emergency stop.
