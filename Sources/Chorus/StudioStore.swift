import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ChorusKit
import ChatterboxCoreML
import ChorusKokoro
import ChorusPocket

enum Workspace: String, CaseIterable, Identifiable { case studio = "Voice Studio", speech = "Text to Speech", voices = "Voice Library"; var id: String { rawValue } }
private struct Snapshot: Codable {
    var project: StudioProject
    var voices: [LocalVoice]
    var singleText: String
    var singleVoice: UUID?
    var modelPath: String?
    var variant: String
}

@MainActor final class StudioStore: ObservableObject {
    @Published var project = StudioProject.example { didSet { scheduleSave() } }
    @Published var voices: [LocalVoice] = [] { didSet { scheduleSave() } }
    @Published var singleText = "Some ideas deserve to be heard. Give yours a voice." { didSet { scheduleSave() } }
    @Published var singleVoice: UUID? { didSet { scheduleSave() } }
    @Published var workspace: Workspace = .studio
    @Published var modelVariant = "nano" { didSet { scheduleSave() } }
    @Published var modelPath: String? { didSet { scheduleSave() } }
    @Published private(set) var loadedModelVariant: String?
    @Published var ready = false
    @Published private(set) var modelResident = false
    @Published private(set) var residentEngine: String?
    @Published var busy = false {
        didSet {
            idleTask?.cancel(); idleTask = nil
            if !busy, modelResident { scheduleIdleRelease() }
        }
    }
    @Published var status = "Set up your local engine"
    @Published var progress: Double = 0
    @Published var generatingID: UUID?
    @Published var completedIDs: Set<UUID> = []
    @Published var errorMessage: String?
    @Published var showSetup = false
    @Published var showEngine = false
    @Published var showImporter = false
    @Published var showVoiceCreator = false
    @Published var showVoiceCloner = false
    @Published var editingVoice: LocalVoice?
    @Published var presetBaseID = BuiltInVoice.defaultVoice.id
    @Published var previewBusy = false
    @Published var output: WAVFile?
    @Published var waveform: [Float] = []
    @Published var generationSeconds: Double?
    @Published var outputProject: StudioProject?
    @Published var outputSingleText: String?
    @Published var outputSingleVoice: UUID?
    @Published var outputWasSingle = false
    @Published var outputVoiceSettings: [VoiceSettings] = []
    @Published private(set) var draftCharacter: CharacterVoiceRecipe?
    private var outputCharacterRecipes: [CharacterVoiceRecipe?] = []
    private var outputKokoroRecipes: [KokoroRecipe?] = []
    let player = AudioPlayer()
    let voicePreview = AudioPlayer()
    let engine = LocalEngine()
    let root: URL
    private var task: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewAudio: WAVFile?
    private var draftLabReference: URL?
    private var idleTask: Task<Void, Never>?
    private var saveTask: DispatchWorkItem?
    private var restoring = true

