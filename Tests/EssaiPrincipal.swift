import Foundation

/// Chargé par XCTest avant le premier test (NSPrincipalClass du lot, voir project.yml) : les tests sont écrits avec le
/// prénom de l'auteur, « Sacha ». Ils ne lisent jamais le reglages.json de la machine.
@objc(EssaiPrincipal) final class EssaiPrincipal: NSObject {
    static let reglages: Reglages = { var r = Reglages(); r.prenom = "Sacha"; return r }()
    override init() {
        super.init()
        Reglages.remplacement = Self.reglages
    }
}
