import Foundation
import KokoroCoreML
import ChorusKit

/// Called from LocalEngine, which serializes engine switching and inference.
public final class KokoroBackend: @unchecked Sendable {
    private let engine: KokoroEngine
    public static func isInstalled(at directory: URL) -> Bool { KokoroEngine.isDownloaded(at: directory) }
    public init(directory: URL) throws {
        // GPU warmup stalls in the macOS 27 driver on the development M1 Pro.
        // CPU placement also avoids allocating an additional GPU working set.
        engine = try KokoroEngine(modelDirectory: directory, forceCPU: true)
    }

    /// Install into staging, then rename. Cancelled/failed downloads never look complete.
    public static func install(at directory: URL) async throws {
        if isInstalled(at: directory) { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = directory.deletingLastPathComponent().appendingPathComponent("kokoro-install-\(UUID())")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let url = URL(string: "https://github.com/Jud/kokoro-coreml/releases/download/models-2026-03-23/kokoro-models.tar.gz")!
        let (download, response) = try await URLSession.shared.download(from: url)
        defer { try? fm.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xzf", download.path, "-C", staging.path]
        try process.run(); process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0, isInstalled(at: staging) else {
            throw StudioError.invalidAudio("The Kokoro download is incomplete. Please retry the preview.")
        }
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: staging, to: directory)
    }

    public func generate(text: String, recipe: KokoroRecipe, settings: VoiceSettings) throws -> WAVFile {
        _ = try recipe.validated(); try recipe.validate(settings: settings)
        let chunks = KokoroRecipe.chunks(try recipe.preparedText(text))
        let audio = try WAVFile()
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                let result = try engine.synthesize(text: chunk, voice: recipe.voice, speed: Float(settings.speed))
                try Task.checkCancellation()
                if index > 0 { try audio.appendSilence(seconds: 0.1) }
                try audio.append(result.samples)
            }
        }
        try audio.finish()
        return audio
    }
}