    var home: URL { root.appendingPathComponent("Models", isDirectory: true) }
    var pocketDirectory: URL { home.appendingPathComponent("Pocket", isDirectory: true) }
    var pocketInstalled: Bool { PocketBackend.isInstalled(at: pocketDirectory) }
    var kokoroDirectory: URL { home.appendingPathComponent("Kokoro", isDirectory: true) }
    var kokoroInstalled: Bool { KokoroBackend.isInstalled(at: kokoroDirectory) }
    private var workspaceVoiceIDs: [UUID?] {
        if workspace == .speech { return [singleVoice] }
        if project.dialogue.isEmpty { return [BuiltInVoice.defaultVoice.id] }
        return project.dialogue.map { block in
            project.speakers.first(where: { $0.id == block.speakerID })?.voiceID
        }
    }
    var workspaceUsesKokoro: Bool {
        let ids = workspaceVoiceIDs
        return !ids.isEmpty && ids.allSatisfy { kokoroRecipe($0) != nil }
    }
    var engineLabel: String {
        if residentEngine == "Character" { return "Voice engine · loaded" }
        let ids = workspaceVoiceIDs
        if !ids.isEmpty && ids.allSatisfy({ characterRecipe($0) != nil && characterRecipe($0)?.kokoroBase == nil }) { return "Pocket TTS · legacy voices" }
        if residentEngine == "Kokoro" { return "Kokoro · loaded" }
        if workspaceUsesKokoro { return kokoroInstalled ? "Kokoro · loads when needed" : "Kokoro · first-use download" }
        return ready ? "Chatterbox \((loadedModelVariant ?? modelVariant).capitalized)" : "Choose a voice to get started"
    }
    var voiceFolder: URL { root.appendingPathComponent("Voices", isDirectory: true) }
    func isModelLoaded(_ variant: String) -> Bool { ready && modelResident && residentEngine == "Chatterbox" && loadedModelVariant == variant }
    func isModelSleeping(_ variant: String) -> Bool { ready && residentEngine != "Chatterbox" && loadedModelVariant == variant }
    func localModelDirectory(for variant: String) -> URL? {
        if let modelPath {
            let directory = URL(fileURLWithPath: modelPath)
            if ModelRepository.detectVariant(in: directory)?.rawValue == variant,
               LocalModelFiles.canLoad(directory, watermarkDirectory: watermarkDirectory) { return directory }
        }
        let repo = variant == "nano" ? ModelRepository.defaultNanoRepoId : ModelRepository.defaultRepoId
        guard let directory = ModelRepository.existingModelDirectory(hfHome: home, repoId: repo),
              LocalModelFiles.canLoad(directory, watermarkDirectory: watermarkDirectory) else { return nil }
        return directory
    }
    private var watermarkDirectory: URL { ModelRepository.downloadDirectory(hfHome: home, repoId: ModelRepository.perthRepoId) }
    var selectedModelActionTitle: String {
        if isModelLoaded(modelVariant) { return "Loaded" }
        return localModelDirectory(for: modelVariant) == nil ? "Download & load" : "Load"
    }
    func prepareSelectedModel() {
        guard !isModelLoaded(modelVariant) else { return }
        if let directory = localModelDirectory(for: modelVariant) { loadModel(directory) }
        else { downloadModel() }
    }
    var isStale: Bool {
        guard output != nil else { return false }
        let ids = outputWasSingle ? [singleVoice] : project.dialogue.map { block in project.speakers.first { $0.id == block.speakerID }?.voiceID }
        let changed = ids.map { voiceSettings($0) } != outputVoiceSettings || ids.map { kokoroRecipe($0) } != outputKokoroRecipes || ids.map { characterRecipe($0) } != outputCharacterRecipes
        return changed || (outputWasSingle ? outputSingleText != singleText || outputSingleVoice != singleVoice : outputProject != project)
    }
    var canExport: Bool { output != nil && !isStale && !busy }
    var wordCount: Int { (workspace == .speech ? singleText : project.dialogue.map(\.text).joined(separator: " ")).split(whereSeparator: \.isWhitespace).count }
    var estimatedSeconds: Int { max(1, Int(Double(wordCount) / 2.6)) }

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Chorus", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: voiceFolder, withIntermediateDirectories: true)
            let autosave = self.root.appendingPathComponent("studio.json")
            if FileManager.default.fileExists(atPath: autosave.path) {
                let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: autosave))
                project = try saved.project.validated().assigningVoices(localVoices: saved.voices)
                voices = saved.voices; singleText = saved.singleText
                singleVoice = saved.singleVoice; modelPath = saved.modelPath; modelVariant = saved.variant
            }
        } catch { errorMessage = "Could not restore the local workspace: \(error.localizedDescription)" }
        restoring = false
        showSetup = localModelDirectory(for: "nano") == nil || !kokoroInstalled
    }
    func scheduleSave() {
        guard !restoring else { return }
        saveTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        saveTask = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func persist() {
        do {
            let snapshot = Snapshot(project: project, voices: voices, singleText: singleText,
                                    singleVoice: singleVoice, modelPath: modelPath, variant: modelVariant)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: root.appendingPathComponent("studio.json"), options: .atomic)
        } catch { errorMessage = "Could not save the workspace: \(error.localizedDescription)" }
    }
    func shutdown() {
        persist()
        task?.cancel(); idleTask?.cancel(); cancelVoicePreview()
        player.clear(); output = nil
    }
    func autoLoad() {
        guard !showSetup, !busy, !ready,
              let directory = localModelDirectory(for: modelVariant) ?? localModelDirectory(for: "nano") else { return }
        busy = true
        task = Task {
            do {
                let variant = try await engine.configure(directory: directory, home: home)
                modelVariant = variant; modelPath = directory.path; loadedModelVariant = variant; ready = true
                status = "\(variant.capitalized) · loads when needed"
            } catch { errorMessage = error.localizedDescription }
            busy = false; task = nil
        }
    }
    func setupDefaultEngines() {
        guard !busy else { return }
        busy = true; errorMessage = nil; progress = 0
        task = Task {
            do {
                let nano: URL
                if let cached = localModelDirectory(for: "nano") {
                    nano = cached
                } else {
                    status = "Downloading Chatterbox Nano…"
                    nano = try await engine.download(variant: "nano", home: home) { [weak self] value in
                        Task { @MainActor in self?.progress = value * 0.9 }
                    }
                }
                try Task.checkCancellation()
                progress = 0.9
                status = kokoroInstalled ? "Preparing your local voices…" : "Downloading Kokoro…"
                try await KokoroBackend.install(at: kokoroDirectory)
                try Task.checkCancellation()
                let variant = try await engine.configure(directory: nano, home: home)
                modelVariant = variant; modelPath = nano.path; loadedModelVariant = variant
                ready = true; modelResident = false; residentEngine = nil
                progress = 1; status = "Nano and Kokoro ready · all local"
                showSetup = false
            } catch is CancellationError {
                status = "Setup paused · you can retry when ready"
            } catch {
                status = "Setup needs attention"; errorMessage = error.localizedDescription
            }
            busy = false; task = nil
        }
    }
    private func scheduleIdleRelease() {
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            guard let self, !self.busy, self.modelResident else { return }
            // Mark busy across the actor hop so generation cannot race the release.
            self.busy = true
            let label = self.residentEngine == "Character" ? "Voice engine" : self.residentEngine == "Kokoro" ? "Kokoro" : self.loadedModelVariant?.capitalized ?? "Engine"
            await self.engine.releaseIdleModel()
            self.modelResident = false; self.residentEngine = nil; self.busy = false
            self.status = "\(label) · loads when needed"
        }
    }
    func loadModel(_ directory: URL) {
        guard !busy else { return }
        errorMessage = nil; busy = true; ready = false; modelResident = false; loadedModelVariant = nil; status = "Loading local model…"; progress = 0
        task = Task {
            do {
                let variant = try await engine.load(directory: directory, home: home)
                try Task.checkCancellation()
                modelVariant = variant; modelPath = directory.path; loadedModelVariant = variant; ready = true; modelResident = true; residentEngine = "Chatterbox"
                status = "\(variant.capitalized) · ready offline"; showEngine = false
            } catch is CancellationError { status = "Model load cancelled" }
            catch { status = "Model could not load"; errorMessage = error.localizedDescription }
            if !ready { await engine.unload(); modelResident = false }
            busy = false; task = nil
        }
    }
    func chooseModel() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Load model"; panel.message = "Choose the folder containing T3LM and the Chatterbox support files."
        if panel.runModal() == .OK, let url = panel.url { loadModel(url) }
    }
    func unloadModel() {
        guard !busy else { return }
        busy = true
        cancelVoicePreview()
        task = Task {
            await engine.unload()
            ready = false; modelResident = false; residentEngine = nil; loadedModelVariant = nil; busy = false; task = nil
            status = "Engine unloaded · audio still available"
        }
    }
    func downloadModel() {
        guard !busy else { return }
        let variant = modelVariant
        errorMessage = nil
        busy = true; ready = false; modelResident = false; loadedModelVariant = nil; status = "Downloading \(variant.capitalized)…"; progress = 0
        task = Task {
            do {
                let directory = try await engine.download(variant: variant, home: home) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                try Task.checkCancellation()
                status = "Compiling local models…"; progress = 1
                let loaded = try await engine.load(directory: directory, home: home)
                try Task.checkCancellation()
                modelVariant = loaded; modelPath = directory.path; loadedModelVariant = loaded; ready = true; modelResident = true; residentEngine = "Chatterbox"
                status = "\(loaded.capitalized) · ready offline"; showEngine = false
            } catch is CancellationError { status = "Setup cancelled · download can resume" }
            catch { status = "Setup needs attention"; errorMessage = error.localizedDescription }
            if !ready { await engine.unload(); modelResident = false }
            busy = false; task = nil
        }
    }
    func voiceURL(_ id: UUID?) throws -> URL? {
        guard let id else { return try BuiltInVoice.defaultVoice.conditioningURL() }
        if let builtin = BuiltInVoice.named(id) { return try builtin.conditioningURL() }
        guard let voice = voices.first(where: { $0.id == id }) else {
            throw EngineFailure.message("This voice is missing from your library. Choose another voice on the dialogue block or in Text to Speech.")
        }
        if voice.kind == .character {
            guard let recipe = voice.character else { throw EngineFailure.message("The character voice recipe is missing.") }
            _ = try recipe.validated()
            if recipe.kokoroBase != nil {
                guard let filename = voice.filename, filename == URL(fileURLWithPath: filename).lastPathComponent,
                      FileManager.default.fileExists(atPath: voiceFolder.appendingPathComponent(filename).path) else { throw EngineFailure.message("The Lab voice reference is missing. Preview and save it again.") }
                return voiceFolder.appendingPathComponent(filename)
            }
            return nil
        }
        if voice.kind == .kokoro {
            guard let recipe = voice.kokoro else { throw EngineFailure.message("The Kokoro voice recipe is missing.") }
            _ = try recipe.validated(); return nil
        }
        if voice.kind == .preset {
            guard let base = BuiltInVoice.named(voice.baseVoiceID) else { throw EngineFailure.message("This voice preset's base voice is missing.") }
            return try base.conditioningURL()
        }
        guard let filename = voice.filename, filename == URL(fileURLWithPath: filename).lastPathComponent else {
            throw EngineFailure.message("The cloned voice file is invalid.")
        }
        let url = voiceFolder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw EngineFailure.message("The voice file for \(voice.name) is missing. Recreate or reassign this voice.") }
        return url
    }
    func voiceSettings(_ id: UUID?) -> VoiceSettings {
        guard let id else { return BuiltInVoice.defaultVoice.settings }
        return voices.first { $0.id == id }?.settings ?? BuiltInVoice.named(id)?.settings ?? .init()
    }
    func characterRecipe(_ id: UUID?) -> CharacterVoiceRecipe? { voices.first { $0.id == id && $0.kind == .character }?.character }
    func previewLab(selection: VoiceLabSelection) {
        guard !busy else { return }
        guard ready else { showEngine = true; return }
        do {
            let recipe = try VoiceLabCompiler.compile(selection)
            cancelVoicePreview()
            busy = true; previewBusy = true; errorMessage = nil
            if player.isPlaying { player.toggle() }
            status = "Creating Kokoro reference for Chatterbox…"
            previewTask = Task {
                do {
                    let reference = FileManager.default.temporaryDirectory.appendingPathComponent("Chorus-Lab-\(UUID().uuidString).safetensors")
                    draftLabReference = reference
                    try await engine.createLabReference(recipe: recipe, kokoroDirectory: kokoroDirectory, output: reference)
                    try Task.checkCancellation()
                    status = "Previewing with Chatterbox…"
                    let rawAudio = try await engine.generateLab(text: "Some ideas deserve to be heard. Give yours a voice. [chuckle] Well, this is unexpected. Let's see what happens next!", recipe: recipe, voice: reference)
                    try Task.checkCancellation()
                    let audio = try await engine.levelSpeech(rawAudio)
                    try Task.checkCancellation()
                    try voicePreview.load(url: audio.url)
                    previewAudio = audio; draftCharacter = recipe; voicePreview.toggle()
                    status = "Sample ready"
                } catch is CancellationError { status = "Sample cancelled" }
                catch { if Task.isCancelled { status = "Sample cancelled" } else { errorMessage = error.localizedDescription; status = "Sample needs attention" } }
                modelResident = await engine.isLoaded; residentEngine = await engine.residentName
                previewBusy = false; busy = false; previewTask = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func saveLab(name: String, selection: VoiceLabSelection, editing: LocalVoice? = nil) {
        guard !busy, let recipe = draftCharacter, previewAudio != nil,
              let expected = try? VoiceLabCompiler.compile(selection), recipe == expected else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Give your voice a name."; return }
        guard let reference = draftLabReference else { return }
        let filename = "\(UUID().uuidString)-conds.safetensors"
        do {
            try FileManager.default.createDirectory(at: voiceFolder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: reference, to: voiceFolder.appendingPathComponent(filename))
        } catch { errorMessage = error.localizedDescription; return }
        let profile = LocalVoice(id: editing?.id ?? UUID(), name: trimmed, filename: filename, kind: .character, character: recipe)
        if let index = voices.firstIndex(where: { $0.id == profile.id }) { voices[index] = profile }
        else { voices.append(profile) }
        persist(); cancelVoicePreview(); showVoiceCreator = false; editingVoice = nil
        status = "\(trimmed) saved to your voice library"
    }
    func deleteVoice(_ id: UUID) {
        guard !busy, BuiltInVoice.named(id) == nil,
              let voice = voices.first(where: { $0.id == id }) else { return }
        do {
            if let filename = voice.filename,
               filename == URL(fileURLWithPath: filename).lastPathComponent,
               !voices.contains(where: { $0.id != id && $0.filename == filename }) {
                let file = voiceFolder.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                }
            }
            cancelVoicePreview()
            if editingVoice?.id == id { editingVoice = nil }
            for index in project.speakers.indices where project.speakers[index].voiceID == id {
                project.speakers[index].voiceID = BuiltInVoice.defaultVoice.id
            }
            if singleVoice == id { singleVoice = BuiltInVoice.defaultVoice.id }
            voices.removeAll { $0.id == id }
            persist()
            status = "\(voice.name) deleted"
        } catch { errorMessage = "Could not delete this voice: \(error.localizedDescription)" }
    }
    func kokoroRecipe(_ id: UUID?) -> KokoroRecipe? { voices.first { $0.id == id && $0.kind == .kokoro }?.kokoro }
    func saveKokoroVoice(name: String, recipe: KokoroRecipe, settings: VoiceSettings, editing: LocalVoice? = nil) {
        guard !busy else { return }
        do {
            _ = try recipe.validated(); try recipe.validate(settings: settings)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw EngineFailure.message("Enter a voice name.") }
            let profile = LocalVoice(id: editing?.id ?? UUID(), name: trimmed, kind: .kokoro, settings: settings, kokoro: recipe)
            if let index = voices.firstIndex(where: { $0.id == profile.id }) { voices[index] = profile }
            else { voices.append(profile) }
            cancelVoicePreview(); showVoiceCreator = false; editingVoice = nil
            status = "\(trimmed) saved · Kokoro"
        } catch { errorMessage = error.localizedDescription }
    }
    func previewKokoroVoice(recipe: KokoroRecipe, settings: VoiceSettings) {
        guard !busy else { return }
        do {
            _ = try recipe.validated(); try recipe.validate(settings: settings)
            busy = true; previewBusy = true; errorMessage = nil; voicePreview.clear(); previewAudio = nil
            if player.isPlaying { player.toggle() }
            status = kokoroInstalled ? "Generating Kokoro preview…" : "Downloading Kokoro · 103 MB · first use only…"
            previewTask = Task {
                do {
                    let rawAudio = try await engine.generateKokoro(text: "Some ideas deserve to be heard. Give yours a voice.", recipe: recipe, settings: settings, directory: kokoroDirectory)
                    try Task.checkCancellation()
                    let audio = try await engine.levelSpeech(rawAudio)
                    try Task.checkCancellation()
                    try voicePreview.load(url: audio.url); previewAudio = audio; voicePreview.toggle()
                    status = "Kokoro preview ready · all local"
                } catch is CancellationError { status = "Voice preview cancelled" }
                catch {
                    if Task.isCancelled { status = "Voice preview cancelled" }
                    else { errorMessage = error.localizedDescription; status = "Kokoro preview needs attention" }
                }
                modelResident = await engine.isLoaded; residentEngine = await engine.residentName
                previewBusy = false; busy = false; previewTask = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func openVoiceCreator(base: UUID = BuiltInVoice.defaultVoice.id) { presetBaseID = base; showVoiceCreator = true }
    func saveVoicePreset(name: String, base: UUID, settings: VoiceSettings, editing: LocalVoice? = nil) {
        guard !busy else { return }
        do {
            _ = try settings.validated()
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, BuiltInVoice.named(base) != nil else { throw EngineFailure.message("Choose a base voice and enter a name.") }
            var profile = editing ?? .init(name: trimmed, kind: .preset, baseVoiceID: base)
            profile.name = trimmed; profile.settings = settings
            if profile.kind == .preset { profile.baseVoiceID = base }
            if let index = voices.firstIndex(where: { $0.id == profile.id }) { voices[index] = profile }
            else { voices.append(profile) }
            cancelVoicePreview(); showVoiceCreator = false; editingVoice = nil
            status = "\(trimmed) saved to your voice library"
        } catch { errorMessage = error.localizedDescription }
    }
    func previewVoice(base: UUID, settings: VoiceSettings, editing: LocalVoice? = nil) {
        guard ready, !busy else { return }
        do {
            _ = try settings.validated()
            let url = try editing?.kind == .cloned ? voiceURL(editing?.id) : BuiltInVoice.named(base)?.conditioningURL()
            busy = true; previewBusy = true; errorMessage = nil; voicePreview.clear(); previewAudio = nil
            if player.isPlaying { player.toggle() }
            status = "Generating voice preview…"
            previewTask = Task {
                do {
                    let rawAudio = try await engine.generate(text: "Some ideas deserve to be heard. Give yours a voice.", voice: url, settings: settings)
                    try Task.checkCancellation()
                    let audio = try await engine.levelSpeech(rawAudio)
                    try Task.checkCancellation()
                    try voicePreview.load(url: audio.url); previewAudio = audio; voicePreview.toggle()
                    status = "Voice preview ready · all local"
                } catch is CancellationError { status = "Voice preview cancelled" }
                catch { errorMessage = error.localizedDescription; status = "Voice preview needs attention" }
                modelResident = await engine.isLoaded; residentEngine = await engine.residentName
                previewBusy = false; busy = false; previewTask = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func cancelVoicePreview() { if let reference = draftLabReference { try? FileManager.default.removeItem(at: reference) }; draftLabReference = nil; draftCharacter = nil; previewTask?.cancel(); voicePreview.clear(); previewAudio = nil }
    func generate() {
        guard !busy else { return }
        let isSingle = workspace == .speech
        let snapshot = project, text = singleText, voice = singleVoice
        let blocks = isSingle ? [Dialogue(speakerID: UUID(), text: text)] : snapshot.dialogue
        do {
            if !isSingle { _ = try snapshot.validated() }
            guard !blocks.isEmpty else { throw EngineFailure.message("Add a dialogue block before generating.") }
            for block in blocks {
                guard !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EngineFailure.message("Every dialogue block needs some text.") }
                let unsupported = ScriptParser.unsupportedTags(in: block.text)
                guard unsupported.isEmpty else { throw EngineFailure.message("Unsupported expression: \(unsupported.joined(separator: ", ")). Choose a tag from the Expression menu.") }
            }
            let ids = blocks.map { block in isSingle ? voice : snapshot.speakers.first(where: { $0.id == block.speakerID })?.voiceID }
            let recipes = ids.map { kokoroRecipe($0) }
            let characters = ids.map { characterRecipe($0) }
            for (index, recipe) in characters.enumerated() { if let recipe { _ = try recipe.preparedText(blocks[index].text) } }
            guard ready || ids.indices.allSatisfy({ recipes[$0] != nil || (characters[$0] != nil && characters[$0]?.kokoroBase == nil) }) else { showEngine = true; return }
            for (index, recipe) in recipes.enumerated() {
                if let recipe { _ = try recipe.preparedText(blocks[index].text); try recipe.validate(settings: voiceSettings(ids[index])) }
            }
            let urls = try ids.map { try voiceURL($0) }
            let settings = blocks.map { block in voiceSettings(isSingle ? voice : snapshot.speakers.first(where: { $0.id == block.speakerID })?.voiceID) }
            cancelVoicePreview()
            busy = true; completedIDs = []; progress = 0; player.clear(); output = nil; waveform = []
            status = "Generating locally…"
            task = Task {
                let start = Date()
                do {
                    let audio = try WAVFile()
                    for (index, block) in blocks.enumerated() {
                        try Task.checkCancellation()
                        generatingID = block.id; status = "Generating \(index + 1) of \(blocks.count)…"
                        let clip: WAVFile
                        if let recipe = characters[index] {
                            if recipe.kokoroBase != nil {
                                guard let reference = urls[index] else { throw EngineFailure.message("Missing Lab reference.") }
                                clip = try await engine.generateLab(text: block.text, recipe: recipe, voice: reference, settings: settings[index])
                            } else {
                                if !pocketInstalled { status = "Downloading legacy Pocket voice engine…" }
                                clip = try await engine.generateCharacter(text: block.text, recipe: recipe, directory: pocketDirectory)
                            }
                        } else if let recipe = recipes[index] {
                            if !kokoroInstalled { status = "Downloading Kokoro · 103 MB · first use only…" }
                            clip = try await engine.generateKokoro(text: block.text, recipe: recipe, settings: settings[index], directory: kokoroDirectory)
                        } else {
                            clip = try await engine.generate(text: block.text, voice: urls[index], settings: settings[index])
                        }
                        try await engine.join(clip, into: audio, pause: index > 0 && !isSingle ? snapshot.pause : 0)
                        completedIDs.insert(block.id); progress = Double(index + 1) / Double(blocks.count)
                    }
                    try Task.checkCancellation()
                    let envelope = try await engine.finish(audio)
                    try Task.checkCancellation()
                    try player.load(url: audio.url)
                    waveform = envelope; output = audio; outputWasSingle = isSingle
                    outputProject = snapshot; outputSingleText = text; outputSingleVoice = voice
                    outputVoiceSettings = settings; outputKokoroRecipes = recipes; outputCharacterRecipes = characters
                    generationSeconds = Date().timeIntervalSince(start)
                    status = "Generated in \(String(format: "%.1f", generationSeconds!))s · all local"
                } catch is CancellationError { status = "Generation cancelled"; completedIDs = [] }
                catch {
                    if Task.isCancelled { status = "Generation cancelled" }
                    else { status = "Generation needs attention"; errorMessage = error.localizedDescription }
                    completedIDs = []
                }
                modelResident = await engine.isLoaded; residentEngine = await engine.residentName
                generatingID = nil; busy = false; task = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func cancel() { task?.cancel(); previewTask?.cancel(); status = "Stopping after the current engine step…" }
    func addDialogue() {
        guard let first = project.speakers.first(where: { $0.id == project.dialogue.last?.speakerID }) ?? project.speakers.first else { return }
        withAnimation(.easeInOut(duration: 0.2)) { project.dialogue.append(.init(speakerID: first.id, text: "")) }
    }
    func moveDialogue(_ id: UUID, offset: Int) {
        guard let from = project.dialogue.firstIndex(where: { $0.id == id }), project.dialogue.indices.contains(from + offset) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { project.dialogue.swapAt(from, from + offset) }
    }
    func importScript(_ text: String) throws {
        let imported = try ScriptParser.parse(text, title: project.title,
            previousSpeakers: project.speakers, localVoices: voices)
        project = imported; workspace = .studio; showImporter = false; completedIDs = []
    }
    func newProject() { project = .init(speakers: [.init(name: "Narrator")], dialogue: []); player.clear(); output = nil; waveform = []; workspace = .studio }
    var safeTitle: String { let s = project.title.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines); return s.isEmpty ? "Untitled" : s }
    func exportWAV() {
        guard canExport, let output else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]; panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(outputWasSingle ? "Chorus speech" : safeTitle).wav"; panel.prompt = "Export WAV"
        if panel.runModal() == .OK, let url = panel.url {
            do { try output.export(to: url) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func cloneVoice(name: String, reference: URL) {
        guard ready, !busy else { return }
        let id = UUID(), filename = "\(UUID().uuidString)-conds.safetensors"
        let destination = voiceFolder.appendingPathComponent(filename)
        errorMessage = nil
        busy = true; status = "Cloning \(name) locally…"; progress = 0
        task = Task {
            let accessed = reference.startAccessingSecurityScopedResource()
            defer { if accessed { reference.stopAccessingSecurityScopedResource() } }
            do {
                try await engine.clone(reference: reference, output: destination)
                try Task.checkCancellation()
                voices.append(.init(id: id, name: name, filename: filename)); showVoiceCloner = false
                status = "\(name) added to your voice library"
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: destination)
                status = "Voice cloning cancelled"
            } catch {
                try? FileManager.default.removeItem(at: destination)
                status = "Voice could not be cloned"; errorMessage = error.localizedDescription
            }
            modelResident = await engine.isLoaded; residentEngine = await engine.residentName
            busy = false; task = nil
        }
    }
}
