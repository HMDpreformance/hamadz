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
- 2026-11-17, Hamad: the LSX garage must be in **Ras Al Khor** (not Al Quoz). Done in the plan: garage beside the Ras Al Khor road, near the lagoon. The built part of the city now reaches east to include Ras Al Khor and Business Bay.
- It has a dyno.
- The garage door opens only when the car is close.

## The city and the map

- The city and the map are shaped like Dubai. Not blocks.
- Based on the real Dubai: research what is really in each area, then build the buildings, trees, shops, traffic, streets and cars from real things in Dubai.
- Map style: dark game map like Midnight Club and Need for Speed, yellow highways, district names. Our own layout, not a copy of another game's map.
- Roads rise and fall with the land: bridges, flyovers, underpass, hills. Not all on one level.
- Medium size: not too big, not too small.
- Build in two halves. First 50% (west side) with the other roads blocked. Then the other 50%.
- Areas in part 1: Jebel Ali, Dubai Marina, JBR, Palm Jumeirah, Al Barsha, Al Quoz, Jumeirah, Al Wasl, Downtown Dubai, Dubai Hills, and since the garage move also Ras Al Khor, Business Bay and Nad Al Sheba.
- Areas in part 2: the Creek east side, Deira, the airport.

## Open questions for Hamad

- Map art picture 1 or picture 2 from Higgsfield (for the look of the full map screen).

## Real car numbers (checked 2026-11-17)

Hamad: look up the real car before building it, so the shape and size are right. Every car body is checked against these numbers.

| Car | Length | Width (no mirrors) | Height | Wheelbase | Tyre diameter |
|---|---|---|---|---|---|
| Corvette C6 coupe | 4.435 m | 1.844 m | 1.245 m | 2.685 m | 0.65 m front, 0.68 m rear |
| GMC Sierra 1500 regular cab, 6.5 ft box (2007 to 2013) | 5.222 m | about 2.03 m | 1.87 m | 3.023 m | 0.80 m |

Tool: `tools/fix_proportions.py <src> <out> <length> <width> <height> real <rear overhang> <wheelbase> <front overhang>` moves the axles to the real places.

## Ideas to add to the city plan (from the road research, not yet built)

- About 12 landmarks to steer by. Six are placed in part 1: the needle tower, the sail hotel, the arch hotel on the Palm, the big wheel, the twisted tower, the ski mall.
- A good first drive out of the LSXmotorsport garage.
- Shortcuts and a few jump and drift spots.
- A tunnel under the creek and a mountain road with switchbacks (part 2).
- Road rules: wide lanes, smooth arcs, slopes up to about 6%, flat junctions, no steps, smooth barriers.

## Map must look like the generated map picture (2026-11-17)

Hamad asked why the game map did not look like the Higgsfield map picture. Rule: the game map and the real city follow that picture's layout and style as closely as the real roads allow.
- Done: streets everywhere, blue glowing sea, only highways yellow, Downtown above the E11 near the sea, bigger Palm. The game uses `unity_assets/city/map_full.jpg` and `map_base.jpg`, drawn from the same plan as the roads.
- 2026-11-17, Hamad: "still the map looks not perfect, try to fix it more". Done in v3: Palm with five fanned fronds each side and water between them, water basin with piers inside the Marina, sand beach line, highway slip roads drawn, slanted labels, needle tower icon, red skyline title.
- 2026-11-17, Hamad: the Palm was made wrong. Fixed to follow the real Palm Jumeirah: long trunk, 16 fronds (8 each side) that curve like palm leaves and fill a round shape, crescent around them, arch hotel at the top. The ski mall was moved off the E11 into its own block in Al Barsha, and no streets run under the landmarks.
- 2026-11-17, Hamad: the inside of the Palm was still not the same design. Redrawn from the Higgsfield picture: fronds fan out from the upper trunk like a palm tree (low ones droop, top ones sweep up), 7 each side.
- Wheel sizes checked against the real cars: sports car front tyre made smaller (0.65 m), pickup rear tyre same size as the front.
- Still to do: round highway junctions (cloverleaf look), Jebel Ali port piers, a mountain area in the south, more organic streets.

## Follow every detail of the generated map (2026-11-17)

Hamad: "focus on the generated map details, I feel you missed a lot of things, one example is the Palm" and "the map in the game looks very cheap". Rule: the city plan is traced from the Higgsfield map picture, and the map picture shown in the game must have that rich look, not a plain drawing.

Differences found and their state:
1. Marina is a round harbour on the coast with piers. Done in plan v4.
2. JBR between the Marina and the Palm road. Done.
3. Road from the Palm trunk inland. Done as a main road (it ends in Al Wasl, not on the E11 yet).
4. Downtown is a big double ring with the tower and the Business Bay canal inside. Done.
5. Creek from the sea east of Downtown down to the lagoon, Deira beside it. Done.
6. Ras Al Khor south of the E11 with the lagoon. Done (lagoon is a plain oval, the picture has a C shape). LSX garage is here.
7. Jebel Ali port with piers on the west. Done.
8. Round cloverleaf junctions. Not done (slip roads only).
9. Mountains in the south and east, Dubai Hills oval with hills. Drawn faintly, hills in the terrain.
10. Airport runways, much denser streets. Runways drawn; streets denser but still less than the picture.
11. The extra north-south highway (Hills Link) is removed.
Next: rich map picture made with Higgsfield from the plan render; cloverleafs; more small streets.

