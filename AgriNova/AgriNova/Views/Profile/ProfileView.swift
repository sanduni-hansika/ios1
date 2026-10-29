import SwiftUI
import PhotosUI
import CoreData

// MARK: - Avatar

/// Profile photo stored in the app's Documents folder.
enum AvatarStore {
    static var url: URL { URL.documentsDirectory.appendingPathComponent("avatar.jpg") }
    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
    static func save(_ image: UIImage) {
        guard let data = image.jpegForStorage(maxSide: 600, quality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)
        AppSettings.shared.avatarVersion += 1
    }
    static func remove() { try? FileManager.default.removeItem(at: url); AppSettings.shared.avatarVersion += 1 }
}

struct AvatarView: View {
    var size: CGFloat = 52
    @Environment(AppSettings.self) private var settings
    var body: some View {
        let _ = settings.avatarVersion
        Group {
            if let img = AvatarStore.load() {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(String((settings.userName.first ?? "A")).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.heroGradient)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 2))
        .shadow(color: Theme.leaf.opacity(0.35), radius: 8, y: 4)
        .accessibilityLabel(tr("prof.title"))
    }
}

// MARK: - Profile screen

struct ProfileView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.managedObjectContext) private var ctx
    @FetchRequest(sortDescriptors: []) private var scans: FetchedResults<CDScan>
    @FetchRequest(sortDescriptors: []) private var farms: FetchedResults<CDFarm>
    @FetchRequest(sortDescriptors: []) private var reports: FetchedResults<CDOutbreak>
    @State private var photoItem: PhotosPickerItem?
    @State private var showEdit = false
    @State private var showPassword = false
    @State private var confirmDelete = false
    @State private var confirmSignOut = false

    private var methodTitle: String {
        switch settings.authMethod { case "google": "Google"; case "apple": "Apple ID"; default: tr("prof.method.password") }
    }
    private var methodIcon: String {
        switch settings.authMethod { case "google": "g.circle.fill"; case "apple": "apple.logo"; default: "key.fill" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                statsRow
                detailsCard
                securityCard
                accountCard
            }.padding(20).readableWidth(720)
        }
        .background(AppBackground())
        .navigationTitle(tr("prof.title")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("common.edit")) { showEdit = true } } }
        .sheet(isPresented: $showEdit) { EditProfileSheet() }
        .sheet(isPresented: $showPassword) { ChangePasswordSheet() }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                AvatarStore.save(img); photoItem = nil; ToastCenter.shared.show(tr("prof.saved"))
            }
        }
        .confirmationDialog(tr("set.sign_out"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(tr("set.sign_out"), role: .destructive) { AuthService.signOut() }
        }
        .confirmationDialog(tr("prof.delete_confirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("prof.delete_account"), role: .destructive) { deleteAccount() }
        } message: { Text(tr("prof.delete_msg")) }
    }

    // MARK: Header
    private var header: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(size: 112)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "camera.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Theme.sunGradient, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }.accessibilityLabel(tr("prof.photo_change"))
            }
            VStack(spacing: 4) {
                Text(settings.userName.isEmpty ? tr("dash.farmer") : settings.userName).font(.rounded(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                Text("@\(settings.username)").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 8) {
                Chip(text: methodTitle, icon: methodIcon, color: Theme.leaf)
                if let since = settings.memberSince {
                    Chip(text: "\(tr("prof.member_since")) \(since.formatted(.dateTime.month(.abbreviated).year()))", icon: "calendar", color: Theme.sky)
                }
            }
            if AvatarStore.load() != nil {
                Button(tr("prof.photo_remove")) { AvatarStore.remove() }.font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.danger)
            }
        }
        .frame(maxWidth: .infinity).padding(22).softCard(radius: 30)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat("\(scans.count)", tr("dash.scans"), "camera.viewfinder", Theme.heroGradient)
            stat("\(farms.count)", tr("prof.farms"), "tree.fill", Theme.sunGradient)
            stat("\(reports.filter(\.isMine).count)", tr("prof.reports"), "megaphone.fill", Theme.dangerGradient)
        }
    }
    private func stat(_ v: String, _ l: String, _ icon: String, _ g: LinearGradient) -> some View {
        VStack(spacing: 8) {
            IconBadge(icon: icon, gradient: g, size: 38)
            Text(v).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text(l).font(.rounded(.caption2, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity).padding(.vertical, 14).softCard(radius: 22, depth: 7)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(l): \(v)")
    }

    // MARK: Details
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("prof.details"), systemImage: "person.text.rectangle.fill").font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
            row("person.fill", tr("auth.name"), settings.userName)
            row("at", tr("auth.username"), settings.username)
            row("envelope.fill", tr("prof.email"), settings.userEmail.isEmpty ? "—" : settings.userEmail)
            row("phone.fill", tr("prof.phone"), settings.userPhone.isEmpty ? "—" : settings.userPhone)
            row("mappin.and.ellipse", tr("prof.district"), settings.userDistrict.isEmpty ? "—" : settings.userDistrict)
            Button { showEdit = true } label: { Label(tr("prof.edit"), systemImage: "pencil").font(.rounded(.subheadline, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12) }
                .buttonStyle(SoftButtonStyle(radius: 20))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    private func row(_ icon: String, _ k: String, _ v: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.leaf).frame(width: 22)
            Text(k).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(v).font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }.accessibilityElement(children: .combine)
    }

    // MARK: Security
    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("prof.security"), systemImage: "lock.shield.fill").font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
            row(methodIcon, tr("prof.signed_in_with"), methodTitle)
            row("server.rack", tr("prof.account_server"), AuthService.usesFirebase ? tr("prof.server_firebase") : tr("prof.server_local"))
            if settings.authMethod == "password" {
                Button { showPassword = true } label: { Label(tr("prof.change_password"), systemImage: "key.fill").font(.rounded(.subheadline, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12) }
                    .buttonStyle(SoftButtonStyle(radius: 20))
            } else {
                Text(tr("prof.pw_managed")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
            }
            Text(tr("prof.quick_note")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    // MARK: Account
    private var accountCard: some View {
        VStack(spacing: 12) {
            Button { confirmSignOut = true } label: { Label(tr("set.sign_out"), systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).padding(.vertical, 14) }
                .buttonStyle(SoftButtonStyle(radius: 22))
            Button(role: .destructive) { confirmDelete = true } label: { Label(tr("prof.delete_account"), systemImage: "trash.fill").font(.rounded(.subheadline, weight: .semibold)) }
        }
    }

    private func deleteAccount() {
        Task {
            do { try await AuthService.deleteAccount(username: settings.username) }
            catch { ToastCenter.shared.show(error.localizedDescription, kind: .error); return }
            wipeLocalAccount()
        }
    }

    private func wipeLocalAccount() {
        NotificationService.cancelAll()
        PersistenceController.shared.wipeAll()
        AvatarStore.remove()
        LocationService.shared.apply([])
        settings.userName = ""; settings.username = ""; settings.userEmail = ""; settings.userPhone = ""; settings.userDistrict = ""; settings.memberSince = nil
        settings.resetPreferences()
        AuthService.signOut()
        WidgetUpdater.refresh()
    }
}

// MARK: - Edit profile

struct EditProfileSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var district = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("prof.details")) {
                    TextField(tr("auth.name"), text: $name).textContentType(.name)
                    HStack { Text(tr("auth.username")).foregroundStyle(.secondary); Spacer(); Text("@\(settings.username)").foregroundStyle(.secondary) }
                    TextField(tr("prof.email"), text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(tr("prof.phone"), text: $phone).keyboardType(.phonePad)
                    TextField(tr("prof.district"), text: $district)
                }
                if let error { Section { Banner(kind: .error, title: error) }.listRowBackground(Color.clear) }
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle(tr("prof.edit")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("common.save")) { save() }.bold() }
            }
            .onAppear { name = settings.userName; email = settings.userEmail; phone = settings.userPhone; district = settings.userDistrict }
        }.presentationDetents([.large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = tr("prof.err.name"); return }
        if !email.isEmpty && !AuthService.isValid(email: email) { error = tr("prof.err.email"); return }
        settings.userName = trimmed; settings.userEmail = email; settings.userPhone = phone; settings.userDistrict = district
        UserDefaults.standard.set(trimmed, forKey: "name.\(settings.username.lowercased())")
        settings.persist()
        ToastCenter.shared.show(tr("prof.saved")); dismiss()
    }
}

// MARK: - Change password

struct ChangePasswordSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var old = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(tr("prof.current_password"), text: $old).textContentType(.password)
                    SecureField(tr("prof.new_password"), text: $new).textContentType(.newPassword)
                    SecureField(tr("prof.confirm_password"), text: $confirm).textContentType(.newPassword)
                } footer: { Text(tr("auth.password_hint")) }
                if let error { Section { Banner(kind: .error, title: error) }.listRowBackground(Color.clear) }
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle(tr("prof.change_password")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("common.save")) { save() }.bold().disabled(old.isEmpty || new.isEmpty) }
            }
        }.presentationDetents([.medium])
    }

    private func save() {
        guard new == confirm else { error = tr("prof.err.mismatch"); return }
        Task {
            do {
                try await AuthService.changePassword(username: settings.username, old: old, new: new)
                ToastCenter.shared.show(tr("prof.password_changed")); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
