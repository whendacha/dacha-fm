import CryptoKit
import Foundation
import NearFMCore
import Observation

@MainActor @Observable
final class AppModel {
    enum SyncState: Equatable { case local, syncing, synced, offline, conflict }

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
    private let baseURL = MobileAPI.configuredURL("MobileAPIBaseURL")
    private let bridgeURL = MobileAPI.configuredURL("MeteorBridgeURL")
    private var libraryStore: LibraryStore?
    private var guestStore: LibraryStore?
    private var libraryRevision = 0
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
    private var syncRunning = false
    private var syncDirty = false
    private var remoteConflict: LibrarySnapshot?
    private var accountGeneration = UUID()
    let isDemo: Bool

    var library: LibrarySnapshot? { _ = libraryRevision; return libraryStore?.snapshot }
    var isSignedIn: Bool { account != nil }
    var apiConfigured: Bool { baseURL != nil }
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
        let restoredAccount = Self.testStoreID == nil ? SessionKeychain.load() : nil
        player = AudioPlayer(restoreURL: directory.appending(path: "playback.json"), ownerID: restoredAccount?.userID)
        do {
            guestStore = try LibraryStore(fileURL: directory.appending(path: "guest-library.json"))
            account = restoredAccount
            if let userID = restoredAccount?.userID {
                libraryStore = try LibraryStore(fileURL: Self.libraryURL(for: userID))
            } else {
                libraryStore = guestStore
            }
            syncState = account == nil ? .local : .offline
        } catch {
            errorText = "Библиотеку не удалось открыть: \(error.localizedDescription). Данные на диске сохранены."
        }
        player.onNeedMoreArtistTracks = { [weak self] artistID, intentID in
            Task { @MainActor [weak self] in await self?.loadMorePlaybackArtist(artistID, intentID: intentID) }
        }
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

    private func api() -> MobileAPI { MobileAPI(baseURL: baseURL, accessToken: account?.accessToken) }
    private var pendingKey: String? {
        guard let account else { return nil }
        return "library-pending-\(account.userID)"
    }
    private var hasPendingChanges: Bool { pendingKey.map { UserDefaults.standard.bool(forKey: $0) } ?? false }
    private func setPending(_ value: Bool) {
        guard let pendingKey else { return }
        UserDefaults.standard.set(value, forKey: pendingKey)
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
        guard apiConfigured else { errorText = MobileAPIError.unconfigured.localizedDescription; return }
        do { config = try await api().config() }
        catch { errorText = error.localizedDescription }
        await search("")
        if account != nil { await refreshLibrary() }
    }

    func search(_ text: String) async {
        searchText = text
        artistPage = 1
        trackPage = 1
        guard !isDemo else { return }
        catalogLoading = true
        defer { catalogLoading = false }
        do {
            async let foundArtists = api().artists(query: text)
            async let foundTracks = api().tracks(query: text)
            let (a, t) = try await (foundArtists, foundTracks)
            guard text == searchText else { return }
            artists = a.artists.filter { !blockedIDs.contains($0.id) }
            tracks = t.tracks.filter { !blockedIDs.contains($0.artistID) }
            artistHasMore = a.hasMore
            catalogHasMore = t.hasMore
        } catch { errorText = error.localizedDescription }
    }

    func loadMoreCatalog() async {
        guard catalogHasMore, !catalogLoading, !isDemo else { return }
        catalogLoading = true
        defer { catalogLoading = false }
        do {
            let page = try await api().tracks(query: searchText, page: trackPage + 1)
            trackPage = page.page
            tracks.append(contentsOf: page.tracks.filter { !blockedIDs.contains($0.artistID) && !tracks.contains($0) })
            catalogHasMore = page.hasMore
        } catch { errorText = error.localizedDescription }
    }

