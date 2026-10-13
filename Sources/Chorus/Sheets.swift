import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ChorusKit

struct SheetHeading: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 25, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineSpacing(4)
        }
    }
}

struct FirstRunSetupSheet: View {
    @ObservedObject var store: StudioStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SheetHeading(title: "Welcome to Chorus", subtitle: "Download your voices once. Create offline from then on.")
            VStack(alignment: .leading, spacing: 18) {
                Label("Chatterbox Nano — conversations and expressive speech", systemImage: "waveform")
                Label("Kokoro — voice creation and English presets", systemImage: "slider.horizontal.3")
            }.font(.system(size: 13))
            Text("Setup downloads Nano, Kokoro, and the required voice encoders to your Mac. Allow roughly 2 GB of free space and keep an internet connection until setup finishes. Turbo is optional in Local engine. The first sample may take a little longer while models compile.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
            if store.busy {
                HStack { ProgressView().controlSize(.small); Text(store.status).font(.system(size: 12)) }
            }
            if let issue = store.errorMessage {
                Text(issue).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                if store.busy {
                    Button("Pause setup") { store.cancel() }
                } else {
                    Button("Set up later") { store.errorMessage = nil; store.showSetup = false; store.autoLoad() }
                    Spacer()
                    Button("Download Nano & Kokoro") { store.setupDefaultEngines() }
                        .modifier(GlassControl(prominent: true)).tint(Theme.action)
                }
            }
        }.padding(32).frame(width: 560).interactiveDismissDisabled(store.busy)
    }
}

struct EngineSheet: View {
    @ObservedObject var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SheetHeading(title: "Your local engines", subtitle: "Choose a voice in your workspace. Chorus uses its engine automatically.")
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kokoro · 82M").font(.system(size: 15, weight: .semibold))
                    Text(store.kokoroInstalled ? "Downloaded · English preset voices" : "103 MB download · English preset voices")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("Create Kokoro voice…") { dismiss(); store.openVoiceCreator() }.disabled(store.busy)
            }
            Divider()
            HStack(spacing: 14) {
                variant("turbo", title: "Chatterbox Turbo", size: "350M parameters", detail: "The expressive everyday choice.")
                variant("nano", title: "Chatterbox Nano", size: "110M parameters", detail: "A lighter footprint for your Mac.")
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Apple Silicon · Core ML", systemImage: "cpu")
                Label("English · vocal reactions & delivery styles", systemImage: "text.bubble")
                Label("No accounts, credits, or cloud generation", systemImage: "lock.shield")
            }.font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Text("Model files and voice encoders are downloaded from Hugging Face. Allow roughly 1–2 GB of disk space; first load compiles the models and may take a few minutes. The engine loads on demand and releases its models after two idle minutes. Unload engine releases them immediately; downloaded files and generated audio stay available.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            if let path = store.localModelDirectory(for: store.modelVariant)?.path {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LOCAL MODEL FOLDER").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Theme.muted)
                    Text(path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(2).textSelection(.enabled)
                }
            }
            Divider()
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
            }
            if store.busy {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: store.progress)
                    HStack { Text(store.status); Spacer(); Text("\(Int(store.progress * 100))%") }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                Button("Use local folder…") { store.chooseModel() }.disabled(store.busy)
                if store.ready || store.modelResident { Button("Unload engine") { store.unloadModel() }.disabled(store.busy) }
                Spacer()
                Button("Done") { store.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(store.selectedModelActionTitle) { store.prepareSelectedModel() }
                    .modifier(GlassControl(prominent: true)).tint(Theme.action).disabled(store.busy || store.isModelLoaded(store.modelVariant))
            }
        }.padding(32).frame(width: 650).interactiveDismissDisabled(store.busy)
    }
    private func variant(_ value: String, title: String, size: String, detail: String) -> some View {
        Button { store.modelVariant = value } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: value == "turbo" ? "waveform" : "leaf").font(.system(size: 22)); Spacer(); Image(systemName: store.modelVariant == value ? "checkmark.circle.fill" : "circle").foregroundStyle(store.modelVariant == value ? Theme.accent : .secondary) }
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(size).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Text(store.isModelLoaded(value) ? "Loaded" : store.isModelSleeping(value) ? "Loads when needed" : store.localModelDirectory(for: value) != nil ? "Downloaded" : "Not downloaded")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(store.modelVariant == value ? Theme.accent.opacity(0.07) : Theme.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(store.modelVariant == value ? Theme.accent.opacity(0.55) : Theme.border))
                .contentShape(RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain).disabled(store.busy)
    }
}

