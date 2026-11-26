# Liftoff — morning boarding assistant for macOS

Date: 2026-11-18 · Owner: Đại · Status: design, pending approval

## 1. Intent

Every weekday Đại arrives at the office around 8:30–9:30 and runs the same
ritual: plug in two Ugreen Type‑C cables, bring up the Acasis 15‑in‑1 dock,
power on the FiiO K7 (red) DAC, open Agent Factory, pour water, put on the
Sennheiser HD 660S2, start music in Apple Music, check Teams, then start
projects.

Liftoff turns that ritual into a pre‑flight checklist: when the Mac wakes in
the morning, a female English voice greets Đại as "Commander" and walks them
through each step, one at a time, over motivational background music. Each
step ticks itself off when the Mac can see it happened.

**The why:** to make the start of the day exciting. Success = Đại looks
forward to the sequence and it feels like a launch, not a to‑do list.

## 2. Goals, non‑goals, anti‑goals

Goals
- Guided, one‑step‑at‑a‑time morning sequence with voice + background music + SFX.
- Auto‑detection of every step the Mac can observe; manual confirm for the rest.
- CleanMyMac‑grade visuals: glossy 3D illustrations, per‑step gradients, smooth transitions.
- Two display modes, user‑selectable: **Notch** (default) and **Fullscreen**.
- Starts by itself on the first wake/login of a weekday morning.

Non‑goals (v1)
- Editing/reordering steps from a UI (steps live in a config file; see §6.4).
- Multi‑user, sync, iOS, analytics, any server component.
- Controlling hardware (it observes, it never switches devices on).
- An evening "Landing" sequence (music off, unplug, dock/DAC off, pack
  headphones, laptop stand, phone stand, keyboard cable, clean desk, close
  lid). Good v2 candidate; the step/config model should not preclude it.

Anti‑goals (failure even if it "works")
- Feels like a nagging to‑do app or a notification spammer.
- Robotic voice reading lines as the main experience.
- Fires at the wrong time (afternoon, weekends, every lid open) or blocks work when Đại is in a hurry.
- Repetitive to the point of annoyance after a week (identical lines every day).

## 3. Constraints

- macOS 26 (Tahoe), Apple Silicon MacBook with a notch. Swift 6.3 via Command
  Line Tools; Xcode is **not** installed, so the build must work with SwiftPM +
  a script that assembles the `.app` bundle (ad‑hoc signed, personal use only).
- Apps on this machine: `/System/Applications/Music.app`,
  `/Applications/Microsoft Teams.app`, `~/Applications/Agent Factory.app`.
- Voice via ElevenLabs needs an API key and network; must degrade gracefully.
  Budget: ~6k characters for the full line set once + ~80/day for the dated
  greeting fits the free tier (10k/month); free tier is personal/non‑commercial.
- Music and imagery must be royalty‑free or user‑supplied (personal use).
- When not running the sequence the app must be idle (no polling loops burning CPU).

## 4. Approaches considered

| | Approach | Trade‑off | Decision |
|---|---|---|---|
| 1 | **Native Swift + SwiftUI app** | All needed APIs first‑class (notch window, IOKit, CoreAudio, NSWorkspace, AVAudioEngine, SMAppService). Light, true Mac look. | **Chosen by Đại.** |
| 2 | Tauri / Electron web app | UI as HTML like the mockups, but notch + device detection still need native code; Electron heavy for a 5‑minute app. | Rejected. |
| — | Hammerspoon/script automation | Can't deliver the visual experience. | Dropped early. |