Rich map pictures (2026-11-17): `unity_assets/city/map_full.jpg` (with names) and `map_base.jpg` (no text, for the small map) are now made with Higgsfield from the plan render, 2224x1600, roads in the same places as the plan. Do NOT overwrite them with `tools/city_plan.py`; write the plain render to `map_full_plain.jpg` instead. When the road plan changes, render the plain map again, restyle it with Higgsfield (GPT Image 2.6, reference = plain render, "keep every road exactly"), then make the no-text copy from the result. The cloud cannot reach the Higgsfield upload host, so the laptop does the upload PUT.

Minimap (2026-11-17): Hamad said the small map looks cheap. He wants it in the same style as the dials, or with the sides removed and a see-through fade from the edge to the middle. Done in code: no frame, no chrome ring, the map is a soft disc (solid in the middle, clear at the rim).

City size (2026-11-17): Hamad likes the map picture, but when driving the streets feel very small compared to the map. He wants bigger distances. Done: plan scale 0.75 -> 1.5, so the city is 4.8 km x 3.45 km (two times longer in every direction, about 141 km of road). Road widths stay the same. Ramp lengths stay the same in metres (factor K in tools/city_plan.py). He also says the roads have many problems; every road must pass a drive test and each problem is listed and fixed.

Playtest 2026-11-17 (afternoon), Hamad's words in short:
- The Corvette looks very tiny. Body should be wider and a little longer. Done in code: all cars 12 % bigger (roads are wide, so real-size cars looked small), Corvette 4 % more, chase camera a little closer.
- Minimap is good now. Zoom it out a bit, and zoom out more when speeding, with a limit. Done in code: 640 m across when slow, up to 980 m at 220 km/h.
- Rain must not be always on: sometimes yes, sometimes no. Rain looks cheap. Done in code: showers come and go during a drive (fade in 18 s, road dries slowly). Rain look still to improve.
- Lighting looks cheap. To improve.
- Buildings look cheap and do not match the map. To improve: real 3D building models per district (Marina, Downtown, villas, old Deira, warehouses), made with Higgsfield.
- Chase camera a little higher, not too much. Done in code: about 0.28 m higher.

Hamad's confirmed problems and fix order (2026-11-17, 14:27 Dubai time). He paused all edits at 13:59 ("stop edit things till i tell u what to do") and said "Continue" at 14:50 with this list. Work in this order and hold visual changes until it is done:
1. Locked controls could make the car reverse (inputLocked full brake selected reverse; reverse powered all four wheels and cancelled the handbrake). FIXED in CarController.cs.
2. Junctions kept collision walls 15 cm above the road. FIXED in tools/build_city.py (side wall stops under the surface inside junctions).
3. Road connections used old point indexes after new start points were added. FIXED (the point is looked up again).
4. Tyre sizes lost the front/rear difference (all four got the average). FIXED (controller keeps the factory radius).
5. Downtown underpass was thrown away (negative heights clamped to zero). FIXED: Downtown Blvd dips 5.6 m under the E11, the E11 is a slab there, clearance 4.3 m.
To test in Unity (not done yet): slopes and crests, car stability (braking downhill, quick steering, kerbs, bridge crests), crash recovery (overturned, water, flyovers).
Also fixed from the drive test: streets that ran along a bigger road and left kerbs across it are cut (Downtown Inner Ring, Al Khail); ground cells can no longer rise through a road edge; the generator now prints a "ground through a road" self check (0 spots).
Rule from Hamad: when he says stop, stop editing until he says what to do.

Test results on the laptop, 2026-11-17 (build of 3ceeb48):
- Locked controls: pass (0.01 m in 3 s at standstill; from 100 km/h stops in 24 m and stays, gear 1).
- Reverse: pass (sport RWD 48 km/h, pickup AWD 27 km/h; handbrake stops it, no creep).
- Wheels: car sits level, suspension has travel left.
- Underpass: 4.38 m clearance, clean southbound at 90 and on the E11 above at 154. Northbound FAILED: a street crossed Downtown Blvd inside the dip and made a 3 m step. Fixed in the generator (streets are cut where a main road dips or climbs a bridge); needs a rebuild to confirm.
- Slopes and crests: Beach Road 6.5% at 122 to 140 km/h no jump; seven highway crests at 170 km/h no air, no bottoming.
- Stability: slalom at 80/140/200 no spin, roll under 9 degrees; hard braking downhill straight; 15 cm kerb at 60 fine. Buildings stand close to the E11 with no barrier (open point).
- Crash recovery: changed to reset on the right lane of the nearest road, plus a reset after 0.8 s in water (the sea had no reset). Overturned and water cases pass. Falling off a flyover lands on drivable ground and does not reset.
- Ramps: json line and asphalt agree (earlier report was a test error).
- Blocker: Unity licence on the laptop expired, the Editor will not start until Hamad signs in to Unity again.

