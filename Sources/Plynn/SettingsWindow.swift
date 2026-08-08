import PlynnKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var engineManager: EngineManager
    let store: PersonalStore?
    @AppStorage("aiPolish") private var aiPolish = true
    @AppStorage("learnCorrections") private var learnCorrections = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    let openOnboarding: () -> Void

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            if let store {
                DictionaryView(store: store)
                    .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
                SnippetsView(store: store)
                    .tabItem { Label("Snippets", systemImage: "text.insert") }
            }
        }
        .frame(width: 480, height: 420)
    }

    private var general: some View {
        Form {
            Section("Transcription") {
                Picker("Engine", selection: $engineManager.preferred) {
                    Text("Automatic").tag(EngineChoice.auto)
                    Text("Parakeet (local)").tag(EngineChoice.parakeet)
                    Text("Apple (built-in)").tag(EngineChoice.apple)
                }
                LabeledContent("Status", value: engineManager.statusLine)
            }
            Section("Formatting") {
                Toggle("AI polish", isOn: $aiPolish)
                Text("Removes filler words, applies self-corrections, formats lists, and matches tone to the app — fully on-device (Qwen3-4B, loads in the background on launch).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Learn from my corrections", isOn: $learnCorrections)
                Text("When you fix a word right after a paste, Plynn adds it to your dictionary automatically. Everything stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Button("Open Setup…") { openOnboarding() }
            }
            Section {
                LabeledContent("Version", value: "0.1 (Phase 1b)")
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let engineManager: EngineManager
    private let store: PersonalStore?
    private let openOnboarding: () -> Void

    init(
        engineManager: EngineManager, store: PersonalStore?,
        openOnboarding: @escaping () -> Void
    ) {
        self.engineManager = engineManager
        self.store = store
        self.openOnboarding = openOnboarding
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "Plynn Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(
                engineManager: engineManager, store: store, openOnboarding: openOnboarding))
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
