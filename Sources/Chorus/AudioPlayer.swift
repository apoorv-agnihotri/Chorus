import AVFoundation
import Combine

@MainActor final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) throws {
        clear()
        let next = try AVAudioPlayer(contentsOf: url)
        next.delegate = self; next.prepareToPlay()
        player = next; duration = next.duration
    }
    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause(); isPlaying = false; timer?.invalidate() }
        else {
            if position >= duration { player.currentTime = 0; position = 0 }
            isPlaying = player.play()
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.position = self?.player?.currentTime ?? 0 }
            }
        }
    }
    func seek(_ value: Double) { player?.currentTime = value; position = value }
    func clear() { player?.stop(); player = nil; timer?.invalidate(); timer = nil; isPlaying = false; position = 0; duration = 0 }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false; self.position = self.duration; self.timer?.invalidate() }
    }
}
