import Foundation
import AVFoundation
import Combine

@MainActor
final class PlayerEngine: ObservableObject {
    static let shared = PlayerEngine()

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?

    @Published var currentTrack: TrackRecord?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    var queue: [TrackRecord] = []
    var queueIndex: Int = -1

    func play(_ track: TrackRecord) {
        stop()
        let url = URL(fileURLWithPath: track.path)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.volume = volume
        currentTrack = track
        duration = track.duration
        setupObservers(item: item)
        player?.play()
        isPlaying = true
    }

    func toggle() {
        guard let p = player else { return }
        if isPlaying { p.pause() } else { p.play() }
        isPlaying.toggle()
    }

    func stop() {
        removeObservers()
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
    }

    func seek(to time: Double) {
        let t = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func next() {
        guard !queue.isEmpty else { return }
        queueIndex = min(queueIndex + 1, queue.count - 1)
        play(queue[queueIndex])
    }

    func previous() {
        if currentTime > 3 { seek(to: 0); return }
        guard !queue.isEmpty else { return }
        queueIndex = max(queueIndex - 1, 0)
        play(queue[queueIndex])
    }

    func setQueue(_ tracks: [TrackRecord], startAt index: Int = 0) {
        queue = tracks
        queueIndex = index
        if index < tracks.count { play(tracks[index]) }
    }

    private func setupObservers(item: AVPlayerItem) {
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 1000),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.currentTime = time.seconds }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime, object: item
        )
    }

    private func removeObservers() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    @objc private func itemDidFinish() {
        if queueIndex < queue.count - 1 { next() } else { isPlaying = false; currentTime = 0 }
    }
}
