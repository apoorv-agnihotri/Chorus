import SwiftUI
import ChorusKit

struct ChorusMark: View {
    var size: CGFloat = 34
    var body: some View {
        HStack(spacing: size * 0.08) {
            ForEach(Array([0.28, 0.58, 0.9, 0.68, 0.4].enumerated()), id: \.offset) { _, h in
                Capsule().fill(Theme.accent).frame(width: size * 0.1, height: size * h)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct StudioView: View {
    @ObservedObject var store: StudioStore
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Divider()
            VStack(spacing: 0) {
                header.modifier(GlassGroup())
                Divider()
                if store.workspace == .voices { VoiceLibraryView(store: store) }
                else {
                    HStack(spacing: 0) {
                        editor.frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        inspector.frame(width: 255)
                    }
                    playback.padding(.horizontal, 26).padding(.bottom, 22).padding(.top, 12)
                }
            }.background(StudioBackdrop())
        }
        .sheet(isPresented: $store.showSetup) { FirstRunSetupSheet(store: store) }
        .sheet(isPresented: $store.showEngine) { EngineSheet(store: store) }
        .sheet(isPresented: $store.showImporter) { ImportSheet(store: store) }
        .sheet(isPresented: $store.showVoiceCreator, onDismiss: { store.cancelVoicePreview() }) { VoicePresetSheet(store: store, base: store.presetBaseID) }
        .sheet(isPresented: $store.showVoiceCloner) { CloneVoiceSheet(store: store) }
        .sheet(item: $store.editingVoice, onDismiss: { store.cancelVoicePreview() }) { voice in VoicePresetSheet(store: store, editing: voice) }
        .alert("Chorus needs your attention", isPresented: Binding(get: { store.errorMessage != nil && !store.showSetup && !store.showEngine && !store.showVoiceCreator && !store.showVoiceCloner && store.editingVoice == nil && !store.showImporter }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { ChorusMark(); Text("Chorus").font(.system(size: 25, weight: .semibold, design: .rounded)) }
                .padding(.top, 30).padding(.bottom, 7)
            Text("YOUR LOCAL VOICE STUDIO").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.secondary)
                .padding(.bottom, 40)
            Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(Theme.muted).padding(.bottom, 12)
            ForEach(Workspace.allCases) { item in
                Button { withAnimation(.easeInOut(duration: 0.18)) { store.workspace = item } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(item)).frame(width: 20)
                        Text(item.rawValue).font(.system(size: 13, weight: store.workspace == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 10).padding(.vertical, 11)
                        .foregroundStyle(store.workspace == item ? Theme.accent : .primary)
                        .modifier(NavigationMaterial(selected: store.workspace == item))
                }.buttonStyle(.plain).padding(.bottom, 3).disabled(store.busy)
            }
            Divider().padding(.vertical, 23)
            Button { store.newProject() } label: { Label("New script", systemImage: "plus").font(.system(size: 12)) }.buttonStyle(.plain).disabled(store.busy)
            Spacer(minLength: 24)
            Button { store.showEngine = true } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Circle().fill(store.ready || store.kokoroInstalled ? Theme.accent : Color.orange).frame(width: 6, height: 6); Text("Local engine").font(.system(size: 12, weight: .medium)); Spacer(); Image(systemName: "slider.horizontal.3") }
                    Text(store.engineLabel).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }.padding(13).background(Theme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
            HStack(spacing: 6) { Image(systemName: "lock.shield"); Text("On your Mac. Always.") }.font(.system(size: 10)).foregroundStyle(Theme.secondary).padding(.top, 16).padding(.bottom, 22)
        }.padding(.horizontal, 18).frame(maxHeight: .infinity).background(Theme.sidebar)
    }
    private func icon(_ item: Workspace) -> String {
        switch item { case .studio: return "square.stack.3d.up"; case .speech: return "waveform"; case .voices: return "person.2" }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.workspace.rawValue).font(.system(size: 24, weight: .semibold))
                Text(store.workspace == .studio ? "A conversation, one voice at a time." : store.workspace == .speech ? "Turn your words into something you can hear." : "The voices behind your stories.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if store.workspace == .studio {
                Button { store.showImporter = true } label: { Label("Import script", systemImage: "text.badge.plus") }.disabled(store.busy)
            } else if store.workspace == .voices {
                Button { store.showVoiceCloner = true } label: { Label("Clone voice", systemImage: "waveform.badge.plus") }.disabled(store.busy)
                Button { store.openVoiceCreator() } label: { Label("Create voice", systemImage: "plus") }.disabled(store.busy)
            }
        }.modifier(GlassControl()).controlSize(.large).padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 24)
    }
    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.workspace == .studio {
                    HStack {
                        TextField("Script title", text: $store.project.title).font(.system(size: 22, weight: .medium)).textFieldStyle(.plain)
                        Spacer()
                        Text("\(store.project.dialogue.count) \(store.project.dialogue.count == 1 ? "BLOCK" : "BLOCKS")").font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(Theme.muted)
                    }.padding(.bottom, 5)
                    if store.project.dialogue.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "text.bubble").font(.system(size: 32)).foregroundStyle(Theme.accent)
                            Text("Start a conversation").font(.title3.weight(.medium))
                            Text("Add your first dialogue block or import a script with [speaker] tags.").font(.callout).foregroundStyle(Theme.secondary)
                        }.padding(.vertical, 40)
                    }
                    LazyVStack(spacing: 16) {
                        ForEach($store.project.dialogue) { $block in
                            DialogueRow(block: $block, store: store)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    Button { store.addDialogue() } label: {
                        HStack(spacing: 8) { Image(systemName: "plus.circle"); Text("Add dialogue") }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                } else {
                    Text("What would you like to say?").font(.system(size: 22, weight: .medium))
                    TextEditor(text: $store.singleText).font(.system(size: 18)).lineSpacing(7)
                        .scrollContentBackground(.hidden).padding(14).frame(minHeight: 320)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 10) {
                        ExpressionMenu(text: $store.singleText)
                        Text("Delivery styles are experimental.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
                HStack { Text("\(store.wordCount) words"); Text("·"); Text("~\(store.estimatedSeconds)s estimated speech") }
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.padding(30).disabled(store.busy)
        }
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.workspace == .studio {
                    voiceActions
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("Between dialogue blocks").font(.system(size: 12, weight: .medium)); Spacer(); Text(String(format: "%.1fs", store.project.pause)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary) }
                        Slider(value: $store.project.pause, in: 0...3, step: 0.1).accessibilityLabel("Pause between dialogue blocks")
                    }
                } else {
                    Text("Voice").font(.system(size: 14, weight: .semibold))
                    VoicePicker(selection: $store.singleVoice, voices: store.voices)
                    voiceActions
                    if let voice = store.voices.first(where: { $0.id == store.singleVoice }) {
                        Button("Customize \(voice.name)…") { store.editingVoice = voice }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("OUTPUT").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.muted)
                    Label("WAV · 24 kHz · Mono", systemImage: "waveform").font(.system(size: 12))
                }
                if !store.ready && !store.workspaceUsesKokoro {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A little setup. Then offline.").font(.system(size: 12, weight: .medium))
                        Text("Download the engine once, or load your local model files.").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
                        Button("Set up engine") { store.showEngine = true }.buttonStyle(.bordered)
                    }
                }
            }.padding(22).disabled(store.busy)
        }.background(Theme.inspector)
    }
    private var playback: some View {
        PlaybackBar(store: store, player: store.player).modifier(GlassGroup()).modifier(FloatingMaterial())
    }
    private var voiceActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { store.openVoiceCreator() } label: { Label("Create voice…", systemImage: "slider.horizontal.3") }
            Button { store.showVoiceCloner = true } label: { Label("Clone voice…", systemImage: "waveform.badge.plus") }
        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
    }
}

