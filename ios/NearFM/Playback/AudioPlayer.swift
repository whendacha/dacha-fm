import AVFoundation
import Foundation
import MediaPlayer
import NearFMCore
import Observation

@MainActor @Observable
final class AudioPlayer {
    private(set) var queue = PlaybackQueue()
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?
    var repeatAll = false { didSet { persist() } }
    private(set) var loadsMoreAuthorTracks = false
    private var authorPaginationExhausted = true
    private var advanceGate = PlaybackAdvanceGate()
    private var pendingFailureSkip = false
    var onNeedMoreArtistTracks: ((String, UUID) -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private let restoreURL: URL
    private var ownerID: String?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var lastCheckpoint = Date.distantPast

    var current: Track? { queue.current }
    var tracks: [Track] { queue.tracks }
    var artistID: String? { queue.artistID }

    init(restoreURL: URL, ownerID: String?) {
        self.restoreURL = restoreURL
        self.ownerID = ownerID
        configureAudioSession()
        installObservers()
        installRemoteCommands()
        restore()
    }

    func play(_ tracks: [Track], artistID: String? = nil, startID: String? = nil, loadMoreAuthorTracks: Bool = false) {
        queue.replace(with: tracks, artistID: artistID, startID: startID)
        loadsMoreAuthorTracks = loadMoreAuthorTracks && artistID != nil
        authorPaginationExhausted = !loadsMoreAuthorTracks
        advanceGate.invalidate()
        pendingFailureSkip = false
        loadCurrent(autoplay: true)
    }

    func append(_ tracks: [Track]) {
        queue.append(tracks)
        persist()
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        advanceGate.invalidate()
        pendingFailureSkip = false
        player.pause()
        isPlaying = false
        persist()
        updateNowPlaying()
    }

    func resume() {
        advanceGate.invalidate()
        pendingFailureSkip = false
        guard current != nil else { return }
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch { errorMessage = "Could not start audio: \(error.localizedDescription)"; return }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func next() {
        guard advanceGate.pendingID == nil else { return }
        if queue.next(repeatAll: false) { loadCurrent(autoplay: true); return }
        if loadsMoreAuthorTracks && !authorPaginationExhausted, let artistID {
            requestAuthorPage(artistID: artistID, afterFailure: false)
            return
        }
        if repeatAll && queue.next(repeatAll: true) { loadCurrent(autoplay: true) }
        else { pause() }
    }

    func resumeAfterAuthorPage(hasMore: Bool, intentID: UUID) {
        authorPaginationExhausted = !hasMore
        let shouldAdvance = advanceGate.consume(intentID)
        guard shouldAdvance else { persist(); return }
        let isFailedSkip = pendingFailureSkip
        pendingFailureSkip = false
        if isFailedSkip {
            if queue.next(repeatAll: false) { loadCurrent(autoplay: true) }
            else if loadsMoreAuthorTracks && !authorPaginationExhausted, let artistID {
                requestAuthorPage(artistID: artistID, afterFailure: true)
            } else { pause() }
        } else { next() }
    }

    func cancelPendingAuthorLoad(intentID: UUID) {
        guard advanceGate.consume(intentID) else { return }
        pendingFailureSkip = false
        pause()
    }

    func previous() {
        advanceGate.invalidate()
        pendingFailureSkip = false
        if elapsed > 3 { seek(to: 0); return }
        guard queue.previous() else { seek(to: 0); return }
        loadCurrent(autoplay: true)
    }

    func seek(to seconds: Double) {
        advanceGate.invalidate()
        pendingFailureSkip = false
        guard seconds.isFinite else { return }
        let maxDuration = duration > 0 ? duration : seconds
        let target = max(0, min(seconds, maxDuration))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        persist()
        updateNowPlaying()
    }

    func shuffle() {
        advanceGate.invalidate()
        pendingFailureSkip = false
        queue.shuffle()
        loadCurrent(autoplay: isPlaying)
    }

    func blockArtist(_ id: String) {
        advanceGate.invalidate()
        pendingFailureSkip = false
        let wasCurrent = current?.artistID == id
        queue.removeArtist(id)
        if wasCurrent { player.pause(); loadCurrent(autoplay: false) }
        persist()
    }

    func hideTracks(_ ids: Set<String>) {
        guard queue.tracks.contains(where: { ids.contains($0.id) }) else { return }
        let removedCurrent = current.map { ids.contains($0.id) } ?? false
        let shouldAutoplay = isPlaying || player.timeControlStatus == .waitingToPlayAtSpecifiedRate || advanceGate.pendingID != nil
        // Removing another queued song must not cancel an in-flight Next request.
        if removedCurrent {
            advanceGate.invalidate()
            pendingFailureSkip = false
        }
        queue.removeTracks(ids)
        if queue.tracks.isEmpty {
            loadsMoreAuthorTracks = false
            authorPaginationExhausted = true
        }
        if removedCurrent { loadCurrent(autoplay: shouldAutoplay) }
        persist()
    }

    func clear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = PlaybackQueue()
        loadsMoreAuthorTracks = false
        authorPaginationExhausted = true
        advanceGate.invalidate()
        pendingFailureSkip = false
        elapsed = 0
        duration = 0
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        persist()
    }

    func switchOwner(_ ownerID: String?) {
        clear()
        self.ownerID = ownerID
        persist()
    }

    private func loadCurrent(autoplay: Bool, resumeAt: Double = 0) {
        statusObservation = nil
        player.pause()
        isPlaying = false
        errorMessage = nil
        guard let track = current else {
            player.replaceCurrentItem(with: nil)
            elapsed = 0
            duration = 0
            updateNowPlaying()
            persist()
            return
        }
        let item = AVPlayerItem(url: track.audioURL)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                guard self?.player.currentItem === item else { return }
                self?.errorMessage = item.error?.localizedDescription ?? "Could not load the song."
                self?.skipUnavailableTrack()
            }
        }
        player.replaceCurrentItem(with: item)
        elapsed = 0
        duration = track.duration ?? 0
        if resumeAt > 0 { seek(to: resumeAt) }
        if autoplay { resume() }
        updateNowPlaying()
        persist()
    }

    private func skipUnavailableTrack() {
        if queue.next(repeatAll: false) { loadCurrent(autoplay: true) }
        else if loadsMoreAuthorTracks && !authorPaginationExhausted, let artistID {
            requestAuthorPage(artistID: artistID, afterFailure: true)
        } else { pause() }
    }

    private func requestAuthorPage(artistID: String, afterFailure: Bool) {
        let intentID = advanceGate.begin()
        pendingFailureSkip = afterFailure
        player.pause()
        isPlaying = false
        persist()
        onNeedMoreArtistTracks?(artistID, intentID)
    }

    private func configureAudioSession() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default) }
        catch { errorMessage = "Audio is unavailable: \(error.localizedDescription)" }
    }

    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsed = max(0, time.seconds.isFinite ? time.seconds : 0)
                if let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 { self.duration = seconds }
                self.updateNowPlaying()
                self.checkpointIfNeeded()
            }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in self?.isPlaying = player.timeControlStatus == .playing }
        }
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let item = note.object as? AVPlayerItem, self?.player.currentItem === item else { return }
                self?.next()
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                self?.pause()
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                self?.pause()
            }
        })
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let actions: [(MPRemoteCommand, () -> Void)] = [
            (center.playCommand, { [weak self] in self?.resume() }),
            (center.pauseCommand, { [weak self] in self?.pause() }),
            (center.nextTrackCommand, { [weak self] in self?.next() }),
            (center.previousTrackCommand, { [weak self] in self?.previous() })
        ]
        for (command, action) in actions {
            let target = command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
            remoteTargets.append((command, target))
        }
        let seekTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: event.positionTime) }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, seekTarget))
    }

    private func updateNowPlaying() {
        guard let current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artistName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private struct RestoredQueue: Codable {
        let ownerID: String?
        let tracks: [Track]
        let index: Int
        let artistID: String?
        let loadsMoreAuthorTracks: Bool
        let authorPaginationExhausted: Bool
        let position: Double
        let repeatAll: Bool
    }

    private func persist() {
        let state = RestoredQueue(ownerID: ownerID, tracks: queue.tracks, index: queue.index, artistID: queue.artistID,
                                  loadsMoreAuthorTracks: loadsMoreAuthorTracks, authorPaginationExhausted: authorPaginationExhausted,
                                  position: elapsed, repeatAll: repeatAll)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: restoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: restoreURL, options: .atomic)) != nil { lastCheckpoint = Date() }
    }

    func checkpoint() { persist() }

    private func checkpointIfNeeded() {
        guard current != nil, Date().timeIntervalSince(lastCheckpoint) >= 5 else { return }
        persist()
    }

    private func restore() {
        guard let data = try? Data(contentsOf: restoreURL),
              let saved = try? JSONDecoder().decode(RestoredQueue.self, from: data),
              saved.ownerID == ownerID,
              saved.tracks.indices.contains(saved.index) else { return }
        repeatAll = saved.repeatAll
        loadsMoreAuthorTracks = saved.loadsMoreAuthorTracks
        authorPaginationExhausted = saved.authorPaginationExhausted
        queue.replace(with: saved.tracks, artistID: saved.artistID, startID: saved.tracks[saved.index].id)
        loadCurrent(autoplay: false, resumeAt: saved.position)
    }
}
