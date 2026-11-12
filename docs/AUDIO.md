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

## Voice lines (hooks ready, no recordings yet)

`Audio.voice(id)` plays `audio/voice/<id>.ogg` if the file exists and does
nothing otherwise. Ids already called by the game: `count_3`, `count_2`,
`count_1`, `go`, `win`, `podium`, `lose`, `garage_welcome`.

## Generated audio (ElevenLabs / Higgsfield)

None is in the build yet. Before any generated voice or music ships:

- Check that the account plan used for the generation grants commercial use
  (free tiers usually do not) and keep a record of plan, date and prompt.
- Do not prompt for a named artist, a named song or a real person's voice.
- Listen to every take for artifacts before it goes in.

## Commercial songs

Not used. Adding one would need, per song and before integration:

1. A **synchronization licence** from the publisher(s) for the composition.
2. A **master-use licence** from the label or owner of the recording.
3. **Distribution terms** in both that cover a mobile game on the stores and
   territories you ship to, the term, and trailers or ads if the song appears there.

Streaming and gameplay videos by players can trigger takedowns for licensed
music, so a licensed track should also be switchable off.
