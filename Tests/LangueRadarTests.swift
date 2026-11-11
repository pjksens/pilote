// La langue du Radar et des vidéos (10/11) : les textes que produisent Shared/Radar.swift, Videos.swift et SuiviVideo.swift
// sortent en anglais et en espagnol sans un mot de français ; le français reste celui d'avant.
import XCTest

final class LangueRadarTests: XCTestCase {
    private let t0 = Dates.iso.date(from: "2026-10-29T12:00:00Z")!
    private var chemins: [URL] = []

    override func setUp() { Loc.dossierBundle = Bundle(for: Self.self).bundleURL }

    override func tearDown() {
        Loc.dossierBundle = nil
        Loc.langue = "fr"
        for c in chemins { for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: c.path + suffixe) } }
        chemins = []
    }

    private func neuf() throws -> Stockage {
        let c = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-langue-radar-\(UUID().uuidString).sqlite")
        chemins.append(c)
        return Stockage(base: try Base(chemin: c))
    }

    // MARK: Données d'exemple

    private func post(_ id: String, vues: Int?, age: Double, compte: String = "k:instagram:a") -> RadarCalcul.Post {
        RadarCalcul.Post(id: id, compteId: compte, plateforme: "instagram", publieLe: t0.addingTimeInterval(-age * 3600), releveLe: t0,
                         vues: vues, likes: nil, commentaires: nil)
    }

    private func obs(_ id: String, vues: Int?, age: Double, compte: String = "renovo") -> RadarObservation {
        RadarObservation(plateforme: "instagram", compte: compte, identifiantPost: id, url: "https://www.instagram.com/reel/\(id)/", legende: "",
                         publieLe: t0.addingTimeInterval(-age * 3600), releveLe: t0, vues: vues, likes: nil, commentaires: nil, source: "manuelle")
    }

    private func garnir(_ s: Stockage, espace: String = "kryva", compte: String = "renovo", references: Int = 5, source: String? = nil) throws {
        for (i, v) in [10_000, 12_000, 15_000, 18_000, 50_000].prefix(references).enumerated() {
            var o = obs("R\(i)", vues: v, age: 100 + Double(i) * 24, compte: compte)
            if let source { o.source = source }
            try s.radarObserve(o, espace: espace, maintenant: t0)
        }
        var chaud = obs("HOT", vues: 60_000, age: 20, compte: compte)
        if let source { chaud.source = source }
        try s.radarObserve(chaud, espace: espace, maintenant: t0)
    }

    private func message(_ f: () throws -> Void) -> String {
        do { try f(); return "" } catch { return "\(error)" }
    }

    // MARK: Les sorties de Radar.swift

    private func sortiesRadar() throws -> [String] {
        var sorties: [String] = []
        // Les raisons d'un ratio absent : pas assez de références (0, 1 et 4 : le pluriel), vues inconnues, médiane nulle.
        for n in [0, 1, 4] {
            let refs = (0..<n).map { post("r\($0)", vues: 10_000, age: 100 + Double($0) * 24) }
            sorties.append(RadarCalcul.evaluer(post("c", vues: 60_000, age: 20), parmi: refs).raison ?? "")
        }
        sorties.append(RadarCalcul.evaluer(post("x", vues: nil, age: 20), parmi: []).raison ?? "")
        let zeros = (0..<5).map { post("z\($0)", vues: 0, age: 100 + Double($0)) }
        sorties.append(RadarCalcul.evaluer(post("c", vues: 1_000, age: 20), parmi: zeros).raison ?? "")
        // Les posts écartés : trop jeune, trop vieux, ratio indéterminé.
        let jeune = post("j", vues: 5, age: 2), vieux = post("v", vues: 5, age: 200), sansRef = post("s", vues: 5, age: 20)
        let (_, exclus) = RadarCalcul.classer(RadarCalcul.evaluer([jeune, vieux, sansRef]))
        sorties += exclus.map(\.1)
        // Les avertissements du classement.
        let vide = try neuf()
        sorties += try vide.radarClassement(espace: "kryva", maintenant: t0).avertissements
        try vide.radarAjouteCompte(espace: "kryva", plateforme: "instagram", identifiant: "renovo")
        sorties += try vide.radarClassement(espace: "kryva", maintenant: t0).avertissements
        let s = try neuf()
        try garnir(s, references: 3)
        sorties += try s.radarClassement(espace: "kryva", maintenant: t0.addingTimeInterval(50 * 3600)).avertissements
        let sim = try neuf()
        try garnir(sim, source: "factice")
        sorties += try sim.radarClassement(espace: "kryva", simulation: true, maintenant: t0).avertissements
        // Les erreurs que l'écran montre : post inconnu, idée inconnue, conflit d'édition.
        sorties.append(message { _ = try s.radarEnregistreIdee(postId: "instagram:INCONNU", espace: "kryva", maintenant: t0) })
        sorties.append(message { _ = try s.radarEcritIdee(id: "zzz", brouillon: "x", revision: 0, maintenant: t0) })
        let g = try neuf()
        try garnir(g)
        let (idee, _) = try g.radarEnregistreIdee(postId: "instagram:HOT", espace: "kryva", maintenant: t0)
        _ = try g.radarEcritIdee(id: idee.id, brouillon: "Ma version", revision: 0, maintenant: t0)
        sorties.append(message { _ = try g.radarEcritIdee(id: idee.id, brouillon: "écrase", revision: 0, maintenant: t0) })
        return sorties
    }

    // MARK: Les sorties de Videos.swift et SuiviVideo.swift

    private func sortiesVideos() throws -> [String] {
        var sorties: [String] = []
        sorties += VideoVocabulaire.statuts.map(\.1) + VideoVocabulaire.comptes.map(\.1)
        sorties += VerdictVocabulaire.verdicts.map(\.1)
        sorties += ["marche", "moyen", "rate", "trop_tot"].map(VerdictVocabulaire.libelle)
        sorties += ["a_choisir", "valide", "tournee", "prete", "publiee", "annulee"].map(VideoVocabulaire.statut)
        // Le mot de la case, dans toutes ses branches (lundi 2, mercredi 4 et vendredi 6 nov. 2026 ; « aujourd'hui » = mercredi 4).
        let auj = "2026-11-04"
        func video(_ statut: String) -> Video { Video(id: "x", jour: "", compte: "kryva", sujet: "S", statut: statut) }
        sorties.append(VideoCalcul.affichage(nil, jour: "2026-11-02", aujourdhui: auj).texte)
        sorties.append(VideoCalcul.affichage(nil, jour: "2026-11-04", aujourdhui: auj).texte)
        for statut in ["publiee", "annulee"] { sorties.append(VideoCalcul.affichage(video(statut), jour: "2026-11-02", aujourdhui: auj).texte) }
        sorties.append(VideoCalcul.affichage(video("prete"), jour: "2026-11-02", aujourdhui: auj).texte)
        sorties.append(VideoCalcul.affichage(video("prete"), jour: auj, aujourdhui: auj).texte)
        sorties.append(VideoCalcul.affichage(video("tournee"), jour: auj, aujourdhui: auj).texte)
        for jour in [auj, "2026-11-05", "2026-11-06"] { sorties.append(VideoCalcul.affichage(video("valide"), jour: jour, aujourdhui: auj).texte) }
        // Les paliers et les délais.
        sorties += [PalierReleve.h48.affichage, PalierReleve.j7.affichage, PalierReleve.autre.affichage,
                    PalierReleve.affichage(code: "48h"), PalierReleve.affichage(code: "7j"), PalierReleve.affichage(code: "autre")]
        sorties += [3.0, 30, 48, 72, 456].map { ReleveVideo(delaiHeures: $0).delaiTexte }
        // Le dernier échange d'un contact.
        sorties += [("entrant", "sms"), ("sortant", "sms"), ("sortant", "mail")].map {
            DernierEchange(le: "2026-10-28T10:00:00Z", canal: $0.1, sens: $0.0, type: "message", texte: "").resumeAffiche
        }
        // Les erreurs montrées par l'écran des vidéos et par celui des stats.
        let s = try neuf()
        sorties.append(message { try s.enregistrerVideo(["jour": "2026-11-07", "compte": "kryva"]) })
        sorties.append(message { try s.enregistrerVideo(["id": "inconnu"]) })
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString).sqlite")
        sorties.append(SuiviVideo.charger(stock: s, chemin: absent).erreur ?? "")
        sorties.append(SuiviVideo.charger(stock: s, chemin: FileManager.default.temporaryDirectory).erreur ?? "")   // un dossier n'est pas une base
        return sorties
    }

    private func message(_ f: () throws -> Video) -> String {
        do { _ = try f(); return "" } catch { return "\(error)" }
    }

    // MARK: Tests

    func testAucunMotFrancaisEnAnglaisNiEnEspagnol() throws {
        for langue in ["en", "es"] {
            Loc.langue = langue
            let sorties = try sortiesRadar() + sortiesVideos()
            XCTAssertGreaterThan(sorties.count, 50)
            for texte in sorties {
                XCTAssertFalse(texte.isEmpty, "\(langue) : une sortie est vide")
                // Les données d'exemple (l'identifiant de post, le chemin d'un dossier) ne sont pas du texte de l'app.
                let francais = ContientDuFrancais(texte, langue: langue, donnees: ["instagram:INCONNU", "kryva", "pilote radar compte-ajoute", "pilote radar importe", NSTemporaryDirectory(), FileManager.default.temporaryDirectory.path])
                XCTAssertEqual(francais, [], "\(langue) : du français dans « \(texte) »")
            }
        }
    }

    func testLeFrancaisResteCeluiDAvant() throws {
        Loc.langue = "fr"
        XCTAssertEqual(VideoVocabulaire.statut("tournee"), "Tournée, en montage")
        XCTAssertEqual(VideoVocabulaire.compte("perso"), "Perso")
        XCTAssertEqual(VerdictVocabulaire.libelle("rate"), "N'a pas marché")
        XCTAssertEqual(PalierReleve.affichage(code: "7j"), "7j")
        XCTAssertEqual(ReleveVideo(delaiHeures: 72).delaiTexte, "3 j")
        XCTAssertEqual(VideoCalcul.affichage(nil, jour: "2026-11-02", aujourdhui: "2026-11-04").texte, "Rien")
        let p = RadarCalcul.evaluer(post("c", vues: 60_000, age: 20), parmi: [post("r", vues: 1, age: 100)]).raison
        XCTAssertEqual(p, "1 autre post de référence sur 30 jours, il en faut 5")
        // En français 0 et 1 s'accordent au singulier (règle des pluriels du catalogue).
        XCTAssertEqual(try sortiesRadar().first, "0 autre post de référence sur 30 jours, il en faut 5")
        let quatre = (0..<4).map { post("r\($0)", vues: 10_000, age: 100 + Double($0) * 24) }
        XCTAssertEqual(RadarCalcul.evaluer(post("c", vues: 60_000, age: 20), parmi: quatre).raison, "4 autres posts de référence sur 30 jours, il en faut 5")
        XCTAssertEqual(VideoVocabulaire.statutsFrancais.map(\.1).first, "Sujet à choisir")
    }

    func testAnglais() throws {
        Loc.langue = "en"
        XCTAssertEqual(VideoVocabulaire.statut("prete"), "Ready")
        XCTAssertEqual(VideoVocabulaire.compte("perso"), "Personal")
        XCTAssertEqual(VerdictVocabulaire.libelle("trop_tot"), "Too early to tell")
        XCTAssertEqual(PalierReleve.affichage(code: "7j"), "7d")
        XCTAssertEqual(ReleveVideo(delaiHeures: 72).delaiTexte, "3 d")
        XCTAssertEqual(VideoCalcul.affichage(nil, jour: "2026-11-02", aujourdhui: "2026-11-04").texte, "Nothing")
        // Les pluriels : une seule clé avec le nombre, l'anglais et le français accordent chacun à leur façon.
        let rien = RadarCalcul.evaluer(post("c", vues: 60_000, age: 20), parmi: []).raison
        XCTAssertEqual(rien, "0 other posts in the 30-day reference set, 5 needed")
        let un = RadarCalcul.evaluer(post("c", vues: 60_000, age: 20), parmi: [post("r", vues: 1, age: 100)]).raison
        XCTAssertEqual(un, "1 other post in the 30-day reference set, 5 needed")
        let n1 = 1, n2 = 2
        XCTAssertEqual(L("\(n1) vidéos"), "1 video")
        XCTAssertEqual(L("\(n2) vidéos"), "2 videos")
        XCTAssertEqual(L("\(n2) à relever"), "2 readings due")
        XCTAssertEqual(L("il y a \(n2) jours"), "2 days ago")
    }

    func testEspagnol() throws {
        Loc.langue = "es"
        XCTAssertEqual(VideoVocabulaire.statut("prete"), "Listo")
        XCTAssertEqual(VerdictVocabulaire.libelle("marche"), "Funcionó")
        XCTAssertEqual(ReleveVideo(delaiHeures: 3).delaiTexte, "3 h")
        let n1 = 1, n3 = 3
        XCTAssertEqual(L("\(n1) vidéos"), "1 vídeo")
        XCTAssertEqual(L("\(n3) vidéos"), "3 vídeos")
        XCTAssertEqual(L("\(n3) publiées"), "3 publicados")
        XCTAssertEqual(L("il y a \(n1) jours"), "hace 1 día")
        let un = RadarCalcul.evaluer(post("c", vues: 60_000, age: 20), parmi: [post("r", vues: 1, age: 100)]).raison
        XCTAssertEqual(un, "1 otra publicación de referencia en 30 días, hacen falta 5")
    }
}