Sub‑decisions made in conversation:
- Detection: **auto‑detect what the Mac can observe, manual confirm otherwise** (Đại chose "B").
- Voice: **ElevenLabs pre‑generated clips, macOS system voice as fallback** (Đại accepted).
- Visual style: **"gradient drop"** (black at the top merging into the notch, bleeding into the step's colour) (Đại chose "B").
- Illustrations: **AI‑generated 3D glossy icons in CleanMyMac style** (Đại chose "A"); SVG/SF Symbol placeholders until they exist.
- Display mode: configurable **Notch / Fullscreen** (Đại's request).

## 5. Experience

### 5.1 The steps (v1, in order)

| # | Step | Detection | Colour (gradient) |
|---|---|---|---|
| 1 | Plug in both Ugreen Type‑C cables (one → external monitor, one → Acasis dock) | Auto: learned external display appears (`NSScreen` / CGDisplay). The dock cable can't be seen yet because the dock is still switched off. | Teal `#0f5c55 → #0a2f3a` |
| 2 | Power on the Acasis 15‑in‑1 dock (already on mains power; switched off overnight) | Auto: learned dock USB devices (hub / Ethernet / card reader) appear | Graphite `#5b6577 → #232a38` |
| 3 | Power up FiiO K7 | Auto: CoreAudio output device matching learned K7 name appears | K7 red `#b3203a → #4a0a22` |
| 4 | Open Agent Factory | Auto: app with Agent Factory bundle id launches (or already running) | Violet `#5c3bd6 → #1d1450` |
| 5 | Pour water | Manual | Water blue `#2aa7d8 → #0b3c63` |
| 6 | Put on HD 660S2 | Manual | Black/bronze `#3b3530 → #0e0c0b` |
| 7 | Start Apple Music | Auto: Music player state becomes Playing (`com.apple.Music.playerInfo` distributed notification) | Music pink‑red `#ff3b5c → #7a0f3a` |
| 8 | Check Teams | Auto: Teams becomes frontmost app at least once | Indigo `#5059c9 → #1f2259` |
| 9 | Liftoff | Final screen | Dawn `#ffb35c → #d4466a → #3a1a5c` |

If a condition is already true when its step starts (e.g. K7 already on),
the step ticks immediately with a short "already confirmed" line.

### 5.2 Flow

1. **Trigger.** Đại closes the lid and takes the laptop home every evening,
   so each morning starts with lid open + unlock at the desk.
   Trigger = first screen‑unlock / wake / login on a weekday (Mon–Fri)
   between 08:00 and 10:30 local time, if the sequence has not run today.
   Outside that window the app stays silent; the menu bar item offers
   "Start pre‑flight now".
2. **Greeting.** Chime → background music fades in → "Good morning,
   Commander. Today is Wednesday, November eighteenth. Let's get you ready
   for launch."
3. **Each step.** Panel transitions to the step's gradient + illustration,
   chime, voice line. While waiting: pulsing "Waiting for FiiO K7…".
   On detection: tick SFX, confirmation line ("Connection confirmed."),
   advance after ~1 s. Manual steps: click "Done" or press Space.
4. **Music handoff.** At step 7, when Apple Music starts playing, the app's
   background music fades out over ~3 s and stays off. Voice lines after
   that play over their music (system ducking not required in v1).
5. **Liftoff.** Rising SFX, "All systems go. Have a great day, Commander.",
   dawn gradient, then the panel collapses into the notch / fullscreen fades out.
6. **Escape hatches.** Skip step (S or button), Skip all (Esc → "Skip
   pre‑flight today"), mute voice / mute music toggles. Never blocks input
   to other apps in Notch mode.
7. **Keyboard (designer's call).** No global hotkeys, no Accessibility
   permission. In Notch mode the panel accepts key focus only after Đại
   clicks it; Space / S / Esc work then. Buttons on the panel are always the
   primary way to act. Fullscreen mode takes key focus normally.
8. **Out‑of‑order and pre‑satisfied steps (designer's call).** Detection is
   state‑first: at each step start the app checks current state (USB/audio
   devices present, app running). Event‑only signals (Teams frontmost, Music
   started playing) are logged from the moment the sequence starts, so they
   count if they happened earlier in the sequence. Apple Music state is also
   queried once at step start via ScriptingBridge (one‑time Automation
   prompt); if denied, the step waits for the next play event or a manual
   "Done".
9. **"Ran today" and interruptions (designer's call).** A day counts as done
   once the sequence completes **or** Đại picks "Skip pre‑flight today".
   Quitting or sleeping mid‑sequence saves the current step; the next
   unlock the same day (within the window) resumes there. The next day
   always starts fresh.

### 5.3 Notch mode (default)

- Borderless, non‑activating panel pinned to top‑centre over the notch,
  above the menu bar, on all Spaces.
- **Expanded** (~600×200 pt): black top merging seamlessly with the notch
  hardware, gradient to the step colour at the bottom; illustration left,
  "Step 3/9", title, one‑line instruction, waiting indicator; 9‑segment
  progress rail at the bottom (done = white, current = 65 % white, rest 20 %).
- **Compact** (~330×34 pt): hugs the notch — current step icon + name on the
  left wing, progress ring on the right wing. Auto‑collapses during manual
  steps after the voice line ends, and whenever the pointer leaves for > 4 s
  on a waiting step; hover re‑expands.
- Expand/collapse with spring animation (matched‑geometry style, like
  Dynamic Island).
- Macs without a notch (external display only): same panel at top‑centre.

### 5.4 Fullscreen mode

- Borderless full‑screen window on the main display, full step gradient,
  large illustration centre, title + subtitle‑style caption, step rail at
  bottom (mockup "B · cinematic" in `look-v1.html`). Same content, sounds, and controls as
  notch mode. Esc exits to notch mode for the rest of the sequence.

### 5.5 Sound design

- **Voice:** female English, warm "starship assistant" tone, addresses Đại
  as "Commander". Each step has **3–4 variant lines** for the prompt and
  2–3 for the confirmation; pick randomly, never the same as yesterday.
- **Background music:** motivational / cinematic, builds through the
  sequence (calm intro → swell near the end), loops seamlessly. Ducks to
  ~35 % while the voice speaks.
- **SFX:** cabin‑chime before each announcement, tick on confirmation,
  liftoff whoosh/rumble at the end.
- Volume levels configurable; all audio honours mute toggles.

## 6. How it works (decided parts)

### 6.1 Stack
Swift 6 + SwiftUI (AppKit where needed for windows), SwiftPM package,
`make app` script that builds, assembles `Liftoff.app`, ad‑hoc signs it and
installs to `~/Applications`. Menu‑bar‑only app (`LSUIElement`), launch at
login via `SMAppService.mainApp`.

### 6.2 Detection sources (all event‑driven)
- USB: IOKit matching notifications (device add/remove).
- Audio: CoreAudio property listener on `kAudioHardwarePropertyDevices`.
- Displays: `NSApplication.didChangeScreenParametersNotification` / CGDisplay
  reconfiguration callback, matched against the learned monitor (step 1).
- Apps: `NSWorkspace` didLaunch / didActivateApplication notifications.
- Music: distributed notification `com.apple.Music.playerInfo` (Player State).
- Wake/unlock: `NSWorkspace.didWakeNotification`,
  `com.apple.screenIsUnlocked`, plus app launch at login.

### 6.3 "Learn my devices" (one‑time setup)
On first launch (and from Settings), a guided setup: "Unplug everything →
now plug in the cables → now the dock → now turn on the K7". The app
snapshots USB/audio devices before and after each action and stores the
new device identifiers (vendor/product id, name) as that step's signature.
Re‑runnable anytime.

### 6.4 Config
- `~/Library/Application Support/Liftoff/config.json`: steps (id, title,
  detection rule, colour, illustration name, voice line ids), trigger
  window, weekdays, display mode, volumes. Settings window exposes display
  mode, trigger window, volumes, voice on/off, "Learn my devices",
  "Regenerate voice", "Run now".
- Assets folder in Application Support so illustrations, music and voice
  clips can be swapped without rebuilding.

### 6.5 Voice pipeline
- `Scripts/voices.json` lists every line (id + text).
- A command (`liftoff voices generate`) calls ElevenLabs TTS for each line
  with the chosen voice id and writes `.mp3` clips to the assets folder.
  API key read from Keychain (set via Settings) or `ELEVENLABS_API_KEY`.
- The date greeting is generated at trigger time if key + network are
  available (cached per day); otherwise a date‑less greeting clip plays.
- Any missing clip → `AVSpeechSynthesizer` with the best installed English
  female voice (prefer premium/enhanced: Zoe, Ava, Samantha).

### 6.6 Illustrations
- Deliverable: `docs/illustration-prompts.md` — one shared style preamble
  ("3D glossy icon, CleanMyMac style, soft studio lighting, subtle
  iridescent rim light, transparent background, 1024×1024") + one prompt per
  device, describing the real product (Ugreen braided Type‑C cable, Acasis
  15‑in‑1 dock, red FiiO K7 with silver knob, Sennheiser HD 660S2, glass of
  water, Apple Music, Teams, Agent Factory, rocket).
- Đại generates the images themself (ChatGPT / Gemini / Midjourney), or later
  provides an image API key for the builder to run them.
- Until then: placeholder art (layered SVG/SF Symbols on the gradient).

## 7. Left to the builder

- Module structure, state machine shape, test strategy (detection and
  trigger logic must be unit‑testable with fake event sources).
- Exact animation curves, spacing, typography sizes (SF Pro; follow the
  mockups in `.superpowers/brainstorm/*/content/notch-v2.html`).
- Picking 1–2 royalty‑free motivational tracks (e.g. Pixabay Music) and SFX;
  user can drop their own `.mp3` into the assets folder.
- Writing the voice line variants (tone per §5.5).
- Choosing the ElevenLabs voice (a warm female English voice; list 2–3 for Đại to pick by ear).
