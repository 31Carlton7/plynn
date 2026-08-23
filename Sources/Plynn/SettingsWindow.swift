import Observation
import PlynnKit
import ServiceManagement
import SwiftUI

enum MainTab: String, Hashable {
    case home, notes, dictionary, snippets, settings
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
                MeetingsView(store: store)
                    .tabItem { Label("Notes", systemImage: "note.text") }
                    .tag(MainTab.notes)
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
    @AppStorage("hotkeyTrigger") private var hotkeyTrigger: HotkeyTrigger = .fn
    @AppStorage("aiPolish") private var aiPolish = true
    @AppStorage("learnCorrections") private var learnCorrections = true
    @AppStorage("soundEffects") private var soundEffects = true
    @AppStorage("haptics") private var haptics = true
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
                Picker("Activation key", selection: $hotkeyTrigger) {
                    ForEach(HotkeyTrigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }
            } header: {
                Text("Hotkey")
            } footer: {
                Text("fn works on Apple keyboards. Some third-party keyboards (NuPhy, Keychron, and similar compact boards) implement Fn as a local layer key that never reaches macOS as fn. If holding fn does nothing, switch to Right Option, Right Command, or Right Control instead. Takes effect immediately.")
            }
            Section {
                Toggle("AI polish", isOn: $aiPolish)
                Toggle("Learn from my corrections", isOn: $learnCorrections)
            } header: {
                Text("Formatting")
            } footer: {
                Text("Polish removes filler words, applies self-corrections, formats lists, and matches tone to the app — on-device via Apple Intelligence. Corrections you make right after a paste teach the dictionary automatically. Everything stays on this Mac.")
            }
            Section {
                Toggle("Sound effects", isOn: $soundEffects)
                    .onChange(of: soundEffects) { _, on in if on { Feedback.play(.success) } }
                Toggle("Haptic feedback", isOn: $haptics)
                    .onChange(of: haptics) { _, on in if on { Feedback.play(.lock) } }
            } header: {
                Text("Feedback")
            } footer: {
                Text("Cues for starting, locking hands-free, pasting, and cancelling — so you can dictate without watching the capsule. Haptics need a Force Touch trackpad.")
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
                HStack(spacing: 10) {
                    socialButton("X / Twitter", "https://x.com/31carlton7")
                    socialButton("Instagram", "https://instagram.com/31carlton7")
                    socialButton("GitHub", "https://github.com/31Carlton7/plynn")
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(
                            URL(string: "https://github.com/sponsors/31Carlton7")!)
                    } label: {
                        Label("Sponsor the Project", systemImage: "heart.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                }
            } header: {
                Text("Follow & Support")
            }
            Section {
                LabeledContent(
                    "Version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                        as? String ?? "dev")
            }
        }
        .formStyle(.grouped)
    }

    private func socialButton(_ title: String, _ urlString: String) -> some View {
        Button(title) {
            NSWorkspace.shared.open(URL(string: urlString)!)
        }
        .buttonStyle(.bordered)
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
        // Stay .accessory: the window can front without a Dock icon appearing.
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
