import Observation
import PlynnKit
import ServiceManagement
import SwiftUI

enum MainTab: String, Hashable {
    case home, dictionary, snippets, settings
}

@MainActor @Observable
final class MainWindowModel {
    var tab: MainTab = .home
}

struct MainView: View {
    @Bindable var model: MainWindowModel
    @Bindable var engineManager: EngineManager
    let store: PersonalStore?
    let openOnboarding: () -> Void

    var body: some View {
        TabView(selection: $model.tab) {
            if let store {
                HomeView(store: store)
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(MainTab.home)
                DictionaryView(store: store)
                    .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
                    .tag(MainTab.dictionary)
                SnippetsView(store: store)
                    .tabItem { Label("Snippets", systemImage: "text.insert") }
                    .tag(MainTab.snippets)
            }
            SettingsPane(engineManager: engineManager, openOnboarding: openOnboarding)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .frame(minWidth: 620, minHeight: 560)
    }
}

struct SettingsPane: View {
    @Bindable var engineManager: EngineManager
    @AppStorage("aiPolish") private var aiPolish = true
    @AppStorage("learnCorrections") private var learnCorrections = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    let openOnboarding: () -> Void

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Engine", selection: $engineManager.preferred) {
                    Text("Automatic").tag(EngineChoice.auto)
                    Text("Parakeet (local)").tag(EngineChoice.parakeet)
                    Text("Apple (built-in)").tag(EngineChoice.apple)
                }
                LabeledContent("Status", value: engineManager.statusLine)
            }
            Section {
                Toggle("AI polish", isOn: $aiPolish)
                Toggle("Learn from my corrections", isOn: $learnCorrections)
            } header: {
                Text("Formatting")
            } footer: {
                Text("Polish removes filler words, applies self-corrections, formats lists, and matches tone to the app — on-device via Apple Intelligence. Corrections you make right after a paste teach the dictionary automatically. Everything stays on this Mac.")
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
                LabeledContent("Version", value: "0.0.1")
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
final class MainWindowController {
    private var window: NSWindow?
    private let model = MainWindowModel()
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

    func show(tab: MainTab) {
        model.tab = store == nil ? .settings : tab
        if window == nil {
            let w = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Plynn"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView(
                model: model, engineManager: engineManager,
                store: store, openOnboarding: openOnboarding))
            w.setContentSize(NSSize(width: 680, height: 600))
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
