import AppKit

/// Barra do ⌥3: aparece em cima do campo de mensagem, já mostrando o resultado da última ação usada.
/// Todas as versões são pedidas de uma vez, então ← → troca na hora; nada muda no campo antes do ↩.
final class RewriteBar: NSPanel {
    var onApply: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let preview = NSTextField(wrappingLabelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private var mainChips: [Chip] = []
    private var moreChips: [Chip] = []
    private let moreRow = NSStackView()

    private var text = ""
    private var language = Language.all[0]
    private var results: [TextAction: String] = [:]
    private var partials: [TextAction: String] = [:]
    private var errors: [TextAction: String] = [:]
    private var tasks: [TextAction: Task<Void, Never>] = [:]
    private var waitingToApply = false
    /// Acima do campo, a barra cresce pra cima (fixa embaixo) pra nunca cobrir o que você escreveu.
    private var growsUp = true
    private var finished = true

    private var current: TextAction = .fix { didSet { refresh() } }
    private var showMore = false { didSet { moreRow.isHidden = !showMore; fit() } }

    private static let width: CGFloat = 520

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                   styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
        build()
    }

    private func build() {
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        contentView = bg

        preview.font = .systemFont(ofSize: 14)
        preview.textColor = .labelColor
        preview.isSelectable = true
        preview.preferredMaxLayoutWidth = Self.width - 32

        mainChips = TextAction.main.enumerated().map { makeChip($1, number: $0 + 1) }
        moreChips = TextAction.more.enumerated().map { makeChip($1, number: TextAction.main.count + $0 + 1) }
        let mainRow = NSStackView(views: mainChips)
        mainRow.spacing = 6
        moreRow.setViews(moreChips, in: .leading)
        moreRow.spacing = 6
        moreRow.isHidden = true

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.stringValue = "←→ trocar   ↓ mais opções   ↩ usar   esc cancelar"

        let line = NSBox()
        line.boxType = .separator

        let stack = NSStackView(views: [preview, line, mainRow, moreRow, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            bg.widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -12),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            line.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makeChip(_ action: TextAction, number: Int) -> Chip {
        let chip = Chip(action: action, number: number)
        chip.onClick = { [weak self] in
            guard let self else { return }
            if self.current == action { self.apply() } else { self.current = action }
        }
        return chip
    }

    override var canBecomeKey: Bool { true }

    // MARK: Abrir

    /// `anchor` é o retângulo do campo de mensagem (coordenadas da tela, origem embaixo); a barra fica logo acima.
    func present(text: String, language: Language, anchor: CGRect?) {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]; results = [:]; partials = [:]; errors = [:]
        self.text = text
        self.language = language
        waitingToApply = false
        finished = false
        showMore = false
        mainChips.first { $0.action == .translate }?.title = "Traduzir \(language.code.prefix(2).uppercased())"

        let last = TextAction(rawValue: UserDefaults.standard.string(forKey: "lastAction") ?? "") ?? .fix
        if TextAction.more.contains(last) { showMore = true }
        current = last
        TextAction.main.forEach(fetch)
        if showMore { TextAction.more.forEach(fetch) }

        fit()
        place(near: anchor)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    private func place(near anchor: CGRect?) {
        let mouse = NSEvent.mouseLocation
        let target = anchor ?? CGRect(origin: mouse, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: target.midX, y: target.midY)) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        var x = anchor.map { $0.minX } ?? target.midX - frame.width / 2
        var y = target.maxY + 8
        growsUp = true
        if y + frame.height + 120 > f.maxY {  // sem espaço em cima: vai pra baixo
            y = target.minY - frame.height - 8
            growsUp = false
        }
        x = min(max(x, f.minX + 8), f.maxX - frame.width - 8)
        y = min(max(y, f.minY + 8), f.maxY - frame.height - 8)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func fit() {
        guard let v = contentView else { return }
        v.layoutSubtreeIfNeeded()
        let size = v.fittingSize
        let y = growsUp ? frame.minY : frame.maxY - size.height
        setFrame(NSRect(x: frame.minX, y: y, width: Self.width, height: size.height), display: true)
    }

    // MARK: Gerar as versões

    private func fetch(_ action: TextAction) {
        guard tasks[action] == nil, results[action] == nil else { return }
        let text = self.text, lang = language
        tasks[action] = Task { @MainActor [weak self] in
            do {
                let partial: (String) -> Void = { p in
                    DispatchQueue.main.async {
                        guard let self, self.text == text else { return }
                        self.partials[action] = p
                        if self.current == action { self.refresh() }
                    }
                }
                let r = action == .translate
                    ? try await Translator.shared.translate(text, to: lang, direction: .outgoing, onPartial: partial)
                    : try await Translator.shared.rewrite(text, action, onPartial: partial)
                guard let self, self.text == text else { return }
                self.results[action] = r
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.text == text else { return }
                self.errors[action] = error.localizedDescription
            }
            guard let self else { return }
            self.tasks[action] = nil
            self.refresh()
            if self.waitingToApply, self.current == action { self.apply() }
        }
    }

    private func refresh() {
        for chip in mainChips + moreChips {
            chip.selected = chip.action == current
            chip.ready = results[chip.action] != nil
        }
        if let r = results[current] {
            preview.stringValue = r
            preview.textColor = .labelColor
        } else if let e = errors[current] {
            preview.stringValue = "Erro: \(e)"
            preview.textColor = .systemRed
        } else {
            preview.stringValue = partials[current] ?? "Gerando…"
            preview.textColor = .secondaryLabelColor
        }
        fit()
    }

    // MARK: Teclado

    private var shownActions: [TextAction] { showMore ? TextAction.main + TextAction.more : TextAction.main }

    private func move(_ step: Int) {
        let list = shownActions
        let i = list.firstIndex(of: current) ?? 0
        current = list[(i + step + list.count) % list.count]
    }

    override func keyDown(with event: NSEvent) {
        let all = TextAction.main + TextAction.more
        if let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...all.count).contains(n) {
            if n > TextAction.main.count { openMore() }
            current = all[n - 1]
            return
        }
        switch Int(event.keyCode) {
        case 124, 48: move(1)        // → e tab
        case 123: move(-1)           // ←
        case 125: openMore()         // ↓
        case 126:                    // ↑
            if TextAction.more.contains(current) { current = TextAction.main[0] }
            showMore = false
        case 36, 76: apply()         // ↩
        case 53: cancelOperation(nil)
        default: super.keyDown(with: event)
        }
    }

    private func openMore() {
        guard !showMore else { return }
        showMore = true
        TextAction.more.forEach(fetch)
    }

    // MARK: Fechar

    private func apply() {
        guard !finished else { return }
        guard let r = results[current] else {
            // Ainda gerando: usa assim que chegar. Se deu erro, tenta de novo.
            if errors[current] != nil { errors[current] = nil; fetch(current) }
            waitingToApply = true
            refresh()
            return
        }
        finished = true
        UserDefaults.standard.set(current.rawValue, forKey: "lastAction")
        tasks.values.forEach { $0.cancel() }
        orderOut(nil)
        onApply?(r)
    }

    override func cancelOperation(_ sender: Any?) {
        guard !finished else { return }
        finished = true
        tasks.values.forEach { $0.cancel() }
        orderOut(nil)
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        // Clicou fora: fecha sem mexer no campo.
        if isVisible { cancelOperation(nil) }
    }
}

private final class Chip: NSView {
    let action: TextAction
    var onClick: (() -> Void)?
    var selected = false { didSet { update() } }
    var ready = false { didSet { update() } }
    var title: String { didSet { label.stringValue = title } }

