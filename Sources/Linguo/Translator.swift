import Foundation

struct Language: Hashable {
    let code: String
    let name: String
    let prompt: String

    static let all: [Language] = [
        Language(code: "es-ES", name: "Espanhol (Espanha)", prompt: "espanhol da Espanha, com vocabulário e expressões de quem é de lá"),
        Language(code: "es-419", name: "Espanhol (América Latina)", prompt: "espanhol latino-americano neutro"),
        Language(code: "en-US", name: "Inglês", prompt: "inglês americano"),
        Language(code: "fr-FR", name: "Francês", prompt: "francês da França"),
        Language(code: "it-IT", name: "Italiano", prompt: "italiano"),
        Language(code: "de-DE", name: "Alemão", prompt: "alemão"),
    ]

    static func find(_ code: String) -> Language { all.first { $0.code == code } ?? all[0] }
}

enum Direction {
    /// Português → idioma do contato (o que você escreve).
    case outgoing
    /// Qualquer idioma → português, ou o contrário se o texto já estiver em português (painel).
    case auto
}

enum TranslatorError: LocalizedError {
    case noKey, http(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "Coloque sua chave da OpenAI no menu do Linguo."
        case .http(let m): return m
        }
    }
}

/// Fala com a OpenAI e guarda as traduções já feitas, pra mesma frase não custar duas vezes.
final class Translator {
    static let shared = Translator()
    static let model = "gpt-6-luna"

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linguo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }()
    private var cache: [String: String] = [:]
    private var order: [String] = []
    private let cacheLimit = 1000
    private let lock = NSLock()

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([[String]].self, from: data) {
            for pair in saved where pair.count == 2 {
                cache[pair[0]] = pair[1]
                order.append(pair[0])
            }
        }
    }

    // O prompt de sistema fica idêntico entre chamadas do mesmo idioma: é o prefixo que o cache da OpenAI reaproveita.
    private func systemPrompt(_ lang: Language, _ dir: Direction) -> String {
        let rules = """
        Regras:
        - Responda só com a tradução, sem aspas, sem comentários, sem explicar nada.
        - É uma conversa de WhatsApp com um cliente: mantenha o tom do original (informal continua informal, educado continua educado).
        - Soe natural para um nativo, nunca como tradução literal.
        - Preserve emojis, quebras de linha, números, valores, links, e-mails e nomes próprios.
        - Não acrescente nem remova informação.
        """
        switch dir {
        case .outgoing:
            return "Você é um tradutor. Traduza a mensagem do usuário, escrita em português do Brasil, para \(lang.prompt).\n\(rules)"
        case .auto:
            return "Você é um tradutor. Se a mensagem do usuário estiver em português, traduza para \(lang.prompt). Se estiver em qualquer outro idioma, traduza para português do Brasil.\n\(rules)"
        }
    }

    private func cacheKey(_ text: String, _ lang: Language, _ dir: Direction) -> String {
        "\(lang.code)|\(dir == .outgoing ? "out" : "auto")|\(text)"
    }

    func cached(_ text: String, _ lang: Language, _ dir: Direction) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[cacheKey(text, lang, dir)]
    }

    private func store(_ text: String, _ lang: Language, _ dir: Direction, _ result: String) {
        lock.lock()
        let key = cacheKey(text, lang, dir)
        if cache[key] == nil { order.append(key) }
        cache[key] = result
        while order.count > cacheLimit { cache.removeValue(forKey: order.removeFirst()) }
        let snapshot = order.compactMap { k in cache[k].map { [k, $0] } }
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: cacheURL, options: .atomic) }
    }

    func clearCache() {
        lock.lock(); cache = [:]; order = []; lock.unlock()
        try? FileManager.default.removeItem(at: cacheURL)
    }

    /// Faz uma chamada mínima pra confirmar que a chave e o modelo funcionam (sem passar pelo cache).
    func check() async throws -> String {
        try await translate("oi \(UUID().uuidString.prefix(4))", to: Language.all[0], direction: .outgoing)
    }

    /// Traduz com streaming; `onPartial` recebe o texto acumulado a cada pedaço.
    func translate(_ text: String, to lang: Language, direction: Direction,
                   onPartial: ((String) -> Void)? = nil) async throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if let hit = cached(text, lang, direction) { return hit }
        guard let key = KeyStore.apiKey, !key.isEmpty else { throw TranslatorError.noKey }

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": Self.model,
            "reasoning_effort": "none",
            "stream": true,
            "prompt_cache_key": "linguo-\(lang.code)-\(direction == .outgoing ? "out" : "auto")",
            "messages": [
                ["role": "system", "content": systemPrompt(lang, direction)],
                ["role": "user", "content": text],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Conexão nova por tentativa: depois de VPN ou do Mac dormir, a conexão reaproveitada costuma vir morta.
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await stream(req, text, lang, direction, onPartial)
            } catch let e as URLError where e.code != .cancelled && attempt < 3 {
                Log.write("tentativa \(attempt) falhou: \(e.code.rawValue) \(e.localizedDescription)")
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch let e as URLError where e.code == .cancelled {
                throw CancellationError()
            } catch {
                if !(error is CancellationError) { Log.write("erro: \(error)") }
                throw error
            }
        }
    }

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.waitsForConnectivity = true
        c.timeoutIntervalForRequest = 30
        c.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: c)
    }()

    private func stream(_ req: URLRequest, _ text: String, _ lang: Language, _ direction: Direction,
                        _ onPartial: ((String) -> Void)?) async throws -> String {
        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            let msg = (try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw TranslatorError.http(msg ?? "OpenAI respondeu \(http.statusCode)")
        }

        var out = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst(6)
            if payload == "[DONE]" { break }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                  let delta = ((obj["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String
            else { continue }
            out += delta
            onPartial?(out)
        }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { store(text, lang, direction, out) }
        return out
    }
}

/// Erros de rede vão pra ~/Library/Logs/Linguo.log, pra dar pra investigar depois.
enum Log {
    static func write(_ msg: String) {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Linguo.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}

/// Chave da OpenAI num arquivo só seu (permissão 600) em Application Support.
/// Saiu do Keychain porque ele pedia a senha do Mac a cada build novo.
enum KeyStore {
    private static let url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Linguo/openai.key")

    static var apiKey: String? {
        get {
            let v = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (v?.isEmpty ?? true) ? nil : v
        }
        set {
            guard let v = newValue, !v.isEmpty else { try? FileManager.default.removeItem(at: url); return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data(v.utf8), attributes: [.posixPermissions: 0o600])
        }
    }
}
