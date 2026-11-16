# HMDnight Club — Game Vision & Living Notes

This is the living design document for the game. Every note, request, decision
and open question about the game goes here. Update it whenever the plan
changes, so any future work starts from the same picture.

- Repo: `HMDpreformance/hamadz` · Engine: Godot 4.4.1 (Mobile renderer) · Platform: Android (APK)
- Package: `com.redlinefoundry.afterhours` (kept so updates install over old builds)
- Working title history: "After Hours: Street Syndicate" → "HMDnight Club" (0.9)
- Last updated: 2026-11-16 (0.14 planning + story mode)

---

## 1. What Hamad asked for (his words, kept as written)

### 2026-11-16 — "make the game 10x better"

> create a md file where u save all the nots
> try to build the game with a story like midnight club 3 and need for speed
> also the same thing apply to the style it is old school style games but keep in mind to make the
> quality and the game look more like a modern need for speed game or a forza
> game play style like midnight club 3
> songs are the same thing too
> build a real cars not a fake once with real look same apply to everything
> make the game over all 10x better

Read as six requirements:

| # | Requirement | What it means for us |
|---|---|---|
| R1 | A notes file | This document. Keep every note here. |
| R2 | A story like Midnight Club 3 and Need for Speed | Career mode with characters, rival crews, a villain, chapters and cutscenes, not just a list of races. |
| R3 | Old-school spirit, modern quality | PS2-era attitude (neon, tuner culture, magazine menus, street racing at night) rendered with modern NFS / Forza Horizon quality: physically based paint, reflections, wet roads, depth, clean UI. |
| R4 | Gameplay like Midnight Club 3 | Open city is the menu, races start in the street, checkpoint racing through traffic, nitrous, drafting, special abilities per car family, crews/clubs. |
| R5 | Songs like Midnight Club 3 | A big street soundtrack in that style: hip-hop, rock, electronic and Middle-Eastern flavoured tracks on in-game radio stations. Original music only. |
| R6 | Real cars, real look, "same for everything" | Photoreal car bodies and a realistic city, UI and audio. See decision D1. |

### Earlier requests (from previous threads)

- PS2-era street racer for Android in the spirit of Midnight Club 3 (2026-11-11).
- Expand, never restart the project; Godot is the engine (2026-11-11).
- Photo-real look (0.9), real 3D car body (0.10), Dubai-style city (0.11), photo facades and wet streets (0.12), Dubai detail pass with bilingual signs and the radio station "NIGHT RIDE FM 99.1" (0.13).
- He keeps saying the look is not real enough: target is a photoreal wet night street in Dubai (stone and glass buildings, cafe awnings, neon reflections).
- Voices and cinematics: 29 voice lines and a 5-second intro film shipped (0.7, 0.8).
- Not done yet from earlier asks: weather, daytime, rain spray. His "master prompt" was cut off twice and never re-sent.

---

## 2. Decisions log

| ID | Date | Decision | Why |
|---|---|---|---|
| D0 | 2026-11-11 | Godot 4.4.1, Mobile renderer. Expand the existing project, never restart. | Runs on phones, already built 13 stages on it. |
| D1 | 2026-11-16 | **Real-looking original cars.** Photoreal 3D cars clearly in the style of real JDM, muscle, Euro, luxury and super cars, with our own names and badges. No real brand names, logos or exact likenesses. | Hamad picked this on a card. Real makes need a license from each carmaker; without one the game can't go on the Play Store or be shared publicly. This way it looks real and stays releasable. |
| D2 | 2026-11-12 | All music, voices, art are original or generated for us. No sampled songs, no real artists' voices, no copied MC3 names/maps/art. | Same release reason as D1. |
| D3 | 2026-11-16 | The story is our own: Dubai at night, our crews, our characters. We copy the *structure* of MC3/NFS careers (crews, rivals, blacklist-style bosses), never their plots or names. | Originality + release safety. |

---

## 3. The game in one paragraph

**HMDnight Club** is a night-time street racer set in a Dubai-style city. You
arrive with a borrowed tuner and nothing else. The city's underground scene is
run by five crews, one per district and car family, and above them all sits
**The Night Club**, an invite-only league led by a man everyone calls **MIDAS**.
You race your way up: beat each crew's runners, call out their leader, win their
car and their special ability, and earn your invite to the Night Club. The city
is the menu: you drive to every race, races start on the street, and the radio
never stops.

