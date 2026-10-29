#!/usr/bin/env bash
# Downloads ONLY the 10 tomato classes of the PlantVillage dataset (colour images) and builds ml/dataset/<ClassName>/*.JPG
# with up to N images per class (default 600). Needs git. Usage: ./scripts/prepare_dataset.sh [N]
set -e
N=${1:-600}
cd "$(dirname "$0")/.."
rm -rf ml/.pv && mkdir -p ml/dataset
git clone --depth 1 --filter=blob:none --sparse https://github.com/spMohanty/PlantVillage-Dataset ml/.pv
cd ml/.pv
git sparse-checkout set --no-cone '/raw/color/Tomato___*/'
cd ../..
for d in ml/.pv/raw/color/Tomato___*; do
  name=$(basename "$d")
  mkdir -p "ml/dataset/$name"
  ls "$d" | head -n "$N" | while read -r f; do cp "$d/$f" "ml/dataset/$name/"; done
  echo "$name: $(ls "ml/dataset/$name" | wc -l) images"
done
rm -rf ml/.pv
echo "✅ Dataset ready in ml/dataset (class folder names are the exact labels the app expects)."
