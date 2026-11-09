// Captures d'écran du mode démo (PILOTE_DEMO=1 et PILOTE_CAPTURES=<dossier>) : l'app photographie sa propre fenêtre,
// page après page, puis se ferme. Rien d'autre n'est capté : pas d'enregistrement de l'écran, aucune permission demandée.
// PILOTE_CAPTURES_PAGES=aujourdhui,claude : seulement ces pages (noms de Ecran).
import AppKit

@MainActor
enum Captures {
    static var fenetre: NSWindow? { NSApp.windows.first { $0.isVisible && $0.canBecomeMain } }

    static func preparer(largeur: CGFloat = 1280, hauteur: CGFloat = 820) {
        guard let f = fenetre else { return }
        f.setContentSize(NSSize(width: largeur, height: hauteur))
        f.center()
    }

    /// La fenêtre entière (barre de titre comprise), en PNG. Une app peut photographier ses propres fenêtres sans la
    /// permission d'enregistrer l'écran ; CGWindowListCreateImage n'est plus déclarée dans le SDK de macOS 15, d'où dlsym.
    @discardableResult
    static func photographier(vers url: URL) -> Bool {
        guard let f = fenetre else { return false }
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return false }
        let capture = unsafeBitCast(sym, to: Capture.self)
        // optionIncludingWindow (1 << 3) ; boundsIgnoreFraming (1 << 0) | bestResolution (1 << 3)
        guard let image = capture(.null, 1 << 3, UInt32(f.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    static func pages(_ env: [String: String]) -> [Ecran] {
        let toutes = [Ecran.aujourdhui] + Ecran.pages
        guard let choix = env["PILOTE_CAPTURES_PAGES"], !choix.isEmpty else { return toutes }
        let noms = choix.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return toutes.filter { noms.contains($0.rawValue) }
    }
}
