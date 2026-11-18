# Laptop session notes (hand-over to the next session), 2026-11-17

## Rules
- Work only in `C:\Users\hamad\Desktop\Cluad\hamadz-unity`. Do not touch "Orginal Disk MNC 3", the Godot game or hmdperformance.com.
- No push, no APK. Do not commit the owner's AI packages (see "Manifest rule").
- Reports go to the coordinator / owner with `mcp__claude-code-remote__send_message` to `@parent`.
- Do not ask the owner about map or Palm questions; the cloud side handles them.
- The coordinator owns these; report problems instead of editing them:
  - tools/build_city.py, tools/city_plan.py, make_gauges.py
  - unity_assets/city/*
  - map_full.jpg, map_base.jpg

## Git state
- Local branch `r15`. Top commits:
  - `dac4adf` Merge a24f9bc (lots 12 m clear of highways, no street across the Downtown Blvd dip). Contains 09833ca and
    f833710.
  - `cf7e240` Test driver: highway side clearance scan; junction test drives roads that start at the junction into it.
  - `63f7bfa` Crash reset onto the nearest road lane and out of the sea; test modes. This is the same code as the
    coordinator's f833710.
- After dac4adf: this notes file only. f833710 already has everything from round 15b except cf7e240.
- Patch for the cloud: `git diff --binary <base>..HEAD -- . ':!handover'`. For the next patch, use a24f9bc as the base.
- Uncommitted on purpose: the owner's Editor changes. Do NOT commit them:
  - Packages/manifest.json and packages-lock.json (com.unity.ai.assistant 2.22.0-pre.1, com.unity.ai.inference 2.6.1)
  - ProjectSettings/*.asset changes, PackageManagerSettings.asset, URPProjectSettings.asset,
    ProjectSettings/Packages/com.unity.ai.assistant/
  - Main.unity, UniversalRenderPipelineGlobalSettings.asset

## Unity
- Editor 6000.3.28f1 at `C:\Program Files\Unity\Hub\Editor\6000.3.28f1\Editor\Unity.exe`. Unity Hub (Store version) is
  signed in, and the licence works again.
- The owner keeps the Editor open on our project. While it is open, batch builds fail ("another Unity instance"). Options:
  - Build through the Editor: the menu `HMD/Setup Project` then `HMD/Build Windows`, by the owner or via the Unity MCP.
  - Or, when the Editor is closed, run `scratchpad/build_clean.sh`. It backs up the owner's manifest and settings,
    restores the git versions, runs a batch build, then puts the owner's files back.
- Manifest rule: builds and tests run WITHOUT the AI packages where possible. The owner's manifest must be restored
  afterwards, and the AI packages are never committed or put in a patch.
- Unity MCP:
  - Package com.unity.ai.assistant in our project. The relay is `C:\Users\hamad\.unity\relay\relay_win.exe --mcp`.
  - The owner pressed Integrations > Claude Code > Configure, which wrote an entry in `C:\Users\hamad\.claude.json`.
  - Check in the Editor (Project Settings > AI > Unity MCP Server): "Unity Bridge" Running. Press Allow under Pending
    Connections the first time.
  - The docs say the MCP server is deprecated in favour of the Unity CLI.
  - Tools are named like Unity_ReadConsole and Unity.ManageScene; there should be one to run a menu item.

## Build without the Editor (batch)
`scratchpad` is `C:\Users\hamad\AppData\Local\Temp\claude\176959f2dfc01b0e\24057c96-4efd-426c-a622-885ea8e8fe3b\scratchpad`.
A new session may not have it; the scripts are short, so recreate them:
```
"/c/Program Files/Unity/Hub/Editor/6000.3.28f1/Editor/Unity.exe" -batchmode -quit -projectPath unity \
  -executeMethod HMD.EditorTools.Build.SetupAndWindows -logFile <log>
# success line: "[HMD] build Succeeded"; errors: grep "error CS"
```
Output: `unity/Builds/Win/HMDNightClub.exe`. The player is Mono.

## Script-only rebuild (no Editor needed)
When only C# under unity/Assets/Game/Runtime changes, compile it with Unity's compiler using the player build's own
settings, and copy the result over the built DLL:
```
E="/c/Program Files/Unity/Hub/Editor/6000.3.28f1/Editor/Data"
# game.rsp = unity/Library/Bee/artifacts/1300b0aP.dag/HMD.Game.rsp without the "Assets/..." source lines, -out and -refout
# lines, plus -out:"<scratch>/HMD.Game.dll" and every Assets/Game/Runtime/**/*.cs in quotes
"$E/NetCoreRuntime/dotnet.exe" "$E/DotNetSdkRoslyn/csc.dll" -nologo @game.rsp
cp HMD.Game.dll unity/Builds/Win/HMDNightClub_Data/Managed/HMD.Game.dll   # not while the game runs
```
This cannot change assets, scenes or the city mesh. A MonoBehaviour that is new only in the DLL may not attach.

## Running tests (built exe)
```
cd unity/Builds/Win
./HMDNightClub.exe -hmdshots -screen-width 1920 -screen-height 1080 -screen-fullscreen 0 -logFile <log> \
  -newcity -ncdrive <mode> -ncnostills
