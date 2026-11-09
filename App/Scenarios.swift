// Démos animées du README. PILOTE_DEMO=1, PILOTE_SCENARIO=suivi|facteur|claude et PILOTE_CAPTURES=<dossier> :
// l'app joue le scénario dans sa propre fenêtre (vrais clics envoyés à la fenêtre, curseur dessiné sur l'image),
// photographie sa fenêtre une dizaine de fois par seconde dans <dossier>/<scénario>/, écrit images.txt (la liste
// pour ffmpeg, avec la durée de chaque image), puis se ferme. scripts/demo.sh --gif en fait des GIF.
// Mode démo seulement : base et fichiers fictifs, aucune permission demandée, rien ne sort de l'app.
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Repères : les vues visées par les scénarios

/// Les vues que les démos animées visent portent `.repere("nom")`. En scénario seulement, une vue AppKit invisible et
/// transparente aux clics se glisse derrière elles : le scénario lit son cadre exact dans la fenêtre (l'arbre
/// d'accessibilité de SwiftUI, lui, ne se construit pas toujours sans lecteur d'écran). Hors scénario : aucun effet.
@MainActor
enum Reperes {
    fileprivate struct Faible { weak var vue: NSView? }
    fileprivate static var table: [String: [Faible]] = [:]

    fileprivate static func noter(_ nom: String, _ v: NSView) {
        for (cle, l) in table { table[cle] = l.filter { $0.vue != nil && $0.vue !== v } }   // une vue réutilisée change de nom
        table[nom, default: []].append(Faible(vue: v))
    }

    /// Les vues de ce nom (« geste:* » : tous les noms qui commencent par « geste: ») dans la fenêtre, affichées, de haut en
    /// bas puis de gauche à droite (rangées par leur cadre entier : une vue sortie du défilement garde sa place).
    static func vues(_ nom: String, dans f: NSWindow) -> [NSView] {
        func place(_ v: NSView) -> CGRect { v.convert(v.bounds, to: nil) }
        let cles = nom.hasSuffix("*") ? table.keys.filter { $0.hasPrefix(String(nom.dropLast())) } : [nom]
        return cles.flatMap { table[$0] ?? [] }.compactMap(\.vue)
            .filter { $0.window === f && !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 2 && $0.bounds.height > 2 }
            .sorted { a, b in
                let p = place(a), q = place(b)
                return p.maxY == q.maxY ? p.minX < q.minX : p.maxY > q.maxY   // origine en bas : plus haut = maxY plus grand
            }
    }

    /// La partie visible de la vue, en points de la fenêtre depuis le coin haut gauche (barre de titre comprise) ;
    /// nil si on n'en voit presque rien.
    static func cadre(_ v: NSView, _ f: NSWindow) -> CGRect? {
        // visibleRect déborde de la vue quand ses parents ne coupent pas leurs bords (clipsToBounds faux depuis macOS 14) :
        // on le ramène à la vue elle-même.
        let vis = v.visibleRect.intersection(v.bounds)
        guard !vis.isNull, vis.width > 4, vis.height > 4 else { return nil }
        let r = v.convert(vis, to: nil)
        return CGRect(x: r.minX, y: f.frame.height - r.maxY, width: r.width, height: r.height)
    }
}

private final class VueRepere: NSView {
    var nom = ""
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // les clics passent à la vraie vue
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { Reperes.noter(nom, self) }
    }
}

private struct Repere: NSViewRepresentable {
    let nom: String
    func makeNSView(context: Context) -> VueRepere {
        let v = VueRepere()
        v.nom = nom
        return v
    }
    func updateNSView(_ v: VueRepere, context: Context) {
        guard v.nom != nom else { return }
        v.nom = nom
        if v.window != nil { Reperes.noter(nom, v) }
    }
}

extension View {
    /// Une cible des démos animées (App/Scenarios.swift). Sans effet hors scénario.
    @ViewBuilder func repere(_ nom: String) -> some View {
        if Scenario.actif { background { Repere(nom: nom) } } else { self }
    }
}

// MARK: - Scénario

@MainActor
final class Scenario {
    /// Un scénario est joué (PILOTE_DEMO=1 et PILOTE_SCENARIO) : repères posés, délai d'annulation raccourci.
    nonisolated static let actif = Demo.actif && !(ProcessInfo.processInfo.environment["PILOTE_SCENARIO"] ?? "").isEmpty

