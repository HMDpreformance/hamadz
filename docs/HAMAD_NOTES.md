# Hamad's notes

Everything Hamad asked for, in one place. This file is kept up to date. When Hamad says something new, it is added here on the same day.

Last update: 2026-11-17

## The goal

- A street racing game in **Dubai at night**: illegal car races and the street racing life.
- The feeling of Midnight Club 3 and Need for Speed: wet shiny night streets, neon, glass towers, real looking cars.
- The game must be "100x better": realistic cars, graphics and physics. It must not feel 2D.
- The Unity game is built next to the Godot game. The Godot game stays and must not be deleted or broken.

## How we work

- Show pictures or a video of each change **before** any phone build. No APK without Hamad's OK.
- Never make the quality lower to fit a size limit.
- Use Higgsfield (Ultra plan, credits approved) for anything that makes the game much better: rims, car models, buildings, shop fronts, signs, textures, map art. Use ElevenLabs for sound and voice. Genjutsu is preferred for car videos.
- Keep messages short and simple.
- Do not touch hmdperformance.com. Do not touch the "Orginal Disk MNC 3" folder on the laptop.
- Take the time needed to understand this type of game well. Research how other racing games do things before building.

## Cars

- Main car: Corvette C6 shape (game name VORTEX Z6). Second car: single cab GMC 1500 pickup (DUNE 1500). About 90% like the real cars, no logos.
- Cars must look like real cars, not RC toys. Length and width must be right.
- 2026-11-17: the sports car should be a bit wider, and the front and back ends longer. (Done in the model, to be checked in game.)
- Tyres and rims must look real. (Now made with Higgsfield as real 3D rims.)
- Tail light and head light glow must sit exactly on the lamps.
- The car intro camera shows the car from the back.
- Cars in traffic should be real cars you see in Dubai.

## Driving

- Roads must be easy and stable to drive. Not too wavy. The game must not be hard because the car is unstable.
- Smooth on Android. FPS counter at the top middle.
- Rain is rare.

## HUD

- Blue flame dial style that fits the game.
- Speed dial with the RPM dial on the right side.
- Dial sides about 80% see-through.
- Dials a bit smaller and a little lower. (Done: about 15% smaller, lower.)
- Small map bottom left with a wrench for the garage, and a full map.
- GARAGE button.

## Garage

- The garage is named **LSXmotorsport**.
- It has a dyno.
- The garage door opens only when the car is close.

## The city and the map

- The city and the map are shaped like Dubai. Not blocks.
- Based on the real Dubai: research what is really in each area, then build the buildings, trees, shops, traffic, streets and cars from real things in Dubai.
- Map style: dark game map like Midnight Club and Need for Speed, yellow highways, district names. Our own layout, not a copy of another game's map.
- Roads rise and fall with the land: bridges, flyovers, underpass, hills. Not all on one level.
- Medium size: not too big, not too small.
- Build in two halves. First 50% (west side) with the other roads blocked. Then the other 50%.
- Areas in part 1: Jebel Ali, Dubai Marina, JBR, Palm Jumeirah, Al Barsha, Al Quoz, Jumeirah, Al Wasl, Downtown Dubai, Dubai Hills.
- Areas in part 2: Business Bay, the Creek, Deira, Ras Al Khor, Nad Al Sheba, the airport.

## Open questions for Hamad

- Map art picture 1 or picture 2 from Higgsfield (for the look of the full map screen).

## Real car numbers (checked 2026-11-17)

Hamad: look up the real car before building it, so the shape and size are right. Every car body is checked against these numbers.

| Car | Length | Width (no mirrors) | Height | Wheelbase | Tyre diameter |
|---|---|---|---|---|---|
| Corvette C6 coupe | 4.435 m | 1.844 m | 1.245 m | 2.685 m | 0.65 m front, 0.68 m rear |
| GMC Sierra 1500 regular cab, 6.5 ft box (2007 to 2013) | 5.222 m | about 2.03 m | 1.87 m | 3.023 m | 0.80 m |

Tool: `tools/fix_proportions.py <src> <out> <length> <width> <height> real <rear overhang> <wheelbase> <front overhang>` moves the axles to the real places.