struct VoicePicker: View {
    @Binding var selection: UUID?
    var voices: [LocalVoice]
    var body: some View {
        Picker("Voice", selection: Binding<UUID?>(get: { selection ?? BuiltInVoice.defaultVoice.id }, set: { selection = $0 })) {
            ForEach(BuiltInVoice.all) { voice in Text(voice.name).tag(Optional(voice.id)) }
            ForEach(voices) { voice in Text(voice.name).tag(Optional(voice.id)) }
            if let selection, !voices.contains(where: { $0.id == selection }), BuiltInVoice.named(selection) == nil { Text("Missing voice · reassign").tag(Optional(selection)) }
            if let selection, !BuiltInVoice.isPublicBase(selection), let previous = BuiltInVoice.named(selection) {
                Text(previous.name).tag(Optional(previous.id))
            }
        }.labelsHidden().pickerStyle(.menu).buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .accessibilityLabel("Assigned voice")
    }
}

struct DialogueRow: View {
    @Binding var block: Dialogue
    @ObservedObject var store: StudioStore
    private var index: Int { store.project.dialogue.firstIndex(where: { $0.id == block.id }) ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                VoicePicker(selection: Binding(
                    get: { store.project.speakers.first(where: { $0.id == block.speakerID })?.voiceID },
                    set: { store.project.assignVoice($0, toDialogue: block.id) }
                ), voices: store.voices)
                    .fixedSize()
                    .accessibilityLabel("Voice for dialogue block \(index + 1)")
                Spacer()
                if store.generatingID == block.id { ProgressView().controlSize(.small) }
                else if store.completedIDs.contains(block.id) && !store.isStale { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                Menu {
                    Button("Move up") { store.moveDialogue(block.id, offset: -1) }.disabled(index == 0)
                    Button("Move down") { store.moveDialogue(block.id, offset: 1) }.disabled(index == store.project.dialogue.count - 1)
                    Button("Duplicate") { store.project.dialogue.insert(.init(speakerID: block.speakerID, text: block.text), at: index + 1) }
                    Divider()
                    Button("Delete", role: .destructive) { withAnimation { store.project.dialogue.removeAll { $0.id == block.id } } }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Dialogue actions")
            }
            TextEditor(text: $block.text).font(.system(size: 16)).lineSpacing(5)
                .scrollContentBackground(.hidden).frame(height: max(66, CGFloat(block.text.components(separatedBy: "\n").count * 26 + 20)))
                .accessibilityLabel("Dialogue text for block \(index + 1)")
            HStack(spacing: 8) {
                ExpressionMenu(text: $block.text)
                Spacer()
            }
        }.padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(store.generatingID == block.id ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1))
    }
}

