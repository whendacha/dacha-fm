import AVKit
import NearFMCore
import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.052, blue: 0.068)
    static let surface = Color(red: 0.105, green: 0.095, blue: 0.119)
    static let elevated = Color(red: 0.16, green: 0.141, blue: 0.16)
    static let accent = Color(red: 1, green: 0.66, blue: 0.43)
    static let muted = Color(red: 0.69, green: 0.66, blue: 0.68)
    static let cream = Color(red: 0.98, green: 0.94, blue: 0.90)
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            tabRoot { ListenView(model: model) }
                .tabItem { Label("Listen", systemImage: "waveform") }.tag(0)
            tabRoot { LibraryView(model: model) }
                .tabItem { Label("Library", systemImage: "square.stack") }.tag(1)
            tabRoot { SettingsView(model: model) }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .sheet(isPresented: $model.playerPresented) { PlayerView(model: model) }
        .alert("Dacha FM", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK", role: .cancel) { model.errorText = nil }
        } message: { Text(model.errorText ?? "") }
        .alert("Done", isPresented: Binding(get: { model.noticeText != nil }, set: { if !$0 { model.noticeText = nil } })) {
            Button("OK", role: .cancel) { model.noticeText = nil }
        } message: { Text(model.noticeText ?? "") }
    }

    private func tabRoot<Root: View>(@ViewBuilder _ content: () -> Root) -> some View {
        VStack(spacing: 0) {
            NavigationStack { content() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Reserve real space for every pushed destination, including at larger text sizes.
            miniPlayer.fixedSize(horizontal: false, vertical: true)
        }
        .background(Theme.background)
    }

    @ViewBuilder private var miniPlayer: some View {
        if model.player.current != nil { MiniPlayer(model: model) }
    }
}

struct ListenView: View {
    let model: AppModel
    @State private var query = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "waveform.path")
                            .font(.title2.weight(.bold)).foregroundStyle(Theme.accent)
                        Text("DACHA FM").font(.caption.weight(.black)).tracking(3).foregroundStyle(Theme.cream)
                        Spacer()
                        if model.isDemo { Text("DEMO").font(.caption2.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 5).background(Theme.accent, in: Capsule()).foregroundStyle(.black) }
                    }
                    Text("Music feels close.")
                        .font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.7)
                        .foregroundStyle(Theme.cream)
                    Text("Find an artist. Stay with their sound.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color(red: 0.30, green: 0.17, blue: 0.19), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28)
                )

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Song or artist", text: $query)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await model.search(query.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                    if !query.isEmpty {
                        Button { query = ""; Task { await model.search("") } } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(15).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))

                if !model.apiConfigured && !model.isDemo {
                    EmptyCard(icon: "wifi.slash", title: "Catalog unavailable", detail: "The service is temporarily unavailable. Please try again later.")
                }

                if !model.artists.isEmpty || model.artistHasMore {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(title: "Artists", subtitle: "One artist. One queue.")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(model.artists) { artist in
                                    NavigationLink { ArtistDetailView(model: model, artist: artist) } label: { ArtistCard(artist: artist) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("artist-\(artist.id)")
                                }
                                if model.artistHasMore {
                                    Button("More artists") { Task { await model.loadMoreArtists() } }
                                        .frame(width: 130, height: 170).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(title: query.isEmpty ? "Songs" : "Search results", subtitle: "Listen and save")
                    if model.tracks.isEmpty && !model.catalogLoading {
                        EmptyCard(icon: "music.note", title: "No songs yet", detail: model.isDemo ? "Demo audio is unavailable." : "Try another search or check back later.")
                    }
                    ForEach(model.tracks) { track in TrackRow(model: model, track: track) { model.playTrack(track) } }
                    if model.catalogHasMore {
                        Button { Task { await model.loadMoreCatalog() } } label: {
                            Label("Show more", systemImage: "arrow.down")
                                .frame(maxWidth: .infinity).padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityIdentifier("catalog-show-more")
                    }
                    if model.catalogLoading { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 28)
        }
        .accessibilityIdentifier("listen-scroll")
        .background(Theme.background)
        .navigationBarHidden(true)
    }
}

struct ArtistDetailView: View {
    let model: AppModel
    let artist: Artist
    @State private var reportPresented = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Artwork(url: artist.artworkURL, symbol: "person.crop.circle.fill", size: 170)
                    .frame(maxWidth: .infinity).padding(.top, 10)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ARTIST").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.accent)
                    Text(artist.name).font(.largeTitle.bold()).foregroundStyle(Theme.cream)
                    Text(artist.trackCount >= 0 ? "\(artist.trackCount) songs" : "Play artist").foregroundStyle(Theme.muted)
                }
                Button { model.playArtist(artist) } label: {
                    Label("Play this artist only", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(17)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.black)
                }
                .disabled(model.selectedArtistTracks.isEmpty)
                HStack {
                    Text("Songs").font(.title2.bold())
                    Spacer()
                    Menu {
                        Button("Report", systemImage: "flag") { reportPresented = true }
                        Button("Hide artist", systemImage: "hand.raised", role: .destructive) { model.blockArtist(artist.id) }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        .accessibilityLabel("Artist options")
                }
                ForEach(model.selectedArtistTracks) { track in
                    TrackRow(model: model, track: track) { model.playArtist(artist, starting: track) }
                }
                if model.selectedArtistTracks.isEmpty { EmptyCard(icon: "music.note", title: model.selectedArtistHasMore ? "Finding songs" : "No songs", detail: model.selectedArtistHasMore ? "Load the next catalog page to keep looking." : "This artist has no available recordings yet.") }
                if model.selectedArtistHasMore {
                    Button("Show more") { Task { await model.loadMoreArtistTracks(artistID: artist.id) } }
                        .frame(maxWidth: .infinity).padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("artist-show-more")
                }
            }.padding(20)
        }
        .accessibilityIdentifier("artist-scroll")
        .background(Theme.background)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artist.id) { await model.selectArtist(artist) }
        .sheet(isPresented: $reportPresented) { ReportView(model: model, track: nil, artistID: artist.id) }
    }
}

