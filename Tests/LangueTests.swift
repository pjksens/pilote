// La langue de l'app (10/11) : l'infrastructure de localisation (Loc, L, catalogue compilé dans le bundle des tests).
import XCTest

final class LangueTests: XCTestCase {
    override func setUp() { Loc.dossierBundle = Bundle(for: Self.self).bundleURL }
    override func tearDown() { Loc.dossierBundle = nil; Loc.langue = "fr" }

    func testUnTexteCalculeSeTraduit() {
        let titre = "Facture"
        Loc.langue = "fr"
        XCTAssertEqual(L("Rappel lié : « \(titre) », coché"), "Rappel lié : « Facture », coché")
        Loc.langue = "en"
        XCTAssertEqual(L("Rappel lié : « \(titre) », coché"), "Linked reminder: “Facture”, checked off")
        Loc.langue = "es"
        XCTAssertEqual(L("Rappel lié : « \(titre) », coché"), "Recordatorio vinculado: «Facture», marcado como hecho")
    }

    /// Un texte avec un mot et un nombre : l'accord suit le nombre (la variante « one » ou « other » du catalogue).
    func testLesPluriels() {
        let jour = "lun. 10/11"
        let attendu: [String: [Int: String]] = [
            "fr": [1: "Demain (lun. 10/11) pas prêt : 1 trou", 3: "Demain (lun. 10/11) pas prêt : 3 trous"],
            "en": [1: "Tomorrow (lun. 10/11) not ready: 1 gap", 3: "Tomorrow (lun. 10/11) not ready: 3 gaps"],
            "es": [1: "Mañana (lun. 10/11) no está listo: 1 hueco", 3: "Mañana (lun. 10/11) no está listo: 3 huecos"],
        ]
        for (langue, cas) in attendu {
            Loc.langue = langue
            for (n, texte) in cas { XCTAssertEqual(L("Demain (\(jour)) pas prêt : \(n) trous"), texte, "\(langue) \(n)") }
        }
        Loc.langue = "en"
        XCTAssertEqual(L("\(1) relances"), "1 follow-up")
        XCTAssertEqual(L("\(2) relances"), "2 follow-ups")
    }

    /// `Loc.enFrancais` : les textes écrits pour les agents restent en français, et la langue de l'app revient après.
    func testEnFrancaisImposeLeFrancaisLeTempsDeLaFermeture() {
        Loc.langue = "en"
        let dedans = Loc.enFrancais { L("Rappel lié : « \("X") », coché") }
        XCTAssertEqual(dedans, "Rappel lié : « X », coché")
        XCTAssertEqual(Loc.langue, "en")
        XCTAssertEqual(L("Rappel lié : « \("X") », coché"), "Linked reminder: “X”, checked off")
    }

    // MARK: Le catalogue (App/Localizable.xcstrings)

    /// Les entrées du catalogue : clé française → langue → toutes les formes (une chaîne, ou les formes de pluriel).
    private func catalogue() throws -> [String: [String: [String]]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let chaines = json["strings"] as! [String: [String: Any]]
        var sortie: [String: [String: [String]]] = [:]
        for (cle, entree) in chaines {
            var parLangue: [String: [String]] = [:]
            for (langue, loc) in (entree["localizations"] as? [String: [String: Any]]) ?? [:] {
                if let u = loc["stringUnit"] as? [String: Any], let v = u["value"] as? String {
                    parLangue[langue] = [v]
                } else if let plur = (loc["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] {
                    parLangue[langue] = plur.values.compactMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
                }
            }
            sortie[cle] = parLangue
        }
        return sortie
    }

    /// Une clé sans lettre (« · », « %@ · %@ ») n'a rien à traduire.
    private func aTraduire(_ cle: String) -> Bool {
        let sansMarques = cle.replacingOccurrences(of: #"%(?:\d+\$)?(?:l{0,2}[dfu]|@)"#, with: "", options: .regularExpression)
        return sansMarques.range(of: #"\p{L}"#, options: .regularExpression) != nil
    }

    private func marques(_ t: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:l{0,2}[dfu]|@)"#)
        let sansPourcent = t.replacingOccurrences(of: "%%", with: "")
        return re.matches(in: sansPourcent, range: NSRange(sansPourcent.startIndex..., in: sansPourcent))
            .map { String(sansPourcent[Range($0.range, in: sansPourcent)!]).replacingOccurrences(of: #"%\d\$"#, with: "%", options: .regularExpression) }
            .sorted()
    }

    /// Mots qui n'existent qu'en français (ni en anglais, ni en espagnol) : s'il en reste dans une traduction, elle est oubliée.
    private static let motsFrancais: Set<String> = [
        "les", "des", "du", "à", "pour", "avec", "dans", "est", "pas", "une", "et", "ou", "sans", "sur", "aujourd'hui",
        "demain", "vous", "votre", "vos", "mais", "être", "déjà", "où", "chez", "tous", "faire", "fait", "ce", "cette", "ces",
        "ses", "qui", "quand", "rien", "jour", "jours", "semaine", "envoyé",
    ]

    private func motsFrancaisDans(_ texte: String) -> [String] {
        // « Rendez-vous » est le nom réel d'un calendrier de Sacha : pas du texte de l'app, on ne le traduit pas.
        let t = texte.replacingOccurrences(of: "Rendez-vous", with: " ")
        let re = try! NSRegularExpression(pattern: #"[\p{L}'’]+"#)
        return re.matches(in: t, range: NSRange(t.startIndex..., in: t)).compactMap { m -> String? in
            let mot = String(t[Range(m.range, in: t)!]).lowercased().replacingOccurrences(of: "’", with: "'")
            return Self.motsFrancais.contains(mot) ? mot : nil
        }
    }

    func testLeCatalogueEstCompletEnAnglaisEtEspagnol() throws {
        let cat = try catalogue()
        XCTAssertGreaterThan(cat.count, 100)
        var manques: [String] = [], marquesKo: [String] = []
        for (cle, langues) in cat where aTraduire(cle) {
            for langue in ["en", "es"] {
                guard let formes = langues[langue], !formes.isEmpty else { manques.append("\(langue) : \(cle)"); continue }
                for f in formes where marques(f) != marques(cle) { marquesKo.append("\(langue) : \(cle) → \(f)") }
            }
        }
        XCTAssertEqual(manques.count, 0, "traductions manquantes : \(manques.sorted().prefix(15))")
        XCTAssertEqual(marquesKo.count, 0, "%@ / %lld différents de la clé : \(marquesKo.sorted().prefix(10))")
    }

    func testAucunMotFrancaisDansLesTraductions() throws {
        var restes: [String] = []
        for (cle, langues) in try catalogue() where aTraduire(cle) {
            for langue in ["en", "es"] {
                for f in langues[langue] ?? [] {
                    let mots = motsFrancaisDans(f)
                    if !mots.isEmpty { restes.append("\(langue) : \(f)  [\(mots.joined(separator: ", "))]") }
                }
            }
        }
        XCTAssertEqual(restes.count, 0, "du français dans les traductions : \(restes.sorted().prefix(15))")
    }
}
