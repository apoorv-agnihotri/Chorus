import Foundation
import ChorusKit
import Darwin

@main struct ChorusKitTests {
    static func main() async {
        let suite = ChorusKitTests()
        let cases: [(String, () async throws -> Void)] = [
            ("Targeted Core ML load recovery and cancellation", suite.testModelLoadRecovery),
            ("Speaker and reaction tag import", suite.testDialogueAndReactionTagImport),
            ("Malformed script rejection", suite.testImporterRejectsMissingSpeakerAndStageDirections),
            ("Multiline dialogue and reaction preservation", suite.testImporterPreservesMultilineTextAndInlineReactions),
            ("PCM WAV headers and clipping", suite.testWAVHeaderAndSampleClipping),
            ("Exact inter-dialogue spacing", suite.testStitchAddsSilenceBetweenClipsOnly),
            ("File-backed audio matches PCM and cleans up", suite.testWAVFile),
            ("Speech leveling bypass, headroom, and duration", suite.testSpeechLeveling),
            ("Project roundtrip and invalid data rejection", suite.testProjectRoundTripAndValidation),
            ("Expression import and case normalization", suite.testExpressions),
            ("Legacy cloned voices and preset persistence", suite.testVoiceProfiles),
            ("Kokoro persistence, validation, and bounded text", suite.testKokoroVoices),
            ("Voice Lab compiler, compatibility, and randomization", suite.testVoiceLab),
            ("Voice Lab EQ, saturation, and modulation", suite.testLabDSP),
            ("Character recipes persist and reject invalid profiles", suite.testCharacters),
            ("Character rendering changes pitch and duration", suite.testCharacterRendering),
            ("Speed rendering preserves pitch and duration", suite.testSpeedRendering),
            ("Bundled bases and previous preset compatibility", suite.testBundledVoices),
            ("Case-insensitive speaker voice assignment", suite.testSpeakerVoiceAssignment),
            ("Dialogue voice changes are independent and persist", suite.testIndependentDialogueVoices),
            ("Imported disco script and gasp alias", suite.testDiscoScript),
            ("Spoken text normalization regressions", suite.testSpeechNormalization),
            ("Normalization boundaries and protected text", suite.testNormalizationBoundaries),
            ("Generation preparation preserves original scripts", suite.testNormalizationIntegration)
        ]
        var failed = 0
        for (name, test) in cases {
            do { try await test(); print("PASS: \(name)") }
            catch { failed += 1; print("FAIL: \(name): \(error)") }
        }
        print("\(cases.count - failed)/\(cases.count) suites passed")
        if failed > 0 { exit(1) }
    }

