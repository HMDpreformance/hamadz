# HMDnight Club

(Formerly "After Hours: Street Syndicate". The package id is unchanged so new builds install over old ones.)

A vertical-slice street racing demo for Android in the spirit of early-2000s
PS2 tuner games: cinematic intro, animated main menu, a fully interactive
tuning garage and a night-city test drive.

Built with **Godot 4.4.1** (Mobile/Vulkan renderer). Every asset is original:
car bodies, wheels, the garage and the city are generated procedurally in
GDScript, and all music and sound effects are synthesized by
`tools/gen_audio.py`. No third-party game assets, names or likenesses are used.

## What is in the demo

| Area | What works |
| --- | --- |
| Startup | Animated studio ident, in-engine night cinematic with motion blur, title slam, "Tap to start" (tap any time to skip) |
| Main menu | Career / Arcade (polished "Coming soon" panels), Garage, Options, Credits, Exit. Your current car sits under neon while cameras cycle |
| Garage | Orbit camera (drag, pinch, auto camera moves per category), 3 cars, 15 upgrade slots, live stat preview, prices, cash, buy/install, floor reflection |
| Cars | Kaido RS-7 (tuner coupe), Brawler 427 (muscle), Verano GT (European), each with its own body, lights and engine sound |
| Customization | 12 paints x 5 finishes, front/rear bumpers, spoilers, side skirts, hoods, underglow, 6 rim designs, 7 rim colours, 4 wheel sizes, engine, turbo, exhaust, suspension. Every option changes the 3D car |
| Test drive | Night city with traffic, traffic lights, neon, wet roads. Arcade handling, handbrake drifts, nitro, chase and hood cameras, speedometer and tach, tyre smoke, a 12-checkpoint timed run that pays cash |
| Options | 3 graphics presets, music and SFX volume, button or tilt steering, FPS counter, save reset |
| Saving | Cars, parts, cash, best time and settings are saved automatically to `user://save.json` |

## 0.9.0: photo-real look

- **Car Lot** (main menu > CAR LOT, or GARAGE > VEHICLES): buy and pick cars in a photographic workshop. Car carousel with class letters (D/C/B/A/S from the performance rating), price, acceleration / top speed / handling bars, change colour (new cars: pick the factory colour for free; owned cars: cycle the colours you own), cash, chrome frame.
- **Garage** is now a photographic 360 workshop (generated panorama) with a reflective concrete floor instead of the modelled room.
- **Cars**: deeper clearcoat paint, curved body sides and crowned panels, reflections from the workshop panorama.
- **Race HUD**: big race timer and position, round chrome minimap, tall side arcs (left = race progress, right = speed), yellow speedometer with tach and gear badge, yellow checkpoint chevron.
- **Streets**: photo asphalt texture, wetter roads, sparks when you scrape walls or cars, stronger speed blur.
- Generated images (original, no brands): `textures/` (see `docs/TEXTURES.md`).

## Install the APK

1. Copy `AfterHours-StreetSyndicate.apk` to the phone (or download it there).
2. Open it from the Files app and allow "Install unknown apps" when Android asks.
3. Launch **After Hours**. Needs Android 7.0+ and a Vulkan-capable phone
   (arm64 or 32-bit ARM).

The APK is a debug build signed with a debug key. It is fine for testing; a
Play Store upload needs a release build signed with your own keystore.

## Controls

| Action | Touch | Keyboard |
| --- | --- | --- |
| Steer | `<` `>` buttons, or tilt (Options) | A / D or arrows |
| Gas / Brake + reverse | GAS / BRAKE | W / S |
| Handbrake (drift) | DRIFT | Space |
| Nitro | N2O | Shift |
| Camera | CAM | C |
| Pause | II or Android Back | Esc / P |

Garage: drag to rotate, pinch (or mouse wheel) to zoom.

## Build it yourself

