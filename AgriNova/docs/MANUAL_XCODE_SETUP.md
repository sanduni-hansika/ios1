# Using Xcode only (no XcodeGen) – Xcode 16 / 26

## Part A – open the included project (try this first, 2 minutes)
1. Unzip. Double-click **`AgriNova.xcodeproj`** (it is in the same folder as `README.md`).
2. Xcode opens. In the left sidebar you should see the folders **AgriNova, AgriNovaWidget, Shared, AgriNovaTests**. (They are "synchronized folders": every file inside is included automatically – you never add files by hand.)
3. Click the blue **AgriNova** project icon ▸ for each of the 3 targets (**AgriNova, AgriNovaWidget, AgriNovaTests**) ▸ **Signing & Capabilities** ▸ tick *Automatically manage signing* ▸ choose your **Team** (your Apple ID: Xcode ▸ Settings ▸ Accounts ▸ +).
4. Change the bundle ids if Xcode says they are taken: AgriNova `com.agrinova.app` → e.g. `com.yourname.agrinova`; widget `…​.widget`; tests `…​.tests` (Signing & Capabilities ▸ Bundle Identifier). If you change the app id also change the **App Group** and **iCloud container** names (steps below) and the two matching strings in code: `SharedStore.groupID` (Shared/WidgetSnapshot.swift) and `PersistenceController.cloudContainerID`.
5. **Free Apple ID (no paid developer account)?** Replace the two entitlement files with empty ones, otherwise signing fails:
   copy `scripts/entitlements-free/AgriNova.entitlements` over `AgriNova/AgriNova.entitlements`, and `scripts/entitlements-free/AgriNovaWidget.entitlements` over `AgriNovaWidget/AgriNovaWidget.entitlements`. (You lose iCloud sync, Sign in with Apple, push registration and live widget data; everything else works.)
   **Paid account?** Keep them; make sure the capabilities appear under Signing & Capabilities (App Groups, iCloud ▸ CloudKit, Push Notifications, Sign in with Apple) – if a capability shows a red error, click "Try again" / register the container.
6. Pick an **iPhone 16** (or any iOS 17+) simulator at the top ▸ press **⌘B** to build. Fix errors one by one (copy the red message to your AI assistant).
7. Optional: **Google sign-in** needs a package. File ▸ Add Package Dependencies ▸ `https://github.com/google/GoogleSignIn-iOS` ▸ add the *GoogleSignIn* product to the **AgriNova** target. If your PC blocks GitHub downloads skip this – the app builds fine and the Google icon says "not set up".
8. Add the Core ML model: drag `AgriNovaLeaf.mlpackage` into the **AgriNova/Resources/Models** folder in Xcode (tick *Copy items if needed*, target **AgriNova** ✓). Then ⌘R.

If Xcode reports **"project is damaged" / cannot open** (I generated the file without being able to test it in Xcode) → do Part B.

## Part B – build the project yourself in Xcode (15 minutes, always works)
1. Xcode ▸ **File ▸ New ▸ Project ▸ iOS ▸ App** ▸ Product Name **AgriNova**, Team = yours, Organization Identifier `com.agrinova`, Interface **SwiftUI**, Language **Swift**, Storage **None**, Testing System **Swift Testing**. Save it in a NEW empty folder (e.g. `Desktop/AgriNova-xcode`).
2. In the sidebar delete the template files **ContentView.swift**, **AgriNovaApp.swift** and the template **Assets.xcassets** (Move to Trash). Also delete the template test file inside AgriNovaTests.
3. Add my code: in Finder open the unzipped `AgriNova/AgriNova` folder, select **App, Core, Intents, Models, Persistence, Resources, Services, ViewModels, Views, Assets.xcassets** and drag them onto the yellow **AgriNova** group in Xcode ▸ tick **Copy items if needed**, **Create groups**, Add to targets: **AgriNova** only ▸ Finish.
4. Drag `Shared/WidgetSnapshot.swift` in the same way (target AgriNova ✓).
5. **Widget:** File ▸ New ▸ Target ▸ iOS ▸ **Widget Extension** ▸ Product Name **AgriNovaWidget** ▸ untick *Include Live Activity* and *Include Configuration App Intent* ▸ Finish ▸ (Activate scheme? **Cancel**). Delete all template files Xcode created in the AgriNovaWidget group. Drag my `AgriNovaWidget/AgriNovaWidget.swift` in (target **AgriNovaWidget** only). Click `WidgetSnapshot.swift` ▸ right panel File Inspector ▸ Target Membership: tick **both** AgriNova and AgriNovaWidget.
6. **Tests:** drag my `AgriNovaTests/AgriNovaTests.swift` into the AgriNovaTests group (target AgriNovaTests only).
7. **Build settings – very important for Xcode 26.** Click the project ▸ for each target ▸ *Build Settings* ▸ search and set:
   - **iOS Deployment Target** = 17.0
   - **Swift Language Version** = Swift 5
   - **Default Actor Isolation** = **nonisolated** (Xcode 26 new projects default to MainActor, which breaks this code)
   - **Approachable Concurrency** = No
   - **Targeted Device Family** = iPhone, iPad
8. **Info.plist:** drag my `AgriNova/Info.plist` into the AgriNova group (untick all targets in the dialog), then AgriNova target ▸ Build Settings: **Generate Info.plist File = No**, **Info.plist File = `AgriNova/Info.plist`** (path as shown in Xcode). Do the same for the widget with `AgriNovaWidget/Info.plist`. (They contain the camera / location / Face ID texts, orientations, languages.)
9. **Capabilities** (paid account only – free account: skip, no entitlements file needed): AgriNova target ▸ Signing & Capabilities ▸ **+ Capability** ▸ **App Groups** (`group.com.agrinova.app`), **iCloud** (tick CloudKit, container `iCloud.com.agrinova.app`), **Push Notifications**, **Sign in with Apple**. Widget target ▸ **App Groups** with the same group.
10. Bundle identifiers: app `com.agrinova.app`, widget `com.agrinova.app.widget`, tests `com.agrinova.app.tests` (the widget id MUST start with the app id).
11. ⌘B, fix errors, ⌘R. Run tests with ⌘U.
12. For GitHub: copy `docs/`, `ml/`, `scripts/`, `README.md`, `.gitignore` next to your new `AgriNova.xcodeproj` and push that folder.
