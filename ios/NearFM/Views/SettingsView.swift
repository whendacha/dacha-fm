import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var deleteConfirmation = false
    @State private var logoutConfirmation = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Settings").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.cream)
                    Text("Your account and music").foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 13) {
                        Image(systemName: model.isSignedIn ? "person.crop.circle.fill" : "iphone.gen3")
                            .font(.title).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.isSignedIn ? "Dacha FM account" : "Guest")
                                .font(.headline).foregroundStyle(Theme.cream)
                            Text(model.isSignedIn ? (model.accountLabel) : "Library saved on this iPhone")
                                .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    HStack(spacing: 8) {
                        Circle().fill(syncColor).frame(width: 7, height: 7)
                        Text(syncLabel).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))

                if !model.isSignedIn {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionTitle(title: model.cloudConfigured ? "Cloud sync" : "Your account", subtitle: model.cloudConfigured ? "Sign in with the same wallet on your other devices to sync favorites and playlists." : "Sign in with your wallet. Your library stays on this iPhone.")
                        if model.canAppleLogin {
                        AppleSignInButton { Task { await model.loginWithApple() } }
                            .frame(height: 52)
                            .disabled(model.isAuthenticating || !model.canAppleLogin)
                            .accessibilityLabel("Sign in with Apple")
                        }
                        Button { Task { await model.loginWithMeteor() } } label: {
                            Label("Sign in with Meteor Wallet", systemImage: "sparkles")
                                .font(.headline).frame(maxWidth: .infinity).padding(16)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                        }.disabled(model.isAuthenticating || !model.canMeteorLogin)
                        if model.isAuthenticating { ProgressView("Signing in…").padding(.top, 4) }
                        if !model.canMeteorLogin {
                            Text("Some sign-in options are temporarily unavailable.")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Text("Meteor will ask you to sign a message to verify your account. Dacha FM never requests private keys or transfers funds.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Library", subtitle: model.account?.isCloudWallet == true || model.cloudSyncEnabled ? "Sync status" : "Saved on this iPhone for your account")
                        if model.canEnableCloud || model.needsCloudReauthentication {
                            Button(model.needsCloudReauthentication ? "Sign in to cloud sync again" : "Enable sync with Meteor") {
                                Task { await model.loginWithMeteor() }
                            }
                            .disabled(model.isAuthenticating || model.isChangingAccount || !model.canMeteorLogin)
                            Text("Confirm the same wallet. Your library saved on this iPhone will remain available.")
                                .font(.caption).foregroundStyle(Theme.muted)
                            if model.isAuthenticating { ProgressView("Signing in…") }
                        }
                        if model.guestMergeAvailable {
                            Button { model.mergeGuestLibrary() } label: {
                                Label("Merge guest library", systemImage: "square.stack.3d.up")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                            Text("Your guest library will also stay on this iPhone.").font(.caption).foregroundStyle(Theme.muted)
                        }
                        if model.syncState == .conflict {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your library changed on another device. Choose one complete version, including its deletions and playlist order.").font(.subheadline)
                                Button("Use cloud version") { model.resolveConflictUseCloud() }
                                Button("Use this iPhone’s version") { Task { await model.resolveConflictUseDevice() } }
                            }.padding(16).background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
                        }
                        if model.cloudSyncEnabled && model.syncState != .conflict {
                            Button(model.syncState == .offline ? "Retry sync" : "Sync now") { Task { await model.refreshLibrary() } }
                                .disabled(model.syncState == .syncing || model.isChangingAccount)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Account", subtitle: "Manage sign-in and data")
                        Button("Sign out") { logoutConfirmation = true }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .disabled(model.isChangingAccount || model.isAuthenticating)
                        Button("Delete account", role: .destructive) { deleteConfirmation = true }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .disabled(model.isChangingAccount || model.isAuthenticating)
                        Text("Deleting your account removes your Dacha FM profile and personal library. Your Meteor wallet and blockchain data remain yours.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }

                NavigationLink { HiddenSongsView(model: model) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "eye.slash").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hidden songs").font(.headline)
                            Text(songCountLabel(model.library?.hiddenTracks.count ?? 0))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityIdentifier("hidden-songs-link")

                if let blocked = model.library?.blockedArtistIDs, !blocked.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Hidden artists", subtitle: "Their music is hidden and will not play")
                        ForEach(blocked, id: \.self) { id in
                            HStack {
                                Text(id).font(.subheadline).lineLimit(1)
                                Spacer()
                                Button("Unhide") { model.unblockArtist(id) }.font(.caption.weight(.semibold))
                            }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Help and policies", subtitle: "Support and privacy")
                    if let url = model.supportURL { Link(destination: url) { SettingsLink(title: "Support", symbol: "questionmark.circle") } }
                    else { SettingsLink(title: "Support is temporarily unavailable", symbol: "questionmark.circle").foregroundStyle(Theme.muted) }
                    if let url = model.privacyURL { Link(destination: url) { SettingsLink(title: "Privacy policy", symbol: "hand.raised") } }
                    else { SettingsLink(title: "Privacy policy is temporarily unavailable", symbol: "hand.raised").foregroundStyle(Theme.muted) }
                }
            }.padding(20)
        }
        .accessibilityIdentifier("settings-scroll")
        .background(Theme.background)
        .navigationBarHidden(true)
        .confirmationDialog("Sign out?", isPresented: $logoutConfirmation) {
            Button("Sign out") { Task { await model.logout() } }
        } message: { Text("Your local guest library will appear after you sign out.") }
        .confirmationDialog("Delete your Dacha FM account?", isPresented: $deleteConfirmation) {
            Button("Delete account", role: .destructive) { Task { await model.deleteAccount() } }
        } message: { Text(model.cloudSyncEnabled || model.account?.isCloudWallet == true ? "Your profile and synced library will be removed once the server confirms deletion. If your session has expired, you will need to confirm your wallet again." : "Your profile and its library will be removed from this iPhone. Your wallet will remain yours.") }
    }

    private var syncLabel: String {
        switch model.syncState {
        case .local: "On this device only"
        case .syncing: "Syncing…"
        case .synced: "Up to date"
        case .offline: "Changes saved locally, waiting to sync"
        case .conflict: "Choose a library version"
        case .reauthenticationRequired: "Sign in again. Changes are saved on this iPhone."
        }
    }
    private var syncColor: Color {
        switch model.syncState {
        case .local, .synced: .green
        case .syncing: Theme.accent
        case .offline, .conflict, .reauthenticationRequired: .orange
        }
    }
}

