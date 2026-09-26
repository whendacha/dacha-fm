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
                    Text("Настройки").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.cream)
                    Text("Аккаунт и ваша музыка").foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 13) {
                        Image(systemName: model.isSignedIn ? "person.crop.circle.fill" : "iphone.gen3")
                            .font(.title).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.isSignedIn ? "Аккаунт Near.fm" : "Гость")
                                .font(.headline).foregroundStyle(Theme.cream)
                            Text(model.isSignedIn ? (model.accountLabel) : "Библиотека хранится на iPhone")
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
                        SectionTitle(title: "Синхронизация", subtitle: "Войдите, чтобы видеть плейлисты на других устройствах")
                        AppleSignInButton { Task { await model.loginWithApple() } }
                            .frame(height: 52)
                            .disabled(model.isAuthenticating || !model.canAppleLogin)
                            .accessibilityLabel("Войти через Apple")
                        Button { Task { await model.loginWithMeteor() } } label: {
                            Label("Войти через Meteor", systemImage: "sparkles")
                                .font(.headline).frame(maxWidth: .infinity).padding(16)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                        }.disabled(model.isAuthenticating || !model.canMeteorLogin)
                        if model.isAuthenticating { ProgressView("Выполняется вход…").padding(.top, 4) }
                        if !model.canAppleLogin || !model.canMeteorLogin {
                            Text("Некоторые способы входа временно недоступны.")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Text("Meteor попросит подписать только подтверждение владения аккаунтом. Приложение не запрашивает ключи и не выполняет перевод.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Библиотека", subtitle: "Состояние синхронизации")
                        if model.guestMergeAvailable {
                            Button { model.mergeGuestLibrary() } label: {
                                Label("Объединить гостевую библиотеку", systemImage: "square.stack.3d.up")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                            Text("Гостевые записи останутся на этом iPhone.").font(.caption).foregroundStyle(Theme.muted)
                        }
                        if model.syncState == .conflict {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Библиотека изменилась на другом устройстве.").font(.subheadline)
                                Button("Использовать облачную версию") { model.resolveConflictUseCloud() }
                                Button("Объединить обе версии") { model.resolveConflictMerge() }
                            }.padding(16).background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
                        }
                        if model.syncState == .offline {
                            Button("Повторить синхронизацию") { Task { await model.refreshLibrary() } }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Аккаунт", subtitle: "Управление входом и данными")
                        Button("Выйти") { logoutConfirmation = true }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        Button("Удалить аккаунт", role: .destructive) { deleteConfirmation = true }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        Text("Удаление стирает профиль Near.fm и личную библиотеку. Кошелёк Meteor и данные блокчейна остаются у вас.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }

                if let blocked = model.library?.blockedArtistIDs, !blocked.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Скрытые авторы", subtitle: "Их музыка не показывается и не играет")
                        ForEach(blocked, id: \.self) { id in
                            HStack {
                                Text(id).font(.subheadline).lineLimit(1)
                                Spacer()
                                Button("Показать") { model.unblockArtist(id) }.font(.caption.weight(.semibold))
                            }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Помощь и документы", subtitle: "Связь и правила")
                    if let url = model.supportURL { Link(destination: url) { SettingsLink(title: "Поддержка", symbol: "questionmark.circle") } }
                    else { SettingsLink(title: "Поддержка временно недоступна", symbol: "questionmark.circle").foregroundStyle(Theme.muted) }
                    if let url = model.privacyURL { Link(destination: url) { SettingsLink(title: "Политика приватности", symbol: "hand.raised") } }
                    else { SettingsLink(title: "Политика приватности временно недоступна", symbol: "hand.raised").foregroundStyle(Theme.muted) }
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationBarHidden(true)
        .confirmationDialog("Выйти из аккаунта?", isPresented: $logoutConfirmation) {
            Button("Выйти") { Task { await model.logout() } }
        } message: { Text("Локальная библиотека гостя будет показана после выхода.") }
        .confirmationDialog("Удалить аккаунт Near.fm?", isPresented: $deleteConfirmation) {
            Button("Удалить аккаунт", role: .destructive) { Task { await model.deleteAccount() } }
        } message: { Text("Профиль и синхронизированная библиотека будут удалены после подтверждения сервером.") }
    }

    private var syncLabel: String {
        switch model.syncState {
        case .local: "Только на устройстве"
        case .syncing: "Синхронизация…"
        case .synced: "Синхронизировано"
        case .offline: "Локальные изменения ожидают связи"
        case .conflict: "Требуется выбор версии"
        }
    }
    private var syncColor: Color {
        switch model.syncState {
        case .local, .synced: .green
        case .syncing: Theme.accent
        case .offline, .conflict: .orange
        }
    }
}

private extension AppModel {
    var accountLabel: String { "Вход выполнен" }
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