```
Shots land in `unity/Builds/Win/Shots/*.png`. The log lines start with `[HMD]`.

Modes (NcShots.cs):
- `default` (no -ncdrive): highways plus 6 ramps, then the stills (nc_00..nc_18).
- `highway` | `main` | `ramp` | `street` | `all`:
  - autopilot drives; streets are sampled, at most 2 per name
  - logs `nc drove`, `BUMP`, `DROP`, `STOP (wall?)`, `RUN-OFF` (off asphalt or more than 12 m past the edge), `FLIP`
  - mains take about 50 s each, so use a timeout of 2400 s
- `tests`: the owner's checks:
  - locked controls, reverse RWD/AWD with handbrake
  - slalom at 80/140/200, hard braking downhill, kerb
  - Beach Road slope, highway crests
  - Downtown Blvd underpass both ways, its clearance, and the E11 over it; shot nc_20_underpass
  - crash recovery (overturned, water, off a flyover)
  - ramp json line vs the mesh
- `junctions`: 2 junctions per district, every road through each, both ways at 60 km/h. `<-- CHECK` marks problems.
  Shots nc_21_junction_*.
- `profiles`: surface profiles at known spots plus `side clearance` for each highway (how close the lots are, with no
  barrier).
- `-ncaudit`: static raycast audit along every road. `-uncap`: no FPS cap. `-rain` / `-dry`: force the weather.
- Game.cs crash reset logs `[HMD] car reset from .. to .. (fell|water|flipped)`.

Note: in this game, reverse = hold the brake at a standstill. `reverseHeld` is not set by the game.

## Publishing
- Artifact: https://claude.ai/artifact/38c8jxCBHzg9rQVFDpQyA2 (private). The source is `scratchpad/gallery/`:
  - index.html: the figures list, newest first under the header
  - shots/*.jpg: convert the PNGs with System.Drawing, quality 86
  - handover/overnight.patch and handover/status.txt
- Publish with the Artifact tool: `url` = the artifact, `file_path` = gallery/index.html, `root` = gallery, and `files`
  mapping the new shots plus the handover files. A new session must first `read` those files (Artifact read with `paths`)
  or the publish is refused.

## Pending work (the coordinator's round 15b)
1. The a24f9bc build exists (built from the Editor at 16:35; the city glb and json in Assets match unity_assets).
2. A test chain was running on it at 16:37: profiles, tests, junctions, main, ramp, highway, street. Logs are in
   `scratchpad/e_<mode>.log` and shots in `scratchpad/shots15/`. A restart kills it, so rerun whatever did not finish.
3. Report:
   - underpass both ways (northbound must now get through; before, a 3.1 m wall at about (2524,1347))
   - junction results
   - highway lot scan (before a24f9bc: E11 nearest 2.8 m, E44 2.7 m, 6 spots under 5 m; now expected at least 12 m)
   - road drive defects
4. Shots: the underpass, two junctions (top and street level).
5. status.txt plus the patch (base a24f9bc, without handover/ and without the AI packages), publish, note to the
   coordinator.
6. On hold: visual work (rain look, lighting, buildings).

## Results so far (3ceeb48 build): see handover/status.txt

## Update 17:55 (next laptop session)
- r15 head 70026b7: cdcc699 (test runs set Application.runInBackground; the 16:37 chain had paused when the window
  lost focus) and 70026b7 (junction test: roads that end at the junction count as through).
- Tests now run from `unity/Builds/Win2` (a copy of the a24f9bc build with the newer HMD.Game.dll; ignored by git), so a
  run never fights the Editor build folder. Scripts: `<scratchpad>/run.sh` and `chain.sh` in session 41363677.
- Unity MCP works (server unity-mcp: Unity_GetConsoleLogs, Unity_RunCommand, captures). The city exists only at runtime.
- Results are in the artifact's handover/status.txt (version 20). Open: ramp asphalt gap at each ramp split (the
  coordinator's generator), Downtown Inner Ring (2550,1792), E11 crest (282,1491) test anomaly.
- Run one game window at a time and let each one close before starting the next. Never `git commit -a` (the owner's
  Editor files would go in).
