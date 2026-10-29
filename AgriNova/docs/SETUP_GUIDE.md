# Setup guide (macOS, Xcode 16+, iOS 17+ simulator or device)

## 1. Open the project
**Xcode only:** double-click `AgriNova.xcodeproj` and follow docs/MANUAL_XCODE_SETUP.md. *(The XcodeGen route below is optional.)*

### XcodeGen route (optional)
`./scripts/bootstrap.sh` (installs XcodeGen via Homebrew, creates `AgriNova.xcodeproj`). Re-run it whenever you add/remove files or change `project.yml`.
If Xcode shows compile errors on first build, fix them one by one (copy the red error text to your AI assistant) – the code has not been compiled by its author.

## 2. Signing & capabilities
| Capability | Needs paid account? | Where used | If you skip it |
|---|---|---|---|
| App Groups `group.com.agrinova.app` | usually yes | widget reads live app data | widget shows placeholder data |
| iCloud (CloudKit) `iCloud.com.agrinova.app` | yes | Settings ▸ iCloud sync | leave the toggle off |
| Sign in with Apple | yes | auth screen button | use password / Face ID / Google |
| Push Notifications | yes | remote push token registration | local notifications still work |
| Location (When in use + Always) | no | geofencing | – |
| Local notifications | no | reminders | – |
Change bundle ids if `com.agrinova.app` is taken (also edit the group/container ids in `project.yml`, `SharedStore.groupID`, `PersistenceController.cloudContainerID`).
Free Apple ID → run `python3 scripts/free_account_mode.py` then `./scripts/bootstrap.sh`.

## 3. Core ML model → docs/ML_MODEL_GUIDE.md (mandatory for scanning)

## 4. Optional services
- **Firebase Authentication + Firestore** (real accounts, access tokens, shared reports) → docs/BACKEND_SETUP.md
- **Google sign-in**: console.cloud.google.com ▸ APIs & Services ▸ Credentials ▸ OAuth client ID (iOS, your bundle id). In `project.yml` set `GIDClientID` to the client id and the URL scheme to the *reversed* client id (`com.googleusercontent.apps.<digits-hash>`), regenerate. Until then the Google button shows a friendly "not set up" message.
- **iCloud sync**: enable iCloud ▸ CloudKit capability, sign in to iCloud on the device/simulator, switch the toggle on in Settings and relaunch. In CloudKit Dashboard deploy the schema to Production before release.

## 5. Running the demo
1. Settings ▸ Seed Data console ▸ *Create demo farm* (Core Data → geofences armed).
2. *Classify all 10 samples* (PlantVillage photos → Vision → Core ML → saved scans, history, widget).
3. *Seed outbreak reports* (outbox queue → backend → live map). Turn on Airplane Mode, report an outbreak, turn it off: it uploads automatically (Radar shows "waiting to upload").
4. Geofence: grant *Always* location (Farm detail ▸ Enable), run the app, Xcode ▸ Debug ▸ Simulate Location ▸ *AgriNova-FarmWalk*. A local notification + farm log entry appears when you enter *Tomato Block A*.
5. Siri: Shortcuts app ▸ AgriNova, or say "Scan a leaf with AgriNova". Widgets: long-press Home Screen ▸ + ▸ AgriNova (also Lock Screen).
6. Face ID in simulator: Features ▸ Face ID ▸ Enrolled, then use *Matching Face*.
7. Real camera: run on a physical iPhone (simulator has no camera; "Choose photo" works there).
8. iPad: run on an iPad simulator (sidebar layout) and rotate/split-screen.
9. Languages: switch on the splash/onboarding screen or Settings; Dynamic Type: Settings ▸ Accessibility ▸ Larger Text; VoiceOver: Accessibility Inspector.

## 6. Troubleshooting
- *"AI model not installed"* → add `AgriNovaLeaf.mlpackage` (step 3).
- Widget empty → App Group not provisioned (see table) or run the app once.
- No location alerts → need *Always* permission and a GPX/real movement; max 20 regions.
- Sign in with Apple fails in simulator → sign in to an Apple ID in the simulator's Settings.

## 7. What changed in this revision (your 6 requests)
1. Language is chosen **only on the splash screen** (still changeable later in Settings ▸ Language).
2. Sign-in screen = username + password form, plus icon buttons for **Face ID, Touch ID, Google, Apple ID**. Show/hide each icon in Settings ▸ Quick sign-in. Face ID / Touch ID sign in the *last user on the device*, so sign in once with a password first. Apple/Google need the setup in section 2 and 4.
3. New **Profile** screen (dashboard avatar or Settings ▸ profile card): photo, name, username, optional email/phone/district, activity stats, sign-in method, change password, sign out, delete account.
4. Trained model: none is bundled. See docs/ML_MODEL_GUIDE.md **Path 0** (convert a public pre-trained PyTorch model; untested) or Paths A/B.
5. Radar map now has: zoom-based clustering, severity hotspots, 3 map styles, farm-zone overlays, distance ring + local risk, spread-timeline replay, in-app driving route with ETA (MKDirections), nearby agri-service search (MKLocalSearch) and Look Around street view (only where Apple has coverage – may be missing in Sri Lanka, the sheet says so). Routes and place search need internet.
6. Onboarding is a single welcome screen.

## 8. What changed in v4
- **Real authentication**: Firebase Authentication (REST) with ID/refresh tokens in the Keychain, automatic token refresh, Bearer tokens on Firestore calls, Apple nonce + Google provider exchange. Device-only fallback when no key is set.
- **AVFoundation camera** with live lighting/sharpness hints, tap-to-focus, torch, correct rotation on iPhone and iPad (replaces the UIKit picker).
- **Remote push registration** (APNs token → Firestore) + documented Cloud Function.
- **Pre-trained MobileNetV2** conversion script (Hugging Face) + graceful "not a tomato leaf" handling for 38-class models; other-crop labels can no longer be mistaken for tomato diseases.