    func loadMoreArtists() async {
        guard artistHasMore, !catalogLoading, !isDemo else { return }
        catalogLoading = true
        defer { catalogLoading = false }
        do {
            let page = try await api().artists(query: searchText, page: artistPage + 1)
            artistPage = page.page
            artists.append(contentsOf: page.artists.filter { !blockedIDs.contains($0.id) && !artists.contains($0) })
            artistHasMore = page.hasMore
        } catch { errorText = error.localizedDescription }
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
            let page = try await api().tracks(artistID: artistID, page: requestedPage)
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
                let page = try await api().tracks(artistID: artistID, page: pageNumber)
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
        guard let libraryStore else { errorText = "Библиотека недоступна."; return }
        do {
            try body(libraryStore)
            libraryRevision += 1
            if isSignedIn { setPending(true); requestSync() }
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
        editLibrary { try $0.blockArtist(artistID) }
        player.blockArtist(artistID)
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
        guard canAppleLogin else { errorText = "Вход через Apple временно недоступен."; return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do { try await acceptSession(authentication.signInWithApple(api: api())) }
        catch AuthenticationError.cancelled {} catch { errorText = error.localizedDescription }
    }

    func loginWithMeteor() async {
        guard canMeteorLogin else { errorText = "Вход через Meteor временно недоступен."; return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do { try await acceptSession(authentication.signInWithMeteor(api: api(), bridgeURL: bridgeURL)) }
        catch AuthenticationError.cancelled {} catch { errorText = error.localizedDescription }
    }

    private func acceptSession(_ incoming: MobileSession) async throws {
        let incomingStore = try LibraryStore(fileURL: Self.libraryURL(for: incoming.userID))
        try SessionKeychain.save(incoming)
        accountGeneration = UUID()
        remoteConflict = nil
        account = incoming
        libraryStore = incomingStore
        libraryRevision += 1
        player.switchOwner(incoming.userID)
        syncDirty = false
        playbackGeneration = UUID()
        guestMergeAvailable = !(guestStore?.snapshot.favorites.isEmpty ?? true) || !(guestStore?.snapshot.playlists.isEmpty ?? true)
        syncState = .offline
        await refreshLibrary()
    }

    func refreshLibrary() async {
        guard let userID = account?.userID else { return }
        let generation = accountGeneration
        do {
            let remote = try await api().library()
            guard account?.userID == userID, accountGeneration == generation else { return }
            if hasPendingChanges {
                remoteConflict = remote
                syncState = .conflict
            } else {
                try libraryStore?.replace(remote)
                libraryRevision += 1
                syncState = .synced
            }
        } catch MobileAPIError.unauthorized {
            if account?.userID == userID && accountGeneration == generation { expireSession() }
        } catch {
            guard account?.userID == userID, accountGeneration == generation else { return }
            syncState = .offline
            errorText = error.localizedDescription
        }
    }

    private func requestSync() {
        syncDirty = true
        guard !syncRunning else { return }
        Task { await syncLoop() }
    }

    private func syncLoop() async {
        guard let userID = account?.userID, !syncRunning else { return }
        let generation = accountGeneration
        syncRunning = true
        defer {
            syncRunning = false
            if syncDirty && accountGeneration != generation { requestSync() }
        }
        while syncDirty {
            guard account?.userID == userID, accountGeneration == generation else { return }
            syncDirty = false
            guard let snapshot = libraryStore?.snapshot else { return }
            syncState = .syncing
            do {
                let saved = try await api().saveLibrary(snapshot)
                guard account?.userID == userID, accountGeneration == generation else { return }
                if syncDirty, let latest = libraryStore?.snapshot {
                    let updated = LibrarySnapshot(version: saved.version, favorites: latest.favorites,
                                                  playlists: latest.playlists, blockedArtistIDs: latest.blockedArtistIDs)
                    try libraryStore?.replace(updated)
                    libraryRevision += 1
                } else {
                    try libraryStore?.replace(saved)
                    libraryRevision += 1
                    setPending(false)
                    syncState = .synced
                }
            } catch MobileAPIError.conflict {
                guard account?.userID == userID, accountGeneration == generation else { return }
                do {
                    let fetchedConflict = try await api().library()
                    guard account?.userID == userID, accountGeneration == generation else { return }
                    remoteConflict = fetchedConflict
                    syncState = .conflict
                } catch {
                    guard account?.userID == userID, accountGeneration == generation else { return }
                    syncState = .offline
                    errorText = error.localizedDescription
                }
                return
            } catch MobileAPIError.unauthorized {
                if account?.userID == userID && accountGeneration == generation { expireSession() }
                return
            } catch {
                guard account?.userID == userID, accountGeneration == generation else { return }
                syncState = .offline
                errorText = error.localizedDescription
                return
            }
        }
    }

    func resolveConflictUseCloud() {
        guard let remoteConflict else { return }
        do { try libraryStore?.replace(remoteConflict); libraryRevision += 1; setPending(false); self.remoteConflict = nil; syncState = .synced }
        catch { errorText = error.localizedDescription }
    }

    func resolveConflictMerge() {
        guard let remoteConflict, let current = libraryStore?.snapshot else { return }
        do {
            let mergedBlocks = Array(Set(remoteConflict.blockedArtistIDs + current.blockedArtistIDs))
            let base = LibrarySnapshot(version: remoteConflict.version, favorites: remoteConflict.favorites,
                                       playlists: remoteConflict.playlists, blockedArtistIDs: mergedBlocks)
            try libraryStore?.replace(base)
            try libraryStore?.mergeGuest(current)
            libraryRevision += 1
            self.remoteConflict = nil
            setPending(true)
            requestSync()
        } catch { errorText = error.localizedDescription }
    }

    func mergeGuestLibrary() {
        guard account != nil, let guest = guestStore?.snapshot else { return }
        do {
            try libraryStore?.mergeGuest(guest)
            libraryRevision += 1
            guestMergeAvailable = false
            setPending(true)
            requestSync()
        } catch { errorText = error.localizedDescription }
    }

    func logout() async {
        guard account != nil else { return }
        let generation = accountGeneration
        do { try await api().logout() }
        catch {
            guard accountGeneration == generation else { return }
            errorText = "Выход на сервере не подтверждён: \(error.localizedDescription)"
            return
        }
        if accountGeneration == generation { expireSession() }
    }

    func deleteAccount() async {
        guard account != nil else { return }
        let generation = accountGeneration
        do {
            try await api().deleteAccount()
            guard accountGeneration == generation else { return }
            setPending(false)
            let oldURL = Self.libraryURL(for: account?.userID)
            SessionKeychain.clear()
            account = nil
            accountGeneration = UUID()
            remoteConflict = nil
            libraryStore = guestStore
            libraryRevision += 1
            player.switchOwner(nil)
            playbackGeneration = UUID()
            syncDirty = false
            syncState = .local
            try? FileManager.default.removeItem(at: oldURL)
            noticeText = "Аккаунт и его библиотека удалены."
        } catch {
            guard accountGeneration == generation else { return }
            errorText = "Удаление не подтверждено сервером: \(error.localizedDescription)"
        }
    }

    private func expireSession() {
        SessionKeychain.clear()
        account = nil
        accountGeneration = UUID()
        remoteConflict = nil
        libraryStore = guestStore
        libraryRevision += 1
        player.switchOwner(nil)
        playbackGeneration = UUID()
        syncDirty = false
        syncState = .local
        errorText = "Сессия завершилась. Войдите снова."
    }
}
