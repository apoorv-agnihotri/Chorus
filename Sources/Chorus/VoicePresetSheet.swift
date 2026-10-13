import SwiftUI
import ChorusKit

struct ExpressionMenu: View {
    @Binding var text: String
    var body: some View {
        Menu {
            Section("Vocal reactions") {
                ForEach(ScriptParser.vocalReactions, id: \.self) { tag in
                    Button(tag.capitalized) { insert(tag) }
                }
            }
            Section("Delivery styles · experimental") {
                ForEach(ScriptParser.deliveryStyles, id: \.self) { tag in
                    Button(tag.capitalized) { insert(tag) }
                }
            }
        } label: { Label("Expression", systemImage: "waveform") }
            .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
            .help("Insert an expression at the start of this text")
    }
    private func insert(_ tag: String) { text = "[\(tag)] " + text }
}

private struct LegacyVoicePresetEditor: View {
    @ObservedObject var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    var editing: LocalVoice?
    @ViewState<String> private var name: String
    @ViewState<UUID> private var base: UUID
    @ViewState<VoiceSettings> private var settings: VoiceSettings
    @ViewState<Bool> private var useKokoro: Bool
    @ViewState<KokoroRecipe> private var recipe: KokoroRecipe
    init(store: StudioStore, base: UUID = BuiltInVoice.defaultVoice.id, editing: LocalVoice? = nil) {
        self.store = store; self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _base = State(initialValue: editing?.baseVoiceID ?? base)
        _useKokoro = State(initialValue: editing == nil || editing?.kind == .kokoro)
        _recipe = State(initialValue: editing?.kokoro ?? .init())
        _settings = State(initialValue: editing?.settings ?? .init())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeading(title: editing == nil ? "Create voice" : "Customize voice",
                subtitle: editing?.kind == .cloned ? "Adjust the delivery of your cloned voice." : "Choose a voice, preview it, and save it to your library.")
            TextField("Voice name, e.g. My narrator", text: $name).textFieldStyle(.roundedBorder).controlSize(.large)
                .accessibilityLabel("Preset voice name").disabled(store.busy)
            if useKokoro {
                Picker("Base voice", selection: $recipe.voice) {
                    ForEach(KokoroVoice.all) { voice in
                        Text("\(voice.name) · \(voice.id.hasPrefix("af_") ? "F" : "M")").tag(voice.id)
                    }
                }.disabled(store.busy)
                Text("American English · Kokoro-82M. Bella, Fenrir, Onyx, Heart, and Nicole are the original bases behind Rue, Kai, Atlas, Zia, and Indie.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            } else if editing?.kind != .cloned {
                Picker("Base voice", selection: $base) {
                    ForEach(BuiltInVoice.all) { voice in Text(voice.name).tag(voice.id) }
                    if !BuiltInVoice.isPublicBase(base), let previous = BuiltInVoice.named(base) {
                        Text(previous.name).tag(previous.id)
                    }
                }.disabled(store.busy)
                if let voice = BuiltInVoice.named(base) {
                    Text(voice.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            Divider()
            VoiceDeliveryControls(settings: $settings, kokoro: useKokoro).disabled(store.busy)
            Text(useKokoro ? "Speed is included in the exported WAV. Use punctuation for natural pauses. Kokoro presets do not support expression tags or reference cloning." : "Speed and pauses are included in the exported WAV. Delivery variation changes how freely the model samples; it isn't an emotion-strength control.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            if let error = store.errorMessage { Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled) }
            if store.previewBusy {
                HStack { ProgressView().controlSize(.small); Text(store.status).font(.system(size: 11)); Spacer(); Button("Stop preview") { store.cancel() } }
            }
            HStack {
                Button("Preview voice") {
                    if useKokoro { store.previewKokoroVoice(recipe: recipe, settings: settings) }
                    else { store.previewVoice(base: base, settings: settings, editing: editing) }
                }.disabled((!useKokoro && !store.ready) || store.busy)
                VoicePreviewPlayback(player: store.voicePreview)
                Spacer()
                Button("Cancel") { store.errorMessage = nil; store.cancelVoicePreview(); dismiss() }.keyboardShortcut(.cancelAction).disabled(store.busy)
                Button(editing == nil ? "Create voice" : "Save changes") {
                    if useKokoro { store.saveKokoroVoice(name: name, recipe: recipe, settings: settings, editing: editing) }
                    else { store.saveVoicePreset(name: name, base: base, settings: settings, editing: editing) }
                }.modifier(GlassControl(prominent: true)).tint(Theme.action).disabled(store.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if useKokoro {
                Text(store.kokoroInstalled ? "Kokoro is downloaded. Preview and generation work offline." : "First preview downloads Kokoro (103 MB). You can save a voice without downloading.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } else if !store.ready { Text("Load your Chatterbox engine to preview. You can save a preset now.").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
        }.padding(30).frame(width: 570).interactiveDismissDisabled(store.busy)
            .onChange(of: useKokoro) { _, _ in store.cancelVoicePreview(); store.errorMessage = nil; settings = useKokoro ? .init() : BuiltInVoice.named(base)?.settings ?? .init() }
            .onChange(of: recipe) { _, _ in store.cancelVoicePreview(); store.errorMessage = nil }
            .onChange(of: settings) { _, _ in store.cancelVoicePreview() }
            .onChange(of: base) { _, value in
                store.cancelVoicePreview()
                settings = BuiltInVoice.named(value)?.settings ?? .init()
            }
    }
}

private struct VoicePreviewPlayback: View {
    @ObservedObject var player: AudioPlayer
    var body: some View {
        if player.duration > 0 {
            Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                .accessibilityLabel(player.isPlaying ? "Pause voice preview" : "Play voice preview")
        }
    }
}

struct VoiceDeliveryControls: View {
    @Binding var settings: VoiceSettings
    var kokoro = false
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            control("Speed", value: $settings.speed, range: 0.75...1.35, step: 0.05, display: String(format: "%.2f×", settings.speed))
            if !kokoro {
                control("Delivery variation", value: $settings.variation, range: 0.5...1.1, step: 0.05, display: String(format: "%.2f", settings.variation))
                control("Sentence pause", value: $settings.sentencePause, range: 0...1.5, step: 0.05, display: pause(settings.sentencePause))
                control("Clause pause", value: $settings.commaPause, range: 0...0.6, step: 0.05, display: pause(settings.commaPause))
                Picker("Delivery style", selection: $settings.expression) {
                    Text("Natural · no expression tag").tag("")
                    ForEach(ScriptParser.deliveryStyles, id: \.self) { style in Text(style.capitalized).tag(style) }
                }
                Text("Delivery styles are experimental. Preview before saving.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
    }
    private func pause(_ value: Double) -> String { value == 0 ? "Model decides" : String(format: "%.2fs", value) }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        VStack(spacing: 7) {
            HStack { Text(title).font(.system(size: 12, weight: .medium)); Spacer(); Text(display).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary) }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
}

struct VoicePresetSheet: View {
    @ObservedObject var store: StudioStore
    var base: UUID = BuiltInVoice.defaultVoice.id
    var editing: LocalVoice?
    var body: some View {
        if let editing, editing.kind != .character {
            LegacyVoicePresetEditor(store: store, base: base, editing: editing)
        } else {
            VoiceLabCreator(store: store, editing: editing)
        }
    }
}

private struct VoiceLabCreator: View {
    @ObservedObject var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<VoiceLabSelection> private var selection: VoiceLabSelection
    @ViewState<VoiceLabCategory> private var category = .identity
    @ViewState<String> private var name: String
    var editing: LocalVoice?
    init(store: StudioStore, editing: LocalVoice?) {
        self.store = store; self.editing = editing
        _selection = State(initialValue: editing?.character?.lab ?? VoiceLabSelection(identity: editing?.character?.voice ?? "mature", seed: editing?.character?.seed ?? 42))
        _name = State(initialValue: editing?.name ?? "")
    }
    private var compiled: CharacterVoiceRecipe? { try? VoiceLabCompiler.compile(selection) }
    private var sampleReady: Bool { compiled != nil && store.draftCharacter == compiled }
    private var selectedTrait: VoiceLabTrait { VoiceLabCatalog.trait(selection.id(in: category), in: category)! }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetHeading(title: "Voice Lab", subtitle: "Combine traits, listen to a sample, and save your voice.")
            HStack {
                TextField("Voice name", text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Voice name").frame(width: 280).disabled(store.busy)
                Spacer()
                Button { randomize() } label: { Label("Randomize", systemImage: "shuffle") }
                    .disabled(store.busy).help("Choose a random option in each category")
            }
            HStack(spacing: 8) {
                ForEach(VoiceLabCategory.allCases) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { category = item }
                    } label: {
                        Text(item.title).font(.system(size: 13, weight: category == item ? .semibold : .medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(category == item ? Theme.background : Theme.ink)
                            .background(category == item ? Theme.ink : .clear, in: Capsule())
                            .overlay(Capsule().stroke(category == item ? .clear : Theme.border, lineWidth: 1))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).disabled(store.busy)
                        .accessibilityLabel(item.title).accessibilityValue(category == item ? "Selected" : "")
                }
            }
            HStack(alignment: .top) {
                Text(category.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(VoiceLabCatalog.traits(in: category).filter(\.isSelectable).count) options")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).fixedSize()
            }.frame(height: 27, alignment: .top)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(VoiceLabCatalog.traits(in: category).filter(\.isSelectable)) { trait in
                        Button { choose(trait) } label: {
                            HStack {
                              VStack(alignment: .leading, spacing: 4) {
                                Text(trait.title).font(.system(size: 12, weight: selectedTrait.id == trait.id ? .semibold : .regular))
                                    .foregroundStyle(trait.isSelectable ? Theme.ink : Theme.secondary).lineLimit(1)
                            }
                              Spacer()
                              if selectedTrait.id == trait.id { Image(systemName: "checkmark").foregroundStyle(Theme.ink) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 11).padding(.vertical, 10)
                                .background(selectedTrait.id == trait.id ? Theme.control : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedTrait.id == trait.id ? Theme.accent : Theme.border.opacity(0.35), lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(store.busy || !trait.isSelectable)
                            .accessibilityLabel(trait.title)
                            .accessibilityValue(selectedTrait.id == trait.id ? "Selected" : "")
                    }
                }.padding(2)
            }.frame(height: 215).id(category).transition(.opacity)
            VStack(alignment: .leading, spacing: 6) {
                Text(selection.summary).font(.system(size: 12, weight: .medium)).lineLimit(2)
                HStack {
                    Text("Specific traits override style suggestions.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer()
                }
            }
            Group {
                if store.previewBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(store.status).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        Spacer(); Button("Stop") { store.cancel() }
                    }.padding(14)
                } else if sampleReady {
                    CharacterSamplePlayer(player: store.voicePreview)
                } else {
                    Text("Create a sample to hear this combination before saving.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
            }.frame(height: 56).animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: sampleReady)
            if let error = store.errorMessage { Text(error).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled) }
            if editing?.character != nil && editing?.character?.lab == nil {
                Text("This older voice keeps its original recipe until you preview and save a Lab combination.")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            HStack {
                Button(sampleReady ? "Another take" : "Create sample") {
                    if sampleReady {
                        store.cancelVoicePreview(); selection.seed = UInt64.random(in: 0...UInt64.max)
                    }
                    store.previewLab(selection: selection)
                }.modifier(GlassControl(prominent: !sampleReady)).tint(Theme.action).disabled(store.busy)
                Spacer()
                Button("Cancel") { store.errorMessage = nil; store.cancelVoicePreview(); dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(store.busy)
                Button("Save voice") { store.saveLab(name: name, selection: selection, editing: editing) }
                    .modifier(GlassControl(prominent: true)).tint(Theme.action)
                    .disabled(store.busy || !sampleReady || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 760).interactiveDismissDisabled(store.busy)
            .onAppear { store.cancelVoicePreview(); store.errorMessage = nil }
            .onChange(of: store.draftCharacter) { _, recipe in
                if name.isEmpty, let recipe { name = "My \(recipe.kokoroBase.map(KokoroVoice.name(for:)) ?? recipe.voice.capitalized) voice" }
            }
            .onDisappear { store.cancelVoicePreview() }
    }
    private func choose(_ trait: VoiceLabTrait) {
        guard trait.isSelectable, trait.id != selection.id(in: category) else { return }
        store.cancelVoicePreview(); store.errorMessage = nil
        selection.select(trait.id, in: category)
    }
    private func randomize() {
        store.cancelVoicePreview(); store.errorMessage = nil
        selection = .randomized(seed: UInt64.random(in: 0...UInt64.max), includeExperimental: true)
    }
}

private struct CharacterSamplePlayer: View {
    @ObservedObject var player: AudioPlayer
    var body: some View {
        HStack(spacing: 12) {
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 22, height: 22)
            }.accessibilityLabel(player.isPlaying ? "Pause sample" : "Play sample")
            VStack(alignment: .leading, spacing: 5) {
                Text("Your sample").font(.system(size: 12, weight: .medium))
                Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(0.01, player.duration))
                    .accessibilityLabel("Sample position")
            }
            Text(String(format: "%.0fs", player.duration)).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondary)
        }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
