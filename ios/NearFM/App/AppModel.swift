import CryptoKit
import Foundation
import NearFMCore
import Observation

@MainActor @Observable
final class AppModel {
    enum SyncState: Equatable { case local, syncing, synced, offline, conflict, reauthenticationRequired }

    private(set) var artists: [Artist] = []
    private(set) var tracks: [Track] = []
    private(set) var selectedArtistTracks: [Track] = []
    private(set) var selectedArtist: Artist?
    private(set) var selectedArtistHasMore = false
    private(set) var searchText = ""
    private(set) var catalogLoading = false
    private(set) var catalogHasMore = false
    private(set) var artistHasMore = false
    private(set) var account: MobileSession?
    private(set) var config: MobileConfig?
    private(set) var syncState: SyncState = .local
    private(set) var guestMergeAvailable = false
    var errorText: String?
    var noticeText: String?
    var isAuthenticating = false
    var playerPresented = false
    let player: AudioPlayer

    private let authentication = AuthenticationService()
    private let publicCatalog = PublicCatalog()
    private let baseURL = MobileAPI.configuredURL("MobileAPIBaseURL")
    private let cloudURL = MobileAPI.configuredURL("CloudAPIBaseURL")
    private let bridgeURL = MobileAPI.configuredURL("MeteorBridgeURL")
    private var libraryStore: LibraryStore?
    private var guestStore: LibraryStore?
    private var libraryRevision = 0
    private var catalogGeneration = UUID()
    private var artistPage = 1
    private var trackPage = 1
    private var browseArtistPage = 0
    private var browseArtistLoadingID: String?
    private var browseGeneration = UUID()
    private var playbackArtistPages: [String: Int] = [:]
    private var playbackArtistExhausted: Set<String> = []
    private var playbackArtistLoading: [String: UUID] = [:]
    private var playbackArtistIntent: [String: UUID] = [:]
    private var playbackGeneration = UUID()
    private var synchronizer: LibrarySynchronizer?
    private var accountActionInProgress = false
    private var appliedBlockedIDs: Set<String> = []
    private var accountGeneration = UUID()
    let isDemo: Bool

    var library: LibrarySnapshot? { _ = libraryRevision; return libraryStore?.snapshot }
    var isSignedIn: Bool { account != nil }
    var usesPublicCatalog: Bool { baseURL == nil }
    var apiConfigured: Bool { true }
    var cloudConfigured: Bool { cloudURL != nil || baseURL != nil }
    var cloudSyncEnabled: Bool {
        cloudConfigured && account != nil && account?.isLocalWallet != true && account?.accessToken.isEmpty == false
    }
    var needsCloudReauthentication: Bool { account?.isCloudWallet == true && account?.accessToken.isEmpty == true }
    var canEnableCloud: Bool { cloudURL != nil && account?.isLocalWallet == true }
    var isChangingAccount: Bool { accountActionInProgress }
    var privacyURL: URL? { config?.privacyURL ?? MobileAPI.configuredURL("PrivacyPolicyURL") }
    var supportURL: URL? { config?.supportURL ?? MobileAPI.configuredURL("SupportURL") }
    var canAppleLogin: Bool { config?.appleEnabled == true }
    var canMeteorLogin: Bool { config?.meteorEnabled == true && bridgeURL != nil }

    init() {
        #if DEBUG
        isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        isDemo = false
        #endif
        let directory = Self.storageDirectory()
        let savedAccount = Self.testStoreID == nil ? SessionKeychain.load() : nil
        let restoredAccount = (savedAccount?.isLocalWallet == true || savedAccount?.isCloudWallet == true
                               || MobileAPI.configuredURL("MobileAPIBaseURL") != nil) ? savedAccount : nil
        player = AudioPlayer(restoreURL: directory.appending(path: "playback.json"), ownerID: restoredAccount?.userID)
        do {
            guestStore = try LibraryStore(fileURL: directory.appending(path: "guest-library.json"))
            account = restoredAccount
            if let userID = restoredAccount?.userID {
                libraryStore = try LibraryStore(fileURL: Self.libraryURL(for: userID))
                if restoredAccount?.isLocalWallet != true {
                    try libraryStore?.enableCloudSync(legacyPending: UserDefaults.standard.bool(forKey: "library-pending-\(userID)"))
                    UserDefaults.standard.removeObject(forKey: "library-pending-\(userID)")
                }
                guestMergeAvailable = !(guestStore?.snapshot.favorites.isEmpty ?? true) || !(guestStore?.snapshot.playlists.isEmpty ?? true)
            } else {
                libraryStore = guestStore
            }
            syncState = account == nil || account?.isLocalWallet == true ? .local : (needsCloudReauthentication ? .reauthenticationRequired : .offline)
        } catch {
            errorText = "Библиотеку не удалось открыть: \(error.localizedDescription). Данные на диске сохранены."
        }
        player.onNeedMoreArtistTracks = { [weak self] artistID, intentID in
            Task { @MainActor [weak self] in await self?.loadMorePlaybackArtist(artistID, intentID: intentID) }
        }
        configureSynchronizer()
        Task { await bootstrap() }
    }

