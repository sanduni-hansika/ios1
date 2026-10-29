# From zero to a working, demo-ready AgriNova – every small step

> Honest status: this code has never been compiled or run by its author (no Mac/Xcode available). Work through the steps in order.
> Do **not** skip Part 3 (the model) – without it the scanner shows "AI model not installed".
> Tick each ✅ box only after you have *seen it work yourself*; those ticks are your evidence for the viva.

## Part 0 – What you need
- A Mac with **Xcode 16 or newer** (App Store). First launch: let it install extra components. Add an iOS 17+ simulator (Xcode ▸ Settings ▸ Platforms).
- Apple ID signed in (Xcode ▸ Settings ▸ Accounts). A **paid** Apple Developer account is only needed for iCloud sync, Sign in with Apple and widget live-data (App Group).
- A real iPhone (strongly recommended: camera, Face ID, geofencing) and, if possible, an iPad.
- Internet (Open-Meteo, Firebase, MapKit tiles/routes).

## Part 1 – Open the project (Xcode only – no XcodeGen needed)
1. Unzip `AgriNova_Xcode_Project_v5.zip` and double-click **`AgriNova.xcodeproj`**.
2. Follow **`docs/MANUAL_XCODE_SETUP.md` Part A** (choose your Team, bundle ids, free-account entitlements, add the model). If Xcode cannot open the project, use **Part B** (build it yourself, 15 min).
3. (Only if you have XcodeGen) `./scripts/bootstrap.sh` regenerates the project from `project.yml`; it is optional.

## Part 2 – First build (expect a few errors)
1. Pick **iPhone 15/16** simulator at the top, press **⌘B**.
2. Red errors? Click the red icon in the left Issue navigator, copy the full message + file/line into your AI assistant, apply the fix, build again. Repeat until it says **Build Succeeded**. (Typical: a missing `import`, a type-check "expression too complex", an API name.)
3. Press **⌘R**. You should see the animated splash → language chips → onboarding → sign-in. ✅

## Part 3 – The Core ML model (the one thing the app cannot work without)
Pick ONE path.
**Path 0 – pre-trained MobileNetV2 (recommended, no training)**: `docs/ML_MODEL_GUIDE.md` Path 0 – model `linkanjarad/mobilenet_v2_1.0_224-plant-disease-identification` on Hugging Face (PlantVillage, 38 classes, 95.4 % reported accuracy). Run `python ml/convert_huggingface_mobilenetv2.py --check` → copy `ml/AgriNovaLeaf.mlpackage` to `AgriNova/Resources/Models/`.
**Path A – Create ML (no code, ~20 min)**
1. Terminal: `./scripts/prepare_dataset.sh 600` → creates `ml/dataset/<10 class folders>` (600 images each). Do not rename the folders.
2. Xcode menu ▸ **Open Developer Tool ▸ Create ML** ▸ **New Document** ▸ template **Image Classifier** ▸ name it `AgriNovaLeaf` ▸ Next.
3. Left panel **Training Data** ▸ click the box ▸ choose the `ml/dataset` folder. Create ML lists 10 classes.
4. Under **Parameters** tick augmentations: *Crop, Rotate, Blur, Exposure, Flip*. Max iterations 25+.
5. Click **Train** (top). Wait. Look at **Validation accuracy** (≥ 90 % is good for PlantVillage). Screenshot it for your report.
6. **Preview** tab: drag a few leaf photos to sanity-check.
7. **Output** tab ▸ **Get** ▸ save as `AgriNovaLeaf.mlmodel` (name must be exactly this).
8. Move it into `AgriNova/Resources/Models/` ▸ run `./scripts/bootstrap.sh` again ▸ ⌘B.
**Path B – train MobileNetV2 yourself**: see `docs/ML_MODEL_GUIDE.md` Path B. Produces `ml/AgriNovaLeaf.mlpackage`.

**Prove Core ML works (do this every time you change the model)**
1. Run the app ▸ sign up ▸ Settings ▸ **Seed Data console** ▸ tap **Classify all 10 samples**.
2. The log must show 10 lines like `🔬 Early Blight → predicted Early Blight (96%)`. Count correct ones; ≥ 8/10 is fine.
3. Wrong labels everywhere? The model's class names don't match (they must be the folder names above). Wrong only sometimes? Train longer / more images.
4. Open **Scan** ▸ *Choose photo* ▸ pick a leaf photo ▸ you should see result card, confidence ring, symptoms. A blurry/dark photo should show the quality warning. A random non-leaf photo should give low confidence → "Not sure yet / scan again" (the 54 % rule). ✅ ✅ ✅

