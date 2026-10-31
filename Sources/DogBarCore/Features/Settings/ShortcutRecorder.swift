import AppKit
import SwiftUI

/// Records physical key codes. Observe recordingDidChange to suspend the switcher event tap while recording.
@MainActor public enum SettingsShortcutRecording {
    public static let recordingDidChange = Notification.Name("DogBar.SettingsShortcutRecordingDidChange")
    public private(set) static var isRecording = false
    private static var owner: UUID?
    static weak var activeRecorder: RecorderButton?
    static func acquire(owner token: UUID) {
        owner = token
        if !isRecording {
            isRecording = true
            NotificationCenter.default.post(name: recordingDidChange, object: nil)
        }
    }
    static func release(owner token: UUID) {
        guard owner == token else { return }
        owner = nil; isRecording = false
        NotificationCenter.default.post(name: recordingDidChange, object: nil)
    }
}

@MainActor struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.value = shortcut
        view.onRecord = { shortcut = $0 }
        view.refreshTitle()
    }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.finish() }
}

@MainActor final class RecorderButton: NSButton {
    var value = KeyboardShortcut.switcher
    var onRecord: ((KeyboardShortcut) -> Void)?
    private let recordingID = UUID()
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self; action = #selector(begin)
        setAccessibilityLabel("Record keyboard shortcut")
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    @objc private func begin() {
        if monitor != nil { finish(); return }
        // End any other recorder before claiming the event stream.
        guard let window, window.isKeyWindow else { return }
        SettingsShortcutRecording.activeRecorder?.finish()
        guard window.makeFirstResponder(self) else { return }
        SettingsShortcutRecording.activeRecorder = self
        SettingsShortcutRecording.acquire(owner: recordingID)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window, self.window?.firstResponder === self else { self.finish(); return event }
            guard !event.isARepeat else { return nil }
            if event.keyCode == 53 { self.finish(); return nil }
            let modifiers = HotkeyModifiers(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(.relevant)
            guard !modifiers.isEmpty else { NSSound.beep(); return nil }
            self.value = KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers)
            self.onRecord?(self.value)
            self.finish()
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finish() }
            }
        refreshTitle()
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    func finish() {
        guard monitor != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        SettingsShortcutRecording.release(owner: recordingID)
        refreshTitle()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { finish() }
        super.viewWillMove(toWindow: newWindow)
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        let token = recordingID
        Task { @MainActor in SettingsShortcutRecording.release(owner: token) }
    }
    func refreshTitle() {
        title = monitor == nil ? Self.label(value) : "Press shortcut (Esc cancels)"
    }
    private static func label(_ shortcut: KeyboardShortcut) -> String {
        let keys: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"Return",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"Tab",49:"Space",50:"`",51:"Delete",76:"Enter",115:"Home",116:"Page Up",117:"Forward Delete",119:"End",121:"Page Down",123:"Left",124:"Right",125:"Down",126:"Up"]
        var label = ""
        if shortcut.modifiers.contains(.control) { label += "⌃" }
        if shortcut.modifiers.contains(.option) { label += "⌥" }
        if shortcut.modifiers.contains(.shift) { label += "⇧" }
        if shortcut.modifiers.contains(.command) { label += "⌘" }
        return label + (keys[shortcut.keyCode] ?? "Key \(shortcut.keyCode)")
    }
}