    enum Cible {
        /// La n-ième vue (0 = la première, de haut en bas) qui porte ce repère (`.repere("nom")`).
        case repere(String, rang: Int = 0)
        /// Le n-ième élément (0 = le premier, de haut en bas) dont le libellé contient ce texte.
        case texte(String, rang: Int = 0)
        /// Le n-ième élément dont le libellé est exactement ce texte.
        case exact(String, rang: Int = 0)
        /// Un point de la fenêtre, en points, depuis le coin haut gauche.
        case point(CGFloat, CGFloat)
    }

    private let fenetre: NSWindow
    private let dossier: URL
    private var curseur: CGPoint
    private var appui: CGFloat = 0
    private var images: [(nom: String, le: TimeInterval)] = []
    private var occupe = false
    private var minuterie: Timer?
    private let file = DispatchQueue(label: "pilote.scenario.images")
    private let echelle: CGFloat = 1   // images à 1 point = 1 pixel (1280 de large) ; le GIF est réduit ensuite

    /// Le fond posé sous chaque image : les coins arrondis de la fenêtre ne restent pas transparents (un GIF les rendrait
    /// d'une couleur au hasard de sa palette).
    private let fond: CGColor

    private init(fenetre: NSWindow, dossier: URL) {
        self.fenetre = fenetre
        self.dossier = dossier
        curseur = CGPoint(x: fenetre.frame.width * 0.62, y: fenetre.frame.height * 0.72)
        var c = CGColor(gray: 0.93, alpha: 1)
        fenetre.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let s = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) { c = s.cgColor }
        }
        fond = c
    }

    static let noms = ["suivi", "facteur", "claude"]

    /// Délai pour annuler un geste de la page Aujourd'hui (EcranUnique.differer) : 5 s, 1,5 s pendant un scénario.
    nonisolated static var annulation: Double { actif ? 1.5 : 5 }

    /// Joue le scénario `nom` et filme. La fenêtre doit être prête (base lue).
    static func jouer(_ nom: String, etat: Etat, dans racine: URL) async {
        guard noms.contains(nom), let f = Captures.fenetre else { return }
        let dossier = racine.appendingPathComponent(nom)
        try? FileManager.default.removeItem(at: dossier)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        // Fenêtre clé : un clic dans un champ lui donne le focus, la frappe y arrive.
        NSApp.activate(ignoringOtherApps: true)
        f.makeKeyAndOrderFront(nil)
        let s = Scenario(fenetre: f, dossier: dossier)
        switch nom {
        case "suivi": await s.suivi(etat)
        case "facteur": await s.facteur(etat)
        default: await s.claude(etat)
        }
    }

    // MARK: - Les trois scénarios

    /// Suivi client avec contexte : le tableau des prospects, puis la fiche d'un contact (fil des échanges, prochaine action).
    private func suivi(_ etat: Etat) async {
        etat.ecran = .prospects
        await pause(1.5)
        filmer()
        await pause(1.0)
        await aller(.repere("prospect:Paul Durand"))
        await cliquer()
        await pause(2.5)
        await aller(.repere("fiche"))
        await defiler(260)
        await pause(2.0)
        await aller(.repere("prospect:Sophie Martin"))
        await cliquer()
        await pause(3.0)
        await finir()
    }

    /// Le Facteur : une session Claude Code pose une question, la réponse part d'un clic et lui est remise.
    private func facteur(_ etat: Etat) async {
        etat.ecran = .aujourdhui
        await pause(1.5)
        filmer()
        await pause(1.2)
        await aller(.repere("choix:SMS"))
        await cliquer()
        // « Choix noté : SMS · Annuler », puis la réponse attend son envoi sur la ligne « Envoyer ».
        await pause(Self.annulation + 1.0)
        await aller(.repere("geste:Envoyer"))
        await cliquer()
        await pause(Self.annulation + 0.8)
        // En vrai, le Facteur (scripts/facteur.py) remet la réponse en quelques secondes ; la démo la marque remise.
        let rangs = etat.decisionsEnvoyees.map(\.id)
        if rangs.isEmpty { manque("réponse envoyée (decisionsEnvoyees vide)") }
        try? Facteur.noter(rangs, etat: .remis)
        etat.relireDecisions()
        await pause(3.0)
        await finir()
    }

    /// Claude Code : ce que font les sessions (pyramide, journal), puis écrire à la session d'un domaine.
    private func claude(_ etat: Etat) async {
        etat.ecran = .claude
        await pause(1.5)
        filmer()
        await pause(1.8)
        await defiler(300)
        await pause(1.4)
        etat.ecran = .aujourdhui
        await pause(1.2)
        await aller(.repere("domaine:app"))
        await cliquer()
        await pause(1.2)
        await aller(.repere("ecrire:app"))
        await cliquer()
        await pause(0.8)
        await aller(.repere("champ:app"))
        await cliquer()
        await pause(0.4)
        await taper("Ajoute le mode sombre à la page Réglages, puis montre-moi la capture.")
        await pause(0.8)
        await aller(.repere("envoyer:app"))
        await cliquer()
        await pause(2.5)
        await finir()
    }

    // MARK: - Gestes

    private func pause(_ secondes: Double) async { try? await Task.sleep(for: .milliseconds(Int(secondes * 1000))) }

    /// Déplace le curseur vers la cible (0,7 s, accélère puis freine). Un repère hors de la zone visible est d'abord
    /// amené à l'écran en faisant défiler sa zone.
    private func aller(_ cible: Cible) async {
        if case let .repere(nom, rang) = cible {
            let l = Reperes.vues(nom, dans: fenetre)
            guard rang < l.count else { return manque(nom) }
            if await amener(l[rang]) { await pause(0.3) }
            let v = l[rang]
            var chaine: [String] = [], s = v.superview
            while let x = s, chaine.count < 5 { chaine.append(String(describing: type(of: x))); s = x.superview }
            noter("\(nom) : \(l.count) vue(s), bounds \(v.bounds), visible \(v.visibleRect), fenêtre \(v.convert(v.bounds, to: nil)), "
                  + "cadre \(Reperes.cadre(v, fenetre).map { "\($0)" } ?? "nil"), parents \(chaine.joined(separator: " < "))")
        }
        guard let but = point(cible) else { return }
        let depart = curseur, pas = 42
        for i in 1...pas {
            let t = Double(i) / Double(pas)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            curseur = CGPoint(x: depart.x + (but.x - depart.x) * e, y: depart.y + (but.y - depart.y) * e)
            await pause(0.7 / Double(pas))
        }
    }

    private func cliquer() async {
        let loc = NSPoint(x: curseur.x, y: fenetre.frame.height - curseur.y)
        appui = 1
        func evenement(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: loc, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: fenetre.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                               pressure: type == .leftMouseDown ? 1 : 0)
        }
        // Le relâchement part d'abord dans la file : un champ de texte suit la souris dans sa propre boucle jusqu'à lui
        // (sinon sendEvent ne rend jamais la main). Une vue sans boucle le reçoit au tour suivant, comme un vrai clic.
        guard let bas = evenement(.leftMouseDown), let haut = evenement(.leftMouseUp) else { return }
        NSApp.postEvent(haut, atStart: false)
        fenetre.sendEvent(bas)
        await pause(0.18)
        for _ in 0..<8 { appui = max(0, appui - 0.125); await pause(0.04) }
        appui = 0
    }

    /// Tape le texte dans le champ qui a le focus, lettre par lettre. Si le clic n'a pas donné le focus, le donne au champ
    /// sous le curseur.
    private func taper(_ texte: String) async {
        if !(fenetre.firstResponder is NSTextView), let cv = fenetre.contentView {
            var v = cv.hitTest(cv.convert(NSPoint(x: curseur.x, y: fenetre.frame.height - curseur.y), from: nil))
            while let x = v, !(x is NSTextField), !(x is NSTextView) { v = x.superview }
            if let v { fenetre.makeFirstResponder(v) }
        }
        guard let champ = fenetre.firstResponder as? NSTextView else { return manque("champ de saisie (focus)") }
        for c in texte {
            champ.insertText(String(c), replacementRange: NSRange(location: NSNotFound, length: 0))
            await pause(c == " " ? 0.07 : 0.045)
        }
    }

    /// Fait défiler en douceur la zone qui contient la vue jusqu'à la montrer entière (marge de 40 points) ; false si elle
    /// était déjà à l'écran ou hors de toute zone qui défile.
    private func amener(_ v: NSView) async -> Bool {
        var s = v.enclosingScrollView
        var deplacements: [(NSClipView, NSScrollView, CGPoint, CGPoint)] = []
        while let defilante = s, let doc = defilante.documentView {
            let clip = defilante.contentView
            let vu = clip.documentVisibleRect, r = v.convert(v.bounds, to: doc), marge: CGFloat = 40
            func axe(_ debut: CGFloat, _ taille: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ total: CGFloat) -> CGFloat {
                var o = debut
                if hi > o + taille { o = hi + marge - taille }
                if lo < o { o = lo - marge }
                return Swift.max(0, Swift.min(o, Swift.max(0, total - taille)))
            }
            let cible = CGPoint(x: axe(vu.minX, vu.width, r.minX, r.maxX, doc.frame.width),
                                y: axe(vu.minY, vu.height, r.minY, r.maxY, doc.frame.height))
            if abs(cible.x - vu.minX) > 1 || abs(cible.y - vu.minY) > 1 {
                deplacements.append((clip, defilante, clip.bounds.origin, cible))
            }
            s = defilante.enclosingScrollView
        }
        guard !deplacements.isEmpty else { return false }
        let pas = 30
        for i in 1...pas {
            let t = Double(i) / Double(pas)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            for (clip, defilante, a, b) in deplacements {
                clip.setBoundsOrigin(NSPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e))
                defilante.reflectScrolledClipView(clip)
            }
            await pause(0.8 / Double(pas))
        }
        return true
    }

    /// Une cible manquée : dans le journal et dans <dossier>/manques.txt (scripts/demo.sh --gif l'affiche).
    private func manque(_ quoi: String) {
        NSLog("Scénario : « \(quoi) » introuvable")
        ajouter(quoi, a: "manques.txt")
    }

    /// Où le scénario a visé (cadres des repères) : <dossier>/journal.txt, pour comprendre un clic à côté.
    private func noter(_ ligne: String) { ajouter(ligne, a: "journal.txt") }

    private func ajouter(_ texte: String, a fichier: String) {
        let url = dossier.appendingPathComponent(fichier)
        let ligne = Data("\(texte)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(ligne); try? h.close()
        } else {
            try? ligne.write(to: url)
        }
    }

    /// Fait défiler la zone sous le curseur de `points` vers le bas (en douceur).
    private func defiler(_ points: CGFloat) async {
        let loc = NSPoint(x: curseur.x, y: fenetre.frame.height - curseur.y)
        guard let vue = fenetre.contentView?.hitTest(fenetre.contentView!.convert(loc, from: nil)),
              let defilante = Self.defilante(vue) else { return }
        let clip = defilante.contentView
        let debut = clip.bounds.origin.y
        let max = (defilante.documentView?.frame.height ?? 0) - clip.bounds.height
        let fin = Swift.max(0, Swift.min(max, debut + (defilante.documentView?.isFlipped == false ? -points : points)))
        let pas = 30
        for i in 1...pas {
            let t = Double(i) / Double(pas)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: debut + (fin - debut) * e))
            defilante.reflectScrolledClipView(clip)
            await pause(0.8 / Double(pas))
        }
    }

    private static func defilante(_ v: NSView) -> NSScrollView? {
        var v: NSView? = v
        while let x = v {
            if let s = x as? NSScrollView, (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 1 { return s }
            v = x.superview
        }
        return nil
    }

    // MARK: - Trouver un élément à l'écran (arbre d'accessibilité de la fenêtre)

    private func point(_ cible: Cible) -> CGPoint? {
        switch cible {
        case let .point(x, y): return CGPoint(x: x, y: y)
        case let .repere(nom, rang):
            let l = Reperes.vues(nom, dans: fenetre)
            guard rang < l.count, let r = Reperes.cadre(l[rang], fenetre) else { manque("\(nom) (pas à l'écran)"); return nil }
            return CGPoint(x: r.midX, y: r.midY)
        case .texte(let t, let rang), .exact(let t, let rang):
            var exact = false
            if case .exact = cible { exact = true }
            var trouves: [CGRect] = []
            parcourir(fenetre, profondeur: 0) { libelle, cadre in
                let ok = exact ? libelle.trimmingCharacters(in: .whitespaces) == t : libelle.contains(t)
                if ok, cadre.width > 0, cadre.height > 0 { trouves.append(cadre) }
            }
            let tries = trouves.map(enFenetre).filter { $0.minY >= 0 && $0.maxY <= fenetre.frame.height }
                .sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
            guard rang < tries.count else { manque(t); return nil }
            let r = tries[rang]
            return CGPoint(x: r.minX + Swift.min(r.width / 2, 60), y: r.midY)
        }
    }

    /// Cadre écran (origine en bas à gauche) → points de la fenêtre depuis le haut.
    private func enFenetre(_ r: CGRect) -> CGRect {
        let f = fenetre.convertFromScreen(r)
        return CGRect(x: f.minX, y: fenetre.frame.height - f.maxY, width: f.width, height: f.height)
    }

    private func parcourir(_ objet: Any, profondeur: Int, _ visite: (String, CGRect) -> Void) {
        guard profondeur < 40, let e = objet as? NSAccessibilityProtocol else { return }
        let libelle = [e.accessibilityLabel(), e.accessibilityTitle(), e.accessibilityValue() as? String]
            .compactMap { $0 }.joined(separator: " ")
        if !libelle.isEmpty { visite(libelle, e.accessibilityFrame()) }
        for enfant in e.accessibilityChildren() ?? [] { parcourir(enfant, profondeur: profondeur + 1, visite) }
    }

    // MARK: - Film

    private func filmer() {
        let debut = ProcessInfo.processInfo.systemUptime
        minuterie = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.image(debut: debut) }
        }
    }

    private func image(debut: TimeInterval) {
        guard !occupe else { return }
        occupe = true
        let n = images.count + 1
        let nom = String(format: "%04d.png", n)
        images.append((nom, ProcessInfo.processInfo.systemUptime - debut))
        let numero = fenetre.windowNumber, taille = fenetre.frame.size, curseur = curseur, appui = appui, fond = fond
        let url = dossier.appendingPathComponent(nom), echelle = echelle
        file.async { [weak self] in
            Self.ecrire(numero: numero, taille: taille, curseur: curseur, appui: appui, echelle: echelle, fond: fond, vers: url)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.occupe = false } }
        }
    }

    private func finir() async {
        minuterie?.invalidate()
        while occupe { await pause(0.05) }
        file.sync {}
        var liste = ""
        for (i, im) in images.enumerated() {
            let suivant = i + 1 < images.count ? images[i + 1].le : im.le + 1.0 / 12
            liste += "file '\(im.nom)'\nduration \(String(format: "%.3f", suivant - im.le))\n"
        }
        if let dernier = images.last { liste += "file '\(dernier.nom)'\n" }
        try? liste.write(to: dossier.appendingPathComponent("images.txt"), atomically: true, encoding: .utf8)
    }

    /// Photographie la fenêtre, la réduit à 1 point = `echelle` pixel et y dessine le curseur.
    nonisolated private static func ecrire(numero: Int, taille: CGSize, curseur: CGPoint, appui: CGFloat, echelle: CGFloat,
                                           fond: CGColor, vers url: URL) {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return }
        let capture = unsafeBitCast(sym, to: Capture.self)
        guard let image = capture(.null, 1 << 3, UInt32(numero), (1 << 0) | (1 << 3))?.takeRetainedValue() else { return }
        let l = Int(taille.width * echelle), h = Int(taille.height * echelle)
        guard let c = CGContext(data: nil, width: l, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        c.setFillColor(fond)
        c.fill(CGRect(x: 0, y: 0, width: l, height: h))
        c.interpolationQuality = .high
        c.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))
        // Le curseur : une flèche noire bordée de blanc, pointe sur `curseur` ; un cercle pendant un clic.
        let x = curseur.x * echelle, y = CGFloat(h) - curseur.y * echelle, k = echelle * 1.15
        if appui > 0 {
            let r = (10 + 10 * (1 - appui)) * echelle
            c.setFillColor(CGColor(red: 0.21, green: 0.46, blue: 1.0, alpha: 0.35 * appui))   // le bleu de l'icône (#3675FF)
            c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        let forme: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4.2, 13.2), (6.9, 19.4), (9.6, 18.3), (6.9, 12.2), (12.4, 12.2)]
        let fleche = forme.map { CGPoint(x: x + $0.0 * k, y: y - $0.1 * k) }
        c.addLines(between: fleche); c.closePath()
        c.setFillColor(CGColor(gray: 0, alpha: 1)); c.setStrokeColor(CGColor(gray: 1, alpha: 1)); c.setLineWidth(1.4 * echelle)
        c.setShadow(offset: CGSize(width: 0, height: -1 * echelle), blur: 3 * echelle, color: CGColor(gray: 0, alpha: 0.35))
        c.drawPath(using: .fillStroke)
        guard let sortie = c.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, sortie, nil)
        CGImageDestinationFinalize(dest)
    }
}
