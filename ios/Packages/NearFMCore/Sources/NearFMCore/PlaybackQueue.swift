import Foundation

public struct PlaybackQueue: Sendable {
    public private(set) var tracks: [Track] = []
    public private(set) var index: Int = 0
    public private(set) var artistID: String?

    public var current: Track? {
        tracks.indices.contains(index) ? tracks[index] : nil
    }

    public init() {}

    public mutating func replace(with tracks: [Track], artistID: String? = nil, startID: String? = nil) {
        var seen = Set<String>()
        self.tracks = tracks.filter { (artistID == nil || $0.artistID == artistID) && seen.insert($0.id).inserted }
        self.artistID = self.tracks.isEmpty ? nil : artistID
        index = self.tracks.firstIndex(where: { $0.id == startID }) ?? 0
    }

    public mutating func append(_ tracks: [Track]) {
        var seen = Set(self.tracks.map(\.id))
        self.tracks += tracks.filter { (artistID == nil || $0.artistID == artistID) && seen.insert($0.id).inserted }
    }

    public mutating func append(_ track: Track) {
        append([track])
    }

    @discardableResult
    public mutating func next(repeatAll: Bool) -> Bool {
        guard !tracks.isEmpty else { return false }
        if index + 1 < tracks.count {
            index += 1
            return true
        }
        if repeatAll {
            index = 0
            return true
        }
        return false
    }

    @discardableResult
    public mutating func previous() -> Bool {
        guard index > 0, !tracks.isEmpty else { return false }
        index -= 1
        return true
    }

    public mutating func removeArtist(_ artistID: String) {
        guard self.artistID == nil || self.artistID == artistID else { return }
        removeTracks(Set(tracks.filter { $0.artistID == artistID }.map(\.id)))
    }

    public mutating func removeTrack(_ trackID: String) {
        removeTracks([trackID])
    }

    /// Keep the current song if possible; otherwise advance in the original order.
    public mutating func removeTracks(_ trackIDs: Set<String>) {
        guard !trackIDs.isEmpty, !tracks.isEmpty else { return }
        let survivors = tracks.enumerated().filter { !trackIDs.contains($0.element.id) }
        guard survivors.count != tracks.count else { return }
        let next = survivors.first(where: { $0.offset >= index }) ?? survivors.last
        tracks = survivors.map(\.element)
        if let next {
            index = tracks.firstIndex(where: { $0.id == next.element.id }) ?? 0
        } else {
            index = 0
            artistID = nil
        }
    }

    public mutating func shuffle() {
        guard let current, tracks.count > 1 else { return }
        var rest = tracks.filter { $0.id != current.id }
        rest.shuffle()
        tracks = [current] + rest
        index = 0
    }
}
