# Intro film

`video/intro.ogv` plays once after the studio logo and before the in-engine
cinematic (`scripts/scenes/intro.gd`, phase `VIDEO`). It is scaled to cover the
screen, sits under the letterbox bars, has no sound of its own (the main theme
plays over it) and a tap skips it. Delete the file and the intro goes straight
to the in-engine cinematic.

- Source: one 5 second, 1280x720, 24 fps clip generated on 2026-11-12 with
  Higgsfield (`seedance_2_5`, text prompt only, 35 credits), converted with
  `ffmpeg -an -c:v libtheora -q:v 7` because Godot plays Ogg Theora only.
- The prompt asked for original, unbranded cars with no logos, text or plates.
  The result still shows small unreadable plates and body shapes that resemble
  well known real sports cars. Review this before any store release.
- The clip is photoreal while the game is stylised low-poly, so the cut into
  the in-engine cinematic is a visible change of look.
- Checked from extracted frames and in-game screenshots, on desktop only.
