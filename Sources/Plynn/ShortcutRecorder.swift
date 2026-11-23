import AppKit
import PlynnKit
import SwiftUI

/// One Settings row: click, then press a combination (⌥Space) or tap a lone
/// modifier (Right Command) to bind it to `action`.
struct ShortcutRecorder: View {
    let action: HotkeyAction
    let setHotkeysPaused: (Bool) -> Void
    @AppStorage private var stored: String?
    @AppStorage("hotkeyTrigger") private var legacyActivationKey: String?
    @State private var capture = KeyCapture()
    @State private var problem: String?

    init(action: HotkeyAction, setHotkeysPaused: @escaping (Bool) -> Void) {
        self.action = action
        self.setHotkeysPaused = setHotkeysPaused
        _stored = AppStorage(action.defaultsKey)
    }

    /// Reads both keys so the row redraws when either changes, as Reset
    /// removes them without touching any other state.
    private var current: Shortcut? {
        _ = (stored, legacyActivationKey)
        return action.shortcut()
    }

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Button(action: toggleRecording) {
                        Text(label)
                            .foregroundStyle(capture.isActive || current == nil ? .secondary : .primary)
                            .frame(minWidth: 130)
                    }
                    if current != action.defaultShortcut {
                        Button {
                            stopRecording()
                            action.resetShortcut()
                            problem = nil
                        } label: {
                            Image(systemName: resetSymbol)
                        }
                        .buttonStyle(.borderless)
                        .help(action.defaultShortcut.map { "Reset to \($0.displayName)" } ?? "Clear")
                    }
                }
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            }
        } label: {
            Text(action.title)
        }
        .onDisappear(perform: stopRecording)
    }

    private var resetSymbol: String {
        action.defaultShortcut == nil ? "xmark.circle.fill" : "arrow.counterclockwise"
    }

    private var label: String {
        if capture.isActive { return "Type shortcut…" }
        return current?.displayName ?? "Record Shortcut"
    }

    private func toggleRecording() {
        if capture.isActive {
            stopRecording()
            return
        }
        problem = nil
        capture.start { shortcut in
            stopRecording()
            guard let shortcut else { return }  // Escape, or another row started recording
            if let reason = shortcut.problem(for: action, among: HotkeyAction.storedShortcuts()) {
                problem = reason
                return
            }
            stored = shortcut.rawValue
        }
        // After start: starting cancels any other row, and that row unpauses.
        setHotkeysPaused(true)
    }

    private func stopRecording() {
        guard capture.isActive else { return }
        capture.stop()
        setHotkeysPaused(false)
    }
}

/// Watches this window's key events while recording and reports the first
/// complete shortcut: a key pressed with its modifiers, or one modifier
/// pressed and released alone. Reports nil for a bare Escape, or when
/// another row starts recording, so only one row ever listens.
@MainActor @Observable
final class KeyCapture {
    private static weak var listening: KeyCapture?

    private(set) var isActive = false
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onCapture: ((Shortcut?) -> Void)?
    @ObservationIgnored private var loneModifier: UInt16?
    @ObservationIgnored private var modifierChordBroken = false

    func start(onCapture: @escaping (Shortcut?) -> Void) {
        Self.listening?.onCapture?(nil)
        Self.listening = self
        self.onCapture = onCapture
        isActive = true
        loneModifier = nil
        modifierChordBroken = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                modifierChordBroken = true
                let modifiers = event.modifierFlags.intersection(Shortcut.comboModifiers)
                if event.keyCode == 53 && modifiers.isEmpty {
                    onCapture(nil)
                } else {
                    onCapture(Shortcut(keyCode: event.keyCode, modifiers: modifiers))
                }
            } else {
                handleFlagsChanged(event, onCapture: onCapture)
            }
            return nil  // keep ⌘W and friends from acting while recording
        }
    }

    private func handleFlagsChanged(_ event: NSEvent, onCapture: (Shortcut?) -> Void) {
        let held = event.modifierFlags.intersection(Shortcut.comboModifiers.union(.function))
        if held.isEmpty {
            if !modifierChordBroken, let key = loneModifier {
                onCapture(Shortcut(keyCode: key))
            }
            loneModifier = nil
            modifierChordBroken = false
        } else if loneModifier == nil {
            loneModifier = event.keyCode
        } else if loneModifier != event.keyCode {
            modifierChordBroken = true
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onCapture = nil
        isActive = false
    }
}