    private let label = NSTextField(labelWithString: "")
    private let key = NSTextField(labelWithString: "")

    init(action: TextAction, number: Int) {
        self.action = action
        self.title = action.title
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        label.stringValue = title
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        key.stringValue = "\(number)"
        key.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let h = NSStackView(views: [key, label])
        h.spacing = 5
        h.edgeInsets = NSEdgeInsets(top: 5, left: 9, bottom: 5, right: 10)
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: leadingAnchor), h.trailingAnchor.constraint(equalTo: trailingAnchor),
            h.topAnchor.constraint(equalTo: topAnchor), h.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func update() {
        layer?.backgroundColor = selected ? NSColor.controlAccentColor.cgColor
                                          : NSColor.labelColor.withAlphaComponent(0.07).cgColor
        // Opção ainda gerando fica mais apagada.
        label.textColor = selected ? .white : (ready ? .labelColor : .secondaryLabelColor)
        key.textColor = selected ? .white.withAlphaComponent(0.75) : .tertiaryLabelColor
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Retângulo do campo com foco no app da frente, via Acessibilidade, já em coordenadas do Cocoa (origem embaixo).
func focusedFieldFrame() -> CGRect? {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
    let el = element as! AXUIElement
    var posRef: CFTypeRef?, sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let posVal = posRef, let sizeVal = sizeRef else { return nil }
    var pos = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
    // Campo muito grande (a janela inteira, por exemplo) não serve de âncora.
    guard size.width > 20, size.height > 10, size.height < 400 else { return nil }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
}
