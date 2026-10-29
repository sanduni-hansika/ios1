import Foundation

// MARK: - Model

/// A signed-in Firebase Authentication session: short-lived **ID token** (sent as `Authorization: Bearer …` to Firestore)
/// plus a long-lived **refresh token** used to obtain new ID tokens silently.
struct FirebaseSession: Codable, Equatable {
    var idToken: String
    var refreshToken: String
    var uid: String
    var email: String
    var displayName: String
    var expiresAt: Date

    /// True when the ID token is expired or about to expire (default 60 s safety margin).
    func needsRefresh(now: Date = Date(), skew: TimeInterval = 60) -> Bool { now.addingTimeInterval(skew) >= expiresAt }
}

enum FirebaseAuthError: LocalizedError, Equatable {
    case notConfigured, notSignedIn, emailExists, invalidCredentials, weakPassword, tooManyAttempts
    case userDisabled, requiresRecentLogin, invalidToken, network, server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: tr("auth.err.not_configured")
        case .notSignedIn: tr("auth.err.session")
        case .emailExists: tr("auth.err.exists")
        case .invalidCredentials: tr("auth.err.credentials")
        case .weakPassword: tr("auth.err.weak")
        case .tooManyAttempts: tr("auth.err.too_many")
        case .userDisabled: tr("auth.err.disabled")
        case .requiresRecentLogin: tr("auth.err.recent_login")
        case .invalidToken: tr("auth.err.session")
        case .network: tr("auth.err.network")
        case .server(let m): m
        }
    }
}

// MARK: - REST client (Firebase Authentication, Identity Toolkit API)

/// Talks to Firebase Authentication over HTTPS – no Firebase SDK needed.
/// Docs: https://firebase.google.com/docs/reference/rest/auth
enum FirebaseAuthClient {
    private static let identity = "https://identitytoolkit.googleapis.com/v1/accounts"
    private static let secureToken = "https://securetoken.googleapis.com/v1/token"

    // MARK: Pure parsing (unit-tested, no network)

    /// Parses the response of signUp / signInWithPassword / signInWithIdp / accounts:update.
    static func parseSession(_ data: Data, now: Date = Date(), fallbackEmail: String = "") throws -> FirebaseSession {
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = j["idToken"] as? String, let refresh = j["refreshToken"] as? String else { throw FirebaseAuthError.invalidToken }
        let seconds = Double((j["expiresIn"] as? String) ?? "3600") ?? 3600
        return FirebaseSession(idToken: id, refreshToken: refresh, uid: j["localId"] as? String ?? "",
                               email: j["email"] as? String ?? fallbackEmail, displayName: j["displayName"] as? String ?? "",
                               expiresAt: now.addingTimeInterval(seconds))
    }

    /// Parses the response of the securetoken refresh endpoint (snake_case keys).
    static func parseRefresh(_ data: Data, previous: FirebaseSession, now: Date = Date()) throws -> FirebaseSession {
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (j["id_token"] as? String) ?? (j["access_token"] as? String) else { throw FirebaseAuthError.invalidToken }
        var s = previous
        s.idToken = id
        s.refreshToken = (j["refresh_token"] as? String) ?? previous.refreshToken
        s.uid = (j["user_id"] as? String) ?? previous.uid
        s.expiresAt = now.addingTimeInterval(Double((j["expires_in"] as? String) ?? "3600") ?? 3600)
        return s
    }

    /// Maps Firebase's `{"error":{"message":"EMAIL_EXISTS"}}` codes to typed errors.
    static func parseError(_ data: Data) -> FirebaseAuthError {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = (j["error"] as? [String: Any])?["message"] as? String else { return .server("Unknown error") }
        switch true {
        case msg.hasPrefix("EMAIL_EXISTS"): return .emailExists
        case msg.hasPrefix("INVALID_LOGIN_CREDENTIALS"), msg.hasPrefix("INVALID_PASSWORD"), msg.hasPrefix("EMAIL_NOT_FOUND"): return .invalidCredentials
        case msg.hasPrefix("WEAK_PASSWORD"): return .weakPassword
        case msg.hasPrefix("TOO_MANY_ATTEMPTS"): return .tooManyAttempts
        case msg.hasPrefix("USER_DISABLED"): return .userDisabled
        case msg.hasPrefix("CREDENTIAL_TOO_OLD_LOGIN_AGAIN"): return .requiresRecentLogin
        case msg.hasPrefix("TOKEN_EXPIRED"), msg.hasPrefix("INVALID_ID_TOKEN"), msg.hasPrefix("INVALID_REFRESH_TOKEN"), msg.hasPrefix("USER_NOT_FOUND"): return .invalidToken
        default: return .server(msg)
        }
    }

    /// Username → the synthetic e-mail address Firebase Auth uses as account id (usernames aren't real inboxes).
    static func email(forUsername username: String) -> String { "\(username.lowercased())@\(BackendConfig.authEmailDomain)" }