---

## 4. Story (R2)

Structure borrowed from MC3 (crews per car family, win their cars and powers)
and NFS Most Wanted / Underground (a rival who humiliates you in the prologue,
a list of bosses, a final showdown). Plot, names and characters are ours.

### Cast

| Character | Role | Notes |
|---|---|---|
| **You** | New driver in the city | Silent, like the classics. Name shown as "YOU". |
| **DESTINY** | Your contact and navigator | Texts you race invites and gossip, explains the scene. The NFS "guide" role. |
| **BARRETT** | Mechanic, owns the garage you work out of | Already voiced (garage lines). Upgrades, car advice. |
| **KNOX** | The race starter | Already voiced (countdowns, briefs, results). Neutral, runs every start line. |
| **JUNO** | Night DJ on NIGHT RIDE FM 99.1 | Already voiced. Comments on your rise between songs. |
| **VIPER** | Your rival | Beats you on night one and laughs. MIDAS's right hand. Final boss before MIDAS. |
| **MIDAS** | Boss of The Night Club | Old money, gold-wrapped exotic, never loses. Final race. |

### Crews (MC3-style clubs, one per district and car family)

| Crew | District | Car family | Leader | Ability you win |
|---|---|---|---|---|
| NEON RONIN | Downtown | Japanese tuners | KOJI | **FOCUS** (time slows) |
| COASTLINE KINGS | Jumeirah | Luxury sedans | LUXE | **RAM** (plough through traffic) |
| WAREHOUSE WOLVES | Al Quoz | American muscle | BRICK | **ROAR** (shockwave clears traffic) |
| DUNE TITANS | Sheikh Zayed Road | SUVs / trucks | TORQUE | (car reward: Titan LX) |
| MARINA ROYALE | Dubai Marina | European exotics | NOVA | (car reward: Verano GT) |
| THE NIGHT CLUB | Whole city | Everything | VIPER, then MIDAS | Ardente V12 + the title |

### Chapters

| Ch | Title | Where | Races | Ends with |
|---|---|---|---|---|
| 0 | WELCOME TO DUBAI | Downtown | Midnight Loop | VIPER cuts in at the finish, mocks your car. DESTINY gets you in touch with the crews. |
| 1 | NEON RONIN | Downtown | Downtown Circuit, Ronin Run, **KOJI call-out** | You win KOJI's respect and FOCUS. |
| 2 | COASTLINE KINGS | Jumeirah | Palm Heights Call-Out, Beach Road Sprint, **LUXE call-out** | Vanta S6 + RAM. |
| 3 | WAREHOUSE WOLVES | Al Quoz | Ironworks Dash, Container Yard, **BRICK call-out** | Brawler 427 + ROAR. |
| 4 | DUNE TITANS | Sheikh Zayed Road | Tunnel Run, Bayshore Sprint, **TORQUE call-out** | Titan LX. |
| 5 | MARINA ROYALE | Dubai Marina | Ocean Strip Circuit, Marina Dash, **NOVA call-out** | Verano GT. Invite to the Night Club. |
| 6 | THE NIGHT CLUB | City-wide | The Full Ring, **VIPER call-out**, **MIDAS: Gold Rush** | Ardente V12. You run the city. Credits. |

Story beats are shown as in-engine cutscenes: letterbox bars, the cinematic
camera orbiting your car, a speaker name plate and portrait badge, and
typewriter dialogue you tap through. Later: voiced lines (see section 9).

Free roam stays open the whole time: every race can be replayed for cash and
rep, story races are marked STORY on the map and on their card.

---

## 5. Gameplay like Midnight Club 3 (R4)

