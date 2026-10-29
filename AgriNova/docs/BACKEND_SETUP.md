# Backend – Firebase Authentication + Firestore (+ optional remote push)

The coursework's mandatory "external API / backend" is met by **Open-Meteo REST** (weather, no key) and **Firebase** (accounts + shared outbreak reports).
With no keys the app still runs: accounts live on the device (Keychain) and reports go to an on-device demo backend – both clearly labelled
(Profile ▸ "Account stored on", Settings ▸ Sync ▸ Backend). Real sign-in, access tokens and shared reports need the steps below.

## How the real authentication works (what to explain in the viva)
1. Sign-up / sign-in sends the username (mapped to `<username>@users.agrinova.app`) and password over HTTPS to **Firebase Authentication** (Identity Toolkit REST API). Passwords are never stored by the app.
2. Firebase returns an **ID token** (JWT, valid 1 hour) and a long-lived **refresh token**. Both live in the iOS **Keychain** (`AuthSession`).
3. Every Firestore request carries `Authorization: Bearer <ID token>`. `AuthSession.validIDToken()` refreshes the token automatically (securetoken API) about a minute before it expires, so users stay signed in.
4. Security rules check `request.auth` – anonymous requests are rejected. Reports store the reporter's `uid`.
5. Google and Apple sign-in exchange the provider's ID token with Firebase (`signInWithIdp`; Apple uses a SHA-256 nonce against replay). Face ID / Touch ID simply unlock the stored session.

## Steps (0 → hero)
1. https://console.firebase.google.com → **Add project** (name e.g. `agrinova-xxxxx`; Analytics can be off).
2. **Build ▸ Authentication ▸ Get started ▸ Sign-in method ▸ Email/Password ▸ Enable ▸ Save**. (Optional: enable **Google** and **Apple** providers – Apple needs your Apple Developer Services ID; Google needs the project's iOS client.)
3. **Build ▸ Firestore Database ▸ Create database ▸ Production mode** ▸ choose a nearby region (e.g. `asia-south1`).
4. **Rules** tab ▸ paste the rules below ▸ **Publish**.
5. **Project settings (⚙) ▸ General**: copy **Project ID** and **Web API Key**.
6. Paste them in `AgriNova/Services/OutbreakBackend.swift`:
   `static let firebaseProjectID = "agrinova-xxxxx"` and `static let firebaseWebAPIKey = "AIza…"`.
   (Optional hardening: Google Cloud Console ▸ APIs & Services ▸ Credentials ▸ restrict the key to your iOS bundle id.)
7. Rebuild, **sign up** (a new account – device-only accounts made before are not Firebase accounts). Check: Firebase console ▸ Authentication ▸ Users shows your `username@users.agrinova.app` ✅.
8. Profile ▸ Security should say **Account stored on: Firebase Authentication** ✅. Settings ▸ Sync ▸ Backend: **Firebase Firestore** ✅.
9. Radar ▸ report an outbreak ▸ Firestore ▸ `outbreaks` shows the document with your `uid` ✅. Delete + reinstall the app, sign in, Radar shows it again ✅.
10. Offline queue: Airplane Mode ▸ submit ▸ "waiting to upload" ▸ Airplane off ▸ uploads automatically ✅.

## Firestore security rules (signed-in users only)
```
rules_version = '2';
service cloud.firestore { match /databases/{db}/documents {
  match /outbreaks/{id} {
    allow read: if request.auth != null;
    allow create: if request.auth != null
      && request.resource.data.uid == request.auth.uid
      && request.resource.data.severity in [1,2,3]
      && request.resource.data.notes.size() < 500;
    allow update, delete: if false;
  }
  match /devices/{uid} {                       // push-notification tokens (see below)
    allow read, write: if request.auth != null && request.auth.uid == uid;
  }
} }
```
Extension officers read documents where `sharedWithExtension == true` (Firebase console query or a small web dashboard).

## Limits to be honest about
- Usernames use synthetic e-mails, so **"forgot password" by e-mail is not possible** (no real inbox). Offer a real e-mail field + `accounts:sendOobCode` if you need it.
- I could not test any of this against a real Firebase project – the request formats follow Google's REST reference; test each step above and send me the error text if one fails.
- Sign out keeps the refresh token in the Keychain so Face ID can resume. "Delete account" removes the Firebase user.

## Remote push notifications (optional, advanced)
The app **registers for APNs and uploads its device token** to `devices/<uid>` (with location + language) after sign-in. Local notifications work regardless.
To actually send "outbreak near you" pushes you need: a paid Apple Developer account (Push Notifications capability + an APNs Auth Key `.p8`) and Firebase **Cloud Functions (Blaze plan)**. Sketch of a function (untested):
```js
// functions/index.js  – triggers when someone reports an outbreak
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin"); const apn = require("@parse/node-apn");
admin.initializeApp();
const provider = new apn.Provider({token: {key: process.env.APNS_KEY, keyId: process.env.APNS_KEY_ID, teamId: process.env.APPLE_TEAM_ID}, production: false});
exports.notifyNearby = onDocumentCreated("outbreaks/{id}", async (event) => {
  const r = event.data.data();
  const devices = await admin.firestore().collection("devices").get();
  for (const d of devices.docs) {
    const t = d.data();
    if (d.id === r.uid) continue;
    const km = haversineKm(r.latitude, r.longitude, t.latitude, t.longitude);
    if (km > 15) continue;
    const n = new apn.Notification({alert: {title: "Outbreak near you", body: `${r.diseaseLabel} reported ${km.toFixed(1)} km away`}, topic: "com.agrinova.app", payload: {route: "radar"}});
    await provider.send(n, t.apnsToken);
  }
});
```