struct ImportSheet: View {
    @ObservedObject var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var script = "[rue]\nDid you really just say that?\n\n[kai]\n[laugh] Yes! And I'd say it again!\n\n[rue]\nThat's unbelievable."
    @ViewState<String?> private var issue: String?
    @ViewState<StudioProject?> private var preview: StudioProject?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeading(title: "Bring your script", subtitle: "Put each [speaker] on its own line. Chorus turns your script into dialogue blocks.")
            TextEditor(text: $script).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(14).frame(height: 280).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Tagged script")
            HStack {
                Button("Open text file…") { openText() }
                Spacer()
                if let preview { Text("\(preview.speakers.count) speakers · \(preview.dialogue.count) blocks").foregroundStyle(Theme.accent) }
            }.font(.system(size: 12))
            if let issue { Text(issue).font(.system(size: 12)).foregroundStyle(.red) }
            Text("Import replaces the current script. Speaker names match bundled and saved voices regardless of capitalization. Existing voice assignments are kept. Choose a voice directly on each dialogue block.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Import script") {
                do { try store.importScript(script) } catch { issue = error.localizedDescription }
            }.modifier(GlassControl(prominent: true)).tint(Theme.action).disabled(preview == nil) }
        }.padding(32).frame(width: 630)
            .onAppear { validate() }.onChange(of: script) { _, _ in validate() }
    }
    private func validate() {
        do { preview = try ScriptParser.parse(script); issue = nil }
        catch { preview = nil; issue = error.localizedDescription }
    }
    private func openText() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do { script = try String(contentsOf: url, encoding: .utf8) } catch { issue = error.localizedDescription }
        }
    }
}

struct CloneVoiceSheet: View {
    @ObservedObject var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var name = ""
    @ViewState<URL?> private var reference: URL?
    @ViewState<Bool> private var authorized = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeading(title: "Clone voice", subtitle: "Create a reusable clone from your local reference recording.")
            VStack(alignment: .leading, spacing: 9) {
                Text("VOICE NAME").font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(Theme.secondary)
                TextField("e.g. My voice", text: $name).textFieldStyle(.roundedBorder).controlSize(.large)
            }
            Button { chooseReference() } label: {
                VStack(spacing: 13) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 27)).foregroundStyle(Theme.accent)
                    Text(reference?.lastPathComponent ?? "Choose reference audio").font(.system(size: 14, weight: .medium)).lineLimit(2)
                    Text("WAV, AIFF, M4A, MP3 · 25–30 seconds recommended").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 29).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(store.busy)
            Text("Use clean speech from a single speaker, without music. At least 10 seconds is required. Your recording is processed locally; Chorus keeps the resulting voice file.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
            Toggle("This is my voice, or I have permission to use it.", isOn: $authorized).font(.system(size: 12)).disabled(store.busy)
            if !store.ready {
                HStack { Label("Set up your engine to clone voices.", systemImage: "cpu"); Spacer(); Button("Set up") { dismiss(); store.showEngine = true } }.font(.system(size: 12))
            }
            if store.busy { HStack { ProgressView().controlSize(.small); Text(store.status).font(.system(size: 12)).foregroundStyle(Theme.secondary) } }
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { store.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction).disabled(store.busy)
                Button("Clone voice") {
                    if let reference { store.cloneVoice(name: name.trimmingCharacters(in: .whitespacesAndNewlines), reference: reference) }
                }.modifier(GlassControl(prominent: true)).tint(Theme.action).disabled(!store.ready || store.busy || reference == nil || !authorized || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(32).frame(width: 570).interactiveDismissDisabled(store.busy)
    }
    private func chooseReference() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.prompt = "Use reference"
        if panel.runModal() == .OK { reference = panel.url }
    }
}