## Part 4 – Test every advanced feature (what "working" means)
**Core ML + Vision (iPhone and iPad)** – same code on both. iPad: run the iPad Pro simulator, repeat the proof above; the result screen shows two columns in landscape. Camera: real devices only.
**Camera (AVFoundation) + Photos (PhotosUI)** – real iPhone/iPad only: Scan ▸ *Take photo* ▸ allow the camera ▸ full-screen live camera with a leaf frame. Cover the lens partly / go to a dark corner → chip says *Too dark*; shake the phone → *Blurry*; normal light → *Good light – hold steady* ✅. Tap the screen to focus, ⚡ torch, big shutter. Rotate the iPad: preview and photo stay upright ✅. Deny camera permission once → the screen offers *Open iOS Settings* ✅. Simulator has no camera: use *Choose photo* (PhotosUI) ✅.
**Core Data** – Create a farm ▸ add a zone ▸ do a scan ▸ stop the app (swipe away) ▸ reopen ▸ all still there ✅. Offline: turn on Airplane Mode and repeat – works.
**Face ID / Touch ID** – Simulator: Features ▸ Face ID ▸ **Enrolled**. Sign up with username/password ▸ Settings ▸ Sign out ▸ tap the **Face ID** icon ▸ Features ▸ Face ID ▸ **Matching Face** ✅. (It signs in the *last user on the device*.)
**Open-Meteo weather** – Dashboard card shows temperature, humidity, rain %, fungal risk; pull to refresh ✅. Airplane mode → shows "Saved data" chip.
**Local notifications** – Settings ▸ Notifications ▸ *Send a test notification* ✅. Seed console ▸ *Schedule a re-check reminder in 10 s*, press Home, wait ✅. Real flow: scan a diseased leaf ▸ Start treatment plan ▸ reminders for day 3/7/14 are scheduled.
**Firebase Authentication + Firestore (real accounts, access tokens, shared reports)** – without keys the app uses device-only accounts + a demo backend.
  1. Follow `docs/BACKEND_SETUP.md` steps 1–6 (create project, enable Email/Password, create Firestore, publish the rules, paste Project ID + Web API key into `OutbreakBackend.swift`).
  2. Rebuild and **sign up** with a new username/password ✅. Firebase console ▸ Authentication ▸ Users shows `username@users.agrinova.app` ✅. Profile ▸ Security ▸ *Account stored on: Firebase Authentication* ✅.
  3. Wrong password → red banner "Email or password is incorrect" ✅. Airplane Mode → "No internet connection" ✅.
  4. Radar ▸ report an outbreak ▸ Firestore ▸ `outbreaks` shows the document **with your uid** ✅. Delete/reinstall the app, sign in → the report comes back ✅.
  5. Access token: leave the app unused > 1 hour, reopen, pull-to-refresh on Radar – it still syncs (the token was refreshed automatically) ✅. Console ▸ Authentication ▸ disable the user → next sync shows "Sign in again so your reports can sync" ✅.
  6. Offline queue: Airplane Mode ▸ submit ▸ "waiting to upload" ▸ Airplane off ▸ uploads ✅.
  7. Google / Apple buttons: enable the providers in Firebase (Authentication ▸ Sign-in method) and complete the Google client setup (`docs/SETUP_GUIDE.md` §4). Apple needs a paid account + Sign in with Apple capability.
**Remote push (optional)** – paid account only: Signing & Capabilities ▸ + Push Notifications. After sign-in the app uploads its APNs token to Firestore `devices/<uid>` (check in console ✅). Sending pushes needs a Cloud Function (sketch in `docs/BACKEND_SETUP.md`). Local notifications work without it.
**MapKit** – Radar tab: seed reports (Settings ▸ Seed console ▸ Seed outbreak reports). Check: pins + coloured hotspots ✅; zoom out → numbered cluster bubbles, tap one to zoom ✅; layers button (◫) ▸ switch Satellite ✅, Distance ring 10 km shows "N reports within 10 km • risk" ✅, Spread timeline ▶ replays ✅, Agri services nearby (needs internet; may be empty in some areas) ✅; tap a pin ▸ **Route here in the app** draws a blue route + minutes (needs internet and a road path) ✅; *Look Around* may say "not available" – normal outside covered countries.
**Core Location + geofencing** (the guideline says alerts on **entering or leaving**; both now notify)
  1. Seed console ▸ *Create demo farm* (3 zones armed).
  2. Settings ▸ allow location **While Using**, then Farm ▸ farm ▸ **Enable** ▸ choose **Always** (real device: Settings ▸ AgriNova ▸ Location ▸ Always).
  3. Simulator: keep the app running ▸ Xcode menu **Debug ▸ Simulate Location ▸ AgriNova-FarmWalk** (the GPX file is listed after you add it; if it is missing, Xcode ▸ Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ Default Location ▸ *Add GPX file…* ▸ `AgriNova/Resources/GPX/AgriNova-FarmWalk.gpx`).
  4. Within ~1 minute: banner "Entered Tomato Block A", a farm-log entry, later "Left …" ✅. Simulator region events can be flaky – **confirm on a real iPhone** by walking/driving or using the same GPX from Xcode with the phone connected.