    // MARK: Network

    private static func send(_ urlString: String, json: [String: Any]? = nil, form: String? = nil) async throws -> Data {
        guard BackendConfig.isAuthConfigured else { throw FirebaseAuthError.notConfigured }
        var c = URLComponents(string: urlString)!
        c.queryItems = [URLQueryItem(name: "key", value: BackendConfig.firebaseWebAPIKey)]
        var req = URLRequest(url: c.url!)
        req.httpMethod = "POST"; req.timeoutInterval = 20
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if let form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(form.utf8)
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch { throw FirebaseAuthError.network }
        guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { throw parseError(data) }
        return data
    }

    static func signUp(email: String, password: String) async throws -> FirebaseSession {
        let d = try await send("\(identity):signUp", json: ["email": email, "password": password, "returnSecureToken": true])
        return try parseSession(d, fallbackEmail: email)
    }

    static func signIn(email: String, password: String) async throws -> FirebaseSession {
        let d = try await send("\(identity):signInWithPassword", json: ["email": email, "password": password, "returnSecureToken": true])
        return try parseSession(d, fallbackEmail: email)
    }

    /// Google / Apple sign-in: exchanges the provider's ID token for a Firebase session.
    static func signInWithProvider(providerId: String, idToken: String, accessToken: String? = nil, rawNonce: String? = nil) async throws -> FirebaseSession {
        var post = "id_token=\(idToken)&providerId=\(providerId)"
        if let accessToken { post += "&access_token=\(accessToken)" }
        if let rawNonce { post += "&nonce=\(rawNonce)" }
        let d = try await send("\(identity):signInWithIdp",
                               json: ["postBody": post, "requestUri": "http://localhost", "returnIdpCredential": true, "returnSecureToken": true])
        return try parseSession(d)
    }

    static func refresh(_ s: FirebaseSession) async throws -> FirebaseSession {
        let d = try await send(secureToken, form: "grant_type=refresh_token&refresh_token=\(s.refreshToken)")
        return try parseRefresh(d, previous: s)
    }

    static func updateDisplayName(idToken: String, name: String) async throws {
        _ = try await send("\(identity):update", json: ["idToken": idToken, "displayName": name, "returnSecureToken": false])
    }

    static func changePassword(idToken: String, newPassword: String) async throws -> FirebaseSession {
        let d = try await send("\(identity):update", json: ["idToken": idToken, "password": newPassword, "returnSecureToken": true])
        return try parseSession(d)
    }

    static func deleteAccount(idToken: String) async throws {
        _ = try await send("\(identity):delete", json: ["idToken": idToken])
    }
}

// MARK: - Token manager

/// Keeps the Firebase session in the Keychain and hands out a **valid** ID token, refreshing it automatically
/// when it is about to expire. Thread-safe (lock-protected) so the sync engine and the UI can both use it.
final class AuthSession: @unchecked Sendable {
    static let shared = AuthSession()
    private static let keychainKey = "firebase.session"
    private let lock = NSLock()
    private var current: FirebaseSession?
    private var refreshTask: Task<FirebaseSession, Error>?

    init() {
        if let d = Keychain.get(Self.keychainKey), let s = try? JSONDecoder().decode(FirebaseSession.self, from: d) { current = s }
    }

    var session: FirebaseSession? { lock.lock(); defer { lock.unlock() }; return current }
    var uid: String? { session?.uid }
    var isSignedIn: Bool { session != nil }

    func set(_ s: FirebaseSession) {
        lock.lock(); current = s; lock.unlock()
        if let d = try? JSONEncoder().encode(s) { Keychain.set(d, for: Self.keychainKey) }
    }

    func clear() {
        lock.lock(); current = nil; refreshTask?.cancel(); refreshTask = nil; lock.unlock()
        Keychain.delete(Self.keychainKey)
    }

    // Lock-protected helpers are synchronous on purpose (NSLock must not be used directly in async code).
    private func startOrJoinRefresh(_ s: FirebaseSession) -> Task<FirebaseSession, Error> {
        lock.lock(); defer { lock.unlock() }
        if let existing = refreshTask { return existing }
        let task = Task { try await FirebaseAuthClient.refresh(s) }
        refreshTask = task
        return task
    }
    private func finishRefresh() { lock.lock(); refreshTask = nil; lock.unlock() }

    /// Returns a non-expired ID token, refreshing through the securetoken API when needed.
    func validIDToken() async throws -> String {
        guard let s = session else { throw FirebaseAuthError.notSignedIn }
        if !s.needsRefresh() { return s.idToken }
        let task = startOrJoinRefresh(s)
        do {
            let fresh = try await task.value
            set(fresh); finishRefresh()
            return fresh.idToken
        } catch {
            finishRefresh()
            if let e = error as? FirebaseAuthError, e == .invalidToken { clear() }     // refresh token revoked → sign in again
            throw error
        }
    }
}
