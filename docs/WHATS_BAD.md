# What is bad in v0.20, and the fix plan

Written 2026-11-16 after Hamad tested v0.20 b22 and said: little changed, it
feels like a 2D game, the garage entrance does not work, the car intro shows
the front and should show the back, buildings/streets/design must be much
better, use real textures, improve music and car sounds, and show every change
before it goes into an APK.

Status key: FIXED (in the branch, shown to Hamad), DOING, TODO.

## Rule for all work from here

**Show before ship.** No APK is built or delivered until Hamad has seen
screenshots or video of the change and reacted.

## A. Why it felt like a 2D game (root causes found in the code)

| # | Problem in v0.20 | Status |
|---|---|---|
| A1 | Every city block was ONE flat 54 m box with a photo stuck on it, plus box towers. No doors, no window depth, no shopfront glass. | FIXED: real street buildings (see C) |
| A2 | The whole road network was one flat plane with a painted shader: no real asphalt texture, no normal map, purple/pink smear instead of reflections. | FIXED: photo-scanned asphalt, puddles, real mirror reflection |
| A3 | Purple ambient light and a painted purple sky made everything look like a cartoon. | FIXED: real night-sky HDRI, neutral night lighting |
| A4 | Palms were flat photo cards that glowed white at night. | FIXED: real 3D palms |
| A5 | Parked cars and traffic are low-poly boxes. | TODO |
| A6 | Street lamps: a few thick black posts, light pools were flat orange decals. | DOING: lamp light is now computed on the road; lamp model still old |
| A7 | Far buildings are plain blue boxes. | DOING: now skinned with a lit office facade; needs better silhouettes |
| A8 | The garage interior is a flat panorama photo behind the car, not a room. | FIXED: real 3D workshop room (see D) |
| A9 | The game runs on Godot's Mobile renderer, which has no screen-space reflections or SSAO. Earlier "SSR" work did nothing on the phone. | FIXED: reflections now come from a mirror camera that works on mobile |

## B. Bugs Hamad named

| # | Bug | Cause | Status |
|---|---|---|---|
| B1 | Garage entrance does not work | Entering needed the keyboard Enter key. The "ENTER LSXMOTORSPORT" text was only a label, so on a phone there was no way in. | FIXED: drive onto the pad at low speed and it takes you in. Verified in a headless run; must be re-verified in the exported APK. |
| B2 | Car intro shows the front end | Intro shot 1 filmed headlights coming at the camera, the hero shot orbited the nose, the race-start camera started in front, and the generated intro film is nose-on. | FIXED: all three in-engine cameras now sit behind the car (tail lights). The old nose-on film is switched off until a rear-view film is made (Genjutsu). |
| B3 | His LSX logo and workshop/dyno photos were not followed | Exterior sign is cyan neon text, not his logo; interior is a generic panorama. | DOING: logo on the building, real workshop room (see D) |

## C. City, streets and buildings (what the new version does)

Assets are real and free to use (CC0): Poly Haven and ambientCG.

- Road: photo-scanned asphalt with normal map, worn paint, puddles with rain
  rings, wet film. Sodium lamp light pools are computed per pixel for every
  lamp on the grid (no 8-light limit).
- Reflections: a second camera mirrored through the road renders the city,
  and the wet surface shows it. Towers, neon, shop windows and cars reflect.
  Off on the PERFORMANCE preset.
- Sidewalks: paving texture, granite kerbs, lanterns, bins, hydrants,
  utility boxes (photo-scanned props).
- Buildings, three real types on every block edge:
  1. Apartment houses from a photo-scanned modular facade kit (real doors,
     window frames, cornices).
  2. Mid-rises: glass shopfronts with stone piers, recessed glass, sign band,
     neon tube, awnings and blade signs; photo facade above with piers and
     cornice.
  3. Towers: stepped shafts with real facade skins and lit-window maps.
- Windows: every window is a small lit room (interior mapping), some lit,
  some dark, some with curtains. Shop windows show a real shop interior.
- Industrial blocks: corrugated-iron warehouses with roller shutters.

Still to do in the city:

| # | Item | Status |
|---|---|---|
| C1 | Real 3D parked cars and traffic cars | TODO |
| C2 | New road lamp model, traffic lights with real housings | TODO |
| C3 | Highway, bridge, tunnel, promenade: still the old look | TODO |
| C4 | Special blocks (gas station, parking, park, yard, plaza) still old | TODO |
| C5 | Distant skyline shapes, billboards, landmark | TODO |
| C6 | Marker text reflects in the road (should not) | TODO |
| C7 | Phone performance of the new city is NOT measured yet (cannot test on a phone from the cloud). Needs Hamad's FPS reading; presets will be tuned. | TODO |
| C8 | Blocks are built on the main thread (15-100 ms each on a PC); needs to move to a worker thread to avoid hitches on a phone. | TODO |

## D. LSXmotorsport garage and dyno (Hamad's photos)

Reference: `/mnt/project-files/after-hours-demo/lsx-reference/` (logo,
workshop, dyno bay).

First 3D version built 2026-11-16 (`scripts/world/lsx_workshop.gd`,
`scripts/scenes/garage_dyno.gd`, `scripts/ui/dyno_screen.gd`), shown to Hamad,
waiting for his reaction.

| Photo shows | Game now | Status |
|---|---|---|
| Chrome "LS" + red brushed "X" + MOTORSPORT logo | Real logo on the building sign, wall banners and dyno TV | DONE (loading screen still TODO) |
| Cream corrugated metal walls with a black lower band, black columns | Same, real corrugated-steel texture | DONE |
| White drop ceiling with square LED panels | Same | DONE |
| Grey concrete floor, yellow bay lines | Same | DONE |
| Red scissor lift, red tool chests, oil shelf, hoods on the wall, banners, cooler | All in 3D (simple shapes plus scanned props). Wheels on the wall, cables and clutter still missing | DOING |
| Other customer cars in the bays (Corvettes) | none | TODO |
| Dyno: car strapped on rollers in the floor, fan, dyno banner | Car on rollers with straps, orange fan, banner, wall TV | DONE (first version) |
| Brand banners (Weld, Mickey Thompson, Summit, Mustang Dyno) | Made-up brands plus LSX banners (real brand logos are not ours to use) | DONE |

Dyno behaviour Hamad asked for: the car sits on the rollers, the run starts,
the wheels spin and the engine sound rises, and only then the graph appears.
The graph is on a **TV on the wall**; tapping the TV moves the camera close to
it. Enter and exit animations for the garage.

All of that works in the editor build: fade to the bay, engine start, 6.5 s
pull with rising engine note, driven wheels and rollers spinning, live graph
on the TV, tap the TV to zoom, RUN AGAIN / DONE. The car rolls in through a
shutter door on arrival and drives out through it on leaving.

## E. Cars

| # | Problem | Status |
|---|---|---|
| E1 | Generated 3D bodies are soft in places (panel lines, lights) and wheels are procedural | TODO: better wheels/tyres, glass, light meshes |
| E2 | No interior visible through the glass | TODO |
| E3 | Head and tail lights do not light the road strongly | TODO |

## F. Sound and music

| # | Problem | Status |
|---|---|---|
| F1 | Engine sounds are synthesised tones, not real recordings | TODO: real engine loops per engine type (idle, low, mid, high, off-throttle), turbo, backfire |
| F2 | Tyre, wind, collision sounds are thin | TODO |
| F3 | Music: 8 generated tracks; needs a stronger, larger street soundtrack and better radio mixing | TODO |
| F4 | Voice lines were never listened to, only measured | TODO: audition and redo weak ones |

## G. Game feel and UI (from the walkthrough)

| # | Problem | Status |
|---|---|---|
| G1 | FPS counter is forced on | TODO: off by default |
| G2 | HUD is large and covers the road on a phone | TODO: tighten |
| G3 | Menu background city is the old flat style | TODO: use the new city |
| G4 | Intro film is switched off (was nose-on) | TODO: new rear-view film |

## H. Order of work

1. City and streets (C) - first preview shown 2026-11-16.
2. LSX garage + dyno scene (D).
3. Cars in the world: parked, traffic, lights (A5, E).
4. Sound and music (F).
5. Menus, intro film, HUD (G).
6. APK only after Hamad has seen each part.
