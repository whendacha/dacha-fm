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
        let prior = current?.id
        tracks.removeAll { $0.artistID == artistID }
        if tracks.isEmpty { index = 0; self.artistID = nil }
        else if let prior, let newIndex = tracks.firstIndex(where: { $0.id == prior }) { index = newIndex }
        else { index = min(index, tracks.count - 1) }
    }

    public mutating func shuffle() {
        guard let current, tracks.count > 1 else { return }
        var rest = tracks.filter { $0.id != current.id }
        rest.shuffle()
        tracks = [current] + rest
        index = 0
    }
}
