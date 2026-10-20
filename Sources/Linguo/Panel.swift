import AppKit

/// Janela flutuante do ⌘3: escreve em português, vê a tradução ao vivo e ↩ cola no app de onde você veio.
final class TranslatorPanel: NSPanel, NSTextViewDelegate {
    var onLanguageChange: ((Language) -> Void)?

    private let input = NSTextView()
    private let output = NSTextView()
    private let status = NSTextField(labelWithString: "")
    private let placeholder = NSTextField(labelWithString: "Escreva em português ou cole a mensagem do cliente…")
    private let picker = NSPopUpButton()
    private var previousApp: NSRunningApplication?
    private var debounce: DispatchWorkItem?
    private var pending: Task<String, Error>?
    private var pendingText = ""

    var language: Language { Language.find(UserDefaults.standard.string(forKey: "language") ?? "es-ES") }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 540, height: 330),
                   styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        build()
    }

    // MARK: Layout

    private func build() {
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        contentView = bg

        let title = NSTextField(labelWithString: "Linguo")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        for lang in Language.all { picker.addItem(withTitle: lang.name) }
        picker.selectItem(withTitle: language.name)
        picker.controlSize = .small
        picker.target = self
        picker.action = #selector(pickLanguage)

        let header = NSStackView(views: [title, NSView(), picker])
        header.orientation = .horizontal

        styleText(input, editable: true)
        input.delegate = self
        placeholder.textColor = .placeholderTextColor
        placeholder.font = input.font
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        input.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 5),
            placeholder.topAnchor.constraint(equalTo: input.topAnchor, constant: 0),
        ])

        styleText(output, editable: false)
        output.textColor = .labelColor

        let inBox = box(input, height: 96)
        let outBox = box(output, height: 120)
        outBox.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        let hint = NSTextField(labelWithString: "↩ colar   ⌘↩ copiar   ⇧↩ nova linha   esc fechar")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        let footer = NSStackView(views: [status, NSView(), hint])
        footer.orientation = .horizontal

        let stack = NSStackView(views: [header, inBox, outBox, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -14),
        ])
        for v in [header, inBox, outBox, footer] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    private func styleText(_ tv: NSTextView, editable: Bool) {
        tv.isEditable = editable
        tv.isSelectable = true
        tv.isRichText = false
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 15)
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.allowsUndo = editable
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
    }

    private func box(_ tv: NSTextView, height: CGFloat) -> NSView {
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let wrap = NSView()
        wrap.wantsLayer = true
        wrap.layer?.cornerRadius = 10
        wrap.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        wrap.addSubview(scroll)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: height),
            scroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -8),
        ])
        return wrap
    }

    override var canBecomeKey: Bool { true }

    // MARK: Abrir e fechar

    func toggle() { isVisible ? dismiss() : present() }

    func present() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        picker.selectItem(withTitle: language.name)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - f.height * 0.18))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(input)
        input.selectAll(nil)
    }

    func dismiss() {
        orderOut(nil)
        previousApp?.activate()
    }

    func setLanguage(_ lang: Language) {
        picker.selectItem(withTitle: lang.name)
        retranslate()
    }

    @objc private func pickLanguage() {
        let lang = Language.all[picker.indexOfSelectedItem]
        UserDefaults.standard.set(lang.code, forKey: "language")
        onLanguageChange?(lang)
        retranslate()
    }

    // MARK: Tradução ao vivo

    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !input.string.isEmpty
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.retranslate() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func retranslate() {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        pending?.cancel()
        guard !text.isEmpty else { output.string = ""; status.stringValue = ""; return }
        let lang = language
        if let hit = Translator.shared.cached(text, lang, .auto) {
            output.string = hit
            status.stringValue = "do cache"
            pendingText = text
            pending = Task { hit }
            return
        }
        status.stringValue = "traduzindo…"
        pendingText = text
        pending = Task { [weak self] in
            do {
                let r = try await Translator.shared.translate(text, to: lang, direction: .auto) { partial in
                    DispatchQueue.main.async { self?.output.string = partial }
                }
                await MainActor.run { self?.output.string = r; self?.status.stringValue = "" }
                return r
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                await MainActor.run {
                    // Uma tradução antiga que falhou não pode sobrescrever o status da atual.
                    guard self?.pendingText == text else { return }
                    self?.status.stringValue = "Erro: \(error.localizedDescription)"
                }
                throw error
            }
        }
    }

    /// Espera a tradução do texto atual (reaproveita a que já está em andamento).
    private func finalTranslation() async -> String? {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        debounce?.cancel()
        if pendingText != text || pending == nil { retranslate() }
        return try? await pending?.value
    }

    private func deliver(paste: Bool) {
        Task { @MainActor in
            guard let result = await finalTranslation(), !result.isEmpty else { NSSound.beep(); return }
            ClipboardSnapshot.set(result)
            dismiss()
            input.string = ""
            output.string = ""
            placeholder.isHidden = false
            guard paste else { return }
            guard Keyboard.trusted else { Keyboard.askForAccess(); return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            Keyboard.paste()
        }
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        switch selector {
        case #selector(insertNewline(_:)):
            if flags.contains(.shift) { textView.insertNewlineIgnoringFieldEditor(nil); return true }
            deliver(paste: !flags.contains(.command))
            return true
        case #selector(cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
}
