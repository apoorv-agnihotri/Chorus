import SwiftUI
import AppKit

// Avoid the SDK 27 @State macro overload, whose plugin is absent from CLT.
// This alias keeps the established SwiftUI property-wrapper behavior.
typealias ViewState<Value> = SwiftUI.State<Value>

@main struct ChorusApp: App {
    @StateObject private var store = StudioStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        Window("Chorus", id: "studio") {
            StudioView(store: store)
                .frame(minWidth: 1080, minHeight: 720)
                .containerBackground(Theme.background, for: .window)
                .tint(Theme.accent)
                .foregroundStyle(Theme.ink)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
                .task { store.autoLoad() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.shutdown() }
        }
        .defaultSize(width: 1280, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Script") { store.newProject() }.keyboardShortcut("n").disabled(store.busy)
                Divider()
                Button("Import Tagged Script…") { store.showImporter = true }.keyboardShortcut("i").disabled(store.busy)
                Button("Export WAV…") { store.exportWAV() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!store.canExport)
            }
            CommandGroup(after: .toolbar) {
                Menu("Appearance") {
                    Button("System") { appearance = "system" }.keyboardShortcut("s", modifiers: [.command, .option])
                    Button("Light") { appearance = "light" }.keyboardShortcut("l", modifiers: [.command, .option])
                    Button("Dark") { appearance = "dark" }.keyboardShortcut("d", modifiers: [.command, .option])
                }
            }
            CommandMenu("Studio") {
                Button("Generate Audio") { store.generate() }.keyboardShortcut(.return, modifiers: .command).disabled(store.busy || store.workspace == .voices)
                Button("Set Up Nano & Kokoro…") { store.showSetup = true }.disabled(store.busy)
                Button("Local Engine…") { store.showEngine = true }
                Button("Unload Engine") { store.unloadModel() }.disabled(store.busy || (!store.ready && !store.modelResident))
                Button("Create Voice…") { store.openVoiceCreator() }.disabled(store.busy)
                Button("Clone Voice…") { store.showVoiceCloner = true }.disabled(store.busy)
            }
        }
    }
}
