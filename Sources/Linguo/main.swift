import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = TranslatorPanel()
    private let bar = RewriteBar()
    private var busy = false { didSet { refreshIcon() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshIcon()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        panel.onLanguageChange = { [weak self] _ in self?.refreshIcon() }

        // ⌘3 abre o painel; ⌃3 traduz o que está escrito no campo do WhatsApp, no lugar; ⌥3 abre as outras ações.
        HotKeys.shared.register(keyCode: kVK_ANSI_3, modifiers: cmdKey) { [weak self] in self?.panel.toggle() }
        HotKeys.shared.register(keyCode: kVK_ANSI_3, modifiers: controlKey) { [weak self] in self?.translateInPlace() }
        HotKeys.shared.register(keyCode: kVK_ANSI_3, modifiers: optionKey) { [weak self] in self?.showActions() }

        if KeyStore.apiKey == nil { DispatchQueue.main.async { self.askForKey(message: nil) } }
        if !Keyboard.trusted { Keyboard.askForAccess() }
    }

    private var language: Language { panel.language }

    private func refreshIcon() {
        item.button?.image = MenuIcon.make(code: language.code, busy: busy)
        item.button?.title = ""
    }

    // MARK: No campo do app (⌃3 traduz, ⌥3 abre as ações)

    /// Seleciona tudo no campo do app da frente e copia; devolve o texto e o clipboard antigo pra restaurar depois.
    @MainActor
    private func captureField() async -> (text: String, snapshot: ClipboardSnapshot)? {
        guard Keyboard.trusted else { Keyboard.askForAccess(); return nil }
        let pb = NSPasteboard.general
        let snapshot = ClipboardSnapshot()
        let before = pb.changeCount
        Keyboard.selectAll()
        try? await Task.sleep(nanoseconds: 60_000_000)
        Keyboard.copy()
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard pb.changeCount != before, let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            snapshot.restore(); NSSound.beep(); return nil
        }
        return (text, snapshot)
    }

    /// Roda o pedido e troca o texto do campo pelo resultado.
    @MainActor
    private func replaceField(_ snapshot: ClipboardSnapshot, reselect: Bool,
                              _ work: @escaping () async throws -> String) async {
        busy = true
        defer { busy = false }
        do {
            let result = try await work()
            ClipboardSnapshot.set(result)
            if reselect {
                Keyboard.selectAll()
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            Keyboard.paste()
            try? await Task.sleep(nanoseconds: 400_000_000)
            snapshot.restore()
        } catch {
            snapshot.restore()
            if !(error is CancellationError) { notify(error.localizedDescription) }
        }
    }

    private func translateInPlace() {
        guard !busy else { return }
        let lang = language
        Task { @MainActor in
            guard let (text, snapshot) = await captureField() else { return }
            await replaceField(snapshot, reselect: false) {
                try await Translator.shared.translate(text, to: lang, direction: .outgoing)
            }
        }
    }

    private func showActions() {
        guard !busy, !bar.isVisible else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let lang = language
        // Pega a posição do campo antes de o Linguo vir pra frente.
        let anchor = focusedFieldFrame()
        Task { @MainActor in
            guard let (text, snapshot) = await captureField() else { return }
            bar.onCancel = {
                snapshot.restore()
                front?.activate()
            }
            bar.onApply = { [weak self] result in
                front?.activate()
                Task { @MainActor in
                    // Espera o app voltar pra frente antes de colar.
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    await self?.replaceField(snapshot, reselect: true) { result }
                }
            }
            bar.present(text: text, language: lang, anchor: anchor)
        }
    }

    private func notify(_ message: String) {
        NSSound.beep()
        let alert = NSAlert()
        alert.messageText = "Linguo"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "Traduzir para", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for lang in Language.all {
            let mi = NSMenuItem(title: lang.name, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = lang.code
            mi.state = lang == language ? .on : .off
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        add(menu, "Abrir tradutor  (⌘3)", #selector(openPanel))
        add(menu, "Traduzir campo do WhatsApp  (⌃3)", #selector(inPlaceFromMenu))
        add(menu, "Corrigir, melhorar, humanizar…  (⌥3)", #selector(actionsFromMenu))
        menu.addItem(.separator())
        if !Keyboard.trusted { add(menu, "Permitir Acessibilidade (pra colar sozinho)…", #selector(askAccess)) }
        add(menu, KeyStore.apiKey == nil ? "Definir chave da OpenAI…" : "Trocar chave da OpenAI…", #selector(askForKeyFromMenu))
        add(menu, "Limpar traduções guardadas", #selector(clearCache))
        let login = add(menu, "Abrir ao iniciar o Mac", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(menu, "Sair", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = target ?? self
        menu.addItem(mi)
        return mi
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        UserDefaults.standard.set(code, forKey: "language")
        panel.setLanguage(Language.find(code))
        refreshIcon()
    }

    @objc private func openPanel() { panel.present() }
    @objc private func inPlaceFromMenu() {
        // Dá tempo do menu fechar e o foco voltar pro WhatsApp.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.translateInPlace() }
    }
    @objc private func actionsFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showActions() }
    }
    @objc private func askAccess() { Keyboard.askForAccess() }
    @objc private func clearCache() { Translator.shared.clearCache() }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do { svc.status == .enabled ? try svc.unregister() : try svc.register() }
        catch { notify("Não deu pra mudar: \(error.localizedDescription)") }
    }

    @objc private func askForKeyFromMenu() { askForKey(message: nil) }

    /// Cada pessoa usa a própria chave da OpenAI; ela é testada antes de salvar.
    private func askForKey(message: String?) {
        let alert = NSAlert()
        alert.messageText = "Sua chave da OpenAI"
        alert.informativeText = message ?? """
        O Linguo traduz com o \(Translator.model) usando a sua conta da OpenAI. \
        Crie uma chave em platform.openai.com/api-keys e cole aqui. Ela fica guardada só neste Mac.
        """
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = "sk-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Criar chave na OpenAI")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            let previous = KeyStore.apiKey
            KeyStore.apiKey = key
            Task { @MainActor in
                do {
                    _ = try await Translator.shared.check()
                } catch {
                    KeyStore.apiKey = previous
                    askForKey(message: "Essa chave não funcionou: \(error.localizedDescription)")
                }
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://platform.openai.com/api-keys")!)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.askForKey(message: nil) }
        default:
            break
        }
    }
}

/// Menu Editar invisível: sem ele, ⌘V, ⌘C, ⌘A e ⌘Z não funcionam nos campos do painel.
func editMenu() -> NSMenu {
    let main = NSMenu()
    let edit = NSMenu(title: "Editar")
    edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Selecionar tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let item = NSMenuItem()
    item.submenu = edit
    main.addItem(item)
    return main
}

let app = NSApplication.shared
app.mainMenu = editMenu()
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
