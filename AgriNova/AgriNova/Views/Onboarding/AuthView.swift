import SwiftUI
import AuthenticationServices
import LocalAuthentication

@MainActor @Observable
final class AuthViewModel {
    enum Mode { case signIn, signUp }
    var mode: Mode = .signIn
    var name = ""
    var username = ""
    var password = ""
    var isLoading = false
    var error: String?
    private let apple = AppleSignInCoordinator()

    var canSubmit: Bool {
        AuthService.isValid(username: username) && AuthService.isStrong(password: password)
            && (mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Normal username + password sign-in / sign-up.
    func submit() async {
        error = nil; isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .signIn: try await AuthService.signIn(username: username, password: password)
            case .signUp: try await AuthService.signUp(name: name, username: username, password: password)
            }
            ToastCenter.shared.show(tr("auth.welcome"))
        } catch { self.error = error.localizedDescription }
    }

    /// Face ID or Touch ID icon (whichever the user tapped).
    func biometric(_ type: LABiometryType) async {
        error = nil; isLoading = true
        defer { isLoading = false }
        do { try await AuthService.signInWithBiometrics(type: type) }
        catch AuthError.cancelled { }
        catch { self.error = error.localizedDescription }
    }

    func google() async {
        error = nil; isLoading = true
        defer { isLoading = false }
        do { try await AuthService.signInWithGoogle() }
        catch AuthError.cancelled { }
        catch { self.error = error.localizedDescription }
    }

    func appleID() async {
        error = nil; isLoading = true
        defer { isLoading = false }
        let nonce = AuthService.makeNonce()
        do { try await AuthService.completeApple(.success(try await apple.start(hashedNonce: AuthService.sha256Hex(nonce))), rawNonce: nonce) }
        catch AuthError.cancelled { }
        catch let e as ASAuthorizationError where e.code == .canceled { }
        catch { self.error = AuthError.methodUnavailable.localizedDescription }
    }
}

struct AuthView: View {
    @Environment(AppSettings.self) private var settings
    @State private var vm = AuthViewModel()
    @State private var showPassword = false
    @FocusState private var focus: Field?
    private enum Field { case name, username, password }

    private var anyQuickMethod: Bool { settings.allowFaceID || settings.allowTouchID || settings.allowGoogle || settings.allowApple }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    LeafLogo(size: 84)
                    Text(vm.mode == .signIn ? tr("auth.welcome_back") : tr("auth.create"))
                        .font(.rounded(.largeTitle, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(tr("auth.subtitle")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                }.padding(.top, 30)

                Picker("", selection: $vm.mode.animation(.spring)) {
                    Text(tr("auth.sign_in")).tag(AuthViewModel.Mode.signIn)
                    Text(tr("auth.sign_up")).tag(AuthViewModel.Mode.signUp)
                }.pickerStyle(.segmented)

                VStack(spacing: 14) {
                    if vm.mode == .signUp {
                        field(icon: "person.fill") {
                            TextField(tr("auth.name"), text: $vm.name).textContentType(.name).focused($focus, equals: .name)
                        }.transition(.move(edge: .top).combined(with: .opacity))
                    }
                    field(icon: "at") {
                        TextField(tr("auth.username"), text: $vm.username)
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: .username)
                    }
                    field(icon: "lock.fill") {
                        HStack {
                            Group {
                                if showPassword { TextField(tr("auth.password"), text: $vm.password) }
                                else { SecureField(tr("auth.password"), text: $vm.password) }
                            }.textContentType(vm.mode == .signUp ? .newPassword : .password).focused($focus, equals: .password)
                            Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill").foregroundStyle(Theme.inkSoft) }
                                .accessibilityLabel(tr("auth.show_password"))
                        }
                    }
                    if vm.mode == .signUp {
                        Text(tr("auth.username_hint") + " • " + tr("auth.password_hint")).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let e = vm.error { Banner(kind: .error, title: e).transition(.scale.combined(with: .opacity)) }

                Button { focus = nil; Task { await vm.submit() } } label: {
                    if vm.isLoading { ProgressView().tint(.white) }
                    else { Text(vm.mode == .signIn ? tr("auth.sign_in") : tr("auth.sign_up")) }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(!vm.canSubmit || vm.isLoading).opacity(vm.canSubmit ? 1 : 0.55)

                if anyQuickMethod { quickMethods }
            }
            .padding(24).readableWidth(520)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.mode)
            .animation(.spring, value: vm.error)
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.error, trigger: vm.error)
    }

    // MARK: Icon buttons – Face ID, Touch ID, Google, Apple ID (shown/hidden from Settings ▸ Quick sign-in)
    private var quickMethods: some View {
        VStack(spacing: 14) {
            HStack {
                Rectangle().fill(Theme.inkSoft.opacity(0.25)).frame(height: 1)
                Text(tr("auth.or")).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                Rectangle().fill(Theme.inkSoft.opacity(0.25)).frame(height: 1)
            }
            HStack(spacing: 18) {
                if settings.allowFaceID { iconButton(system: "faceid", label: tr("auth.face"), dimmed: AuthService.biometryType != .faceID) { await vm.biometric(.faceID) } }
                if settings.allowTouchID { iconButton(system: "touchid", label: tr("auth.touch"), dimmed: AuthService.biometryType != .touchID) { await vm.biometric(.touchID) } }
                if settings.allowGoogle { iconButton(text: "G", tint: Theme.sky, label: tr("auth.google")) { await vm.google() } }
                if settings.allowApple { iconButton(system: "apple.logo", label: tr("auth.apple_short")) { await vm.appleID() } }
            }
            Text(tr("auth.quick_hint")).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
        }
    }

    private func iconButton(system: String? = nil, text: String? = nil, tint: Color = Theme.ink, label: String, dimmed: Bool = false,
                            _ action: @escaping () async -> Void) -> some View {
        Button { focus = nil; Task { await action() } } label: {
            VStack(spacing: 8) {
                Group {
                    if let system { Image(systemName: system).font(.system(size: 26, weight: .semibold)) }
                    else { Text(text ?? "").font(.system(size: 28, weight: .heavy, design: .rounded)) }
                }
                .foregroundStyle(tint).frame(width: 64, height: 64)
                .softCard(radius: 22, depth: 7).opacity(dimmed ? 0.45 : 1)
                Text(label).font(.rounded(.caption2, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
        .buttonStyle(CardPressStyle())
        .disabled(vm.isLoading)
        .accessibilityLabel(label)
        .accessibilityHint(tr("auth.sign_in"))
    }

    private func field<Content: View>(icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.leaf).frame(width: 22)
            content().font(.rounded(.body)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 15).softCard(radius: 18, depth: 6)
    }
}