What makes MC3 feel good (full study: MC3 feel study doc,
https://claude.ai/artifact/Bd5e1PNYrSxrmyHCW8uUWD):

1. One city, no menus between races.
2. Races you find on the street.
3. Short, readable checkpoint races where your own shortcut matters.
4. Forgiving, fast arcade handling with drafting, nitrous, launch boosts.
5. One special power per car family.
6. A career built on car clubs.
7. Deep garage and loud style, big soundtrack.

### Systems and status

| System | Status | Notes |
|---|---|---|
| Open city, drive to races | Have | Dubai-style grid, highway ring, 5 districts. |
| Race types: checkpoint, circuit, sprint, time trial, duel | Have | 8 events → 0.14 adds story events and crew-leader duels. |
| Light-beam checkpoints + minimap arrow | Have | |
| Traffic, traffic lights | Have | |
| Nitrous, handbrake drifts | Have | |
| **Near-miss bonus** (refills nitro and ability meter) | 0.14 | Pop-up word + sound. |
| **Slipstream / drafting** behind cars | 0.14 | Fills while tucked in, then a speed push. |
| **Perfect launch** at GO | 0.14 | Throttle held in the right rev band on the grid. |
| **Special abilities** FOCUS / RAM / ROAR | 0.14 | One per car family, meter filled by near misses, drafting, drifting. Unlocked through the story. |
| **Story mode / crews / chapters** | 0.14 | See section 4. |
| Street call-outs (flash lights at a cruising rival) | Planned 0.15 | Rival crew cars cruising the city. |
| Police / heat | Planned | MC3 had cops; adds chases. |
| Any-order and cone-run races | Planned | |
| Shortcuts, alleys, jumps per district | Planned | |
| Bikes | Not planned | |

---

## 6. Look: old-school soul, modern NFS / Forza quality (R3, R6)

Target: a modern NFS (Heat / Unbound without the cartoon effects) or Forza
Horizon night drive, on a phone. Old-school identity comes from the setting and
attitude (neon, chrome title type, tuner culture, magazine menus), not from low
quality.

### What "modern quality" means in practice

| Area | Target | Status |
|---|---|---|
| Car paint | Clearcoat PBR paint, metallic flake, sharp environment reflections | Have basics (0.9). Improve reflection probes, flake. |
| Car models | Photoreal 3D bodies for every car, ~60–90k tris, proper glass, lights, interiors seen through windows | 1 of 8 (Kaido RS-7, 0.10). Rest blocked on credits (section 10). |
| Wheels / tyres | Real rim designs, tyre sidewall detail, brake discs and calipers | Procedural; upgrade. |
| City | Photo facades, wet asphalt with neon reflections, glass towers, palms, signs | Have (0.12–0.13). Next: screen-space reflections on high, more props, parked cars, pedestrians' silhouettes. |
| Lighting | Night with strong headlight cones, street lamp pools, bloom on neon, light trails | Partly. |
| Weather / time | Rain with spray behind cars, wet/dry, dusk and night | Rain have (0.13.1); spray and dusk planned. |
| Camera | Speed-dependent FOV and shake, low chase cam, cinematic replays/photo mode | Partly. Photo mode planned. |
| UI | Clean modern NFS-style HUD with old-school chrome titles | Have (0.9). Story UI in 0.14. |

### Phone reality

A phone can't match a console NFS frame for frame. We aim for the same *look*
(reflections, wet roads, glow, sharp cars) with tricks that are cheap on
mobile: baked reflections, screen-space effects on the high preset only,
LODs, and photo textures. Three graphics presets stay.

---

## 7. Cars (R6, D1)

Real-looking originals, each clearly in the style of a real class of car.

| Id | Name | Style reference (class, not a brand) | Family / ability | 3D body |
|---|---|---|---|---|
| tuner | KAIDO RS-7 | 90s Japanese turbo coupe | Tuner / FOCUS | Real 3D (0.10) |
| rotary | AKAGI RZ-8 | Japanese twin-rotor sports coupe | Tuner / FOCUS | Procedural |
| muscle | BRAWLER 427 | Late-60s American big-block | Muscle / ROAR | Procedural |
| classic | CORONADO '64 | 60s American lowrider | Muscle / ROAR | Procedural |
| sedan | VANTA S6 | German luxury sport sedan | Luxury / RAM | Procedural |
| suv | TITAN LX | Supercharged luxury SUV | Luxury / RAM | Procedural |
| euro | VERANO GT | Rear-engined German flat-six | Exotic / FOCUS | Procedural |
| exotic | ARDENTE V12 | Italian mid-engined V12 | Exotic / FOCUS | Procedural |

Plan: generate a photoreal 3D body for each of the remaining 7 cars with the
same pipeline as the Kaido (concept image → image-to-3D → simplify to ~86k tris
→ repaint key). About 12 Higgsfield credits per car (~84 total). Car
silhouettes must not copy a single real model one for one; the generator tends
to drift toward real cars, so every concept gets checked for badges and exact
likenesses.

Later cars to add (ideas): Gulf-style desert pickup, a hot hatch, a
supercharged British GT, an electric hypercar.

---

## 8. Soundtrack (R5)

MC3's soundtrack was a mix of hip-hop, rock, electronic and regional music on
the radio. Ours: original tracks in those styles, no real artists, no samples.

| Have | Tracks |
|---|---|
| NIGHT RIDE FM 99.1 (0.13) | Midnight Cruise, Break Point, Desert Highway (generated, 2 min each) + 6 synthesized tracks (0.6) + main theme |

Plan:
- Two stations to start: **NIGHT RIDE FM** (hip-hop / electronic) and a rock /
  drum-and-bass station; later an Arabic-electronic station that fits Dubai.
- 10–12 new tracks at ~17.5 Higgsfield credits per 2-minute track (or
  ElevenLabs music if that account gets funds).
- Race music that ramps with the race (calm in roam, harder on GO, final lap stinger).
- DJ JUNO lines that react to your story progress.

---

## 9. Audio and voices

- Engine sounds: synthesized per engine type (i4 turbo, rotary, V6, V8, V12,
  supercharged V8). Next step toward "real": recorded-style layering
  (intake, exhaust, transmission whine, turbo flutter) and interior/exterior mix.
- Voices: 29 lines (starter KNOX, mechanic BARRETT, DJ JUNO). Never auditioned
  by ear; only length and loudness checked.
- Story voices wanted: DESTINY, VIPER, MIDAS, KOJI, LUXE, BRICK, TORQUE, NOVA.
  About 60–80 short lines at ~0.15 credits each (~10–12 credits).

---

## 10. Budget and blockers

- Higgsfield balance on 2026-11-16: **7.99 credits** (Plus plan). Every new
  generation needs Hamad's OK.
- ElevenLabs connector: no funds (as of 2026-11-12).
- Rough cost of the full "real" upgrade:
  - 7 photoreal car bodies: ~84 credits
  - 10–12 soundtrack tracks: ~175–210 credits
  - Story voices: ~10–12 credits
  - City textures / props: ~15–30 credits
- Network: OpenStreetMap and some CDNs are blocked in the cloud build
  environment, so the city is built by hand on our grid.

Everything that doesn't need credits (story, gameplay systems, rendering,
UI, physics) goes ahead now.

