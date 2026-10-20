import AppKit

/// O que o ⌥3 sabe fazer com o texto do campo.
enum TextAction: String, CaseIterable {
    case fix, improve, humanize, marketing, translate, professional, friendly, shorter

    /// As cinco da primeira linha da barra; as outras ficam no ↓.
    static let main: [TextAction] = [.fix, .improve, .humanize, .marketing, .translate]
    static let more: [TextAction] = [.professional, .friendly, .shorter]

    var title: String {
        switch self {
        case .translate: return "Traduzir"
        case .fix: return "Corrigir"
        case .improve: return "Melhorar"
        case .humanize: return "Humanizar"
        case .marketing: return "Marketing"
        case .professional: return "Profissional"
        case .friendly: return "Simpático"
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

