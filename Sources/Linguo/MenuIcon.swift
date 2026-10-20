import AppKit

/// Ícone da barra de menu: os dois balões do ícone do app, com a sigla do idioma escolhido vazada no balão da frente.
/// É template, então o macOS pinta de preto ou branco conforme o tema da barra.
enum MenuIcon {
    static func make(code: String, busy: Bool) -> NSImage {
        let label = busy ? "…" : String(code.prefix(2)).uppercased()
        let font = NSFont.systemFont(ofSize: 7.5, weight: .heavy)
        let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
        let frontWidth = max(14, textWidth + 6)
        let size = NSSize(width: 7 + frontWidth + 0.5, height: 18)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Balão de trás: só o contorno, com a ponta embaixo à esquerda.
            let back = bubble(NSRect(x: 0.75, y: 6.6, width: 12.5, height: 9.5), radius: 3.2, tailLeft: true)
            NSColor.black.setStroke()
            back.lineWidth = 1.4
            back.stroke()

            // Abre um respiro em volta do balão da frente, pra ele descolar do de trás.
            let frontRect = NSRect(x: 7, y: 2.8, width: frontWidth, height: 10.5)
            ctx.setBlendMode(.clear)
            let gap = bubble(frontRect, radius: 3.6, tailLeft: false)
            gap.lineWidth = 2.4
            gap.stroke()
            gap.fill()
            ctx.setBlendMode(.normal)

            // Balão da frente cheio, com a sigla recortada.
            NSColor.black.setFill()
            bubble(frontRect, radius: 3.6, tailLeft: false).fill()
            ctx.setBlendMode(.destinationOut)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .kern: 0.2]
            let textSize = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(at: NSPoint(x: frontRect.midX - textSize.width / 2,
                                                 y: frontRect.midY - textSize.height / 2 + 0.3),
                                     withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Linguo, traduzindo para \(code)"
        return image
    }

    /// Balão com a ponta num canto de baixo, como uma forma só (a união evita o traço do retângulo atravessando a ponta).
    private static func bubble(_ r: NSRect, radius: CGFloat, tailLeft: Bool) -> NSBezierPath {
        let base = tailLeft ? r.minX + 2.5 : r.maxX - 2.5
        let dir: CGFloat = tailLeft ? 1 : -1
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: base, y: r.minY + 1.5))
        tail.addLine(to: CGPoint(x: base - dir * 1.2, y: r.minY - 2.6))
        tail.addLine(to: CGPoint(x: base + dir * 3.5, y: r.minY + 0.2))
        tail.closeSubpath()
        let body = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        return NSBezierPath(cgPath: body.union(tail))
    }
}
