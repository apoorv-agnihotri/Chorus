import Foundation
import Darwin
import MLX
import MLXRandom
import ChorusKit

public final class PocketBackend: @unchecked Sendable {
    private let model: PocketTTSModel
    public static let revision = "cbf71d5f6657bbc3f4bc02f85ee408261225bec7"
    private static let files = ["config.json", "model.safetensors", "tokenizer.json"] + CharacterVoiceRecipe.voices.map { "embeddings/\($0).safetensors" }
    public static func isInstalled(at directory: URL) -> Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }
    public static func install(at directory: URL) async throws {
        if isInstalled(at: directory) { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stage = directory.deletingLastPathComponent().appendingPathComponent("pocket-install-\(UUID())")
        try fm.createDirectory(at: stage.appendingPathComponent("embeddings"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        for file in files {
            try Task.checkCancellation()
            let url = URL(string: "https://huggingface.co/mlx-community/pocket-tts/resolve/\(revision)/\(file)")!
            let (temporary, response) = try await URLSession.shared.download(from: url)
            defer { try? fm.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try Task.checkCancellation()
            if file == "model.safetensors", (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.intValue != 235_739_497 {
                throw StudioError.invalidAudio("The voice download is incomplete. Please retry.")
            }
            try fm.moveItem(at: temporary, to: stage.appendingPathComponent(file))
        }
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: stage, to: directory)
    }
    public static func load(directory: URL, metallib: URL? = nil) async throws -> PocketBackend {
        let library = metallib ?? Bundle.main.url(forResource: "mlx", withExtension: "metallib")
        guard let library, FileManager.default.fileExists(atPath: library.path) else {
            throw StudioError.invalidAudio("The voice engine's Metal library is missing. Rebuild the app bundle.")
        }
        setenv("CHORUS_MLX_METALLIB", library.path, 1)
        Memory.cacheLimit = 128 * 1024 * 1024
        let model = try await PocketTTSModel.fromModelDirectory(directory)
        model.train(false)
        try Task.checkCancellation()
        return PocketBackend(model: model)
    }
    private init(model: PocketTTSModel) { self.model = model }
    public static func clearCache() { Memory.clearCache() }
    public func generate(text: String, recipe: CharacterVoiceRecipe) async throws -> WAVFile {
        _ = try recipe.validated()
        let prepared = try recipe.preparedText(text)
        let output = try WAVFile()
        MLXRandom.seed(recipe.seed)
        for chunk in KokoroRecipe.chunks(prepared, limit: 300) {
            try Task.checkCancellation()
            let audio = try await model.synthesize(text: chunk, voice: recipe.voice)
            eval(audio)
            try Task.checkCancellation()
            let rendered = try autoreleasepool { try AudioProcessing.renderCharacter(audio.asArray(Float.self), recipe: recipe) }
            try output.append(rendered)
        }
        try output.finish()
        Memory.clearCache()
        return output
    }
}
