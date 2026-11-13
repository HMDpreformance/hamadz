# Audio: sources, rights and how to add more

Everything that ships in the game today was made for this project. Nothing is
sampled from, or modelled on the melody or lyrics of, any commercial recording.

## What is in the build

| Content | Files | How it was made | Rights |
|---|---|---|---|
| Engine, exhaust, turbo, tyres, UI sounds | `audio/*.wav`, `audio/engines/` | Synthesized by `tools/gen_engines.py` and `tools/gen_audio.py` | Original, owned by the project |
| Soundtrack (6 tracks, about 9 minutes) | `audio/music/*.ogg` | Synthesized by `tools/gen_music.py` (drum machines, bass, pads and leads written as code) | Original, owned by the project |
| Win / lose stings | `audio/sting_win.wav`, `audio/sting_lose.wav` | `tools/gen_music.py` | Original |

These are **synthesized, not recordings**. No real car was recorded and no
musician or vocalist performed. The tracks are instrumental.

## Music system

- Catalogue: `scripts/core/soundtrack.gd` (title, artist name, radio flag).
- States (`Audio.music_state`): `intro`, `menu` (main theme), `garage` (radio,
  quiet and filtered), `roam` and `race` (radio rotation, shuffled, moves on when
  a track ends). Countdown ducks and filters the music; GO opens it back up;
  the result screen plays a win or lose sting; pause muffles it.
- Radio: station "Syndicate FM 99.1". RADIO button on the driving HUD skips
  tracks, the pause menu turns it on or off, and the choice is saved.
- To add a track: drop an `.ogg` in `audio/music/` and add a row to `TRACKS`.

## Voice lines

`Audio.voice(id, db, priority)` plays `audio/voice/<id>.ogg`, or one of
`<id>_2.ogg`, `<id>_3.ogg` ... when variants exist (never the same one twice in a
row), on its own "Voice" bus. The music ducks by itself while a line plays
(side-chain compressor on the Music bus). One voice talks at a time; a line only
interrupts another when its priority is at least as high. A missing file is
silently skipped, so a line can be removed by deleting its `.ogg`.

| Speaker | Preset voice | Ids | When |
|---|---|---|---|
| Race starter | Knox | `count_3`, `count_2`, `count_1`, `go` | Countdown |
| | | `brief_checkpoint`, `brief_duel`, `brief_trial`, `brief_circuit`, `brief_sprint` | Event title card (the card waits for the line) |
| | | `final_lap`, `lead_taken`, `lead_lost` | During a race |
| | | `win`, `win_2`, `podium`, `lose`, `lose_2` | Result |
| | | `title` | Title screen |
| Mechanic | Barrett | `garage_welcome` (3 takes), `garage_install` (2 takes), `garage_broke`, `garage_new_car` | Garage |
| Syndicate FM DJ | Juno | `dj`, `dj_2`, `dj_3`, `dj_4` | Free roam only, shortly after arriving and after every second song |

## Generated audio (Higgsfield)

The 29 voice lines were generated on 2026-11-12 with Higgsfield
(`text2speech_v2`, engine ElevenLabs, preset voices above) on the account's Plus
plan, about 0.15 credits per line. The scripts are original and name no real
person. Each file was trimmed and levelled by `ffmpeg` + numpy (RMS of the
speech to -18 dBFS, mono 44.1 kHz Vorbis).

- **Not auditioned by ear.** Lengths and loudness were measured and the trigger
  points were tested in headless runs, but nobody has listened to the takes yet.
  Replace or delete any that sound wrong.
- Before a store release, confirm that the Higgsfield plan in use grants
  commercial rights to generated speech and keep this record.
- Do not prompt for a named artist, a named song or a real person's voice.

## Commercial songs

Not used. Adding one would need, per song and before integration:

1. A **synchronization licence** from the publisher(s) for the composition.
2. A **master-use licence** from the label or owner of the recording.
3. **Distribution terms** in both that cover a mobile game on the stores and
   territories you ship to, the term, and trailers or ads if the song appears there.

Streaming and gameplay videos by players can trigger takedowns for licensed
music, so a licensed track should also be switchable off.
