import UIKit

/// Client side of **remote push notifications** (APNs). The app registers, stores the device token and uploads it to
/// Firestore (`devices/<uid>`) together with the farmer's area. A server-side Cloud Function (see docs/BACKEND_SETUP.md)
/// can then push "outbreak near you" alerts even when the app is closed. Local notifications keep working without any of this.
/// Needs the Push Notifications capability (paid Apple Developer account) – without it iOS simply reports a registration failure.
enum PushRegistration {
    private static let tokenKey = "apns.token"

    @MainActor static func register() { UIApplication.shared.registerForRemoteNotifications() }

    static func didReceive(deviceToken: Data) {
        UserDefaults.standard.set(deviceToken.map { String(format: "%02x", $0) }.joined(), forKey: tokenKey)
        uploadPendingToken()
    }

    /// Uploads the stored token once a Firebase session exists (also called right after sign-in).
    static func uploadPendingToken() {
        guard BackendConfig.isConfigured, AuthSession.shared.isSignedIn, let uid = AuthSession.shared.uid,
              let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        Task { await upload(token: token, uid: uid) }
    }

    private static func upload(token: String, uid: String) async {
        do {
            let idToken = try await AuthSession.shared.validIDToken()
            let here = await MainActor.run { LocationService.shared.coordinate }
            let lang = await MainActor.run { AppSettings.shared.language.rawValue }
            var c = URLComponents(string: "https://firestore.googleapis.com/v1/projects/\(BackendConfig.firebaseProjectID)/databases/(default)/documents/devices/\(uid)")!
            c.queryItems = ["apnsToken", "platform", "latitude", "longitude", "language", "updatedAt"].map { URLQueryItem(name: "updateMask.fieldPaths", value: $0) }
            var req = URLRequest(url: c.url!)
            req.httpMethod = "PATCH"; req.timeoutInterval = 20
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["fields": [
                "apnsToken": ["stringValue": token], "platform": ["stringValue": "ios"],
                "latitude": ["doubleValue": here.latitude], "longitude": ["doubleValue": here.longitude],
                "language": ["stringValue": lang], "updatedAt": ["timestampValue": ISO8601DateFormatter().string(from: Date())]
            ]])
            _ = try await URLSession.shared.data(for: req)
        } catch { print("Push token upload failed: \(error.localizedDescription)") }
    }
}
