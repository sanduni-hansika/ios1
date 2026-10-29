#!/usr/bin/env bash
# One-command project generation for macOS.  Usage:  ./scripts/bootstrap.sh
set -e
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen with Homebrew…"
  command -v brew >/dev/null 2>&1 || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
  brew install xcodegen
fi
xcodegen generate
echo "✅ AgriNova.xcodeproj created."
if [ ! -d "AgriNova/Resources/Models/AgriNovaLeaf.mlpackage" ] && [ ! -f "AgriNova/Resources/Models/AgriNovaLeaf.mlmodel" ]; then
  echo "⚠️  No Core ML model found yet. Follow docs/ML_MODEL_GUIDE.md and put AgriNovaLeaf.mlpackage in AgriNova/Resources/Models/ then run this script again."
fi
open AgriNova.xcodeproj