1. Install [Godot 4.4.1](https://godotengine.org/download/archive/4.4.1-stable/)
   (standard build, not .NET) and, from inside the editor,
   *Editor > Manage Export Templates > Download and Install*.
2. Install Android Studio or the command-line SDK (platform-tools and
   build-tools 34+) and a JDK 17. In Godot open *Editor > Editor Settings >
   Export > Android* and set the **Android SDK Path** and **Java SDK Path**.
3. Open `project.godot`. Press F5 to play on desktop.
4. *Project > Export > Android > Export Project* (preset is included), or from
   a terminal: `GODOT=/path/to/godot tools/build_apk.sh debug`.
5. For a store build, create a keystore, fill in *Keystore > Release* in the
   export preset and export with "Export With Debug" off.

Regenerating assets (optional): `python3 tools/gen_audio.py` (needs numpy,
scipy, ffmpeg) and `python3 tools/gen_icon.py` (needs Pillow).

## Project layout

```
scenes/            four tiny scenes; each one's script builds its world in code
scripts/core/      autoloads
  game.gd          player profile + save/load            (Game)
  car_db.gd        cars, parts, prices, stat maths       (CarDB)
  gfx.gd           graphics presets + environment        (GFX)
  audio.gd         music, ambience, SFX pool             (Audio)
  nav.gd           scene manager + loading screen        (Nav)
  controls.gd      input actions, touch/tilt/keyboard    (Controls)
  dev.gd           screenshot/smoke-test helper, off unless AH_DEV is set
scripts/vehicle/
  car_specs.gd     body shape data for each car
  car_visual.gd    lofted body, parts, materials, config application
  wheel_factory.gd rims, tyres, brakes
  player_car.gd    arcade vehicle controller
  engine_audio.gd  RPM-driven engine, turbo, tyre and wind sound
  car_fx.gd        smoke, nitro flames, headlights
  traffic_car.gd   ambient traffic
scripts/world/     garage_room.gd, city.gd, orbit_camera.gd, chase_camera.gd, env_kit.gd
scripts/ui/        ui.gd (toolkit), neon_button.gd, touch_key.gd, options_panel.gd, post_fx.gd
scripts/scenes/    intro.gd, menu.gd, garage.gd, drive.gd
tools/             asset generators, build and check scripts
```

## Continuing development

- **Add a car:** add an entry to `CarDB.CARS` and `CAR_ORDER`, a shape to
  `CarSpecs.SPECS` (copy an existing one and edit the profile curves), and
  engine loops named `eng_<id>_on/off.wav`.
- **Add a part option:** append it to the slot in `CarDB.parts()` and handle
  the new index in the matching `_part_*` function in `car_visual.gd`.
- **Add an upgrade slot:** add it to `SLOT_ORDER`, `GROUPS` and `parts()`.
  Saves pick up new slots automatically.
- **Career / Arcade:** `Nav.goto("drive", {...})` already passes arguments to a
  scene; `drive.gd` keeps its route in `_route()` and state in `_set_state()`,
  so new event types slot in there. `TrafficCar` is the starting point for AI
  rivals.
- **Imported art:** `CarVisual` is the only place that builds car meshes. To
  move to authored models, load a `.glb` there and keep the same public API
  (`setup`, `apply`, `spin_wheels`, `set_steer`, ...).
- `tools/check.sh` parses every script; `AH_DEV="scene=garage;wait=2;shot=shots/x.png"`
  drives the game for automated screenshots (see `scripts/core/dev.gd`).

## Known limits of this demo

- Tested on desktop with the same Mobile renderer the phone uses; it has not
  been profiled on physical Android hardware yet, so use the graphics presets
  if a device struggles.
- The Mobile renderer has no screen-space ambient occlusion; contact shadows
  under the cars are baked-style blobs instead.
- Flat city (no hills), no car damage, traffic ignores red lights.

## Licences

- Code, procedural assets and audio in this repository: yours to use; see `LICENSE`.
- Fonts: Russo One and Rajdhani, SIL Open Font License 1.1 (`fonts/*OFL.txt`).
- Godot Engine: MIT licence.
