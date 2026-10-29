import Foundation
import CryptoKit
import LocalAuthentication
import Security
import UIKit
import AuthenticationServices
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum AuthError: LocalizedError {
    case invalidUsername, invalidEmail, weakPassword, exists, notFound, wrongPassword, biometricUnavailable, biometricFailed
    case noPreviousUser, methodUnavailable, googleUnavailable, googleNotConfigured, cancelled, notPasswordAccount
    var errorDescription: String? {
        switch self {
        case .invalidUsername: tr("auth.err.username")
        case .invalidEmail: tr("prof.err.email")
        case .weakPassword: tr("auth.err.weak")
        case .exists: tr("auth.err.exists")
        case .notFound, .wrongPassword: tr("auth.err.credentials")
        case .biometricUnavailable: tr("auth.err.bio_unavailable")
        case .biometricFailed: tr("auth.err.bio_failed")
        case .noPreviousUser: tr("auth.err.no_user")
        case .methodUnavailable: tr("auth.err.method_unavailable")
        case .googleUnavailable, .googleNotConfigured: tr("auth.err.google")
        case .cancelled: tr("auth.err.cancelled")
        case .notPasswordAccount: tr("prof.pw_managed")
        }
    }
}

enum Keychain {
    private static let service = "com.agrinova.auth"
    static func set(_ data: Data, for key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q; add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
    }
}