struct HiddenSongsView: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Hidden songs will not appear in lists or play. They stay saved in your favorites and playlists, ready to restore.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                if model.library?.hiddenTracks.isEmpty != false {
                    EmptyCard(icon: "eye", title: "No hidden songs", detail: "Use Hide song in a song's options to hide only that recording.")
                }
                ForEach(model.library?.hiddenTracks ?? []) { track in
                    HStack(spacing: 12) {
                        Artwork(url: track.artworkURL, symbol: "music.note", size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(track.artistName).font(.caption).foregroundStyle(Theme.muted)
                            if model.blockedIDs.contains(track.artistID) {
                                Text("This artist is also hidden.").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("Unhide") { model.unhideTrack(track.id) }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("unhide-track-\(track.id)")
                    }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(20)
        }
        .accessibilityIdentifier("hidden-songs-scroll")
        .background(Theme.background)
        .navigationTitle("Hidden songs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AppModel {
    var accountLabel: String { account?.isLocalWallet == true || account?.isCloudWallet == true ? (account?.userID ?? "") : "Signed in" }
}

struct SettingsLink: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 25)
            Text(title).font(.subheadline)
            Spacer()
            Image(systemName: "arrow.up.right").font(.caption)
        }.padding(15).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct AppleSignInButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 14
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func didTap() { action() }
    }
}