---

## 11. Upgrade plan ("10x better"), stage by stage

Each stage is one playable APK.

| Stage | Version | Content | Needs credits? |
|---|---|---|---|
| A | **0.14** | This doc. Story mode (chapters, crews, cutscene dialogue, rewards). MC3 street skills: near miss, drafting, perfect launch, FOCUS / RAM / ROAR abilities with meter and button. Crew-leader duels and new district events. | No |
| B | 0.15 | Street call-outs: crew cars cruising each district, flash to challenge, race starts on the spot. Police heat level. Any-order races. | No |
| C | 0.16 | Modern look pass: better reflections and paint flake, headlight cones, rain spray, dusk preset, photo mode, camera polish. | No |
| D | 0.17 | Real 3D bodies for the other 7 cars. | ~84 credits |
| E | 0.18 | Soundtrack expansion and second station; story voices. | ~185–220 credits |
| F | 0.19+ | Shortcuts and jumps, more cars, garage depth (lowrider bounce, decals), polish. | Some |

---

## 12. Open questions for Hamad

1. Credits: OK to spend on cars (D) and music/voices (E)? Current balance (~8) covers only the story voices.
2. Story tone: keep it like MC3 (light, about respect and cars) or darker like NFS Most Wanted (cops, betrayal)? Current draft is in between.
3. Should story races be required in order, or can chapters be played in any order once unlocked (MC3 let you pick clubs)? Current build: in order.
4. Police chases: wanted, or keep it pure racing?
5. The "master prompt" from earlier threads was cut off. Re-send it if there is more.

---

## 13. Change history of this document

- 2026-11-16: Created. Captured all requests so far, decisions D0–D3, story, gameplay systems, look targets, cars, soundtrack, budget, stage plan.