struct LibraryView: View {
    let model: AppModel
    @State private var newPlaylist = ""
    @State private var creating = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your music").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(model.cloudSyncEnabled && model.isSignedIn ? "Your account library" : "Saved on this iPhone")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                if let library = model.library {
                    NavigationLink { FavoritesView(model: model) } label: {
                        HStack(spacing: 15) {
                            Image(systemName: "heart.fill").font(.title2).foregroundStyle(Theme.accent)
                                .frame(width: 50, height: 50).background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Favorites").font(.headline)
                                Text("\(library.favorites.count) songs").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).accessibilityIdentifier("favorites-link")
                    HStack {
                        Text("Playlists").font(.title2.bold())
                        Spacer()
                        Button { creating = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .accessibilityLabel("Create playlist")
                    }
                    if library.playlists.isEmpty { EmptyCard(icon: "square.stack", title: "No playlists yet", detail: "Collect the music you want to return to.") }
                    ForEach(library.playlists) { playlist in
                        NavigationLink { PlaylistView(model: model, playlistID: playlist.id) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "music.note.list").font(.title2).foregroundStyle(Theme.accent)
                                    .frame(width: 54, height: 54).background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name).font(.headline)
                                    Text("\(playlist.tracks.count) songs").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                            }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).accessibilityIdentifier("playlist-\(playlist.id)")
                    }
                } else { EmptyCard(icon: "externaldrive.badge.exclamationmark", title: "Library unavailable", detail: "The library could not be opened. Check the startup message.") }
            }.padding(20)
        }
        .accessibilityIdentifier("library-scroll")
        .background(Theme.background)
        .navigationTitle("Library")
        .alert("New playlist", isPresented: $creating) {
            TextField("Name", text: $newPlaylist)
            Button("Create") { model.createPlaylist(name: newPlaylist); newPlaylist = "" }
            Button("Cancel", role: .cancel) { newPlaylist = "" }
        }
    }
}

struct FavoritesView: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.library?.favorites.isEmpty != false { EmptyCard(icon: "heart", title: "No favorites yet", detail: "Tap the heart beside a song to save it.") }
                ForEach(model.library?.favorites ?? []) { track in
                    TrackRow(model: model, track: track) { model.playTracks(model.library?.favorites ?? [], startID: track.id) }
                }
            }.padding(20)
        }.accessibilityIdentifier("favorites-scroll").background(Theme.background).navigationTitle("Favorites")
    }
}