    private static func storageDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #if DEBUG
        let directory = testStoreID.map { root.appending(path: "NearFM-UITests/\($0)", directoryHint: .isDirectory) }
            ?? root.appending(path: "NearFM", directoryHint: .isDirectory)
        #else
        let directory = root.appending(path: "NearFM", directoryHint: .isDirectory)
        #endif
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var testStoreID: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--ui-test-store"), arguments.indices.contains(flag + 1),
              let id = UUID(uuidString: arguments[flag + 1]) else { return nil }
        return id.uuidString
        #else
        return nil
        #endif
    }

    private static func libraryURL(for userID: String?) -> URL {
        let name: String
        if let userID {
            let digest = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
            name = "account-\(digest).json"
        } else { name = "guest-library.json" }
        return storageDirectory().appending(path: name)
    }

    private func api() -> MobileAPI {
        // A cloud-wallet token never belongs on the separate catalog or legacy service.
        MobileAPI(baseURL: baseURL, accessToken: account?.kind == nil ? account?.accessToken : nil)
    }
    private func cloudAPI(authenticated: Bool = true) -> MobileAPI {
        MobileAPI(baseURL: cloudURL ?? baseURL, accessToken: authenticated ? account?.accessToken : nil)
    }
    private func catalogTracks(query: String = "", artistID: String? = nil, page: Int = 1) async throws -> TrackPage {
        if usesPublicCatalog { return try await publicCatalog.tracks(query: query, artistID: artistID, page: page) }
        return try await api().tracks(query: query, artistID: artistID, page: page)
    }
    private func catalogArtists(query: String = "", page: Int = 1) async throws -> ArtistPage {
        if usesPublicCatalog { return try await publicCatalog.artists(query: query, page: page) }
        return try await api().artists(query: query, page: page)
    }

    private func bootstrap() async {
        if isDemo {
            #if DEBUG
            guard let fixture = Bundle.main.url(forResource: "demo", withExtension: "wav") else {
                errorText = "Демо-аудио отсутствует в сборке."
                return
            }
            let demo = Track(id: "demo-track", title: "Демо-запись", artistID: "demo-artist", artistName: "Демо-автор", audioURL: fixture, artworkURL: nil, duration: nil)
            artists = [Artist(id: "demo-artist", name: "Демо-автор", artworkURL: nil, trackCount: 1)]
            tracks = [demo]
            catalogHasMore = false
            #endif
            return
        }
        if usesPublicCatalog {
            config = MobileConfig(meteorEnabled: bridgeURL != nil, appleEnabled: false, privacyURL: privacyURL, supportURL: supportURL)
        } else {
            do { config = try await api().config() }
            catch { errorText = error.localizedDescription }
        }
        await search("")
        if cloudURL != nil {
            // Cloud outages must not prevent loading or playing the public catalog.
            if let cloudConfig = try? await cloudAPI(authenticated: false).config() { config = cloudConfig }
        }
        if account != nil { await refreshLibrary() }
    }

    func search(_ text: String) async {
        searchText = text
        catalogGeneration = UUID()
        let generation = catalogGeneration
        artistPage = 1
        trackPage = 1
        guard !isDemo else { return }
        catalogLoading = true
        defer { if catalogGeneration == generation { catalogLoading = false } }
        do {
            async let foundArtists = catalogArtists(query: text)
            async let foundTracks = catalogTracks(query: text)
            let (a, t) = try await (foundArtists, foundTracks)
            guard generation == catalogGeneration else { return }
            artistPage = a.page
            trackPage = t.page
            artists = a.artists.filter { !blockedIDs.contains($0.id) }
            tracks = t.tracks.filter { !blockedIDs.contains($0.artistID) }
            artistHasMore = a.hasMore
            catalogHasMore = t.hasMore
        } catch { if catalogGeneration == generation { errorText = error.localizedDescription } }
    }

    func loadMoreCatalog() async {
        guard catalogHasMore, !catalogLoading, !isDemo else { return }
        let generation = catalogGeneration
        let query = searchText
        catalogLoading = true
        defer { if catalogGeneration == generation { catalogLoading = false } }
        do {
            let page = try await catalogTracks(query: query, page: trackPage + 1)
            guard catalogGeneration == generation else { return }
            trackPage = page.page
            tracks.append(contentsOf: page.tracks.filter { incoming in !blockedIDs.contains(incoming.artistID) && !tracks.contains(where: { $0.id == incoming.id }) })
            catalogHasMore = page.hasMore
        } catch { if catalogGeneration == generation { errorText = error.localizedDescription } }
    }

    func loadMoreArtists() async {
        guard artistHasMore, !catalogLoading, !isDemo else { return }
        let generation = catalogGeneration
        let query = searchText
        catalogLoading = true
        defer { if catalogGeneration == generation { catalogLoading = false } }
        do {
            let page = try await catalogArtists(query: query, page: artistPage + 1)
            guard catalogGeneration == generation else { return }
            artistPage = page.page
            artists.append(contentsOf: page.artists.filter { incoming in !blockedIDs.contains(incoming.id) && !artists.contains(where: { $0.id == incoming.id }) })
            artistHasMore = page.hasMore
        } catch { if catalogGeneration == generation { errorText = error.localizedDescription } }
    }

    func selectArtist(_ artist: Artist) async {
        selectedArtist = artist
        selectedArtistTracks = []
        selectedArtistHasMore = true
        browseArtistPage = 0
        browseArtistLoadingID = nil
        browseGeneration = UUID()
        await loadMoreArtistTracks(artistID: artist.id)
    }

    func loadMoreArtistTracks(artistID: String) async {
        guard !blockedIDs.contains(artistID), selectedArtist?.id == artistID,
              selectedArtistHasMore, browseArtistLoadingID != artistID else { return }
        if isDemo {
            selectedArtistTracks = tracks.filter { $0.artistID == artistID }
            selectedArtistHasMore = false
            return
        }
        browseArtistLoadingID = artistID
        let generation = browseGeneration
        defer { if browseArtistLoadingID == artistID && browseGeneration == generation { browseArtistLoadingID = nil } }
        let requestedPage = browseArtistPage + 1
        do {
            let page = try await catalogTracks(artistID: artistID, page: requestedPage)
            guard selectedArtist?.id == artistID, browseGeneration == generation else { return }
            browseArtistPage = page.page
            selectedArtistHasMore = page.hasMore
            let additions = page.tracks.filter { $0.artistID == artistID && !blockedIDs.contains($0.artistID) && !selectedArtistTracks.contains($0) }
            selectedArtistTracks.append(contentsOf: additions)
        } catch { errorText = error.localizedDescription }
    }

    private func loadMorePlaybackArtist(_ artistID: String, intentID: UUID) async {
        guard player.artistID == artistID, player.loadsMoreAuthorTracks,
              !blockedIDs.contains(artistID), !playbackArtistExhausted.contains(artistID) else {
            player.cancelPendingAuthorLoad(intentID: intentID)
            return
        }
        playbackArtistIntent[artistID] = intentID
        // An existing request will deliver the next page to the latest explicit Next intent.
        guard playbackArtistLoading[artistID] == nil else { return }
        let requestID = UUID()
        let generation = playbackGeneration
        playbackArtistLoading[artistID] = requestID
        defer { if playbackArtistLoading[artistID] == requestID { playbackArtistLoading[artistID] = nil } }
        guard !isDemo else {
            playbackArtistExhausted.insert(artistID)
            let activeIntent = playbackArtistIntent.removeValue(forKey: artistID) ?? intentID
            player.resumeAfterAuthorPage(hasMore: false, intentID: activeIntent)
            return
        }
        do {
            while player.artistID == artistID && playbackGeneration == generation {
                let pageNumber = (playbackArtistPages[artistID] ?? 0) + 1
                let page = try await catalogTracks(artistID: artistID, page: pageNumber)
                guard player.artistID == artistID, playbackGeneration == generation,
                      !blockedIDs.contains(artistID) else { return }
                playbackArtistPages[artistID] = page.page
                let existing = Set(player.tracks.map(\.id))
                let additions = page.tracks.filter { $0.artistID == artistID && !existing.contains($0.id) }
                player.append(additions)
                if !page.hasMore { playbackArtistExhausted.insert(artistID) }
                if !additions.isEmpty || !page.hasMore {
                    let activeIntent = playbackArtistIntent.removeValue(forKey: artistID) ?? intentID
                    player.resumeAfterAuthorPage(hasMore: page.hasMore, intentID: activeIntent)
                    return
                }
            }
        } catch {
            guard player.artistID == artistID, playbackGeneration == generation else { return }
            let activeIntent = playbackArtistIntent.removeValue(forKey: artistID) ?? intentID
            player.cancelPendingAuthorLoad(intentID: activeIntent)
            errorText = error.localizedDescription
        }
    }

    func playArtist(_ artist: Artist, starting track: Track? = nil) {
        let songs = selectedArtistTracks.filter { $0.artistID == artist.id && !blockedIDs.contains($0.artistID) }
        guard !songs.isEmpty else { return }
        playbackGeneration = UUID()
        playbackArtistLoading[artist.id] = nil
        playbackArtistIntent[artist.id] = nil
        playbackArtistPages[artist.id] = browseArtistPage
        if selectedArtistHasMore { playbackArtistExhausted.remove(artist.id) }
        else { playbackArtistExhausted.insert(artist.id) }
        player.play(songs, artistID: artist.id, startID: track?.id, loadMoreAuthorTracks: selectedArtistHasMore)
    }

    func playTrack(_ track: Track) {
        guard !blockedIDs.contains(track.artistID) else { return }
        playbackGeneration = UUID()
        player.play([track], artistID: track.artistID, startID: track.id)
    }

    func playPlaylist(_ playlist: Playlist, startID: String? = nil) {
        playTracks(playlist.tracks, startID: startID ?? playlist.tracks.first?.id)
    }

    func playTracks(_ tracks: [Track], startID: String?) {
        let songs = tracks.filter { !blockedIDs.contains($0.artistID) }
        playbackGeneration = UUID()
        player.play(songs, startID: startID)
    }

    var blockedIDs: Set<String> { Set(library?.blockedArtistIDs ?? []) }
    func isFavorite(_ track: Track) -> Bool { library?.favorites.contains(where: { $0.id == track.id }) == true }

    private func editLibrary(_ body: (LibraryStore) throws -> Void) {
        guard !accountActionInProgress else { return }
        guard let libraryStore else { errorText = "Библиотека недоступна."; return }
        do {
            try body(libraryStore)
            libraryRevision += 1
            if isSignedIn && cloudSyncEnabled { requestSync() }
        } catch { errorText = error.localizedDescription }
    }

    func toggleFavorite(_ track: Track) { editLibrary { try $0.toggleFavorite(track) } }
    func createPlaylist(name: String) { editLibrary { _ = try $0.createPlaylist(name: name) } }
    func renamePlaylist(_ id: String, name: String) { editLibrary { try $0.renamePlaylist(id: id, name: name) } }
    func deletePlaylist(_ id: String) { editLibrary { try $0.deletePlaylist(id: id) } }
    func add(_ track: Track, to playlistID: String) { editLibrary { try $0.add(track, to: playlistID) } }
    func remove(_ trackID: String, from playlistID: String) { editLibrary { try $0.remove(trackID: trackID, from: playlistID) } }
    func move(in playlistID: String, from: Int, to: Int) { editLibrary { try $0.moveTrack(in: playlistID, from: from, to: to) } }
    func blockArtist(_ artistID: String) {
        guard !accountActionInProgress else { return }
        editLibrary { try $0.blockArtist(artistID) }
        guard blockedIDs.contains(artistID) else { return }
        player.blockArtist(artistID)
        appliedBlockedIDs.insert(artistID)
        artists.removeAll { $0.id == artistID }
        tracks.removeAll { $0.artistID == artistID }
        selectedArtistTracks.removeAll { $0.artistID == artistID }
    }
    func unblockArtist(_ artistID: String) { editLibrary { try $0.unblockArtist(artistID) }; Task { await search(searchText) } }

    func report(track: Track?, artistID: String?, reason: String) async {
        guard !isDemo else { errorText = "В демо-режиме жалобы не отправляются."; return }
        do {
            try await api().report(trackID: track?.id, artistID: artistID, reason: reason)
            noticeText = "Жалоба отправлена на рассмотрение."
        } catch { errorText = error.localizedDescription }
    }

    func loginWithApple() async {
        guard !isAuthenticating, !accountActionInProgress else { return }
        guard canAppleLogin else { errorText = "Вход через Apple временно недоступен."; return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do { try await acceptSession(authentication.signInWithApple(api: api())) }
        catch AuthenticationError.cancelled {} catch { errorText = error.localizedDescription }
    }

    func loginWithMeteor() async {
        guard canMeteorLogin, !isAuthenticating, !accountActionInProgress else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            if cloudURL != nil {
                try await acceptSession(authentication.signInWithMeteorCloud(api: cloudAPI(authenticated: false), bridgeURL: bridgeURL))
            } else if usesPublicCatalog, let bridgeURL {
                let accountID = try await authentication.meteorIdentity(bridgeURL: bridgeURL)
                try await acceptSession(MobileSession(accessToken: "", userID: accountID, kind: "verified-local-wallet"))
            } else {
                try await acceptSession(authentication.signInWithMeteor(api: api(), bridgeURL: bridgeURL))
            }
        }
        catch AuthenticationError.cancelled {} catch { errorText = error.localizedDescription }
    }

    private func acceptSession(_ incoming: MobileSession) async throws {
        let incomingStore = try LibraryStore(fileURL: Self.libraryURL(for: incoming.userID))
        if !incoming.isLocalWallet {
            try incomingStore.enableCloudSync(legacyPending: UserDefaults.standard.bool(forKey: "library-pending-\(incoming.userID)"))
        }
        try SessionKeychain.save(incoming)
        synchronizer?.invalidate()
        accountGeneration = UUID()
        account = incoming
        libraryStore = incomingStore
        libraryRevision += 1
        player.switchOwner(incoming.userID)
        appliedBlockedIDs = []
        playbackGeneration = UUID()
        guestMergeAvailable = !(guestStore?.snapshot.favorites.isEmpty ?? true) || !(guestStore?.snapshot.playlists.isEmpty ?? true)
        syncState = incoming.isLocalWallet ? .local : .offline
        UserDefaults.standard.removeObject(forKey: "library-pending-\(incoming.userID)")
        configureSynchronizer()
        applyLibraryBlocks()
        if cloudSyncEnabled { await refreshLibrary() }
    }

    private func configureSynchronizer() {
        synchronizer?.invalidate()
        synchronizer = nil
        guard cloudSyncEnabled, let libraryStore else { return }
        let generation = accountGeneration
        let coordinator = LibrarySynchronizer(store: libraryStore, remote: cloudAPI())
        coordinator.onChange = { [weak self, weak coordinator] in
            guard let self, let coordinator, self.accountGeneration == generation else { return }
            self.libraryRevision += 1
            self.applyLibraryBlocks()
            switch coordinator.state {
            case .idle: self.syncState = .offline
            case .syncing: self.syncState = .syncing
            case .synced: self.syncState = .synced
            case .offline: self.syncState = .offline
            case .conflict: self.syncState = .conflict
            case .reauthenticationRequired:
                self.requireReauthentication()
            }
        }
        synchronizer = coordinator
    }

    private func requireReauthentication() {
        guard let account, account.isCloudWallet else { expireSession(); return }
        // Keep the wallet's local library, including offline edits, available.
        synchronizer?.invalidate()
        synchronizer = nil
        let expired = MobileSession(accessToken: "", userID: account.userID, kind: account.kind)
        self.account = expired
        syncState = .reauthenticationRequired
        do { try SessionKeychain.save(expired) }
        catch { errorText = error.localizedDescription }
    }

    private func applyLibraryBlocks() {
        let blocked = blockedIDs
        for id in blocked.subtracting(appliedBlockedIDs) { player.blockArtist(id) }
        appliedBlockedIDs = blocked
        artists.removeAll { blockedIDs.contains($0.id) }
        tracks.removeAll { blockedIDs.contains($0.artistID) }
        selectedArtistTracks.removeAll { blockedIDs.contains($0.artistID) }
    }

    func refreshLibrary() async {
        guard cloudSyncEnabled, !accountActionInProgress else { return }
        if synchronizer == nil { configureSynchronizer() }
        await synchronizer?.synchronize()
    }

    func sceneBecameActive() async {
        guard !isDemo, !isAuthenticating else { return }
        await refreshLibrary()
    }

    private func requestSync() {
        guard cloudSyncEnabled, !accountActionInProgress else { return }
        Task { await refreshLibrary() }
    }

    func resolveConflictUseCloud() {
        do { try synchronizer?.useCloud() }
        catch { errorText = error.localizedDescription }
    }

    func resolveConflictUseDevice() async {
        do { try await synchronizer?.useDevice() }
        catch { errorText = error.localizedDescription }
    }

    func mergeGuestLibrary() {
        guard account != nil, !accountActionInProgress, let guest = guestStore?.snapshot else { return }
        do {
            try libraryStore?.mergeGuest(guest)
            libraryRevision += 1
            guestMergeAvailable = false
            if cloudSyncEnabled { requestSync() }
        } catch { errorText = error.localizedDescription }
    }

    func logout() async {
        guard account != nil, !accountActionInProgress else { return }
        accountActionInProgress = true
        defer { accountActionInProgress = false }
        let generation = accountGeneration
        synchronizer?.invalidate()
        do { if cloudSyncEnabled { try await cloudAPI().logout() } }
        catch MobileAPIError.unauthorized {
            // An already expired/revoked token cannot prevent local sign-out.
        } catch {
            guard accountGeneration == generation else { return }
            configureSynchronizer()
            errorText = "Выход на сервере не подтверждён: \(error.localizedDescription)"
            return
        }
        if accountGeneration == generation { expireSession(showExpired: false) }
    }

    func deleteAccount() async {
        guard let deletingAccount = account, !accountActionInProgress else { return }
        if deletingAccount.isCloudWallet && !cloudSyncEnabled {
            errorText = "Войдите через Meteor ещё раз, чтобы удалить облачный профиль и его данные."
            return
        }
        accountActionInProgress = true
        defer { accountActionInProgress = false }
        let generation = accountGeneration
        synchronizer?.invalidate()
        var cloudDeleted = false
        do {
            if cloudSyncEnabled { try await cloudAPI().deleteAccount(); cloudDeleted = true }
            guard accountGeneration == generation else { return }
            let oldURL = Self.libraryURL(for: deletingAccount.userID)
            if FileManager.default.fileExists(atPath: oldURL.path) { try FileManager.default.removeItem(at: oldURL) }
            UserDefaults.standard.removeObject(forKey: "library-pending-\(deletingAccount.userID)")
            expireSession(showExpired: false)
            noticeText = "Аккаунт и его библиотека удалены."
        } catch MobileAPIError.unauthorized {
            guard accountGeneration == generation else { return }
            requireReauthentication()
            errorText = "Срок действия входа истёк. Подтвердите кошелёк через Meteor ещё раз, чтобы удалить облачный профиль. Локальная библиотека сохранена."
        } catch {
            guard accountGeneration == generation else { return }
            if cloudDeleted {
                // Server deletion succeeded; allow retrying just the failed local cleanup.
                let local = MobileSession(accessToken: "", userID: deletingAccount.userID, kind: "verified-local-wallet")
                account = local
                try? SessionKeychain.save(local)
                syncState = .local
            } else {
                configureSynchronizer()
            }
            errorText = "Удалить профиль не удалось: \(error.localizedDescription)"
        }
    }

    private func expireSession(showExpired: Bool = true) {
        synchronizer?.invalidate()
        synchronizer = nil
        SessionKeychain.clear()
        account = nil
        accountGeneration = UUID()
        libraryStore = guestStore
        libraryRevision += 1
        player.switchOwner(nil)
        appliedBlockedIDs = []
        playbackGeneration = UUID()
        guestMergeAvailable = false
        syncState = .local
        applyLibraryBlocks()
        if showExpired { errorText = "Сессия завершилась. Войдите снова." }
    }
}
