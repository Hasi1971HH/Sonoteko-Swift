import Foundation

struct ReplayGainResult {
    var trackGain: String
    var trackPeak: String
    var albumGain: String
    var albumPeak: String
}

actor ReplayGainService {
    static let shared = ReplayGainService()

    // nonisolated: pure filesystem check, no actor state accessed
    private nonisolated func ffmpegPath() -> String? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    nonisolated func isFFmpegAvailable() -> Bool { ffmpegPath() != nil }

    func analyzeTrack(path: String) async -> ReplayGainResult? {
        guard let ff = ffmpegPath() else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ff)
        task.arguments = ["-i", path, "-af", "replaygain", "-f", "null", "-"]
        let errPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errPipe
        try? task.run(); task.waitUntilExit()
        let output = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parseFFmpegReplayGain(output)
    }

    func analyzeAlbum(paths: [String], progress: @escaping (Int, Int) -> Void) async -> [String: ReplayGainResult] {
        var results: [String: ReplayGainResult] = [:]
        var trackGains: [Double] = []
        var trackPeaks: [Double] = []
        for (i, path) in paths.enumerated() {
            if let r = await analyzeTrack(path: path) {
                results[path] = r
                if let g = Double(r.trackGain.replacingOccurrences(of: " dB", with: "")) { trackGains.append(g) }
                if let p = Double(r.trackPeak) { trackPeaks.append(p) }
            }
            progress(i + 1, paths.count)
        }
        if !trackGains.isEmpty {
            let albumGain = String(format: "%.2f dB", trackGains.reduce(0, +) / Double(trackGains.count))
            let albumPeak = String(format: "%.6f", trackPeaks.max() ?? 1.0)
            for path in paths {
                if results[path] != nil {
                    results[path]!.albumGain = albumGain
                    results[path]!.albumPeak = albumPeak
                }
            }
        }
        return results
    }

    private func parseFFmpegReplayGain(_ output: String) -> ReplayGainResult? {
        var gain = "", peak = ""
        for line in output.components(separatedBy: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.contains("track_gain") {
                if let v = l.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) {
                    gain = v.hasSuffix(" dB") ? v : v + " dB"
                }
            } else if l.contains("track_peak") {
                peak = l.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) ?? ""
            }
        }
        if gain.isEmpty { return nil }
        return ReplayGainResult(trackGain: gain, trackPeak: peak, albumGain: "", albumPeak: "")
    }
}