struct PlaylistView: View {
    let model: AppModel
    let playlistID: String
    @State private var editingName = false
    @State private var name = ""
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    private var playlist: Playlist? { model.library?.playlists.first { $0.id == playlistID } }
    var body: some View {
        VStack(spacing: 0) {
            if let playlist {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(playlist.name).font(.largeTitle.bold())
                        Text("\(playlist.tracks.count) songs · drag to reorder")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Menu {
                        Button("Rename", systemImage: "pencil") { name = playlist.name; editingName = true }
                        Button("Delete playlist", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                        .accessibilityLabel("Playlist options")
                }.padding(20)
                Button { model.playPlaylist(playlist) } label: {
                    Label("Play playlist", systemImage: "play.fill").frame(maxWidth: .infinity).padding(14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                }.disabled(playlist.tracks.isEmpty).padding(.horizontal, 20)
                List {
                    ForEach(playlist.tracks) { track in
                        TrackRow(model: model, track: track) { model.playPlaylist(playlist, startID: track.id) }
                            .listRowBackground(Theme.background)
                            .swipeActions { Button("Remove", role: .destructive) { model.remove(track.id, from: playlistID) } }
                    }
                    .onMove { source, destination in
                        guard let from = source.first else { return }
                        let finalIndex = destination > from ? destination - 1 : destination
                        model.move(in: playlistID, from: from, to: finalIndex)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .accessibilityIdentifier("playlist-list")
                .environment(\.editMode, .constant(.active))
            }
        }
        .background(Theme.background).navigationTitle("Playlist").navigationBarTitleDisplayMode(.inline)
        .alert("Rename", isPresented: $editingName) {
            TextField("Name", text: $name)
            Button("Save") { model.renamePlaylist(playlistID, name: name) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete playlist?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { model.deletePlaylist(playlistID); dismiss() }
        } message: { Text("Songs will remain in the catalog and your favorites.") }
    }
}

struct TrackRow: View {
    let model: AppModel
    let track: Track
    let play: () -> Void
    @State private var addPresented = false
    @State private var reportPresented = false
    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) { Artwork(url: track.artworkURL, symbol: "music.note", size: 54) }
                .buttonStyle(.plain).accessibilityLabel("Play \(track.title)")
                .accessibilityIdentifier("play-track-\(track.id)")
            Button(action: play) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(Theme.cream)
                    Text(track.artistName).font(.caption).lineLimit(1).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button { model.toggleFavorite(track) } label: {
                Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                    .foregroundStyle(model.isFavorite(track) ? Theme.accent : Theme.muted)
            }.accessibilityLabel(model.isFavorite(track) ? "Remove from favorites" : "Add to favorites")
            Menu {
                Button("Add to playlist", systemImage: "text.badge.plus") { addPresented = true }
                Button("Report", systemImage: "flag") { reportPresented = true }
                Button("Hide artist", systemImage: "hand.raised", role: .destructive) { model.blockArtist(track.artistID) }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 38).foregroundStyle(Theme.muted) }
                .accessibilityLabel("Song options")
        }
        .padding(11).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .confirmationDialog("Add to playlist", isPresented: $addPresented) {
            ForEach(model.library?.playlists ?? []) { playlist in
                Button(playlist.name) { model.add(track, to: playlist.id) }
            }
        }
        .sheet(isPresented: $reportPresented) { ReportView(model: model, track: track, artistID: nil) }
    }
}

struct ReportView: View {
    let model: AppModel
    let track: Track?
    let artistID: String?
    @State private var reason = ""
    @State private var sending = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if model.usesPublicCatalog {
                    Section("Public catalog music") {
                        Text("The platform hosting this recording handles reports. Open the source to report a concern.")
                        if let track, let url = URL(string: "https://near.fm/song/\(track.id)") {
                            Link("Open recording page", destination: url)
                        } else {
                            Link("Open source catalog", destination: URL(string: "https://near.fm")!)
                        }
                        Button("Hide this artist") {
                            if let id = artistID ?? track?.artistID { model.blockArtist(id) }
                            dismiss()
                        }
                    }
                } else {
                    Section("Reason for report") {
                        TextField("Describe the issue", text: $reason, axis: .vertical).lineLimit(3...6)
                    }
                    Section { Text("Your report will be submitted for review after the server confirms receipt.").foregroundStyle(Theme.muted) }
                }
            }
            .navigationTitle("Report").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if !model.usesPublicCatalog {
                    Button("Send") {
                        sending = true
                        Task { await model.report(track: track, artistID: artistID, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)); sending = false; if model.noticeText != nil { dismiss() } }
                    }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    }
                }
            }
        }.tint(Theme.accent)
    }
}

struct Artwork: View {
    let url: URL?
    let symbol: String
    let size: CGFloat
    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                LinearGradient(colors: [Theme.elevated, Color(red: 0.28, green: 0.19, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol).font(.system(size: size * 0.34)).foregroundStyle(Theme.accent.opacity(0.8))
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .accessibilityHidden(true)
    }
}

struct ArtistCard: View {
    let artist: Artist
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Artwork(url: artist.artworkURL, symbol: "person.fill", size: 132)
            Text(artist.name).font(.subheadline.weight(.bold)).lineLimit(1).foregroundStyle(Theme.cream)
            Text(artist.trackCount >= 0 ? "\(artist.trackCount) songs" : "Play artist").font(.caption).foregroundStyle(Theme.muted)
        }.frame(width: 132, alignment: .leading)
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.bold()).foregroundStyle(Theme.cream)
            Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct EmptyCard: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(Theme.accent)
            Text(title).font(.headline).foregroundStyle(Theme.cream)
            Text(detail).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(28).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