**WidgetKit** – Needs the App Group (paid account). Run the app once (do a scan) ▸ Home Screen long-press ▸ **+** ▸ AgriNova ▸ add small/medium; Lock Screen: long-press ▸ Customize ▸ add AgriNova ✅. After new scans the widget refreshes (can take a few minutes; Seed console ▸ *Refresh widgets*). Free account: widget shows placeholder only.
**Siri / App Intents** – Shortcuts app ▸ search AgriNova ▸ run "Scan a leaf", "Last scan result", "Check fungal risk" ✅. Say: "Hey Siri, check fungal risk in AgriNova" on a real device.
**CloudKit** – paid account only. Xcode ▸ target ▸ Signing & Capabilities ▸ **+ Capability ▸ iCloud ▸ CloudKit** ▸ tick container `iCloud.<your id>`. Sign into iCloud on two devices (Settings ▸ [your name]). In the app: Settings ▸ Sync ▸ **iCloud sync ON ▸ close and reopen the app** on both. Create a farm on device 1 ▸ it should appear on device 2 within minutes ✅. If nothing syncs: check CloudKit Dashboard (icloud.developer.apple.com) for errors and that both devices use the same Apple ID. This is the riskiest feature – if you cannot verify it, say so honestly in the report.
**PDFKit** – open a scan result ▸ *PDF report* ▸ view ▸ share ✅.
**Charts** – Insights tab after ≥ 5 scans ✅.
**Localization** – Splash chips: Sinhala / Tamil ▸ all screens change. Have a native speaker review the text.
**Accessibility** – Xcode ▸ Open Developer Tool ▸ **Accessibility Inspector** ▸ point at the simulator ▸ run *Audit*; fix warnings. Simulator Settings ▸ Accessibility ▸ Display & Text Size ▸ Larger Text (drag to max) ▸ no clipped text ✅. VoiceOver: on a real phone triple-click side button, swipe through the dashboard and the result screen.
**iPad adaptation** – iPad simulator: sidebar + split layout; rotate; Slide Over / Split View; screenshot for your LO1 reflection.

## Part 5 – Unit tests (Swift Testing)
1. Press **⌘U**. All suites in `AgriNovaTests` run. Fix failures one by one (a failure tells you the file/line).
2. Screenshot the green Test navigator for your report. Don't claim tests you haven't seen pass.

## Part 6 – Make the proposal wording match the code (the viva will check)
| Your text says | The app really does | What to write |
|---|---|---|
| "AVFoundation … leaf capture through the camera" | ✅ **now true** – `CameraService`/`LeafCameraView` (AVCaptureSession, live quality hint) + PhotosUI | keep |
| "local notifications **and push notifications**" | local ✅; push = **client registration + token upload** ✅, but *sending* pushes needs a Cloud Function (sketch only) and a paid account | write "local notifications; remote push registration implemented, server sender documented" |
| "Apple's localization team handles English, Sinhala, Tamil" | in-app translation table `Strings.swift`, AI-assisted, runtime switching | write "custom runtime localisation (EN/SI/TA), reviewed by a native speaker" |
| "MobileNetV2 … once it is obtained" | ✅ Path 0 converts a real MobileNetV2 (Hugging Face) | keep; cite the model + licence |
| "the map now reflects actual user contributions" | ✅ only after Firebase keys are set | configure Firebase before recording the demo |
| Authentication | ✅ real Firebase Authentication (ID + refresh tokens in Keychain, Bearer tokens to Firestore) when keys are set; device-only otherwise | say which mode your demo uses |
| MVP platform features | Component 2 needs 2 of 3 | claim **Core Data + Face ID/Touch ID** (+ local notifications as bonus) |

## Part 7 – Submission checklist (from the coursework sheet)
- ☐ Xcode project builds on a clean machine (zip with all resources) ☐ **GitHub private repo**, lecturer added, final **commit hash** noted
- ☐ Narrated screen recording (features in the order of the demo script in `docs/REPORT_AND_VIVA_GUIDE.md`)
- ☐ Final report (overview, process, challenges, advanced features + rationale, **LO1–LO4 reflection**, AI-use declaration)
- ☐ Unit-test screenshot ☐ Accessibility evidence ☐ iPhone + iPad screenshots ☐ Be ready for the live viva: explain any file you submit.
