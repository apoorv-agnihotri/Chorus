import Foundation
import AVFoundation
import ChatterboxCoreML
import PerthCoreML
import ChorusKit
import ChorusKokoro
import ChorusPocket
import OSLog

enum EngineFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Owns the model and runs all inference and reference processing off the UI actor.
actor LocalEngine {
    private static let loadLog = Logger(subsystem: "com.chorus.studio", category: "model-load")
    private var model: ChatterboxCoreMLModel?
    private var kokoro: KokoroBackend?
    private var pocket: PocketBackend?
    var residentName: String? { pocket != nil ? "Character" : kokoro != nil ? "Kokoro" : model != nil ? "Chatterbox" : nil }
    private var directory: URL?
    private var home: URL?
    var isLoaded: Bool { model != nil || kokoro != nil || pocket != nil }

    func configure(directory: URL, home: URL) throws -> String {
        let perth = ModelRepository.downloadDirectory(hfHome: home, repoId: ModelRepository.perthRepoId)
        guard LocalModelFiles.canLoad(directory, watermarkDirectory: perth),
              let variant = ModelRepository.detectVariant(in: directory), variant != .multilingual else {
            throw EngineFailure.message("Choose a complete Chatterbox Turbo or Nano model folder.")
        }
        unload()
        self.directory = directory; self.home = home
        return variant.rawValue
    }

    /// Keep local configuration so the next generation can wake the engine.
    private func releasePocket() { if pocket != nil { pocket = nil; PocketBackend.clearCache() } }

    func releaseIdleModel() { model = nil; kokoro = nil; releasePocket() }

    func unload() {
        releaseIdleModel()
        directory = nil
        home = nil
    }

    func load(directory: URL, home: URL) async throws -> String {
        let cachedPerth = ModelRepository.downloadDirectory(hfHome: home, repoId: ModelRepository.perthRepoId)
        let perthDirectory = hasPerth(directory) ? directory : cachedPerth
        guard hasPerth(perthDirectory) else {
            throw EngineFailure.message("The local watermark model is missing. Use Download & load once to complete offline setup.")
        }
        // Construct from local files directly. Never call the upstream network fallback on load/generate.
        unload() // Release all previous model resources before allocating the replacement.
        self.directory = directory; self.home = home
        try Task.checkCancellation()
        let watermarker = try PerthWatermarker(modelDirectory: perthDirectory)
        // Automatic (.all) T3 placement can fail loading the decode function on
        // macOS 27. Keep its non-ANE operations on CPU; synth retains its defaults.
        let loaded = try await ModelLoadRecovery.load {
            try await ChatterboxCoreMLModel.load(from: directory,
                watermarker: PerthWatermark(watermarker: watermarker),
                computeUnits: PipelineComputeUnits(t3: .cpuAndNeuralEngine))
        } cpuFallback: {
            Self.loadLog.notice("Core ML function loading failed; retrying T3 on CPU.")
            return try await ChatterboxCoreMLModel.load(from: directory,
                watermarker: PerthWatermark(watermarker: watermarker),
                computeUnits: PipelineComputeUnits(t3: .cpuOnly))
        }
        guard loaded.loadedVariant != .multilingual else {
            throw EngineFailure.message("Choose a Chatterbox Turbo or Nano English model folder.")
        }
        try Task.checkCancellation()
        self.model = loaded; self.directory = directory; self.home = home
        return loaded.loadedVariant.rawValue
    }

    func download(variant: String, home: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let choice: ModelRepository.Variant = variant == "nano" ? .nano : .turbo
        let result = try await ModelRepository.download(repoId: choice.repoId, hfHome: home) { progress($0 * 0.94) }
        try Task.checkCancellation()
        guard !result.isPartiallyApplied, result.stillStale.isEmpty else {
            throw EngineFailure.message("The model download is incomplete. Retry to resume the remaining files.")
        }
        let perth = try await ModelRepository.download(repoId: ModelRepository.perthRepoId, hfHome: home,
            matching: ModelRepository.perthGlobs) { progress(0.94 + $0 * 0.06) }
        guard !perth.isPartiallyApplied, perth.stillStale.isEmpty else {
            throw EngineFailure.message("The watermark download is incomplete. Retry to finish setup.")
        }
        return result.directory
    }

    func generate(text: String, voice: URL?, settings: VoiceSettings = .init()) async throws -> WAVFile {
        _ = try settings.validated()
        releasePocket()
        kokoro = nil
        if model == nil {
            guard let directory, let home else { throw EngineFailure.message("Set up a local model first.") }
            _ = try await load(directory: directory, home: home)
        }
        guard let model else { throw EngineFailure.message("The local model could not load.") }
        var options = GenerationOptions.default
        options.temperature = Float(settings.variation)
        // Pacing values describe the final output, even when speed is changed.
        options.sentencePause = settings.sentencePause * settings.speed
        options.commaPause = settings.commaPause * settings.speed
        let audio = try WAVFile()
        var samples: [Float] = []
        for try await chunk in model.generateStream(settings.preparedText(text), voice: voice, options: options) {
            try Task.checkCancellation()
            if abs(settings.speed - 1) <= 0.001 {
                try audio.append(chunk.samples)
            } else {
                // Time stretching needs a complete block to preserve continuity.
                samples.append(contentsOf: chunk.samples)
            }
        }
        try Task.checkCancellation()
        if !samples.isEmpty { try audio.append(AudioProcessing.changeSpeed(samples, rate: settings.speed)) }
        try audio.finish()
        return audio
    }

    func generateKokoro(text: String, recipe: KokoroRecipe, settings: VoiceSettings, directory: URL) async throws -> WAVFile {
        _ = try recipe.validated(); try recipe.validate(settings: settings)
        _ = try recipe.preparedText(text)
        releasePocket()
        model = nil
        if kokoro == nil {
            try await KokoroBackend.install(at: directory)
            try Task.checkCancellation()
            kokoro = try KokoroBackend(directory: directory)
        }
        guard let kokoro else { throw EngineFailure.message("Kokoro could not load.") }
        return try kokoro.generate(text: text, recipe: recipe, settings: settings)
    }

    func generateCharacter(text: String, recipe: CharacterVoiceRecipe, directory: URL) async throws -> WAVFile {
        _ = try recipe.validated(); _ = try recipe.preparedText(text)
        model = nil; kokoro = nil
        if pocket == nil {
            try await PocketBackend.install(at: directory)
            try Task.checkCancellation()
            pocket = try await PocketBackend.load(directory: directory)
        }
        guard let pocket else { throw EngineFailure.message("The voice engine could not load.") }
        return try await pocket.generate(text: text, recipe: recipe)
    }

    func createLabReference(recipe: CharacterVoiceRecipe, kokoroDirectory: URL, output: URL) async throws {
        guard let base = recipe.kokoroBase else { throw EngineFailure.message("Missing Kokoro base.") }
        guard let home else { throw EngineFailure.message("Set up Chatterbox first.") }
        let cache = home.appendingPathComponent("LabReferences", isDirectory: true)
        let cached = cache.appendingPathComponent("\(base)-v1.safetensors")
        if FileManager.default.fileExists(atPath: cached.path) {
            try FileManager.default.copyItem(at: cached, to: output); return
        }
        let reference = try await generateKokoro(text: "Welcome to the voice studio. Every story begins with an idea, and every idea deserves to be heard. Today we are exploring a new voice for clear and expressive narration. Imagine a quiet morning, a journey through an unfamiliar city, and a conversation with an old friend. The light changes across the room as the afternoon approaches. There is always another chapter to discover, another question to ask, and something unexpected waiting around the corner. Take a moment, listen carefully, and let the story unfold in its own time.", recipe: KokoroRecipe(voice: base), settings: .init(), directory: kokoroDirectory)
        try await clone(reference: reference.url, output: output)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: output, to: cached)
    }

    func generateLab(text: String, recipe: CharacterVoiceRecipe, voice: URL, settings: VoiceSettings = .init()) async throws -> WAVFile {
        _ = try recipe.validated()
        // The clean reference supplies identity. Apply the recipe once, after synthesis.
        var delivery = settings
        if delivery.expression.isEmpty, let lab = recipe.lab {
            let styles = ["angry": "angry", "sad": "crying", "excited": "happy", "energetic": "happy", "dramatic": "dramatic", "whimsical": "happy", "tired": "narration", "sleepy": "narration", "calm": "narration", "monotone": "narration"]
            delivery.expression = styles[lab.delivery] ?? ""
        }
        let source = try await generate(text: text, voice: voice, settings: delivery)
        let file = try AVAudioFile(forReading: source.url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw EngineFailure.message("Could not read generated speech.") }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw EngineFailure.message("Invalid generated speech format.") }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let output = try WAVFile()
        try output.append(AudioProcessing.renderCharacter(samples, recipe: recipe))
        try output.finish()
        return output
    }

    func levelSpeech(_ audio: WAVFile) throws -> WAVFile { try audio.leveledSpeech() }

    func join(_ clip: WAVFile, into output: WAVFile, pause: Double) throws {
        let leveled = try levelSpeech(clip)
        try output.appendSilence(seconds: pause)
        try output.append(contentsOf: leveled)
    }

    func finish(_ audio: WAVFile) throws -> [Float] {
        try audio.finish()
        return try audio.envelope()
    }

    func clone(reference: URL, output: URL) async throws {
        guard let directory else { throw EngineFailure.message("Load a model before creating a voice.") }
        let file = try AVAudioFile(forReading: reference)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration >= 10 else { throw EngineFailure.message("Choose at least 10 seconds of clean speech. A 25–30 second reference gives more stable results.") }
        // Cloning uses its own reference encoders; do not keep synthesis models
        // resident alongside them. The next generation reloads on demand.
        releaseIdleModel()
        // The macOS 27 GPU GatherND path aborts inside S3Tokenizer.
        // Use the upstream supported CPU placement for reference encoding.
        setenv("CHATTERBOX_VC_CU", "cpu", 1)
        let cloner = try await VoiceCloner(modelDirectory: directory)
        try Task.checkCancellation()
        try cloner.cloneVoice(from: reference, to: output)
    }

    private func hasPerth(_ dir: URL) -> Bool {
        ["PerthEncoder.mlmodelc", "PerthEncoder.mlpackage"].contains {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }
}
