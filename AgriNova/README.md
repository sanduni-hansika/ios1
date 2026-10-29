# 🌿 AgriNova – Precision Farm & Crop Health Companion (iOS 17+, iPhone + iPad)

SwiftUI · MVVM · Core ML + Vision · Core Data · CloudKit · Core Location geofencing · MapKit · WidgetKit · App Intents (Siri) · PDFKit · Swift Charts · Open-Meteo · Firebase Firestore (REST) · Swift Testing

> **Read this first – honest status.** This project was generated without a Mac/Xcode, so it has **never been compiled or run**.
> Expect to fix a few small compile errors on first build (paste them to your AI assistant). Two things also need *you*:
> 1. **the Core ML model** (docs/ML_MODEL_GUIDE.md – no trained model is included; Path 0 converts a real pre-trained MobileNetV2 from Hugging Face, untested), and
> 2. **your own accounts/keys** (Apple team, Firebase Auth + Firestore, Google) – see docs/SETUP_GUIDE.md and docs/BACKEND_SETUP.md. Everything degrades gracefully until you add them (device-only accounts + demo backend).

## Start here: docs/STEP_BY_STEP_TO_WORKING.md (every small step, per feature)

## Quick start (10 minutes + model training)
**No XcodeGen? (e.g. a locked-down PC with only Xcode)** – the zip already contains **`AgriNova.xcodeproj`**: just double-click it. Steps + a from-scratch fallback: **docs/MANUAL_XCODE_SETUP.md**.
**Have XcodeGen?** `./scripts/bootstrap.sh` regenerates the project from `project.yml` (optional).
1. (XcodeGen users) In Xcode select each target (AgriNova, AgriNovaWidget, AgriNovaTests) → *Signing & Capabilities* → choose your Team and change the bundle ids / App Group / iCloud container if needed.
   *Free Apple ID?* run `python3 scripts/free_account_mode.py` first (removes iCloud, Sign in with Apple, App Group).
2. Train/convert the model (docs/ML_MODEL_GUIDE.md) and put `AgriNovaLeaf.mlpackage` in `AgriNova/Resources/Models/`, re-run `./scripts/bootstrap.sh`.
3. Run on an iPhone simulator → Settings ▸ **Seed Data console** → *Create demo farm*, *Classify all 10 samples*, *Seed outbreak reports*.
4. Run the tests: ⌘U (Swift Testing).
5. Geofence demo: Debug ▸ Simulate Location ▸ **AgriNova-FarmWalk** (GPX in `AgriNova/Resources/GPX`).

## Folder map
| Folder | What it holds |
|---|---|
| `AgriNova/App` | `@main`, root flow (splash → onboarding → auth → shell) |
| `AgriNova/Core` | theme (soft-3D design system), settings, localisation (`Strings.swift`, EN/SI/TA) |
| `AgriNova/Models` | `Disease` catalogue (10 classes, trilingual names) |
| `AgriNova/Persistence` | Core Data model built in code (+CloudKit option) |
| `AgriNova/Services` | Core ML/Vision pipeline, weather, location+geofencing, notifications, backend + sync queue, auth, PDF, seed |
| `AgriNova/ViewModels` | MVVM view models (scan, dashboard, farm CRUD, radar, insights, auth) |
| `AgriNova/Views` | SwiftUI screens (adaptive iPhone tab bar / iPad sidebar) |
| `AgriNova/Intents` | Siri / Shortcuts via App Intents |
| `AgriNovaWidget` | Home-Screen + Lock-Screen widgets |
| `AgriNovaTests` | Swift Testing suites |
| `ml/` `scripts/` | model training/conversion and helper scripts |
| `docs/` | setup, ML guide, backend guide, feature checklist, report template, viva guide |

## Third-party code & data
PlantVillage dataset (training/sample images, CC0 per the dataset's repo) · GoogleSignIn-iOS (optional SPM package) · Open-Meteo API.
Declare AI-assistance in your report as your module's integrity policy requires.
