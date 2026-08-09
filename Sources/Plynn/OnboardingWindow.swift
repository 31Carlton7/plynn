import PlynnKit
import SwiftUI

/// Live-updating permissions checklist shown on first launch (or via Setup…).
struct OnboardingView: View {
    let engineManager: EngineManager
    @State private var mic = Permissions.micGranted()
    @State private var ax = Permissions.accessibilityGranted()
    @State private var globe = Permissions.globeKeySafe()
    @State private var grantedAxThisRun = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up Plynn")
                .font(.title2.bold())
            Text("Three quick steps, then hold **fn** anywhere and talk.")
                .foregroundStyle(.secondary)

            row(done: mic, title: "Microphone",
                detail: "Plynn hears you only while a hotkey is held.") {
                Button("Grant") { Permissions.requestMic() }
            }
            row(done: ax, title: "Accessibility",
                detail: "Lets Plynn see the fn key and paste text for you.") {
                Button("Grant") {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
            row(done: globe, title: "Globe key",
                detail: "Stops the 🌐 key from opening Apple's emoji/dictation UI.") {
                Button("Fix") { Permissions.setGlobeKeyDoNothing(); globe = Permissions.globeKeySafe() }
            }

            Divider()

            HStack {
                Image(systemName: "waveform")
                Text(engineManager.statusLine)
                    .foregroundStyle(.secondary)
                Spacer()
                if grantedAxThisRun {
                    Button("Relaunch Plynn") { Permissions.relaunch() }
                        .buttonStyle(.borderedProminent)
                        .help("Needed once so the fn listener starts with the new permission")
                }
            }
            .font(.callout)

            if mic && ax {
                Text("Ready — focus any text field, hold **fn**, and speak.")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onReceive(timer) { _ in
            mic = Permissions.micGranted()
            let axNow = Permissions.accessibilityGranted()
            if axNow && !ax { grantedAxThisRun = true }
            ax = axNow
            globe = Permissions.globeKeySafe()
        }
    }

    @ViewBuilder
    private func row(
        done: Bool, title: String, detail: String,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { action() }
        }
    }
}

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let engineManager: EngineManager

    init(engineManager: EngineManager) {
        self.engineManager = engineManager
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.title = "Plynn Setup"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(engineManager: engineManager))
            w.center()
            window = w
        }
        // Stay .accessory: no Dock icon for a menu-bar app.
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