struct VoiceLibraryView: View {
    @ObservedObject var store: StudioStore
    @ViewState<LocalVoice?> private var voiceToDelete: LocalVoice? = nil
    private func detail(for voice: LocalVoice) -> String {
        switch voice.kind {
        case .character:
            return voice.character?.lab != nil ? "Voice Lab · \(voice.character?.voice.capitalized ?? "Character")" : "Created from a description"
        case .kokoro: return "Kokoro · \(KokoroVoice.name(for: voice.kokoro?.voice ?? ""))"
        case .cloned: return "Cloned voice · local recording"
        case .preset: return "Custom preset · \(BuiltInVoice.named(voice.baseVoiceID)?.name ?? "Missing base")"
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("Bundled voices").font(.system(size: 16, weight: .semibold)); Spacer(); Text("\(BuiltInVoice.all.count) English voices").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                Text("Choose a bundled voice, or combine traits in Voice Lab.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                ForEach(BuiltInVoice.all) { voice in
                    HStack(spacing: 15) {
                        Image(systemName: "waveform").font(.system(size: 23)).foregroundStyle(Theme.accent).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(voice.name).font(.system(size: 16, weight: .medium))
                            Text(voice.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            Text(String(format: "%.2f× speed · %@", voice.settings.speed,
                                voice.settings.expression.isEmpty ? "Natural delivery" : voice.settings.expression.capitalized + " preset"))
                                .font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("Use") { store.singleVoice = voice.id; store.workspace = .speech }
                    }.buttonStyle(.bordered).disabled(store.busy)
                    Divider()
                }
                HStack { Text("Your voices").font(.system(size: 16, weight: .semibold)); Spacer(); Text("\(store.voices.count) local voices").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                if store.voices.isEmpty {
                    Text("Create a Voice Lab combination, or clone your own recording.").font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.vertical, 16)
                }
                ForEach(store.voices) { voice in
                    HStack(spacing: 15) {
                        Text(String(voice.name.prefix(1)).uppercased()).font(.system(size: 19, weight: .medium)).foregroundStyle(Theme.accent).frame(width: 44, height: 44).background(Theme.accent.opacity(0.07), in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(voice.name).font(.system(size: 16, weight: .medium))
                            Text(detail(for: voice))
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            Text(voice.kind == .character ? (voice.character?.lab?.summary ?? "Saved character voice") : String(format: "%.2f× speed · %@", voice.settings.speed, voice.settings.expression.isEmpty ? "Natural delivery" : voice.settings.expression.capitalized))
                                .font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("Use") { store.singleVoice = voice.id; store.workspace = .speech }
                        Button("Customize") { store.editingVoice = voice }
                        Button("Delete", role: .destructive) { voiceToDelete = voice }
                    }.buttonStyle(.bordered).disabled(store.busy)
                    Divider()
                }
            }.padding(38).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .confirmationDialog("Delete \(voiceToDelete?.name ?? "voice")?", isPresented: Binding(
                get: { voiceToDelete != nil }, set: { if !$0 { voiceToDelete = nil } }
            ), titleVisibility: .visible) {
                if let voice = voiceToDelete {
                    Button("Delete voice", role: .destructive) {
                        store.deleteVoice(voice.id)
                        voiceToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { voiceToDelete = nil }
            } message: {
                Text("This removes the voice from your library. Any dialogue blocks or Text to Speech using it will switch to Rue." + (voiceToDelete?.filename != nil ? " Its voice file will be moved to the Trash." : ""))
            }
    }
}
