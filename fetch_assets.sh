#!/usr/bin/env bash
# Fetch the CC0/CC-BY audio beds this game bundles (models stream from R2 at runtime).
# Run from the project root. Audio is small (~1.5 MB) and shipped inside the .pck.
set -euo pipefail
O=https://preview.myapping.com/godot-assets
mkdir -p audio
declare -A MAP=(
 [amb_city.ogg]=audio/realistic/ambient/town_crowd.ogg
 [amb_forest.ogg]=audio/realistic/ambient/forest_birds.ogg
 [amb_beach.ogg]=audio/realistic/ambient/ocean_surf.ogg
 [music.ogg]=audio/realistic/music/calm_town.ogg
 [door_open.ogg]=audio/realistic/sfx/door_open.ogg
 [door_close.ogg]=audio/realistic/sfx/door_close.ogg
 [foot1.ogg]=audio/realistic/sfx/foot_dirt1.ogg
 [foot2.ogg]=audio/realistic/sfx/foot_dirt2.ogg
)
for dst in "${!MAP[@]}"; do
  curl -sfL "$O/${MAP[$dst]}" -o "audio/$dst" && echo "ok $dst"
done
