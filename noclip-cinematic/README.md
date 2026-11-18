# Noclip into the Backrooms: first-person cinematic (Roblox)

A ~10 s first-person sequence that takes the player through a wall and into Backrooms Level 0:

1. **Reach:** the player walks up to the wall. The camera turns to it and their right hand reaches out and sinks into the wall.
2. **Enter:** both hands are in the wall. The player pushes slowly forward while the screen desaturates, blurs, glitches and fades to black.
3. **Fall:** a long fall in the dark, heard rather than seen: wind, plus the Backrooms hum starting very faint and growing louder. At the very end a short fragment becomes visible: the player drops from under the Level 0 ceiling with arms flailing, and the carpet rushes up.
4. **Impact:** the player hits the carpet. Hard cut to black with a thud.
5. **Wake up:** the player fades in lying face down on the Level 0 carpet, with both hands flat on the floor in view. The VHS look kicks in: scanlines, warm tint, `PLAY ▶`, a timestamp and a tape counter.
6. **Stand up:** the player pushes up on their hands onto their knees, then the hands leave the floor and they stand up. Control comes back in first person.

The arms are a **viewmodel built from the player's own avatar** (R15 or R6, keeping their shirt), chained joint to joint with the avatar's rig attachments. The real body is hidden locally during the cinematic. There are no animation assets: everything is procedural camera, viewmodel, post-processing, ScreenGui and sound.

## Files (Rojo layout)

| File | Goes to | What it does |
|---|---|---|
| `src/shared/NoclipConfig.luau` | `ReplicatedStorage.NoclipConfig` (ModuleScript) | Every timing, intensity, position and audio ID |
| `src/server/NoclipServer.server.luau` | `ServerScriptService` (Script) | Trigger detection, cooldown, freezes the character, teleports during the blackout |
| `src/client/NoclipClient.client.luau` | `StarterPlayer.StarterPlayerScripts` (LocalScript) | Scripted camera, viewmodel arms, fall shaft, effects, VHS |

`default.project.json` maps these paths. If your shared folder maps somewhere else, change the `require(ReplicatedStorage:WaitForChild("NoclipConfig"))` line in both scripts.

## Hooking it up

1. **Trigger:** a BasePart right in front of the wall (Anchored, CanCollide off, Transparency 1) with the CollectionService tag **`NoclipTrigger`**. Its **front face (LookVector) must point into the wall**: the client casts a ray that way to find the wall surface.
2. **Level 0 spawn:** a BasePart named **`Level0Spawn`** anywhere in Workspace. The player gets up facing its front face.
3. **Audio:** set your IDs in `NoclipConfig.Audio` (`Breathing`, `WallSting`, `Wind`, `Thud`, `Ambient`). `"rbxassetid://0"` disables a sound.
4. **Tuning:** `Timeline` sets the length of each phase. `Camera`, `Arms`, `Desaturate`, `Glitch`, `Fall` and `VHS` control the look. For a shorter version (~5 s), lower `Reach`, `Enter` and `Fall` and set `WakeUp`/`StandUp` to small values.

## Notes

- The character is anchored and frozen on the server for the whole sequence, and restored afterwards. One sequence per player at a time, with a cooldown.
- The visible part of the fall happens in the real Level 0 above the spawn, so the ceiling height needs to fit `Fall.VisibleHeight` + 1 stud. `Fall.Visible` sets how long it lasts and `Fall.HumStart`/`HumEnd` set how the hum grows.
- `FirstPersonAfter = true` locks the camera in first person after the sequence.
- The VHS layer stays on after waking up. Set `VHS.Enabled = false` to skip it.
