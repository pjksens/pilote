// Image d'en-tête du README, une par langue : `swift scripts/entete.swift` (depuis la racine du dépôt).
// Lit docs/media/logo.png (sinon l'icône de l'app) et docs/captures/01-aujourdhui.png ; écrit docs/media/hero.png
// (anglais) et docs/media/hero.<langue>.png. Pour changer le logo : remplacer docs/media/logo.png et relancer.
import AppKit

struct Texte { let accroche: String; let pastilles: [String] }

let textes: [(String, Texte)] = [
    ("en", Texte(accroche: "Your clients, your projects and your Claude Code team, on one screen.",
                 pastilles: ["Native Mac app", "Works with Claude Code", "Your data stays on your Mac", "Open source"])),
    ("fr", Texte(accroche: "Vos clients, vos projets et votre équipe Claude Code, sur un seul écran.",
                 pastilles: ["App Mac native", "Branché sur Claude Code", "Vos données restent sur votre Mac", "Open source"])),
    ("es", Texte(accroche: "Tus clientes, tus proyectos y tu equipo de Claude Code, en una sola pantalla.",
                 pastilles: ["App nativa para Mac", "Funciona con Claude Code", "Tus datos se quedan en tu Mac", "Código abierto"])),
    ("pt-BR", Texte(accroche: "Seus clientes, seus projetos e sua equipe do Claude Code, em uma só tela.",
                    pastilles: ["App nativo para Mac", "Funciona com o Claude Code", "Seus dados ficam no seu Mac", "Código aberto"])),
    ("de", Texte(accroche: "Deine Kunden, deine Projekte und dein Claude-Code-Team auf einem Bildschirm.",
                 pastilles: ["Native Mac-App", "Arbeitet mit Claude Code", "Deine Daten bleiben auf deinem Mac", "Open Source"])),
    ("it", Texte(accroche: "I tuoi clienti, i tuoi progetti e il tuo team Claude Code, in un solo schermo.",
                 pastilles: ["App nativa per Mac", "Funziona con Claude Code", "I tuoi dati restano sul tuo Mac", "Open source"])),
    ("zh-CN", Texte(accroche: "你的客户、你的项目和你的 Claude Code 团队，尽在一屏。",
                    pastilles: ["原生 Mac 应用", "支持 Claude Code", "数据留在你的 Mac 上", "开源"])),
    // Retours à la ligne posés à la main : sinon « チーム » est coupé en deux.
    ("ja", Texte(accroche: "顧客、プロジェクト、\nClaude Code チームを\nひとつの画面に。",
                 pastilles: ["ネイティブ Mac アプリ", "Claude Code と連携", "データは Mac の中だけ", "オープンソース"])),
    ("ko", Texte(accroche: "고객, 프로젝트, Claude Code 팀을 한 화면에서.",
                 pastilles: ["네이티브 Mac 앱", "Claude Code와 연동", "데이터는 내 Mac에만", "오픈 소스"])),
]

let racine = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let media = racine.appendingPathComponent("docs/media")
try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
let logo = NSImage(contentsOf: media.appendingPathComponent("logo.png"))
    ?? NSImage(contentsOf: racine.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/icone-256@2x.png"))
guard let capture = NSImage(contentsOf: racine.appendingPathComponent("docs/captures/01-aujourdhui.png")) else {
    fatalError("docs/captures/01-aujourdhui.png manque : ./scripts/demo.sh --captures")
}

let L: CGFloat = 1400, H: CGFloat = 500, echelle: CGFloat = 2
let orange = NSColor(srgbRed: 0.76, green: 0.31, blue: 0.17, alpha: 1)

func dessiner(_ t: Texte) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(L * echelle), pixelsHigh: Int(H * echelle),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: L, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Fond sombre et chaud, une lueur orange derrière la capture.
    NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.08, blue: 0.07, alpha: 1),
               ending: NSColor(srgbRed: 0.05, green: 0.045, blue: 0.04, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: L, height: H), angle: -90)
    NSGradient(starting: orange.withAlphaComponent(0.42), ending: orange.withAlphaComponent(0))!
        .draw(fromCenter: NSPoint(x: 1010, y: 210), radius: 0, toCenter: NSPoint(x: 1010, y: 210), radius: 520, options: [])

    // La capture de l'accueil, coupée par le bas.
    let largeur: CGFloat = 720, hauteur = largeur * capture.size.height / capture.size.width
    let cadre = NSRect(x: 630, y: H - 70 - hauteur, width: largeur, height: hauteur)
    let ombre = NSShadow(); ombre.shadowColor = NSColor.black.withAlphaComponent(0.55); ombre.shadowBlurRadius = 40
    ombre.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState(); ombre.set()
    capture.draw(in: cadre, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // Logo et nom.
    if let logo { logo.draw(in: NSRect(x: 64, y: H - 92 - 104, width: 104, height: 104)) }
    let titre = NSAttributedString(string: "Pilote", attributes: [
        .font: NSFont.systemFont(ofSize: 92, weight: .bold), .foregroundColor: NSColor.white, .kern: -1.5])
    titre.draw(at: NSPoint(x: 182, y: H - 92 - 104 + 2))

    // Accroche.
    let para = NSMutableParagraphStyle(); para.lineSpacing = 4
    let accroche = NSAttributedString(string: t.accroche, attributes: [
        .font: NSFont.systemFont(ofSize: 29, weight: .medium),
        .foregroundColor: NSColor(white: 0.92, alpha: 1), .paragraphStyle: para])
    let zone = accroche.boundingRect(with: NSSize(width: 520, height: 200), options: [.usesLineFragmentOrigin])
    let hautAccroche = H - 222
    accroche.draw(with: NSRect(x: 70, y: hautAccroche - zone.height, width: 520, height: zone.height), options: [.usesLineFragmentOrigin])

    // Pastilles, sur une ou deux lignes.
    let police = NSFont.systemFont(ofSize: 17, weight: .medium)
    var x: CGFloat = 70, y = hautAccroche - zone.height - 34 - 34
    for p in t.pastilles {
        let s = NSAttributedString(string: p, attributes: [.font: police, .foregroundColor: NSColor(white: 0.86, alpha: 1)])
        let l = s.size().width + 30
        if x + l > 600 { x = 70; y -= 44 }
        let r = NSRect(x: x, y: y, width: l, height: 34)
        let forme = NSBezierPath(roundedRect: r, xRadius: 17, yRadius: 17)
        NSColor(white: 1, alpha: 0.08).setFill(); forme.fill()
        NSColor(white: 1, alpha: 0.14).setStroke(); forme.lineWidth = 1; forme.stroke()
        s.draw(at: NSPoint(x: x + 15, y: y + (34 - s.size().height) / 2))
        x += l + 10
    }
    return rep.representation(using: .png, properties: [:])
}

for (langue, t) in textes {
    let nom = langue == "en" ? "hero.png" : "hero.\(langue).png"
    guard let png = dessiner(t) else { fatalError("dessin impossible : \(langue)") }
    try png.write(to: media.appendingPathComponent(nom))
    print("docs/media/\(nom)")
}
