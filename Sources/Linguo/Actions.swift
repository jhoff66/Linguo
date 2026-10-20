import AppKit

/// O que o ⌥3 sabe fazer com o texto do campo.
enum TextAction: String, CaseIterable {
    case translate, fix, improve, humanize, marketing, professional, friendly, shorter

    var title: String {
        switch self {
        case .translate: return "Traduzir"
        case .fix: return "Corrigir ortografia"
        case .improve: return "Melhorar texto"
        case .humanize: return "Humanizar"
        case .marketing: return "Marketing"
        case .professional: return "Profissional"
        case .friendly: return "Mais simpático"
        case .shorter: return "Encurtar"
        }
    }

    var symbol: String {
        switch self {
        case .translate: return "character.bubble"
        case .fix: return "checkmark.circle"
        case .improve: return "wand.and.stars"
        case .humanize: return "person.wave.2"
        case .marketing: return "megaphone"
        case .professional: return "briefcase"
        case .friendly: return "face.smiling"
        case .shorter: return "scissors"
        }
    }

    private var instruction: String {
        switch self {
        case .translate:
            return ""
        case .fix:
            return "Corrija só ortografia, acentuação, pontuação e concordância. Não troque palavras, estilo nem tom além do necessário. Se já estiver correto, devolva igual."
        case .improve:
            return "Melhore a clareza e a fluidez, deixando a mensagem bem escrita e fácil de ler, sem mudar o sentido nem o tom."
        case .humanize:
            return "Reescreva para soar como uma pessoa real digitando no WhatsApp: natural, direto, com frases de tamanhos variados. Tire tudo que tenha cara de texto de IA: formalidade exagerada, travessões, listas, frases de efeito, palavras rebuscadas."
        case .marketing:
            return "Reescreva como mensagem de vendas para WhatsApp, com liberdade para reorganizar e refrasear tudo: abra com algo que prenda a atenção, deixe claro o benefício para o cliente e feche com uma chamada para ação. Persuasivo, mas sem exagero e sem prometer nada que o original não diga. No máximo um ou dois emojis, se combinar."
        case .professional:
            return "Reescreva com tom profissional e cordial, adequado para falar com um cliente, sem ficar rebuscado nem frio."
        case .friendly:
            return "Reescreva com tom simpático, próximo e descontraído, sem perder o respeito."
        case .shorter:
            return "Encurte o máximo possível mantendo toda a informação importante."
        }
    }

    var systemPrompt: String {
        """
        Você reescreve mensagens de WhatsApp. \(instruction)
        Regras:
        - Responda só com o texto final, sem aspas, sem comentários, sem opções alternativas.
        - Mantenha o mesmo idioma do original.
        - Preserve emojis que já existam, números, valores, links, e-mails e nomes próprios.
        - Não invente informação.
        """
    }
}

/// Janelinha do ⌥3: lista as ações; número, setas + ↩ ou clique escolhem, esc fecha.
final class ActionPicker: NSPanel {
    var onPick: ((TextAction) -> Void)?
    var onCancel: (() -> Void)?

    private var rows: [ActionRow] = []
    private var finished = true
    private let preview = NSTextField(labelWithString: "")
    private var selected = 0 { didSet { rows.enumerated().forEach { $0.element.highlighted = $0.offset == selected } } }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                   styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        contentView = bg

        preview.font = .systemFont(ofSize: 11)
        preview.textColor = .secondaryLabelColor
        preview.lineBreakMode = .byTruncatingTail
        preview.maximumNumberOfLines = 2
        preview.cell?.wraps = true
        preview.cell?.truncatesLastVisibleLine = true

        let stack = NSStackView(views: [preview])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.setCustomSpacing(8, after: preview)
        for (i, action) in TextAction.allCases.enumerated() {
            let row = ActionRow(action: action, number: i + 1)
            row.onClick = { [weak self] in self?.pick(i) }
            row.onHover = { [weak self] in self?.selected = i }
            rows.append(row)
            stack.addArrangedSubview(row)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -10),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
            bg.widthAnchor.constraint(equalToConstant: 300),
        ])
        preview.preferredMaxLayoutWidth = 272
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6).isActive = true
        rows.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        setContentSize(bg.fittingSize)
    }

    override var canBecomeKey: Bool { true }

    func present(text: String, translateTo lang: Language) {
        preview.stringValue = text.replacingOccurrences(of: "\n", with: " ")
        rows.first?.subtitle = lang.name
        selected = 0
        finished = false
        setContentSize(contentView!.fittingSize)
        if let f = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - f.height * 0.18))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    private func pick(_ i: Int) {
        guard !finished else { return }
        finished = true
        orderOut(nil)
        onPick?(TextAction.allCases[i])
    }

    override func keyDown(with event: NSEvent) {
        if let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...rows.count).contains(n) { pick(n - 1); return }
        switch Int(event.keyCode) {
        case 125: selected = (selected + 1) % rows.count            // ↓
        case 126: selected = (selected - 1 + rows.count) % rows.count // ↑
        case 36, 76: pick(selected)                                  // ↩
        case 53: cancelOperation(nil)                                // esc
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        guard !finished else { return }
        finished = true
        orderOut(nil)
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        // Clicou fora: fecha sem fazer nada.
        if isVisible { cancelOperation(nil) }
    }
}

private final class ActionRow: NSView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var highlighted = false { didSet { updateColors() } }
    var subtitle: String? { didSet { detail.stringValue = subtitle ?? "" } }

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let key = NSTextField(labelWithString: "")

    init(action: TextAction, number: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        icon.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        label.stringValue = action.title
        label.font = .systemFont(ofSize: 13)
        detail.font = .systemFont(ofSize: 11)
        key.stringValue = "\(number)"
        key.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        let h = NSStackView(views: [icon, label, detail, NSView(), key])
        h.orientation = .horizontal
        h.spacing = 8
        h.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 10)
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: leadingAnchor), h.trailingAnchor.constraint(equalTo: trailingAnchor),
            h.topAnchor.constraint(equalTo: topAnchor), h.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateColors() {
        layer?.backgroundColor = highlighted ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        let fg: NSColor = highlighted ? .white : .labelColor
        label.textColor = fg
        icon.contentTintColor = highlighted ? .white : .secondaryLabelColor
        detail.textColor = highlighted ? .white.withAlphaComponent(0.8) : .tertiaryLabelColor
        key.textColor = highlighted ? .white.withAlphaComponent(0.8) : .tertiaryLabelColor
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
