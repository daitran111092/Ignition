# Liftoff illustration prompts

Liftoff shows one illustration per step on the left of the notch panel (and large in
fullscreen mode). Until an image exists the app draws the step's SF Symbol on a glass orb,
so you can add these one at a time, in any order.

## Where the files go

| Step | File name |
|---|---|
| 1 · Plug in the cables | `cables.png` |
| 2 · Power on the dock | `dock.png` |
| 3 · Power up the K7 | `dac.png` |
| 4 · Open Agent Factory | `agentFactory.png` |
| 5 · Pour some water | `water.png` |
| 6 · Headphones on | `headphones.png` |
| 7 · Start the music | `music.png` |
| 8 · Open Teams | `teams.png` |
| 9 · Liftoff | `liftoff.png` |

- Folder: `~/Library/Application Support/Liftoff/illustrations/`
  (Finder → Go → Go to Folder…, paste the path; create `illustrations` if it isn't there).
- Names are case-sensitive and must match exactly (note `agentFactory.png` with a capital F).
- **1024 × 1024 px PNG with a transparent background.** No backdrop, no frame, no shadow plate:
  the panel's colour gradient sits behind the object.
- The app picks up a new or replaced file the next time that step is shown; no restart needed.

## Shared style preamble

Paste this in front of every prompt (or once at the top of the conversation, see tips below):

> 3D glossy icon in the style of CleanMyMac and modern macOS app icons. A single object,
> centred, filling about 80 % of the frame, seen from a slightly elevated three-quarter
> angle. Smooth, rounded, slightly stylised forms (premium product render, not
> photorealistic, not cartoonish). Soft studio lighting from the top left, gentle
> reflections, a subtle iridescent rim light along the edges, a soft contact glow beneath
> the object. Rich but clean materials: anodised aluminium, glossy plastic, glass. No text,
> no logos, no labels, no people, no hands. Transparent background, PNG, 1024×1024.

## The nine prompts

The colour notes match the panel gradient for that step so the object reads well on it.

### 1 · `cables.png` — Ugreen Type-C cables

> Two braided USB Type-C cables from Ugreen, dark grey nylon braid with aluminium
> connector housings in space grey, the two cables loosely curled side by side in an
> elegant S-shape with both connector ends facing the viewer, a tiny teal light glinting on
> the metal. Accent colours: deep teal (#0f5c55) reflections on the aluminium.

### 2 · `dock.png` — Acasis 15-in-1 dock station

> An Acasis 15-in-1 USB-C dock station: a long, low, rectangular aluminium docking hub in
> graphite grey with rounded edges, a neat row of ports along the front (USB-A, USB-C,
> HDMI, Ethernet, SD card slot), a small glowing white power LED, standing on a desk-like
> invisible plane. Accent colours: cool graphite and steel blue (#5b6577).

### 3 · `dac.png` — FiiO K7 (red)

> A FiiO K7 desktop headphone DAC/amplifier in its red finish: a compact box with a
> glossy crimson-red body, a large brushed silver volume knob on the front right with a
> fine indicator line, two small headphone jacks on the front left, a small status light,
> subtle chamfered edges catching the light. Accent colours: K7 red (#b3203a) with deep
> wine shadows (#4a0a22).

### 4 · `agentFactory.png` — Agent Factory

> An abstract, friendly miniature factory for AI agents: a sleek violet robotic arm
> assembling a small glowing cube on a rounded platform, with a stylised factory roofline
> (sawtooth) behind it and a few floating luminous particles. Clean, futuristic, playful.
> Accent colours: electric violet (#5c3bd6) with deep indigo (#1d1450) shadows.

### 5 · `water.png` — glass of water

> A clear, tall drinking glass filled with fresh water, a few tiny bubbles and a single
> droplet on the outside of the glass, light refracting through the water with soft caustic
> highlights, a small splash frozen at the rim. Accent colours: bright water blue (#2aa7d8)
> shading to deep ocean blue (#0b3c63).

### 6 · `headphones.png` — Sennheiser HD 660S2

> Sennheiser HD 660S2 open-back over-ear headphones: matte black headband and yokes,
> large oval earcups with metallic open-back grilles in dark charcoal with a hint of
> bronze, plush black velour ear pads, shown three-quarter view with one earcup slightly
> turned. Accent colours: warm black and bronze (#3b3530).

### 7 · `music.png` — Apple Music

> A glossy 3D musical note glyph (a pair of beamed eighth notes) in the spirit of the
> Apple Music icon, rendered as smooth candy-like glass with a vivid pink-to-red gradient,
> floating above a soft round glow, a few small sound-wave rings radiating behind it. No
> Apple logo, no app-icon square. Accent colours: music pink-red (#ff3b5c) to deep magenta
> (#7a0f3a).

### 8 · `teams.png` — Teams chat

> Two overlapping rounded chat bubbles in the style of Microsoft Teams, one in front with
> three typing dots, one behind, plus two small abstract person silhouettes (a circle head
> and rounded shoulders) peeking from behind, glossy soft-plastic material. No Microsoft
> or Teams logo, no letters. Accent colours: Teams indigo (#5059c9) with deep navy
> (#1f2259).

### 9 · `liftoff.png` — rocket lifting off

> A small, sleek, rounded rocket lifting off at a slight diagonal, glossy white body with
> warm orange and pink accents, a round porthole window, a soft glowing exhaust flame and
> a puff of cloud at the base, a couple of tiny stars. Optimistic, sunrise mood. Accent
> colours: dawn gold (#ffb35c), rose (#d4466a) and twilight purple (#3a1a5c).

## Keeping the set consistent

- **Generate all nine in one conversation.** Paste the preamble first with "Use this style
  for every image I ask for next", then send the prompts one by one. Models drift less
  inside a single thread.
- **Anchor on the first good result.** When one image looks right (the K7 is a good
  anchor), attach it to every later request: "Match the lighting, angle, material and
  level of detail of this reference image."
- **Midjourney:** reuse the same `--seed`, add `--sref <url of your anchor image>` and keep
  `--ar 1:1 --style raw` identical across all nine; then remove the background (Midjourney
  doesn't output transparency).
- **ChatGPT / Gemini:** ask explicitly for a "transparent background PNG". If you get a
  white or checkerboard background, remove it (macOS Preview → Instant Alpha, or
  `Remove Background` in Keynote/Pixelmator/Photomator).
- **Same framing:** the object should fill roughly the same share of the canvas in every
  image, with a little empty margin. Re-generate outliers rather than cropping hard.
- **Check on the real gradient:** drop the PNG into the folder and run
  `swift run Liftoff --preview-notch <step index 0–8>` to see it in the panel.
- **Prefer real-product accuracy for devices you own** (cables, dock, K7, HD 660S2):
  if the first try invents details, attach a product photo and say "same product,
  rendered as a glossy 3D icon".