Retest on the rebuilt city (a24f9bc), 2026-11-17 evening: underpass passes both ways (63 to 66 km/h, no bumps); 112 junction passes in 14 districts with 0 problems; buildings at least 12.8 m from highway edges; street sample clean. Still broken then: highway exit ramps (the ramp line folded back on itself where it leaves the highway: no asphalt, 20 run-offs, 5 flips) and Downtown Inner Ring at (2550,1792) (ran into the bank of Downtown Blvd's canal bridge). Both fixed in the generator in the next commit (ramp control points now always move toward the crossing; two main roads that meet at a bridge foot join at a shared height). Needs a rebuild and retest. Unity MCP is connected on the laptop (server unity-mcp) while the Editor has the game open.

2026-11-17, 18:04 Dubai time. Hamad said "Start", then: fix any junk or cheap thing, use everything that is linked (Higgsfield, ElevenLabs, Unity), do your best; he wants graphics and quality, not simple blocks. The hold on visual work is lifted. Plan: real 3D building models per district made with Higgsfield (10 designs: marina tower, glass office tower, beige beach tower, old midrise with shops, Arabic villa, workshop warehouse, petrol station, mosque, neon shop row, hotel tower), then lighting, rain look, materials and sounds.

## 2026-11-17 evening: "match Dubai", more buildings
- Hamad liked the Higgsfield building designs: "add more not all similar", "try ur best to much dubai".
- Done in the cloud: 21 city building models (unity_assets/buildings, buildings.json with size, lot styles, yaw, weight) and 9 landmark models (unity_assets/buildings/landmarks: needle tower, sail hotel, Palm arch resort, big wheel, twisted tower, ski mall, twin spire towers, future museum, gold frame). Concept sheets are in unity_assets/buildings/concepts.
- Generator: three new landmarks placed, green sign gantries on the highways ("gantries"), a metro viaduct beside the E11 ("metro"), denser towers along the E11, palms on more boulevards.
- Ramp fix after the laptop retest (6 stops, 5 flips at the slip roads): a slip road now has the highway's own height where it lies on the highway, and it leaves the highway 258 m before the crossing (was 215 m, which was on the flyover climb). 24 ramps now (was 30). Main creek bridges are 4.0 m high (was 5.0), Creek Bridge foot is 6.6% (was 8.3%).
- Evening test on the PC (build 0960be3): all 24 ramps clean (0 stops, 0 flips), Creek Bridge clean at 80 and 120 km/h, junctions 112 of 112. New look: lot ground paving, light pools, lit palms, deep blue night sky, far buildings keep their model.
- Swerve test at 80 and 140 km/h on the E11 left the road and hit things beside it (metro pillars). Fix: a 0.85 m concrete safety barrier along both highway edges on the ground, open at slip roads and junctions (6.1 km), and metro pillars 9 m from the edge.
- 2026-11-17 19:08: Hamad agrees the darkness needs work: change the ground textures (use the internet and Higgsfield). The game stays night time only, no day time.
- 2026-11-17 19:45: in the game now: 8 Higgsfield ground textures (asphalt, brick sidewalks, sand, villa tiles, yard concrete, granite, grass), 25 km of grass verges, 1,369 Higgsfield 3D date palms (a third wrapped in lights), neutral dark grey roads, matte highway signs, slim lamp posts, light grey metro on round pillars, moon shadows off. Highway barrier rebuilt (0.95 m, vertical, no tapered ends, continuous over flyovers) after the car climbed it at 80 km/h.

## 2026-11-18 01:30 Dubai: first phone test of the Unity game (b6)
- Hamad's words: "the game when ever i press anything at opens the map always for me fix that problem more then that the fps is low".
- b5 was wrong ("u gave me very old update"): the Dubai city only loaded with a test option. Fixed, the Dubai city is now the default.
- Map bug fixed in code (click handler was on the HUD root). Road mirror effect is off on phones. A phone speed pass is in progress.
- Rule reminder: show him the changes before the next APK. Always test the game with no start options before any APK.
- Hamad 01:32: phone is a Galaxy S21. The game will go to iOS users later too. Do not lose the graphics. 30 to 60 FPS is fine.
- Hamad 01:33: "if things far away why u draw it from very far" (do not draw far small things on the phone).
- Hamad 01:34: light rain all the time, streets wet from rain and reflecting, like before.
- Hamad 01:37: where are the old-school loading screen (like MC3/NFS), the intro and the radio music? Keep the girl voice for races/story for later.
- Hamad 01:38: when you enter a different place, show its name small in the corner, then it disappears.
- Hamad 01:40: loading screen music similar to the Midnight Club 3 loading music. 01:41: use mid-2000s old-school music for the game.
