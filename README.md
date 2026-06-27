# Coastal Stroll

A small **open-world coastal area** you walk around in — a NYC-style downtown that blends into a
forest and ends at a beach. Built with **Godot 4.6.3**, exported for **mobile web**
(Compatibility/WebGL2, single-threaded), and streamed in **chunks** so it stays smooth on a phone.

Walk from the skyscrapers, through the woods, down to the sand and the ocean — one continuous world.

## Features
- **Open world, chunk-streamed.** A 4×4 grid of 20-unit cells (`world.json`). A 3×3 ring of cells
  loads/unloads around you as you walk (≤1 cell built per frame, cells outside the ring evicted), so
  memory stays bounded on mobile. No loading screens between zones.
- **Three blended zones:** a downtown core (procedural skyscrapers with lit-window façades, sidewalks,
  streetlights, hydrants, benches, **yellow cabs**), a forest (trees, a dirt trail, rocks, bushes),
  and a beach (sand, palms, driftwood, an animated ocean).
- **Third-person walking** — touch joystick (drag the left side) **and** WASD/arrows. The camera is a
  wall-aware follow cam.
- **Enterable buildings** — a **Corner Bodega**, a **Diner**, and an **Apartment Lobby**. Step through
  the doorway and the interior is there (furniture, lighting); the roof hides while you're inside and a
  door sound plays as you enter/leave. Walk back out anytime.
- **Wandering pedestrians** — animated people stroll the streets and park.
- **Custom Meshy landmarks** — a hero NYC **subway entrance**, a plaza **fountain**, and a unique
  **street-vendor NPC**, generated with the Meshy API and streamed in (the ordinary props come from the
  CC0 asset library).
- **Per-zone, audible sound** — footsteps as you walk, a door sound on enter/exit, and an ambient bed
  that switches with the biome (city traffic/crowd → forest birds → ocean surf) over a calm music loop.
  Sound starts on first tap (mobile autoplay unlock).
- **Supabase persistence** (real backend, not localStorage):
  - **Resume where you left off** — your position + facing are saved (debounced, ~every 3s and on
    leaving) and restored on load.
  - **Explorer log** — the first time you enter each named place (the 3 zones + 3 buildings) it's
    recorded, and a persistent **`Discovered: N / 6`** HUD reads from Supabase on load, so it survives a
    refresh and a fresh session.

## Backend
Tables in the shared Gogi Supabase project, namespaced per-app and RLS-scoped to the player:
- `usr_nmexs7bytxq2_coastal_stroll_player` — one row: position, facing, zone.
- `usr_nmexs7bytxq2_coastal_stroll_places` — one row per discovered place.

Persistence uses a deterministic per-user account (created server-side) that the client signs into with
no login screen, so the save follows you across sessions. See `.env.example`.

## Project layout
- `main.gd` — orchestration: environment/sky, player + camera, HUD, input, footsteps, zone audio,
  building enter/exit, Supabase save/restore.
- `scripts/world_streamer.gd` — the chunk ring streamer (ground, scatter, props, landmarks, water,
  buildings, pedestrians).
- `scripts/interiors.gd` — towers + enterable buildings (interiors, furniture, roof-fade, cabs).
- `scripts/pedestrian.gd` — wandering NPC behaviour.
- `scripts/assets.gd` — runtime GLB streaming + cache + collider/grounding helpers.
- `shaders/` — façade windows, ocean, HDR sky.
- `web/bridge.js` — Supabase client (auth + save/load), loaded by the export.
- `world.json` / `quests.json` — the data-driven world (chat-editable; winnability-gated).

## Run / export
```bash
./fetch_assets.sh                                   # pull the audio beds, sky, and Meshy models
godot --headless --path . --import
godot --headless --path . --export-release "Web" out/index.html
cp world.json quests.json out/                      # loose files fetched at runtime
cp web/bridge.js out/ ; cp -r models out/           # bridge + Meshy assets next to index.html
```
Serve `out/` with the `.wasm` MIME set to `application/wasm` and **no** COOP/COEP headers
(single-threaded build).