    func testModelLoadRecovery() async throws {
        let issue = NSError(domain: "com.apple.CoreML", code: 0, userInfo: [NSLocalizedDescriptionKey:
            "`MLModelConfiguration`'s `.functionName` property must be `nil` unless the model type is ML Program."])
        let unrelated = NSError(domain: "com.apple.CoreML", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing model file"])
        let wrapped = NSError(domain: "loader", code: 2, userInfo: [NSUnderlyingErrorKey: issue])
        try expect(ModelLoadRecovery.shouldRetryOnCPU(issue))
        try expect(ModelLoadRecovery.shouldRetryOnCPU(wrapped))
        try expect(!ModelLoadRecovery.shouldRetryOnCPU(unrelated))
        try expect(!ModelLoadRecovery.shouldRetryOnCPU(CancellationError()))
        var attempts = 0
        let recovered: String = try await ModelLoadRecovery.load {
            attempts += 1; throw issue
        } cpuFallback: { attempts += 1; return "CPU loaded" }
        try expect(recovered == "CPU loaded" && attempts == 2)
        attempts = 0
        let normal = try await ModelLoadRecovery.load {
            attempts += 1; return "Accelerator loaded"
        } cpuFallback: { attempts += 1; return "unexpected" }
        try expect(normal == "Accelerator loaded" && attempts == 1)
        do {
            let _: String = try await ModelLoadRecovery.load(primary: { throw unrelated }, cpuFallback: { attempts += 1; return "unexpected" })
            try expect(false)
        } catch { try expect((error as NSError).code == unrelated.code && attempts == 1) }
        attempts = 0
        do {
            _ = try await ModelLoadRecovery.load(primary: { attempts += 1; throw issue }, cpuFallback: { attempts += 1; throw unrelated }) as String
            try expect(false)
        } catch { try expect((error as NSError).code == unrelated.code && attempts == 2) }
        attempts = 0
        do {
            let _: String = try await ModelLoadRecovery.load(primary: { throw CancellationError() }, cpuFallback: { attempts += 1; return "unexpected" })
            try expect(false)
        } catch { try expect(error is CancellationError && attempts == 0) }
    }

    func testSpeechLeveling() throws {
        func make(_ samples: [Float]) throws -> WAVFile {
            let file = try WAVFile(); try file.append(samples); try file.finish(); return file
        }
        func sine(_ amplitude: Float, count: Int = 24000) -> [Float] {
            (0..<count).map { amplitude * Float(sin(2 * Double.pi * 220 * Double($0) / 24000)) }
        }
        let normal = try make(sine(0.2))
        let original = try Data(contentsOf: normal.url)
        try expect(try normal.leveledSpeech() === normal)
        try expect(try Data(contentsOf: normal.url) == original)
        let silence = try make([Float](repeating: 0, count: 24000))
        try expect(try silence.leveledSpeech() === silence)
        let noise = try make(sine(0.001))
        try expect(try noise.leveledSpeech() === noise)
        let quiet = try make(sine(0.03))
        let raised = try quiet.leveledSpeech()
        try expect(raised.sampleCount == quiet.sampleCount)
        try expect(abs(raised.peak - 0.06) < 0.0002)
        // Added pauses must not make otherwise adequate speech appear quiet.
        let paused = try make(sine(0.2) + [Float](repeating: 0, count: 240000))
        try expect(try paused.leveledSpeech() === paused)
        var transientSamples = sine(0.04, count: 48000)
        transientSamples[8191] = 1; transientSamples[8192] = -1
        transientSamples[24000] = 0.99; transientSamples[47999] = -1
        let transient = try make(transientSamples)
        let protected = try transient.leveledSpeech()
        try expect(protected.sampleCount == transient.sampleCount)
        try expect(protected.peak <= 0.8501)
        let envelope = try protected.envelope(bins: 200)
        try expect(envelope.allSatisfy { $0.isFinite && $0 <= 0.8501 })
        try expect(envelope[60] > 0.075) // quiet speech still rises after a peak
        let short = try make([0.03, -0.02, 0.99])
        try expect(try short.leveledSpeech() === short)
        let pending = try WAVFile(); try pending.append([0.1])
        try expectThrow { _ = try pending.leveledSpeech() }
        let example = StudioProject.example
        try expect(example.speakers.map(\.voiceID) == [BundledVoice.rue.id, BundledVoice.kai.id])
        let imported = try ScriptParser.parse(example.taggedScript)
        try expect(imported.speakers.map(\.voiceID) == [BundledVoice.rue.id, BundledVoice.kai.id])
    }

    func testIndependentDialogueVoices() throws {
        let originalVoice = BundledVoice.defaultVoice.id
        let newVoice = UUID()
        let speaker = Speaker(name: "Narrator", voiceID: originalVoice)
        let first = Dialogue(speakerID: speaker.id, text: "First line")
        let second = Dialogue(speakerID: speaker.id, text: "Second line")
        var project = StudioProject(speakers: [speaker], dialogue: [first, second])
        project.assignVoice(newVoice, toDialogue: first.id)
        try expect(project.dialogue[1].speakerID == speaker.id)
        try expect(project.speakers.first(where: { $0.id == speaker.id })?.voiceID == originalVoice)
        let firstSpeaker = project.dialogue[0].speakerID
        try expect(firstSpeaker != speaker.id)
        try expect(project.speakers.first(where: { $0.id == firstSpeaker })?.voiceID == newVoice)
        project.assignVoice(originalVoice, toDialogue: first.id)
        try expect(project.speakers.count == 2)
        try expect(project.dialogue[0].speakerID == firstSpeaker)
        project.assignVoice(originalVoice, toDialogue: first.id)
        project.assignVoice(newVoice, toDialogue: UUID())
        try expect(project.speakers.count == 2)
        project.assignVoice(nil, toDialogue: second.id)
        try expect(project.speakers.first(where: { $0.id == firstSpeaker })?.voiceID == originalVoice)
        try expect(project.speakers.first(where: { $0.id == speaker.id })?.voiceID == nil)
        let restored = try JSONDecoder().decode(StudioProject.self, from: JSONEncoder().encode(project)).validated()
        try expect(restored == project)
        try expect(restored.dialogue.map(\.text) == ["First line", "Second line"])
    }

    func testDialogueAndReactionTagImport() throws {
        let script = "[clara]\r\nDid you really just say that?\r\n\r\n[cleo]\r\n[laugh]\r\nYes! And I'd say it again!\r\n\r\n[CLARA]\r\nThat's unbelievable."
        let result = try ScriptParser.parse(script)
        try expect(result.speakers.map(\.name) == ["clara", "cleo"])
        try expect(result.dialogue.count == 3)
        try expect(result.dialogue[0].speakerID == result.dialogue[2].speakerID)
        try expect(result.dialogue[1].text == "[laugh]\nYes! And I'd say it again!")
    }
    func testWAVFile() throws {
        let a: [Float] = [-2, -1, -0.25, 0, 0.25, 1, 2]
        let b: [Float] = [0.2, -0.8, 0.5]
        var clip: WAVFile? = try WAVFile()
        let clipURL = clip!.url
        try clip!.append(a); try clip!.finish()
        try expect(try Data(contentsOf: clipURL) == WAV.encode(a))
        try expectThrow { try clip!.append(b) }
        let joined = try WAVFile()
        try joined.append(contentsOf: clip!)
        clip = nil
        try expect(!FileManager.default.fileExists(atPath: clipURL.path))
        try joined.appendSilence(seconds: 0.01)
        try joined.append(b); try joined.finish()
        let expected = try WAV.encode(WAV.stitch([a, b], pause: 0.01))
        try expect(try Data(contentsOf: joined.url) == expected)
        try expect(joined.sampleCount == a.count + b.count + 240)
        let envelope = try joined.envelope(bins: 3)
        try expect(envelope.count == 3 && envelope[0] == 1 && envelope[2] > 0.79)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("chorus-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: destination) }
        try joined.export(to: destination)
        try expect(try Data(contentsOf: destination) == expected)
        try Data([1, 2, 3]).write(to: destination)
        try joined.export(to: destination)
        try expect(try Data(contentsOf: destination) == expected)
        try expectThrow { try joined.appendSilence(seconds: .nan) }
        var unfinished: WAVFile? = try WAVFile()
        let unfinishedURL = unfinished!.url
        try expectThrow { try unfinished!.finish() }
        try expectThrow { try unfinished!.append([.infinity]) }
        try unfinished!.append([0.5])
        try expectThrow { try joined.append(contentsOf: unfinished!) }
        unfinished = nil
        try expect(!FileManager.default.fileExists(atPath: unfinishedURL.path))
        let multiChunk = try WAVFile()
        let samples = (0..<17003).map { Float($0 % 19 - 9) / 10 }
        try multiChunk.append(samples); try multiChunk.finish()
        try expect(try Data(contentsOf: multiChunk.url) == WAV.encode(samples))
        try expect(try multiChunk.envelope().count == 160)
    }
    func testSpeechNormalization() throws {
        let cases = [
            ("2:00 a.m.", "two in the morning"),
            ("6.9", "six point nine"),
            ("HELLO THERE!", "Hello there!"),
            ("3:45 p.m.", "three forty-five in the afternoon"),
            ("₹1,500", "one thousand five hundred rupees"),
            ("03:05 PM", "three oh five in the afternoon"),
            ("12:00 a.m.", "twelve at night"),
            ("8:30 p.m.", "eight thirty in the evening"),
            ("14:05", "fourteen oh five"),
            ("9:00", "nine o'clock"),
            ("-6.90 and +0.05", "minus six point nine zero and plus zero point zero five"),
            ("1,500 and 42", "one thousand five hundred and forty-two"),
            ("₹1,50,000.50", "one hundred fifty thousand rupees and fifty paise"),
            ("₹1.01", "one rupee and one paisa"),
            ("$2.5, £1.01, €0.00.", "two dollars and fifty cents, one pound and one penny, zero euros."),
            ("Dr. Atlas uses AI, TTS and WAV.", "Doctor Atlas uses A I, T T S and W A V."),
            ("e.g. hello vs. goodbye", "for example hello versus goodbye"),
            ("U.S.A. and U.K.", "U S A and U K"),
            ("HELLO NASA! USE AI!", "Hello NASA! Use A I!")
        ]
        for (input, expected) in cases {
            let actual = SpeechTextNormalizer.normalize(input)
            guard actual == expected else { throw AssertionFailure(description: "\(input) → \(actual), expected \(expected)") }
            let repeated = SpeechTextNormalizer.normalize(actual)
            guard repeated == actual else { throw AssertionFailure(description: "Normalizing twice changed \(actual) → \(repeated)") }
        }
    }
    func testNormalizationBoundaries() throws {
        for original in [
            "Rue and iPhone say Hello there!",
            "Let us meet; I am ready.",
            "[HAPPY] [CLEAR THROAT] [unknown 123]",
            "https://example.com/6.9?q=1500 www.example.com/2:00",
            "atlas123@example.com v1.2.3 127.0.0.1",
            "2026-10-11 11/10/2026 model82M foo_123 clip6.wav",
            "0:00 a.m. 13:45 p.m. 3:99 p.m. 24:00 01:02:03",
            "1234567890123456"
        ] {
            let actual = SpeechTextNormalizer.normalize(original)
            guard actual == original else { throw AssertionFailure(description: "Protected text changed: \(original) → \(actual)") }
        }
        try expect(SpeechTextNormalizer.normalize("[laugh] It costs ₹1,500. Meet Dr. Rue at 2:00 a.m. 😊") ==
            "[laugh] It costs one thousand five hundred rupees. Meet Doctor Rue at two in the morning 😊")
        try expect(SpeechTextNormalizer.normalize("你好 [laugh] 6.9 café") == "你好 [laugh] six point nine café")
    }
    func testNormalizationIntegration() throws {
        let input = "[Atlas]\n[CHUCKLE] Meet Dr. Rue at 2:00 a.m. Bring ₹1,500.\n[zia]\nHELLO THERE! The score is 6.9."
        let project = try ScriptParser.parse(input)
        let roundtrip = try JSONDecoder().decode(StudioProject.self, from: JSONEncoder().encode(project))
        try expect(roundtrip == project)
        try expect(project.dialogue[0].text.contains("₹1,500"))
        var settings = VoiceSettings(); settings.expression = "happy"
        let prepared = settings.preparedText(project.dialogue[0].text)
        try expect(prepared == "[happy] [chuckle] Meet Doctor Rue at two in the morning. Bring one thousand five hundred rupees.")
        try expect(settings.preparedText("[WHISPERING] 6.9") == "[whispering] six point nine")
        try expect(VoiceSettings().preparedText("HELLO THERE!") == "Hello there!")
        try expect(project.speakers[0].voiceID == BundledVoice.atlas.id)
    }
    func testExpressions() throws {
        let tags = ScriptParser.expressions.map { "[\($0)]" }
        let script = "[clara]\n" + tags.joined(separator: "\n") + "\nHello there."
        let parsed = try ScriptParser.parse(script)
        try expect(parsed.speakers.count == 1 && parsed.dialogue.count == 1)
        try expect(parsed.dialogue[0].text.contains("[clear throat]"))
        try expect(ScriptParser.unsupportedTags(in: tags.joined(separator: " ")).isEmpty)
        try expect(ScriptParser.unsupportedTags(in: "[HAPPY] [reacts enthusiastically]") == ["[reacts enthusiastically]"])
        try expect(ScriptParser.normalizedExpressions(in: "[HAPPY] Yes. [CLEAR THROAT] [unknown]") == "[happy] Yes. [clear throat] [unknown]")
    }
    func testVoiceProfiles() throws {
        let id = UUID()
        let legacy = "{\"id\":\"\(id.uuidString)\",\"name\":\"My voice\",\"filename\":\"my-conds.safetensors\"}"
        let clone = try JSONDecoder().decode(LocalVoice.self, from: Data(legacy.utf8))
        try expect(clone.kind == .cloned && clone.settings == VoiceSettings() && clone.id == id)
        var settings = VoiceSettings(); settings.speed = 1.25; settings.expression = "happy"; settings.sentencePause = 0.35
        let preset = LocalVoice(name: "Narrator", kind: .preset, baseVoiceID: UUID(), settings: settings)
        try expect(try JSONDecoder().decode(LocalVoice.self, from: JSONEncoder().encode(preset)) == preset)
        try expect(settings.preparedText("Hello [CHUCKLE]") == "[happy] Hello [chuckle]")
        try expect(settings.preparedText("[WHISPERING] Keep this quiet.") == "[whispering] Keep this quiet.")
        settings.speed = .nan; try expectThrow { try settings.validated() }
        settings = .init(); settings.expression = "enthusiastic"; try expectThrow { try settings.validated() }
        let invalid = legacy.replacingOccurrences(of: "my-conds.safetensors", with: "../my-conds.safetensors")
        try expectThrow { try JSONDecoder().decode(LocalVoice.self, from: Data(invalid.utf8)) }
    }
    func testKokoroVoices() throws {
        var settings = VoiceSettings(); settings.speed = 0.9
        let voice = LocalVoice(name: "Kokoro narrator", kind: .kokoro, settings: settings, kokoro: .init(voice: "am_onyx"))
        let data = try JSONEncoder().encode(voice)
        try expect(try JSONDecoder().decode(LocalVoice.self, from: data) == voice)
        let missing = LocalVoice(name: "Broken", kind: .kokoro)
        try expectThrow { try JSONDecoder().decode(LocalVoice.self, from: JSONEncoder().encode(missing)) }
        try expectThrow { try KokoroRecipe(voice: "../../voice").validated() }
        settings.expression = "happy"
        try expectThrow { try voice.kokoro!.validate(settings: settings) }
        try expectThrow { try voice.kokoro!.preparedText("[CHUCKLE] Hello.") }
        try expectThrow { try voice.kokoro!.preparedText("[gasps] Hello.") }
        try expect(try voice.kokoro!.preparedText("Hello world.") == "Hello world.")
        let text = Array(repeating: "Some ideas deserve to be heard.", count: 100).joined(separator: " ")
        let chunks = KokoroRecipe.chunks(text)
        try expect(chunks.joined(separator: " ") == text)
        try expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 350 })
        let unbroken = String(repeating: "a", count: 1200)
        try expect(KokoroRecipe.chunks(unbroken).joined() == unbroken)
        try expect(KokoroRecipe.chunks(unbroken).allSatisfy { $0.count <= 350 })
        try expect(KokoroRecipe.chunks("   ").isEmpty)
    }
    func testVoiceLab() throws {
        for category in VoiceLabCategory.allCases {
            let catalog = VoiceLabCatalog.traits(in: category)
            try expect(catalog.count == 20 && Set(catalog.map(\.id)).count == 20 && catalog.allSatisfy(\.isSelectable))
            for trait in catalog where !trait.isSelectable {
                var selection = VoiceLabSelection(); selection.select(trait.id, in: category)
                try expectThrow { try VoiceLabCompiler.compile(selection) }
            }
            for trait in catalog where trait.isSelectable {
                var selection = VoiceLabSelection(); selection.select(trait.id, in: category)
                _ = try VoiceLabCompiler.compile(selection).validated()
            }
        }
        let selection = VoiceLabSelection(identity: "javert", pitchBody: "deep", texture: "clean", delivery: "slow", characterStyle: "cartoon", seed: 990)
        let recipe = try VoiceLabCompiler.compile(selection)
        try expect(recipe.voice == "javert" && recipe.pitchCents == -400 && recipe.speed == 0.8)
        try expect(recipe.focusGain == 0 && recipe.grit == 0 && recipe.robot == 0 && recipe.seed == 990)
        try expect(try VoiceLabCompiler.compile(selection) == recipe)
        try expect(recipe.kokoroBase == "am_onyx")
        try expect(recipe.preparedText("[chuckle] Hello").contains("[chuckle]"))
        var oldRecipe = recipe; oldRecipe.kokoroBase = nil
        try expectThrow { try oldRecipe.preparedText("[chuckle] Hello") }
        let layered = try VoiceLabCompiler.compile(.init(pitchBody: "warm", texture: "nasal"))
        try expect(layered.bodyEQ?.gain == 3 && layered.focusGain == 4.5)
        let profile = LocalVoice(name: "Lab voice", kind: .character, character: recipe)
        try expect(try JSONDecoder().decode(LocalVoice.self, from: JSONEncoder().encode(profile)) == profile)
        var invalid = selection; invalid.identity = "missing"
        try expectThrow { try VoiceLabCompiler.compile(invalid) }
        invalid = selection; invalid.version = 2
        try expectThrow { try VoiceLabCompiler.compile(invalid) }
        for seed in (0..<300).map(UInt64.init) + [UInt64.max] {
            let random = VoiceLabSelection.randomized(seed: seed)
            try expect(VoiceLabSelection.randomized(seed: seed) == random)
            for category in VoiceLabCategory.allCases where category != .identity {
                try expect(VoiceLabCatalog.trait(random.id(in: category), in: category)?.support == .supported)
            }
            _ = try VoiceLabCompiler.compile(random)
            _ = try VoiceLabCompiler.compile(.randomized(seed: seed, includeExperimental: true))
        }
        let unique = Set((0..<100).map { VoiceLabSelection.randomized(seed: UInt64($0)).summary })
        try expect(unique.count > 50)
        // Older prompt recipes need neither Lab metadata nor the added body EQ band.
        let old = try VoicePromptResolver.resolve("SpongeBob", seed: 42)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "lab"); json.removeValue(forKey: "bodyEQ")
        let restored = try JSONDecoder().decode(CharacterVoiceRecipe.self, from: JSONSerialization.data(withJSONObject: json))
        try expect(restored == old && restored.lab == nil && restored.bodyEQ == nil)
    }
    func testLabDSP() throws {
        let rate = Double(WAV.sampleRate)
        func tone(_ frequency: Double, amplitude: Double = 0.12) -> [Float] {
            (0..<(WAV.sampleRate * 2)).map { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / rate)) }
        }
        func magnitude(_ samples: [Float], _ frequency: Double) -> Double {
            let start = samples.count / 4, end = samples.count * 3 / 4
            var real = 0.0, imaginary = 0.0
            for i in start..<end {
                let phase = 2 * Double.pi * frequency * Double(i) / rate
                real += Double(samples[i]) * cos(phase); imaginary += Double(samples[i]) * sin(phase)
            }
            return hypot(real, imaginary) / Double(end - start)
        }
        let low = tone(180), high = tone(1650)
        let input = zip(low, high).map { $0 + $1 }
        var recipe = try VoiceLabCompiler.compile(.init(delivery: "normal"))
        let plain = try AudioProcessing.renderCharacter(input, recipe: recipe)
        recipe.bodyEQ = .init(frequency: 180, gain: 6)
        let warm = try AudioProcessing.renderCharacter(input, recipe: recipe)
        let ratio = (magnitude(warm, 180) / magnitude(warm, 1650)) / (magnitude(plain, 180) / magnitude(plain, 1650))
        try expect(ratio > 1.5)
        recipe.focusHz = 1650; recipe.focusGain = 6
        let both = try AudioProcessing.renderCharacter(input, recipe: recipe)
        try expect(magnitude(both, 1650) / magnitude(both, 180) > magnitude(warm, 1650) / magnitude(warm, 180) * 1.5)
        recipe = try VoiceLabCompiler.compile(.init(texture: "metallic", delivery: "normal"))
        let electronic = try AudioProcessing.renderCharacter(tone(440, amplitude: 0.3), recipe: recipe)
        try expect(magnitude(electronic, 375) > 0.03 && magnitude(electronic, 505) > 0.03)
        recipe = try VoiceLabCompiler.compile(.init(texture: "strong-grit", delivery: "normal"))
        let gritty = try AudioProcessing.renderCharacter(tone(440, amplitude: 0.3), recipe: recipe)
        try expect(magnitude(gritty, 1320) > 0.002)
        for output in [warm, both, electronic, gritty] {
            try expect(output.count == input.count && output.allSatisfy { $0.isFinite && abs($0) <= 1 })
        }
    }
    func testCharacters() throws {
        let recipe = try VoicePromptResolver.resolve("Walter White", seed: 42)
        let profile = LocalVoice(name: "Measured narrator", kind: .character, character: recipe)
        try expect(try JSONDecoder().decode(LocalVoice.self, from: JSONEncoder().encode(profile)) == profile)
        try expect(recipe.voice != (try VoicePromptResolver.resolve("SpongeBob", seed: 42)).voice)
        try expect(try VoicePromptResolver.resolve("Walter White", seed: 42) == recipe)
        let retry = try VoicePromptResolver.resolve("Walter White", seed: 901)
        try expect(retry != recipe && retry.voice == recipe.voice)
        var invalid = recipe; invalid.speed = .infinity
        try expectThrow { try invalid.validated() }
        invalid = recipe; invalid.version = 99
        try expectThrow { try invalid.validated() }
        invalid = recipe; invalid.voice = "unknown"
        try expectThrow { try invalid.validated() }
        let missing = LocalVoice(name: "Incomplete", kind: .character)
        try expectThrow { try JSONDecoder().decode(LocalVoice.self, from: JSONEncoder().encode(missing)) }
        try expectThrow { try recipe.preparedText("[laugh] Hello") }
        try expectThrow { try VoicePromptResolver.resolve(String(repeating: "a", count: 601), seed: 42) }
        try expect(try recipe.preparedText("Hello there.") == "Hello there.")
    }
    func testCharacterRendering() throws {
        let input = (0..<(WAV.sampleRate * 2)).map { Float(0.3 * sin(2 * Double.pi * 440 * Double($0) / Double(WAV.sampleRate))) }
        var recipe = try VoicePromptResolver.resolve("A calm narrator", seed: 42)
        recipe.pitchCents = 300; recipe.speed = 1.2
        let output = try AudioProcessing.renderCharacter(input, recipe: recipe)
        try expect(abs(output.count - Int(Double(input.count) / recipe.speed)) <= 1)
        let segment = Array(output[(output.count / 4)..<(output.count * 3 / 4)])
        let crossings = zip(segment, segment.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        let frequency = Double(crossings) * Double(WAV.sampleRate) / Double(segment.count)
        try expect(abs(frequency - 440 * pow(2, 300.0 / 1200)) < 10)
        try expect(output.allSatisfy { $0.isFinite && abs($0) <= 1 })
        try expect(output.suffix(2400).contains { abs($0) > 0.05 })
        try expectThrow { try AudioProcessing.renderCharacter([.nan], recipe: recipe) }
    }
    func testSpeedRendering() throws {
        let input = (0..<(WAV.sampleRate * 2)).map { i in Float(0.3 * sin(2 * Double.pi * 440 * Double(i) / Double(WAV.sampleRate))) }
        try expect(try AudioProcessing.changeSpeed(input, rate: 1) == input)
        for rate in [0.75, 1.25] {
            let output = try AudioProcessing.changeSpeed(input, rate: rate)
            try expect(abs(output.count - Int(Double(input.count) / rate)) <= 1)
            let segment = Array(output[(output.count / 4)..<(output.count * 3 / 4)])
            let crossings = zip(segment, segment.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
            let frequency = Double(crossings) * Double(WAV.sampleRate) / Double(segment.count)
            print("Speed \(rate)×: \(output.count) frames, \(String(format: "%.1f", frequency))Hz")
            try expect(abs(frequency - 440) < 8)
            try expect(output.suffix(2400).contains { abs($0) > 0.05 })
            try expect(try WAV.encode(output).count == 44 + output.count * 2)
        }
        try expectThrow { try AudioProcessing.changeSpeed(input, rate: 0) }
    }
    func testBundledVoices() throws {
        let bases = BundledVoice.all
        try expect(bases.count == 5 && Set(bases.map(\.id)).count == 5)
        try expect(Set(bases.compactMap(\.resource)).count == 5)
        try expect(BundledVoice.defaultVoice.id == bases[0].id)
        for base in bases {
            try expect(base.resource != nil)
            _ = try base.settings.validated()
            let preset = LocalVoice(name: "My \(base.name)", kind: .preset, baseVoiceID: base.id, settings: base.settings)
            let restored = try JSONDecoder().decode(LocalVoice.self, from: JSONEncoder().encode(preset))
            try expect(BundledVoice.named(restored.baseVoiceID)?.id == base.id && restored.settings == base.settings)
        }
        for oldID in ["5B55CE28-A76A-4C97-A8DA-CF39B254ADC0", "5B55CE28-A76A-4C97-A8DA-CF39B254ADC1"] {
            let id = UUID(uuidString: oldID)!
            try expect(!BundledVoice.isPublicBase(id) && BundledVoice.named(id) != nil)
            let previous = LocalVoice(name: "Saved 0.2 preset", kind: .preset, baseVoiceID: id)
            let restored = try JSONDecoder().decode(LocalVoice.self, from: JSONEncoder().encode(previous))
            try expect(restored == previous && BundledVoice.named(restored.baseVoiceID)?.settings == VoiceSettings())
        }
        try expect(BundledVoice.named(UUID()) == nil)
    }
    func testSpeakerVoiceAssignment() throws {
        // Every casing must produce the same five identities, including repeated tags.
        for transform: (String) -> String in [{ $0 }, { $0.lowercased() }, { $0.uppercased() }] {
            let text = BundledVoice.all.map { "[\(transform($0.name))]\nHello." }.joined(separator: "\n")
            let parsed = try ScriptParser.parse(text)
            try expect(parsed.speakers.map(\.voiceID) == BundledVoice.all.map { Optional($0.id) })
        }
        let repeated = try ScriptParser.parse("[Atlas]\nOne.\n[atlas]\nTwo.\n[ATLAS]\nThree.")
        try expect(repeated.speakers.count == 1 && repeated.dialogue.count == 3)
        try expect(repeated.speakers[0].voiceID == BundledVoice.atlas.id)
        let clone = LocalVoice(name: "  My Voice  ", filename: "custom-conds.safetensors")
        let custom = try ScriptParser.parse("[MY_VOICE]\nHello.\n[Atlas]\nHello.",
            previousSpeakers: [Speaker(name: "atlas", voiceID: clone.id)])
        try expect(custom.speakers[0].voiceID == nil && custom.speakers[1].voiceID == clone.id)
        let namedClone = LocalVoice(name: "aTlAs", filename: "custom-conds.safetensors")
        let local = try ScriptParser.parse("[ATLAS]\nHello.", localVoices: [namedClone])
        try expect(local.speakers[0].voiceID == namedClone.id)
        let fresh = try ScriptParser.parse("[Atlas]\nHello.", previousSpeakers: [Speaker(name: "ATLAS")])
        try expect(fresh.speakers[0].voiceID == BundledVoice.atlas.id)
        var saved = StudioProject(speakers: [Speaker(name: "atlas"), Speaker(name: "KAI", voiceID: clone.id)], dialogue: [])
        saved = saved.assigningVoices()
        try expect(saved.speakers[0].voiceID == BundledVoice.atlas.id && saved.speakers[1].voiceID == clone.id)
        let restored = try JSONDecoder().decode(StudioProject.self, from: JSONEncoder().encode(saved))
        try expect(restored.assigningVoices() == saved)
        let ordinary = try ScriptParser.parse("[someone]\nHello.")
        try expect(ordinary.speakers[0].voiceID == nil)
    }
    func testDiscoScript() throws {
        let script = """
        [atlas]
        Five strangers. One elevator. And one very suspicious button.
        [zia]
        [gasps] Guys! Why is it glowing?!
        [kai]
        [chuckle] Relax. What's the worst that could happen?
        [rue]
        [sigh] You really shouldn't have said that.
        [indie]
        [sniff] Wait. Does anyone smell smoke?
        [zia]
        [cough] Okay! Definitely smoke!
        [kai]
        [clear throat] I may have pressed something.
        [rue]
        [groan] You've got to be kidding me!
        [indie]
        [shush] Quiet! Something's coming.
        [atlas]
        [laugh] Congratulations. You've activated the disco floor.
        """
        let project = try ScriptParser.parse(script)
        try expect(project.speakers.map(\.voiceID) == [BundledVoice.atlas.id, BundledVoice.zia.id,
            BundledVoice.kai.id, BundledVoice.rue.id, BundledVoice.indie.id].map(Optional.init))
        try expect(project.dialogue.count == 10)
        for block in project.dialogue { try expect(ScriptParser.unsupportedTags(in: block.text).isEmpty) }
        try expect(ScriptParser.normalizedExpressions(in: project.dialogue[1].text) == "[gasp] Guys! Why is it glowing?!")
        try expect(ScriptParser.normalizedExpressions(in: "[GASPS] [GASP] [laugh]") == "[gasp] [gasp] [laugh]")
        let standalone = try ScriptParser.parse("[zia]\n[GASPS]\nOh!")
        try expect(standalone.speakers.count == 1 && standalone.dialogue.count == 1)
        try expect(ScriptParser.unsupportedTags(in: "[unknown reaction]") == ["[unknown reaction]"])
    }
    func testImporterRejectsMissingSpeakerAndStageDirections() throws {
        for script in ["Hello there", "[laugh]\nHello", "[clara]", "[clara]\nHello\n[reacts enthusiastically]\nHello"] {
            try expectThrow { try ScriptParser.parse(script) }
        }
    }
    func testImporterPreservesMultilineTextAndInlineReactions() throws {
        let result = try ScriptParser.parse("[narrator]\nFirst line.\n\nSecond line. [chuckle]\n[narrator]\nA new block.")
        try expect(result.dialogue.count == 2)
        try expect(result.dialogue[0].text == "First line.\n\nSecond line. [chuckle]")
        try expect(ScriptParser.unsupportedTags(in: "[laugh] Yes [reacts enthusiastically] [chuckle]") == ["[reacts enthusiastically]"])
    }
    func testWAVHeaderAndSampleClipping() throws {
        let bytes = [UInt8](try WAV.encode([-2, -1, 0, 1, 2]))
        try expect(String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF")
        try expect(String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE")
        try expect(bytes.count == 54)
        try expect(Array(bytes[20..<24]) == [1, 0, 1, 0]) // PCM, mono
        try expect(Array(bytes[24..<28]) == [192, 93, 0, 0]) // 24000
        try expect(Array(bytes[34..<36]) == [16, 0])
        try expect(Array(bytes[44...]) == [0, 128, 0, 128, 0, 0, 255, 127, 255, 127])
        try expectThrow { try WAV.encode([]) }
        try expectThrow { try WAV.encode([.nan]) }
    }
    func testStitchAddsSilenceBetweenClipsOnly() throws {
        let result = try WAV.stitch([[0.5, 0.3], [-0.5]], pause: 0.1)
        try expect(result.count == 2403)
        try expect(Array(result.prefix(2)) == [0.5, 0.3])
        try expect(result[2..<2402].allSatisfy { $0 == 0 })
        try expect(result.last == -0.5)
        try expect(try WAV.stitch([[0.5], [0.6]], pause: 0) == [0.5, 0.6])
        try expectThrow { try WAV.stitch([[]], pause: 0) }
        try expectThrow { try WAV.stitch([[1]], pause: .infinity) }
    }
    func testProjectRoundTripAndValidation() throws {
        let original = StudioProject.example
        try expect(try JSONDecoder().decode(StudioProject.self, from: JSONEncoder().encode(original)).validated() == original)
        var broken = original; broken.dialogue[0].speakerID = UUID()
        try expectThrow { try broken.validated() }
        broken = original; broken.speakers.append(broken.speakers[0])
        try expectThrow { try broken.validated() }
        broken = original; broken.pause = -1
        try expectThrow { try broken.validated() }
    }
}

struct AssertionFailure: Error, CustomStringConvertible {
    var description: String
}
func expect(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    guard try condition() else { throw AssertionFailure(description: "Assertion failed at \(file):\(line)") }
}
func expectThrow(_ action: () throws -> Any, file: StaticString = #filePath, line: UInt = #line) throws {
    do { _ = try action() } catch { return }
    throw AssertionFailure(description: "Expected an error at \(file):\(line)")
}
