# Free Floater

A Spider-Man-style web-swinging VR experience for the **Steam Frame**, built
with **Godot 4.7.2 + OpenXR** as a self-contained native **Linux ARM64** app —
no PC streaming required.

Hold a trigger to shoot a web cord at a building; the cord tethers you as a
pendulum and reels you toward the anchor. Release to let go and keep your
momentum as you swing from rooftop to rooftop.

## Features

- **Web swinging** — aim with a controller (a subtle aim dot marks valid
  attach points, with a light haptic tick when acquired), squeeze the trigger
  to attach. Rope physics with pendulum constraint; hold **grip** to reel in
  faster.
- **Low-gravity locomotion** — floaty air for long swings, smooth walk +
  snap-turn on the ground, left **AX** to jump, right **AX** to respawn.
- **Procedural city** — 200+ webbable buildings with generated facade
  textures, lit/dark windows, and roof caps you can land and walk on.
- **Visible hands** — low-poly gloved hands in the web-shoot pose on both
  controllers; cords fire from the palm.
- **On-headset HUD** — status label (web sides, speed, reel indicator) and a
  fading controls hint, plus haptic feedback.

## Repository layout

```
app/
  project.godot            Godot project (mobile renderer, OpenXR enabled)
  scenes/main.tscn         Main scene: City + XR rig
  scripts/
    main.gd                Entry point (XR init, spawn wiring)
    web_rig.gd             XROrigin3D rig: web physics, locomotion, HUD
    city_builder.gd        Procedural city, facades, lighting
    app_log.gd             On-device logging
    build_version.gd       Generated version stamp (do not edit)
  tests/
    test_web.gd            Headless test suite (rope math, scene, wiring)
    screenshot_city.gd     Visual capture harness
  openxr_action_map.tres   Action map: triggers, grip, sticks, AX, D-pad, haptic
tools/
  export.sh                Version stamp + headless ARM64 export
build/                     Export output (git-ignored)
```

## Requirements

- Godot **4.7.2 stable** on `PATH` (`godot --version`)
- Linux export templates for `4.7.2.stable` (arm64) under
  `~/.local/share/godot/export_templates/`

## Build & test

```sh
# Headless test suite
env -u DISPLAY godot --headless --path app -s res://tests/test_web.gd

# Export build/free_floater.arm64 (stamps the version automatically)
./tools/export.sh
```

Bump `config/version` in `app/project.godot` for each release — the export
stamp and the in-VR version label read it.

## Deploy to the Steam Frame

1. Push `build/free_floater.arm64` to the headset and `chmod +x`.
2. Upload via the Devkit Client; paste the name from
   `build/launcher-name.txt` (e.g. `Free Floater v0.2.4 · 2026-…`) into the
   **Name** field — there is no separate version field on-device.
3. Launch from the SteamOS app list.

## Controls

| Input | Action |
|---|---|
| Trigger (hold) | Shoot web at aimed building / release to let go |
| Grip (hold) | Reel in faster while attached |
| Thumbstick | Walk (up/down) / snap-turn (left/right) |
| Left AX | Jump |
| Right AX | Respawn |

## License

All rights reserved — personal project.
