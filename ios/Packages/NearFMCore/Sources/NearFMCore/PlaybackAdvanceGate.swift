import Foundation

/// Matches an asynchronous page response to the user's still-active request to advance.
public struct PlaybackAdvanceGate: Sendable {
    public private(set) var pendingID: UUID?

    public init() {}

    @discardableResult
    public mutating func begin() -> UUID {
        let id = UUID()
        pendingID = id
        return id
    }

    public mutating func invalidate() { pendingID = nil }

    @discardableResult
    public mutating func consume(_ id: UUID) -> Bool {
        guard pendingID == id else { return false }
        pendingID = nil
        return true
    }
}