struct PlaybackBar: View {
    @ObservedObject var store: StudioStore
    @ObservedObject var player: AudioPlayer
    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 14) {
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16))
                        .foregroundStyle(store.output == nil ? Color.secondary : Theme.accent)
                        .frame(width: 38, height: 38).background(Theme.accent.opacity(0.08), in: Circle())
                }.buttonStyle(.plain).disabled(store.output == nil || store.busy).accessibilityLabel(player.isPlaying ? "Pause audio" : "Play audio")
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text("Audio preview").font(.system(size: 11, weight: .medium)); Spacer(); Text("\(time(player.position)) / \(time(player.duration))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary) }
                    WaveformView(values: store.waveform, fraction: player.duration > 0 ? player.position / player.duration : 0).frame(height: 24)
                        .accessibilityHidden(true)
                }
                Button { store.exportWAV() } label: { Label("WAV", systemImage: "square.and.arrow.up") }.modifier(GlassControl()).disabled(!store.canExport).help("Export WAV (⇧⌘E)")
                if store.busy { Button("Cancel") { store.cancel() }.modifier(GlassControl()) }
                else {
                    Button { store.generate() } label: { Label("Generate Audio", systemImage: "waveform") }
                        .modifier(GlassControl(prominent: true)).tint(Theme.action).controlSize(.large)
                }
            }
            if store.output != nil {
                Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(0.01, player.duration))
                    .controlSize(.mini).accessibilityLabel("Playback position")
            }
            HStack(spacing: 6) {
                if store.busy { ProgressView(value: store.progress).frame(width: 55).controlSize(.small) }
                else { Image(systemName: store.isStale ? "arrow.clockwise" : "cpu") }
                Text(store.isStale ? "Script or voice changed · generate again to export" : store.status)
                Spacer()
            }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }.padding(17)
    }
    private func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

struct WaveformView: View {
    var values: [Float]
    var fraction: Double
    var body: some View {
        Canvas { context, size in
            let bins = values.isEmpty ? 100 : values.count
            let step = size.width / CGFloat(bins)
            for i in 0..<bins {
                let amplitude = values.isEmpty ? CGFloat(0.05) : CGFloat(min(1, max(0.06, values[i])))
                let h = max(2, amplitude * size.height)
                let rect = CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: max(1, step - 1.5), height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Double(i) / Double(bins) < fraction ? Theme.accent : Theme.accent.opacity(values.isEmpty ? 0.5 : 0.65)))
            }
        }
    }
}
