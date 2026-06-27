#!/usr/bin/env bash
# Reconstruct the binary assets this game uses (they are NOT committed to keep the repo light).
# Run from the project root BEFORE importing/exporting. Total ~7 MB.
#   - audio beds (CC0, realistic tier) -> res://audio/  (bundled in the .pck)
#   - HDR sky panorama (CC0, Poly Haven) -> res://skies/ (bundled in the .pck)
#   - the 3 custom Meshy models -> res://models/ (served loose next to index.html at runtime)
# Library props/characters stream from R2 at runtime and need no fetch.
set -euo pipefail
O=https://preview.myapping.com/godot-assets
MESHY=https://preview.myapping.com/cloud-bfskoi4ktkmd5ow87ubu/models
mkdir -p audio skies models

declare -A AUDIO=(
 [amb_city.ogg]=audio/realistic/ambient/town_crowd.ogg
 [amb_forest.ogg]=audio/realistic/ambient/forest_birds.ogg
 [amb_beach.ogg]=audio/realistic/ambient/ocean_surf.ogg
 [music.ogg]=audio/realistic/music/calm_town.ogg
 [door_open.ogg]=audio/realistic/sfx/door_open.ogg
 [door_close.ogg]=audio/realistic/sfx/door_close.ogg
 [foot1.ogg]=audio/realistic/sfx/foot_dirt1.ogg
 [foot2.ogg]=audio/realistic/sfx/foot_dirt2.ogg
)
for dst in "${!AUDIO[@]}"; do curl -sfL "$O/${AUDIO[$dst]}" -o "audio/$dst" && echo "ok audio/$dst"; done

curl -sfL "$O/skies/ph_kloofendal_38d_partly_cloudy_puresky.hdr" -o skies/coast_sky.hdr && echo "ok skies/coast_sky.hdr"

# Custom Meshy landmarks (subway entrance, plaza fountain, vendor NPC).
for m in subway_entrance fountain npc_vendor; do
  curl -sfL "$MESHY/$m.glb" -o "models/$m.glb" && echo "ok models/$m.glb" || echo "WARN models/$m.glb unavailable"
done
