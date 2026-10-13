import Foundation
import ChatterboxCoreML
import PerthCoreML
import ChorusKit
import ChorusKokoro
import ChorusPocket
import Darwin

/// Real-engine smoke test and benchmark; never substitutes system speech or mock samples.
@main struct ChorusCheck {
    static func main() async {
        do { try await run() }
        catch { fputs("Chorus check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        func option(_ key: String) -> String? { guard let i = args.firstIndex(of: key), args.indices.contains(i + 1) else { return nil }; return args[i + 1] }
        if let destination = option("--voice-lab-audit"), let directory = option("--pocket-dir") {
            let folder = URL(fileURLWithPath: destination)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let backend = try await PocketBackend.load(directory: URL(fileURLWithPath: directory), metallib: option("--metallib").map { URL(fileURLWithPath: $0) })
            var cases = CharacterVoiceRecipe.voices.map { ($0, VoiceLabSelection(identity: $0)) }
            cases += [
                ("warm-nasal", .init(identity: "marius", pitchBody: "warm", texture: "nasal", delivery: "relaxed")),
                ("robot", .init(identity: "jean", pitchBody: "low", texture: "metallic", delivery: "normal")),
                ("fantasy", .init(identity: "javert", pitchBody: "deep", texture: "light-grit", delivery: "slow", characterStyle: "fantasy")),
                ("cartoon", .init(identity: "marius", pitchBody: "high", texture: "nasal", delivery: "brisk", characterStyle: "cartoon"))
            ]
            var records: [[String: String]] = []
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            for (name, selection) in cases {
                let recipe = try VoiceLabCompiler.compile(selection), start = Date()
                let audio = try await backend.generate(text: "Some ideas deserve to be heard. Give yours a voice. Let us see what happens next.", recipe: recipe)
                let destination = folder.appendingPathComponent(name + ".wav")
                try audio.export(to: destination)
                try encoder.encode(recipe).write(to: folder.appendingPathComponent(name + ".json"))
                records.append(["name": name, "frames": String(audio.sampleCount), "seconds": String(Date().timeIntervalSince(start)), "path": destination.path])
                print("Voice Lab \(name): \(audio.sampleCount) frames, \(Date().timeIntervalSince(start))s")
            }
            try encoder.encode(records).write(to: folder.appendingPathComponent("results.json"))
            return
        }
        if let prompt = option("--character-prompt"), let directory = option("--pocket-dir"), let destination = option("--out") {
            let url = URL(fileURLWithPath: directory)
            let recipe = try VoicePromptResolver.resolve(prompt, seed: UInt64(option("--seed") ?? "42") ?? 42)
            let loadStart = Date()
            let backend = try await PocketBackend.load(directory: url, metallib: option("--metallib").map { URL(fileURLWithPath: $0) })
            print("Loaded Pocket in \(Date().timeIntervalSince(loadStart))s")
            let start = Date()
            let audio = try await backend.generate(text: option("--text") ?? "Some ideas deserve to be heard. Give yours a voice.", recipe: recipe)
            try audio.export(to: URL(fileURLWithPath: destination))
            print("Character \(recipe.voice): \(audio.sampleCount) samples in \(Date().timeIntervalSince(start))s; saved \(destination)")
            return
        }
        if let directory = option("--kokoro-dir"), let destination = option("--out") {
            let url = URL(fileURLWithPath: directory)
            if args.contains("--download-kokoro") { try await KokoroBackend.install(at: url) }
            let backend = try KokoroBackend(directory: url)
            let recipe = KokoroRecipe(voice: option("--kokoro-voice") ?? "af_heart")
            var settings = VoiceSettings(); settings.speed = Double(option("--speed") ?? "1") ?? 1
            let start = Date()
            let audio = try backend.generate(text: option("--text") ?? "Some ideas deserve to be heard. Give yours a voice.", recipe: recipe, settings: settings)
            try audio.export(to: URL(fileURLWithPath: destination))
            print("Kokoro \(recipe.voice): \(audio.sampleCount) samples in \(Date().timeIntervalSince(start))s; saved \(destination)")
            return
        }
        if let mode = option("--audio-memory-benchmark") {
            try audioMemoryBenchmark(mode: mode)
            return
        }
        if let references = option("--prepare-voices"), let destination = option("--voices-out"), let model = option("--model-dir") {
            let cloner = try await VoiceCloner(modelDirectory: URL(fileURLWithPath: model))
            let folder = URL(fileURLWithPath: destination)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for voice in BundledVoice.all {
                let reference = URL(fileURLWithPath: references).appendingPathComponent(voice.name.lowercased() + ".wav")
                let output = folder.appendingPathComponent(voice.resource! + ".safetensors")
                try cloner.cloneVoice(from: reference, to: output)
                print("Prepared \(voice.name): \(output.path)")
            }
            return
        }
        guard let outputIndex = args.firstIndex(of: "--out"), args.indices.contains(outputIndex + 1) else {
            print("Usage: chorus-check --download turbo|nano --home PATH --out WAV [--script TEXTFILE] [--voice CONDS] [--reference AUDIO] [--voice-out CONDS]\n   or: chorus-check --model-dir PATH --home PATH --out WAV [--audition-voices CONDS_DIRECTORY]\n   or: chorus-check --prepare-voices WAV_DIRECTORY --voices-out CONDS_DIRECTORY --model-dir PATH\n   Delivery: --text TEXT --speed 0.75..1.35 --variation 0.5..1.1 --sentence-pause 0..1.5 --clause-pause 0..0.6 --expression STYLE")
            return
        }
        let home = URL(fileURLWithPath: option("--home") ?? FileManager.default.currentDirectoryPath + "/models")
        let directory: URL
        if let variant = option("--download") {
            let repo = variant == "nano" ? ModelRepository.defaultNanoRepoId : ModelRepository.defaultRepoId
            var last = -1
            // Progress callback is @Sendable; print percentage through a serial actor.
            let reporter = ProgressReporter()
            let result = try await ModelRepository.download(repoId: repo, hfHome: home) { progress in
                Task { await reporter.report(progress) }
            }
            last = result.stillStale.count
            guard !result.isPartiallyApplied, last == 0 else { throw StudioError.invalidAudio("Incomplete model download") }
            directory = result.directory
            let perth = try await ModelRepository.download(repoId: ModelRepository.perthRepoId, hfHome: home, matching: ModelRepository.perthGlobs)
            guard !perth.isPartiallyApplied, perth.stillStale.isEmpty else { throw StudioError.invalidAudio("Incomplete watermark download") }
        } else if let path = option("--model-dir") { directory = URL(fileURLWithPath: path) }
        else { throw StudioError.invalidAudio("Specify --download or --model-dir") }
        let watermarkDir = ModelRepository.downloadDirectory(hfHome: home, repoId: ModelRepository.perthRepoId)
        guard ["PerthEncoder.mlpackage", "PerthEncoder.mlmodelc"].contains(where: {
            FileManager.default.fileExists(atPath: watermarkDir.appendingPathComponent($0).path)
        }) else {
            throw StudioError.invalidAudio("No offline Perth watermark model in --home")
        }
        let loadStart = Date()
        let watermarker = try PerthWatermarker(modelDirectory: watermarkDir)
        let model = try await ModelLoadRecovery.load {
            try await ChatterboxCoreMLModel.load(from: directory,
                watermarker: PerthWatermark(watermarker: watermarker),
                computeUnits: PipelineComputeUnits(t3: args.contains("--t3-cpu-only") ? .cpuOnly : .cpuAndNeuralEngine))
        } cpuFallback: {
            print("Core ML function loading failed; retrying T3 on CPU")
            return try await ChatterboxCoreMLModel.load(from: directory,
                watermarker: PerthWatermark(watermarker: watermarker),
                computeUnits: PipelineComputeUnits(t3: .cpuOnly))
        }
        print("Loaded \(model.loadedVariant.rawValue) in \(String(format: "%.2f", Date().timeIntervalSince(loadStart)))s")
        if let reference = option("--reference"), let voiceOut = option("--voice-out") {
            let cloner = try await VoiceCloner(modelDirectory: directory)
            try cloner.cloneVoice(from: URL(fileURLWithPath: reference), to: URL(fileURLWithPath: voiceOut))
            print("Created local reference voice: \(voiceOut)")
        }
        let voice = option("--voice").map { URL(fileURLWithPath: $0) }
        var settings = VoiceSettings()
        func number(_ key: String, fallback: Double) throws -> Double {
            guard let value = option(key) else { return fallback }
            guard let number = Double(value) else { throw StudioError.invalidAudio("Invalid number for \(key)") }
            return number
        }
        settings.speed = try number("--speed", fallback: 1)
        settings.variation = try number("--variation", fallback: 0.8)
        settings.sentencePause = try number("--sentence-pause", fallback: 0)
        settings.commaPause = try number("--clause-pause", fallback: 0)
        settings.expression = option("--expression") ?? ""
        _ = try settings.validated()
        let script: StudioProject
        if let file = option("--script") { script = try ScriptParser.parse(String(contentsOfFile: file, encoding: .utf8)) }
        else {
            let speaker = Speaker(name: "Narrator")
            script = .init(speakers: [speaker], dialogue: [.init(speakerID: speaker.id, text: option("--text") ?? "Hello from Chorus. This voice was generated entirely on this Mac.")])
        }
        let combined = try WAVFile()
        let start = Date()
        let catalog = option("--audition-voices").map { URL(fileURLWithPath: $0) }
        let takes: [(String, String, URL?, VoiceSettings)]
        if let catalog {
            takes = BundledVoice.all.map { base in
                (base.name, option("--text") ?? "Some ideas deserve to be heard. Give yours a voice.",
                 catalog.appendingPathComponent(base.resource! + ".safetensors"), base.settings)
            }
        } else { takes = script.dialogue.map { ("Block", $0.text, voice, settings) } }
        var auditions: [[String: Any]] = []
        for (name, text, voice, settings) in takes {
            var samples: [Float] = []
            let audio = try WAVFile()
            let takeStart = Date()
            var opts = GenerationOptions.default; opts.seed = 42
            opts.temperature = Float(settings.variation)
            opts.sentencePause = settings.sentencePause * settings.speed
            opts.commaPause = settings.commaPause * settings.speed
            let unsupported = ScriptParser.unsupportedTags(in: text)
            guard unsupported.isEmpty else { throw StudioError.invalidScript("Unsupported expressions: \(unsupported)") }
            let spokenText = settings.preparedText(text)
            if spokenText != text { print("Spoken text: \(spokenText)") }
            for try await chunk in model.generateStream(spokenText, voice: voice, options: opts) {
                if abs(settings.speed - 1) <= 0.001 { try audio.append(chunk.samples) }
                else { samples.append(contentsOf: chunk.samples) }
            }
            if !samples.isEmpty { try audio.append(AudioProcessing.changeSpeed(samples, rate: settings.speed)) }
            try audio.finish()
            guard audio.peak > 0.001 else {
                throw StudioError.invalidAudio("Engine emitted empty, invalid, or silent samples")
            }
            print("\(name): \(text) → \(String(format: "%.2f", audio.duration))s")
            if catalog != nil {
                guard audio.sampleCount >= WAV.sampleRate else { throw StudioError.invalidAudio("\(name) emitted less than one second of speech") }
                let output = URL(fileURLWithPath: args[outputIndex + 1]).deletingLastPathComponent()
                    .appendingPathComponent("\(name.lowercased())-\(model.loadedVariant.rawValue).wav")
                try audio.export(to: output)
                auditions.append(["name": name, "audioSeconds": audio.duration,
                    "generationSeconds": Date().timeIntervalSince(takeStart), "speed": settings.speed,
                    "variation": settings.variation, "expression": settings.expression,
                    "sentencePause": settings.sentencePause, "clausePause": settings.commaPause])
            }
            if combined.sampleCount > 0 { try combined.appendSilence(seconds: script.pause) }
            try combined.append(contentsOf: audio)
        }
        try combined.finish()
        let output = URL(fileURLWithPath: args[outputIndex + 1])
        try combined.export(to: output)
        let elapsed = Date().timeIntervalSince(start), seconds = combined.duration
        let metrics: [String: Any] = ["variant": model.loadedVariant.rawValue, "audioSeconds": seconds,
            "generationSeconds": elapsed, "realtimeFactor": elapsed / seconds,
            "peak": combined.peak,
            "sampleRate": WAV.sampleRate, "blocks": takes.count, "modelDirectory": directory.path,
            "speed": settings.speed, "variation": settings.variation, "expression": settings.expression,
            "sentencePause": settings.sentencePause, "clausePause": settings.commaPause, "auditions": auditions]
        let data = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.deletingPathExtension().appendingPathExtension("json"))
        print(String(data: data, encoding: .utf8)!)
    }

    /// Isolates audio retention from model memory: 120 distinct 30-second clips,
    /// one hour of mono 24 kHz PCM, identical old/new audio assembly.
    static func audioMemoryBenchmark(mode: String) throws {
        guard ["legacy", "file"].contains(mode) else { throw StudioError.invalidAudio("Use legacy or file for --audio-memory-benchmark") }
        let start = Date()
        func clip(_ index: Int) -> [Float] {
            (0..<(WAV.sampleRate * 30)).map { Float(($0 + index) % 200 - 100) / 200 }
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Chorus-benchmark-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: destination) }
        if mode == "legacy" {
            var clips: [[Float]] = []
            for index in 0..<120 { clips.append(clip(index)) }
            let samples = try WAV.stitch(clips, pause: 0)
            let data = try WAV.encode(samples)
            try data.write(to: destination)
            print("Legacy waveform bins: \(WAV.envelope(samples).count); retained WAV bytes: \(data.count)")
            withExtendedLifetime(clips) {}
        } else {
            let combined = try WAVFile()
            for index in 0..<120 {
                let audio = try WAVFile()
                try audio.append(clip(index)); try audio.finish()
                try combined.append(contentsOf: audio)
            }
            try combined.finish()
            try combined.export(to: destination)
            print("File waveform bins: \(try combined.envelope().count); frames: \(combined.sampleCount)")
        }
        print("Audio benchmark \(mode): 3600 seconds in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
    }
}
actor ProgressReporter {
    private var last = -1
    func report(_ progress: Double) {
        let percent = Int(progress * 100)
        if percent / 10 != last / 10 || last < 0 { print("Download \(percent)%"); last = percent }
    }
}
