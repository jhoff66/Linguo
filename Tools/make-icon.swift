// Desenha o ícone do app (dois balões de conversa, "A" e "Ñ", sobre base índigo) e grava um PNG de 1024 px.
// Uso: swiftc Tools/make-icon.swift -o build/make-icon && build/make-icon saida.png
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: space, components: [r, g, b, a])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
  CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

/// Balão arredondado com a ponta num dos cantos de baixo.
func bubble(_ r: CGRect, tailLeft: Bool) -> CGPath {
  let p = CGMutablePath()
  // Espelha a ponta quando ela fica do lado direito.
  func pt(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
    CGPoint(x: tailLeft ? r.minX + dx : r.maxX - dx, y: r.minY + dy)
  }
  p.move(to: pt(40, 70))
  p.addQuadCurve(to: pt(10, -70), control: pt(45, -10))
  p.addQuadCurve(to: pt(150, 2), control: pt(80, -30))
  p.addLine(to: pt(150, 70))
  p.closeSubpath()
  // União em vez de soma de caminhos: espelhada, a ponta inverte o sentido e abriria um buraco no balão.
  return CGPath(roundedRect: r, cornerWidth: 120, cornerHeight: 120, transform: nil).union(p)
}

func letter(_ s: String, center: CGPoint, size: CGFloat, color c: NSColor) {
  let font = NSFont.systemFont(ofSize: size, weight: .heavy)
  let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c])
  let line = CTLineCreateWithAttributedString(str)
  let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
  ctx.textPosition = CGPoint(x: center.x - b.midX, y: center.y - b.midY)
  CTLineDraw(line, ctx)
}

// Base no formato dos ícones do macOS: 824 px centrados, cantos contínuos.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient([color(0.36, 0.33, 0.95), color(0.16, 0.12, 0.50)], [0, 1]),
                       start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Balão de trás: o português, branco translúcido.
let back = CGRect(x: 190, y: 470, width: 400, height: 330)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0, 0, 0, 0.30))
ctx.addPath(bubble(back, tailLeft: true))
ctx.setFillColor(color(1, 1, 1, 0.92))
ctx.fillPath()
ctx.restoreGState()
letter("A", center: CGPoint(x: back.midX, y: back.midY + 4), size: 220, color: NSColor(red: 0.24, green: 0.20, blue: 0.70, alpha: 1))

// Balão da frente: a tradução, em laranja quente.
let front = CGRect(x: 420, y: 230, width: 420, height: 350)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 50, color: color(0.05, 0.02, 0.2, 0.55))
ctx.addPath(bubble(front, tailLeft: false))
ctx.clip()
ctx.drawLinearGradient(gradient([color(1.0, 0.66, 0.32), color(0.97, 0.38, 0.30)], [0, 1]),
                       start: CGPoint(x: front.minX, y: front.maxY), end: CGPoint(x: front.maxX, y: front.minY - 80), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()
letter("Ñ", center: CGPoint(x: front.midX, y: front.midY + 4), size: 230, color: .white)
ctx.restoreGState()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
