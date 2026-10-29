# Final report outline + viva preparation

## Report outline (Component 4)
1. **App overview** – problem (Sri Lankan smallholder tomato farmers, language barrier, weak internet), users, USP, screenshots (iPhone + iPad).
2. **Development process** – Figma prototype → MVP → advanced SDKs; architecture diagram (MVVM: Views → ViewModels → Services → Core Data/Backend); git history.
3. **Challenges** – model accuracy vs field photos; geofence 20-region limit; offline queue/idempotent uploads (409 = success); CloudKit schema rules (optional attributes); localisation of 3 scripts; widget data via App Group.
4. **Advanced iOS features & rationale (Component 3)** – Core ML + Vision (classification, saliency crop, plant gate), MapKit (clustering, hotspots, routing, local search, Look Around, timeline) + Core Location geofencing, App Intents, WidgetKit (home + lock), CloudKit. Explain *why each is deeply integrated* (workflow: Scan → Core ML → Result → Farm Log → Treatment → Geofence reminder → Community map).
5. **Mandatory platform features (Component 2: pick 2 of 3)** – Core Data (persistence + sync queue) and Face ID/Touch ID (+ local notifications). *These cannot be claimed for Component 3.*
6. **External API/backend** – Open-Meteo REST (weather → risk + spray timing) and Firebase Firestore REST (shared outbreaks).
7. **Testing** – Swift Testing suites (list), what they cover, results screenshot; manual tests: offline/online, GPX geofence, Dynamic Type, VoiceOver, iPad rotation, languages.
8. **Accessibility** – VoiceOver labels/values, Dynamic Type (all fonts use text styles), icon+text status, 44-pt targets, contrast in dark mode, reduce-motion friendly (no essential animation).
9. **LO reflection** – LO1 platform components across devices (tab bar ↔ sidebar split view, adaptive grids, readable widths, widgets/Siri as extra surfaces); LO2 architecture (MVVM, protocol `OutbreakBackend`, DI-ready services); LO3 external APIs; LO4 sensors (camera, GPS/geofencing, biometrics).
10. **AI-use declaration** – state which AI tools generated which parts and what you changed/verified yourself.
11. **Limitations & future work** – see FEATURE_CHECKLIST "Not done".

## Marking map (aim for 80+)
| Component | Evidence to show |
|---|---|
| C2 MVP (20 %) | Core Data persistence across relaunch, Face ID login, Open-Meteo + Firestore live data, clean MVVM |
| C3 Advanced (20 %) | Live model inference on sample + camera photos, geofence trigger via GPX, live map from backend, widget + Siri |
| C4 Tests/Access/Docs (15 %) | ⌘U green, VoiceOver demo, report |
| C5 Above & beyond (25 %) | iPad sidebar vs iPhone tab bar side by side, offline queue demo, quality gate, polish/animations, 3 languages |
| C1/C6 | your Figma + tutorial (not in this zip) |

## Extra viva questions for the new parts
- How does your access-token flow work? (ID token 1 h → Bearer on Firestore; refresh token in Keychain; `AuthSession.validIDToken()` refreshes ~60 s before expiry; rules check `request.auth.uid`.)
- Why synthetic e-mails for usernames and what is the downside? (no password-reset mail.)
- Why does Apple sign-in use a nonce? (replay protection: SHA-256 in the token, raw value verified by Firebase.)
- How does the live camera hint work? (video frames → luma plane → same Laplacian-variance/brightness maths as `ImageQualityChecker`, ~3 fps.)
- Why a pre-trained MobileNetV2 and how do you keep non-tomato predictions out? (`DiseaseCatalog.find` rejects other crops; `ScanViewModel` shows "not a tomato leaf".)

## Seed-data rule (important)
*seed → Apple SDK → app logic ✅*: samples go through Vision/Core ML; location through Core Location GPX; notifications through UNUserNotificationCenter. Do **not** insert hard-coded scans/outbreaks directly into UI state. (Outbreak seeding goes through the real sync pipeline.)

## 3-minute demo script
Splash+language → sign up → Face ID → Dashboard (weather + risk) → Library card → disease detail → Scan (library photo) → quality warning example (blurry photo) → result + symptoms → low-confidence example → start treatment → tick tasks → add re-check → trend chart ↓ → report outbreak offline → reconnect → live map → farm zones + GPX geofence notification → Insights → PDF → widget/Siri → iPad.

## Likely viva questions
- Why is Core Data / Face ID not your Component 3 feature? (reserved for C2.)
- How does the confidence gate work and why 70 %? How could you calibrate it?
- Explain the affected-% algorithm and its limits (HSV segmentation on saliency crop; not ML).
- How does the offline queue guarantee no duplicates? (UUID doc id; Firestore 409 treated as success; outbox deleted only after success.)
- Why only 20 geofences and how do you pick them? (`prefix(20)` of enabled zones; improvement: nearest-first re-arming on significant location change.)
- How would you secure the backend in production? (App Check, Auth, rules, Cloud Functions.)
- Walk through MVVM in the scan flow: `ScanView` → `ScanViewModel` → `ScanPipeline` → `ScanStore`.
