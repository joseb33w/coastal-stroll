# Goal
Build "Coastal Stroll" (NEW repo `joseb33w/coastal-stroll`): a small open-world coastal area,
chunk-streamed for mobile web in Godot 4.6.3 — a NYC-style downtown that blends into a forest and
ends at a beach. Third-person walk (touch joystick + WASD), 3 enterable buildings with interiors,
wandering pedestrians, per-biome ambient audio, custom Meshy landmarks, and real Supabase persistence
(resume position + an explorer log with a `Discovered: N/6` HUD).

# Files to touch
- `project.godot`, `export_presets.cfg` — Compatibility/WebGL2 + nothreads; head_include with Supabase
  SDK + bridge.js + viewport-fit=cover.
- `main.gd` + `main.tscn` — orchestration: env/HDR sky, third-person player+camera, HUD, input,
  footsteps, zone audio, building enter/exit, Supabase save/restore.
- `scripts/world_streamer.gd` — 4x4 chunk ring streamer (ground/scatter/props/landmark/water/buildings/peds).
- `scripts/interiors.gd` — procedural towers + enterable buildings (interiors, furniture, roof-fade) + cabs.
- `scripts/pedestrian.gd`, `scripts/assets.gd`, `scripts/joystick.gd`.
- `shaders/facade.gdshader`, `water.gdshader`, `hdri_sky.gdshader`.
- `audio_manager.gd` + `default_bus_layout.tres` (reused from the verified template).
- `web/bridge.js` — Supabase client (deterministic auth, save/load).
- `world.json` + `quests.json` — the data-driven, qgcheck-gated world.
- `models/` — 3 custom Meshy assets (subway entrance, fountain, vendor NPC), served loose.
- `audio/` — realistic-tier CC0 beds (town/forest/ocean ambient, calm music, footsteps, doors).

# Backend (Supabase, shared Gogi project, per-app prefix usr_nmexs7bytxq2_coastal_stroll)
- `*_player` (one row: pos/facing/zone) + `*_places` (one row per discovered place). RLS-scoped to the
  authenticated user. Auth via a deterministic per-user account (created server-side, no login screen).

# Verification approach
- Headless smoke + qgcheck winnability (the standard godot-verify harness).
- A targeted Playwright pass: tap to start, drive W/S to confirm facing (no moonwalk), teleport into a
  building to confirm interior + door sound + discovery, assert console is clean.
- Backend proven with real creds (Node/curl): sign-in, RLS positive+negative, upsert, discovery insert.
- An independent QA specialist pass before the PR.

# Out of scope
- Cross-device account login UI (persistence is per-user automatic).
- Vehicles/NPC driving AI, day/night cycle, weather, minimap.