/// Username + password auth (salted SHA-256 hashes in the Keychain), Face ID / Touch ID, Google and Apple ID sign-in.
enum AuthService {
    // MARK: Validation
    /// 3–20 letters, digits, dot or underscore.
    static func isValid(username: String) -> Bool {
        username.range(of: #"^[A-Za-z0-9._]{3,20}$"#, options: .regularExpression) != nil
    }
    static func isValid(email: String) -> Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.range(of: #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }
    static func isStrong(password: String) -> Bool { password.count >= 6 }

    private static func hash(_ password: String, salt: Data) -> Data { Data(SHA256.hash(data: salt + Data(password.utf8))) }
    private static func key(_ username: String) -> String { "pw.\(username.lowercased())" }

    // MARK: Mode
    /// True when a Firebase Web API key is configured → accounts live in Firebase Authentication and the app uses
    /// real access (ID) tokens. Otherwise the app falls back to device-only accounts (demo mode).
    static var usesFirebase: Bool { BackendConfig.isAuthConfigured }

    // MARK: Username + password
    static func signUp(name: String, username: String, password: String) async throws {
        let u = username.trimmingCharacters(in: .whitespaces)
        guard isValid(username: u) else { throw AuthError.invalidUsername }
        guard isStrong(password: password) else { throw AuthError.weakPassword }
        let display = name.isEmpty ? u : name
        if usesFirebase {
            var session = try await FirebaseAuthClient.signUp(email: FirebaseAuthClient.email(forUsername: u), password: password)
            try? await FirebaseAuthClient.updateDisplayName(idToken: session.idToken, name: display)
            session.displayName = display
            AuthSession.shared.set(session)
            finish(name: display, username: u, email: nil, method: "password")
        } else {
            guard Keychain.get(key(u)) == nil else { throw AuthError.exists }
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            Keychain.set(salt + hash(password, salt: salt), for: key(u))
            finish(name: display, username: u, email: nil, method: "password")
        }
    }

    static func signIn(username: String, password: String) async throws {
        let u = username.trimmingCharacters(in: .whitespaces)
        guard isValid(username: u) else { throw AuthError.invalidUsername }
        if usesFirebase {
            let session = try await FirebaseAuthClient.signIn(email: FirebaseAuthClient.email(forUsername: u), password: password)
            AuthSession.shared.set(session)
            finish(name: session.displayName.isEmpty ? u : session.displayName, username: u, email: nil, method: "password")
        } else {
            guard let stored = Keychain.get(key(u)) else { throw AuthError.notFound }
            guard hash(password, salt: Data(stored.prefix(16))) == stored.dropFirst(16) else { throw AuthError.wrongPassword }
            let name = UserDefaults.standard.string(forKey: "name.\(u.lowercased())") ?? u
            finish(name: name, username: u, email: nil, method: "password")
        }
    }

    static func changePassword(username: String, old: String, new: String) async throws {
        guard AppSettings.shared.authMethod == "password" else { throw AuthError.notPasswordAccount }
        guard isStrong(password: new) else { throw AuthError.weakPassword }
        if usesFirebase {
            // Re-authenticate first (Firebase requires a recent login to change a password).
            let fresh = try await FirebaseAuthClient.signIn(email: FirebaseAuthClient.email(forUsername: username), password: old)
            var updated = try await FirebaseAuthClient.changePassword(idToken: fresh.idToken, newPassword: new)
            if updated.displayName.isEmpty { updated.displayName = fresh.displayName }
            AuthSession.shared.set(updated)
        } else {
            guard let stored = Keychain.get(key(username)),
                  hash(old, salt: Data(stored.prefix(16))) == stored.dropFirst(16) else { throw AuthError.wrongPassword }
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            Keychain.set(salt + hash(new, salt: salt), for: key(username))
        }
    }

    /// Deletes the account (server-side too when Firebase is used). The caller wipes local data afterwards.
    static func deleteAccount(username: String) async throws {
        if usesFirebase, AuthSession.shared.isSignedIn {
            try await FirebaseAuthClient.deleteAccount(idToken: try await AuthSession.shared.validIDToken())
            AuthSession.shared.clear()
        }
        Keychain.delete(key(username))
        UserDefaults.standard.removeObject(forKey: "name.\(username.lowercased())")
        UserDefaults.standard.removeObject(forKey: "member.\(username.lowercased())")
    }

    /// Stores the signed-in identity. `email` is only overwritten when provided (Apple/Google supply one).
    static func finish(name: String, username: String, email: String?, method: String) {
        let d = UserDefaults.standard
        d.set(name, forKey: "name.\(username.lowercased())")
        let s = AppSettings.shared
        s.userName = name; s.username = username; s.authMethod = method
        if let email, !email.isEmpty { s.userEmail = email }
        let mk = "member.\(username.lowercased())"
        if let since = d.object(forKey: mk) as? Date { s.memberSince = since }
        else { let now = Date(); d.set(now, forKey: mk); s.memberSince = now }
        s.isSignedIn = true
        s.persist()
        PushRegistration.uploadPendingToken()
    }

    /// Signs out of the app. The Firebase refresh token stays in the Keychain so Face ID / Touch ID can resume the session.
    static func signOut() {
        let s = AppSettings.shared
        s.isSignedIn = false; s.persist()
    }

    // MARK: Biometrics
    static var biometryType: LABiometryType {
        let c = LAContext(); var e: NSError?
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
        return c.biometryType
    }
    static var biometricsAvailable: Bool {
        var e: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
    }
    static var biometricIcon: String { biometryType == .touchID ? "touchid" : "faceid" }

    /// Authenticates with Face ID / Touch ID. The simulator supports this via Features ▸ Face ID ▸ Enrolled.
    static func authenticateWithBiometrics(reason: String) async throws {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { throw AuthError.biometricUnavailable }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if !ok { throw AuthError.biometricFailed }
        } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel {
            throw AuthError.cancelled
        } catch { throw AuthError.biometricFailed }
    }

    /// Biometric sign-in for the last signed-in account. `type` is the icon the user tapped.
    static func signInWithBiometrics(type: LABiometryType) async throws {
        let s = AppSettings.shared
        guard biometryType == type else { throw AuthError.biometricUnavailable }
        guard !s.username.isEmpty else { throw AuthError.noPreviousUser }
        try await authenticateWithBiometrics(reason: tr("auth.bio_reason"))
        if usesFirebase {
            // The stored refresh token proves the earlier password / provider login. Offline is fine as long as a session exists.
            guard AuthSession.shared.isSignedIn else { throw AuthError.noPreviousUser }
            do { _ = try await AuthSession.shared.validIDToken() }
            catch FirebaseAuthError.network { /* offline: keep working with the cached session */ }
            catch { throw AuthError.noPreviousUser }
        }
        finish(name: s.userName, username: s.username, email: nil, method: s.authMethod)
    }

    // MARK: Apple ID
    /// Random nonce + its SHA-256 hex – Apple embeds the hash in the ID token; Firebase checks it against the raw value (replay protection).
    static func makeNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
    static func sha256Hex(_ input: String) -> String { SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// Completes Sign in with Apple. Apple only returns name/email on the very first sign-in, so they are cached per user id.
    static func completeApple(_ result: Result<ASAuthorization, Error>, rawNonce: String = "") async throws {
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code == .canceled { throw AuthError.cancelled }
            throw AuthError.methodUnavailable
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { throw AuthError.methodUnavailable }
            let d = UserDefaults.standard
            let k = "apple.\(cred.user)"
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            if !fullName.isEmpty { d.set(fullName, forKey: k + ".name") }
            if let mail = cred.email { d.set(mail, forKey: k + ".email") }
            var name = d.string(forKey: k + ".name") ?? "Farmer"
            var email = d.string(forKey: k + ".email")
            var username = "apple_\(cred.user.suffix(6))"
            if usesFirebase {
                guard let tokenData = cred.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else { throw AuthError.methodUnavailable }
                var session = try await FirebaseAuthClient.signInWithProvider(providerId: "apple.com", idToken: idToken, rawNonce: rawNonce)
                if d.string(forKey: k + ".name") != nil, session.displayName.isEmpty {
                    try? await FirebaseAuthClient.updateDisplayName(idToken: session.idToken, name: name); session.displayName = name
                }
                AuthSession.shared.set(session)
                if !session.displayName.isEmpty { name = session.displayName }
                if email == nil, !session.email.isEmpty { email = session.email }
                username = "apple_\(session.uid.suffix(6))"
            }
            finish(name: name, username: username, email: email, method: "apple")
        }
    }

    // MARK: Google
    @MainActor
    static func signInWithGoogle() async throws {
        #if canImport(GoogleSignIn)
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.contains("YOUR_GOOGLE_CLIENT_ID") else { throw AuthError.googleNotConfigured }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController
        else { throw AuthError.googleUnavailable }
        let result: GIDSignInResult
        do { result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root) } catch { throw AuthError.cancelled }
        let p = result.user.profile
        var name = p?.name ?? "Farmer"
        var email = p?.email
        var username = "g_" + ((p?.email ?? "user").components(separatedBy: "@").first ?? "user")
        if usesFirebase {
            guard let idToken = result.user.idToken?.tokenString else { throw AuthError.methodUnavailable }
            let session = try await FirebaseAuthClient.signInWithProvider(providerId: "google.com", idToken: idToken,
                                                                         accessToken: result.user.accessToken.tokenString)
            AuthSession.shared.set(session)
            if !session.displayName.isEmpty { name = session.displayName }
            if email == nil { email = session.email }
            username = "g_\(session.uid.suffix(6))"
        }
        finish(name: name, username: username, email: email, method: "google")
        #else
        throw AuthError.googleUnavailable
        #endif
    }

    static func handle(url: URL) {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.handle(url)
        #endif
    }
}

/// Presents the Sign in with Apple sheet from a plain icon button (instead of Apple's stock button).
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func start(hashedNonce: String) async throws -> ASAuthorization {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in self.continuation?.resume(returning: authorization); self.continuation = nil }
    }
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in self.continuation?.resume(throwing: error); self.continuation = nil }
    }
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
