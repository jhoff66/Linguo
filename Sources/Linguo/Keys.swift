import AppKit
import Carbon.HIToolbox

/// Atalhos globais via Carbon (não precisam de permissão de Acessibilidade).
final class HotKeys {
    static let shared = HotKeys()
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKeys.shared.actions[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(keyCode: Int, modifiers: Int, _ action: @escaping () -> Void) {
        let id = UInt32(actions.count + 1)
        actions[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x504F4E54), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}

/// Simula teclas no app da frente (precisa de Acessibilidade).
enum Keyboard {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func askForAccess() {
        let opt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([opt: true] as CFDictionary)
    }

    static func press(_ key: Int, command: Bool = true) {
        let src = CGEventSource(stateID: .combinedSessionState)
        // Ignora as teclas físicas que ainda estejam seguradas (ex.: ⌃ do atalho).
        src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                        state: .eventSuppressionStateSuppressionInterval)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: down)
            e?.flags = command ? .maskCommand : []
            e?.post(tap: .cghidEventTap)
        }
    }

    static func selectAll() { press(kVK_ANSI_A) }
    static func copy() { press(kVK_ANSI_C) }
    static func paste() { press(kVK_ANSI_V) }
}

/// Guarda e devolve o conteúdo da área de transferência, pra tradução no lugar não apagar o que você tinha copiado.
struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init() {
        items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
    }

    func restore() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let restored = items.map { dict -> NSPasteboardItem in
            let it = NSPasteboardItem()
            for (t, v) in dict { it.setData(v, forType: t) }
            return it
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
    }

    static func set(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
