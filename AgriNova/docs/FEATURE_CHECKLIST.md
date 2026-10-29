# Feature checklist – your 34-feature list + brief (status: **implemented in code, not yet compiled/run**)

Legend: ✅ implemented · 🔧 needs your setup/keys · ⚠️ limitation

| # | Feature | Where | Status |
|---|---|---|---|
| 1 | Loading page + language (language is chosen **only on the splash screen**; Settings can change it later) | `SplashView`, `LanguagePicker` | ✅ |
| 2 | **Real authentication**: username + password via Firebase Authentication (ID + refresh tokens in Keychain, auto-refresh, Bearer tokens), icon buttons for Face ID, Touch ID, Google, Apple ID (toggle in Settings) | `AuthService`, `FirebaseAuth`, `AuthView` | ✅ code · 🔧 Firebase key needed (device-only fallback otherwise) · 🔧 Apple (paid) · 🔧 Google (client id) |
| 3 | User profile (photo, name, username, optional email/phone/district, stats, sign-in method, change password, sign out, delete account) | `ProfileView`, `EditProfileSheet`, `ChangePasswordSheet` | ✅ |
| 4 | Leaf capture: **AVFoundation camera** (live lighting/blur hint) + PhotosUI library + post-capture quality gate | `CameraService`, `LeafCameraView`, `PhotosPicker`, `ImageQualityChecker` | ✅ · 🔧 real camera only on device |
| 5 | On-device species ID + description | `LeafClassifier`, `Species` | ⚠️ tomato-only scope: a 38-class model's other crops show "not a tomato leaf" · 🔧 model (Path 0: MobileNetV2) |
| 6 | Healthy / unhealthy label | `StatusBadge`, `ScanResultView` | ✅ |
| 7 | Disease + confidence | `ConfidenceRing` | ✅ |
| 8 | Low-confidence second scan (no advice <70 %) | `ScanResultView.lowConfidencePanel` | ✅ threshold adjustable 50–90 % |
| 9 | Symptom matching | `Disease.symptoms` | ✅ |
| 10 | Early risk warnings | `WeatherService.fungalRisk`, banners, notification | ✅ |
| 11 | Disease-specific treatments | `Disease` + `TreatmentService` | ✅ (EN text; names/summaries trilingual) ⚠️ review agronomy with an extension officer |
| 12 | Treatment checklist | `TreatmentDetailView` | ✅ |
| 13 | Post-treatment progress 3/7/14 days | `LeafAnalyzer`, Swift Charts trend ↓/↑ | ✅ ⚠️ % is a colour-segmentation estimate, not ML |
| 14 | Re-check local notifications (+ remote push token registration) | `TreatmentService.scheduleRechecks` | ✅ |
| 15 | My Farm management (CRUD) | `FarmViews`, `FarmViewModel` | ✅ |
| 16 | Zones (map-placed) | `ZoneEditor` | ✅ |
| 17 | Infected location marking | `InfectedMarkSheet`, "Mark infected location" on result | ✅ |
| 18 | Zone **entry and exit** notifications (geofence), also after a background relaunch | `LocationService` | ✅ 🔧 "Always" permission · ⚠️ max 20 regions |
| 19 | Farm history | `HistoryView`, `CDLog` | ✅ |
| 20 | Statistics dashboard | `InsightsView` (Swift Charts) | ✅ |
| 21 | Local weather | `WeatherService` (Open-Meteo) | ✅ |
| 22 | Community outbreak radar | `ReportOutbreakSheet`, `SyncService` | ✅ 🔧 Firebase for real sharing (demo backend otherwise) |
| 23 | Live outbreak map – live pins **plus** zoom-based clustering, severity hotspots, 3 map styles, farm-zone overlays, distance ring + local risk, spread-timeline replay, in-app driving route (MKDirections) with ETA, nearby agri-service search (MKLocalSearch), Look Around street view | `RadarView`, `RadarViewModel` | ✅ (never rendered – needs on-device check) |
| 24 | Sharing | `ShareLink` (scan+image, reports, PDF) | ✅ |
| 25 | CloudKit sync | `NSPersistentCloudKitContainer` toggle | 🔧 paid account + iCloud capability |
| 26 | WidgetKit (Home + Lock Screen) | `AgriNovaWidget` | ✅ 🔧 App Group |
| 27 | Siri / App Intents | `AgriNovaIntents` | ✅ |
| 28 | PDF report | `ReportService`, `PDFKitView` | ✅ |
| 29 | Settings | `SettingsView` | ✅ |
| 30 | Light/dark | `ThemeMode`, adaptive colours | ✅ |
| 31 | EN/SI/TA | `Strings.swift` (393 strings) | ✅ ⚠️ SI/TA machine-assisted – native review needed; PDFs/notifications use same table |
| 32 | Accessibility | labels, Dynamic Type text styles, icon+text status, `accessibilityElement`, haptics | ✅ test with VoiceOver + Accessibility Inspector |
| 33 | iPhone/iPad adaptive | `MainShell` (tab bar ↔ split view), adaptive grids | ✅ |
| 34 | Offline sync queue | `CDOutbox`, `SyncService` (NWPathMonitor) | ✅ |

## Extra "Above & Beyond" features I added
Single-screen onboarding · Profile screen with photo · Photo-quality gate · Vision saliency crop · spray-timing advice from hourly weather · zone-aware scanning · "test model with sample photo" from the library ·
Seed Data console (SDK-flow compliant) · hotspot circles by severity · directions to an outbreak · lock-screen widgets · 5 Siri shortcuts · haptics/sensory feedback · toasts/skeleton loaders/empty & error states.

## Not done / out of scope (be upfront in viva)
- Remote push (APNs): brief allows local notifications. · Extension-officer web dashboard (data is available in Firestore).
- Multi-crop models (scope limited to tomato family per proposal). · Real field-photo accuracy testing.
- Production App Store hardening (App Check, auth-gated writes, crash reporting, privacy manifest) – listed as future work.
