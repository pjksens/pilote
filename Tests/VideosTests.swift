// Tests des vidéos (2 par jour du lundi au vendredi, tournées la veille ouvrée) et des décisions « ❓ ».
import XCTest

final class VideosTests: XCTestCase {
    private var chemin: URL!

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("videos-tests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: chemin)
    }

    // MARK: Calendrier

    func testVeilleEtLendemainOuvres() {
        XCTAssertEqual(VideoCalcul.veilleOuvree("2026-11-09"), "2026-11-06")   // lundi → vendredi
        XCTAssertEqual(VideoCalcul.veilleOuvree("2026-11-04"), "2026-11-03")
        XCTAssertEqual(VideoCalcul.lendemainOuvre("2026-11-06"), "2026-11-09") // vendredi → lundi
        XCTAssertFalse(VideoCalcul.estOuvre("2026-11-07"))
        XCTAssertTrue(VideoCalcul.estOuvre("2026-11-03"))
    }

    func testSemaine() {
        XCTAssertEqual(VideoCalcul.semaine(de: "2026-11-04"), ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"])
        // Le samedi et le dimanche montrent la semaine qui vient.
        XCTAssertEqual(VideoCalcul.semaine(de: "2026-11-08").first, "2026-11-09")
        XCTAssertEqual(VideoCalcul.decalerSemaine("2026-11-03", 1), "2026-11-10")
    }

    // MARK: Le mot de la case

    private func video(_ statut: String) -> Video { Video(id: "x", jour: "", compte: "kryva", sujet: "S", statut: statut) }

    func testAffichage() {
        let auj = "2026-11-03"
        XCTAssertEqual(VideoCalcul.affichage(nil, jour: "2026-11-02", aujourdhui: auj).texte, "Rien")
        XCTAssertEqual(VideoCalcul.affichage(nil, jour: "2026-11-04", aujourdhui: auj).ton, .rouge)   // demain sans sujet
        XCTAssertEqual(VideoCalcul.affichage(nil, jour: "2026-11-06", aujourdhui: auj).ton, .neutre)
        XCTAssertEqual(VideoCalcul.affichage(video("valide"), jour: "2026-11-04", aujourdhui: auj).texte, "À tourner")
        XCTAssertEqual(VideoCalcul.affichage(video("valide"), jour: "2026-11-05", aujourdhui: auj).texte, "Validée")
        XCTAssertEqual(VideoCalcul.affichage(video("valide"), jour: auj, aujourdhui: auj).texte, "Pas tournée")
        XCTAssertEqual(VideoCalcul.affichage(video("tournee"), jour: "2026-11-04", aujourdhui: auj).texte, "Montage")
        XCTAssertEqual(VideoCalcul.affichage(video("prete"), jour: auj, aujourdhui: auj).ton, .vert)
        XCTAssertEqual(VideoCalcul.affichage(video("prete"), jour: "2026-11-02", aujourdhui: auj).texte, "Ratée")
        XCTAssertEqual(VideoCalcul.affichage(video("publiee"), jour: "2026-11-02", aujourdhui: auj).texte, "Publiée")
    }

    // MARK: Base

    func testEnregistrerVideo() throws {
        let stock = Stockage(base: try Base(chemin: chemin))
        let v = try stock.enregistrerVideo(["jour": "2026-11-04", "compte": "perso", "sujet": "Pilote", "statut": "valide"])
        // Même jour et même compte : la ligne est modifiée, pas doublée.
        let w = try stock.enregistrerVideo(["jour": "2026-11-04", "compte": "perso", "statut": "tournee"])
        XCTAssertEqual(v.id, w.id)
        XCTAssertEqual(w.sujet, "Pilote")
        XCTAssertEqual(w.statut, "tournee")
        XCTAssertThrowsError(try stock.enregistrerVideo(["jour": "2026-11-07", "compte": "kryva"]))   // samedi
        XCTAssertThrowsError(try stock.enregistrerVideo(["jour": "2026-11-04", "compte": "tiktok"]))
        XCTAssertThrowsError(try stock.enregistrerVideo(["jour": "2026-11-04", "statut": "fini"]))
        _ = try stock.enregistrerVideo(["jour": "", "compte": "kryva", "sujet": "Réserve"])
        XCTAssertEqual(try stock.videos(du: "2026-11-02", au: "2026-11-06").count, 1)
        XCTAssertEqual(try stock.videos(du: "2026-11-02", au: "2026-11-06", reserve: true).count, 2)
    }

    // MARK: Décisions

    func testDecisions() {
        XCTAssertTrue(Decisions.estDecision("❓ Sujet perso de mercredi"))
        XCTAssertFalse(Decisions.estDecision("Appeler Karim"))
        XCTAssertEqual(Decisions.question("❓ Sujet perso de mercredi"), "Sujet perso de mercredi")
        let notes = """
        Réseaux propose deux sujets, sources lues.
        Option 1 : Pip en appel client
        Option 2 - Pilote en 30 secondes
        Optionnel : rien à voir
        """
        XCTAssertEqual(Decisions.options(notes), ["Pip en appel client", "Pilote en 30 secondes"])
        XCTAssertEqual(Decisions.contexte("Contexte ici\nOption A : oui"), "Contexte ici")
        // Format des rappels de Réseaux (03/11) : « A : … », « B : … », puis « Docs : » et des liens.
        let reseaux = """
        But : trancher la vidéo KRYVA de mercredi.
        A : poster « 2 ans » mercredi 18:00 (il reste à valider la légende).
        B : pas de vidéo KRYVA mercredi.
        Docs :
        file:///Users/x/FICHE.md
        """
        XCTAssertEqual(Decisions.options(reseaux), ["poster « 2 ans » mercredi 18:00 (il reste à valider la légende).", "pas de vidéo KRYVA mercredi."])
        XCTAssertEqual(Decisions.contexte(reseaux), "But : trancher la vidéo KRYVA de mercredi.")
        XCTAssertEqual(Decisions.pour(liste: "Contenu"), "KRYVA · Réseaux, image, événements")
        XCTAssertEqual(Decisions.pour(liste: "Courses"), "PILOTE")
    }

    func testDestinataireEtDocuments() {
        let notes = """
        But : la release de la semaine.
        Pour : App et interface
        A : décaler au 12/11
        Docs : ~/Projects/x/FICHE.md
        file:///Users/x/Mon%20Dossier/NOTE.md
        """
        XCTAssertEqual(Decisions.pour(liste: "KRYVA", notes: notes), "KRYVA · App et interface")
        XCTAssertEqual(Decisions.pour(liste: "KRYVA"), "PILOTE")
        XCTAssertEqual(Decisions.pour(liste: "KRYVA", notes: "Pour : Papiers"), "KRYVA · Papiers et admin")
        XCTAssertEqual(Decisions.contexte(notes), "But : la release de la semaine.")
        let docs = Decisions.documents(notes)
        XCTAssertEqual(docs.count, 2)
        XCTAssertTrue(docs[0].hasSuffix("/Projects/x/FICHE.md") && !docs[0].hasPrefix("~"))
        XCTAssertEqual(docs[1], "/Users/x/Mon Dossier/NOTE.md")
        let milieu = Decisions.documents("Textes exacts : ~/Projects/freelance/x.md (envoyée dans PILOTE). Rien ne part.")
        XCTAssertEqual(milieu.count, 1)
        XCTAssertTrue(milieu[0].hasSuffix("/Projects/freelance/x.md"))
    }

    func testJourPrevu() {
        XCTAssertEqual(Libelles.jourPrevu("WhatsApp à envoyer par Sacha mer. 04/11 à 09:45 (Paris)\nBonjour", aujourdhui: "2026-11-03"),
                       "2026-11-04")
        XCTAssertEqual(Libelles.jourPrevu("À envoyer le 05/01", aujourdhui: "2026-12-20"), "2027-01-05")
        XCTAssertNil(Libelles.jourPrevu("Bonjour, rendez-vous le 04/11 ?", aujourdhui: "2026-11-03"))
        XCTAssertNil(Libelles.jourPrevu("Bonjour", aujourdhui: "2026-11-03"))
    }

    func testDecisionsEnvoyees() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("envoyees-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let h = Dates.iso.date(from: "2026-11-03T20:00:00Z")!
        try "{\"classe\":\"inconnu\"}\n".write(to: dossier.appendingPathComponent("entrants.jsonl"), atomically: true, encoding: .utf8)
        try Decisions.noter(question: "Q1", choix: "A", ref: "r1", liste: "Contenu", heure: h, dossier: dossier)
        try Decisions.noter(question: "Q2", choix: "Autre : X", ref: "r2", liste: "Textes", pour: "FREELANCE", heure: h, dossier: dossier)
        // La veille a lu les 2 premières lignes : Q1 est partie, Q2 attend.
        try "{\"lignes\": 2}".write(to: dossier.appendingPathComponent("veille-repere.json"), atomically: true, encoding: .utf8)
        let d = Decisions.envoyees(jour: "2026-11-03", dossier: dossier)
        XCTAssertEqual(d.map(\.question), ["Q1", "Q2"])
        XCTAssertEqual(d.map(\.transmise), [true, false])
        XCTAssertEqual(d[1].pour, "FREELANCE")
        XCTAssertEqual(d[0].pour, "KRYVA · Réseaux, image, événements")
        XCTAssertEqual(d[0].heure, "21:00")
    }

    func testFacteurReponsesEnAttente() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("facteur-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let h = Dates.iso.date(from: "2026-11-03T20:00:00Z")!
        try "{\"classe\":\"inconnu\"}\n".write(to: dossier.appendingPathComponent("entrants.jsonl"), atomically: true, encoding: .utf8)
        try Decisions.noter(question: "Ancienne", choix: "A", ref: "r0", liste: "Contenu", heure: h, dossier: dossier)
        try Decisions.noter(question: "Q1", choix: "B", ref: "r1", liste: "Textes", pour: "FREELANCE", heure: h, dossier: dossier)
        try Decisions.noter(question: "Q2", choix: "C", ref: "r2", liste: "Textes", pour: "FREELANCE", heure: h, dossier: dossier)
        try Facteur.ecrire(pour: "FREELANCE", session: "local_x", texte: "Où en es-tu ?", qui: "Sacha", heure: h, dossier: dossier)
        // Mise en service au rang 2 : la ligne 1 est partie à l'ancienne, Q1 et Q2 attendent le clic de Sacha.
        try "{\"rang\": 2}".write(to: dossier.appendingPathComponent("facteur-depart.json"), atomically: true, encoding: .utf8)
        try "{\"lignes\": 2}".write(to: dossier.appendingPathComponent("veille-repere.json"), atomically: true, encoding: .utf8)
        var d = Decisions.envoyees(jour: "2026-11-03", dossier: dossier)
        XCTAssertEqual(d.map(\.question), ["Ancienne", "Q1", "Q2"])
        XCTAssertEqual(d.map(\.enAttente), [false, true, true])
        XCTAssertEqual(d.map(\.transmise), [true, false, false])
        // Sacha envoie Q1, retire Q2 ; le Facteur remet Q1.
        try Facteur.noter([2], etat: .pret, dossier: dossier)
        try Facteur.noter([3], etat: .retire, dossier: dossier)
        d = Decisions.envoyees(jour: "2026-11-03", dossier: dossier)
        XCTAssertEqual(d.map(\.enAttente), [false, false, false])
        XCTAssertEqual(d[1].remise?.etat, .pret)
        XCTAssertEqual(d[2].remise?.etat, .retire)
        try "{\"rang\":2,\"etat\":\"remis\",\"le\":\"2026-11-03T21:01:00+01:00\",\"par\":\"facteur\"}\n"
            .write(to: dossier.appendingPathComponent("remises.jsonl"), atomically: false, encoding: .utf8)
        d = Decisions.envoyees(jour: "2026-11-03", dossier: dossier)
        XCTAssertTrue(d[1].transmise)
        XCTAssertTrue(Facteur.libelle(d[1].remise, pour: "FREELANCE", veille: nil).fait)
        // Le message écrit à une session part tout de suite (« envoyer »: « oui »), avec son identifiant local_….
        let m = Facteur.messages(dossier: dossier, maintenant: h)
        XCTAssertEqual(m.map(\.texte), ["Où en es-tu ?"])
        XCTAssertEqual(m.first?.session, "local_x")
        XCTAssertTrue(Facteur.ligneMessage(pour: "P", session: "s", texte: "t", heure: h, qui: "Sacha").contains("\"envoyer\":\"oui\""))
        // 09/11 (Organisation) : un dépôt qui n'est pas un clic de Sacha porte le nom de qui l'a écrit, jamais « Sacha ».
        let essai = Facteur.ligneMessage(pour: "P", session: "s", texte: "t", heure: h, qui: "Chantier écran unique")
        XCTAssertTrue(essai.contains("\"qui\":\"Chantier écran unique\""), essai)
        XCTAssertFalse(essai.contains("\"qui\":\"Sacha\""), essai)
        XCTAssertFalse(Facteur.actif(dossier: dossier))
    }

    func testPlanDeSession() {
        var plan: [EtapePlan] = []
        Sessions.appliquer(["items": [["content": "Lire", "status": "in_progress"], ["content": "Coder", "status": "pending"],
                                      ["content": "Tester", "status": "pending"]]], a: &plan)
        XCTAssertEqual(plan.map(\.statut), ["in_progress", "pending", "pending"])
        Sessions.appliquer(["advance": true], a: &plan)
        XCTAssertEqual(plan.map(\.statut), ["completed", "in_progress", "pending"])
        Sessions.appliquer(["done": [2], "start": 3], a: &plan)
        XCTAssertEqual(plan.map(\.statut), ["completed", "completed", "in_progress"])
        // Le fil d'une session : la liste rejouée, wrap_up = tout fini.
        let ligne = { (nom: String, entree: [String: Any]) -> [String: Any] in
            ["type": "assistant", "message": ["content": [["type": "tool_use", "name": nom, "input": entree]]]]
        }
        var r = Sessions.resumer([
            ligne("mcp__ccd_turn__update_plan", ["items": [["content": "A", "status": "in_progress"], ["content": "B", "status": "pending"]]]),
            ligne("mcp__ccd_turn__update_plan", ["advance": true]),
        ])
        XCTAssertEqual(r.etape, "B")
        XCTAssertEqual(r.plan.filter(\.faite).count, 1)
        r = Sessions.resumer([
            ligne("mcp__ccd_turn__update_plan", ["items": [["content": "A", "status": "in_progress"]]]),
            ligne("mcp__ccd_turn__wrap_up", ["recap": "Fini."]),
        ])
        XCTAssertEqual(r.recap, "Fini.")
        XCTAssertTrue(r.plan.allSatisfy(\.faite))
        XCTAssertEqual(r.etape, "")
    }

    func testMarkdown() {
        let b = Markdown.blocs("""
        # Titre
        Un paragraphe
        sur deux lignes.

        - puce **grasse**
          - sous-puce
        1. premier
        - [x] fait
        > citation
        ---
        | A | B |
        |---|---|
        | 1 | 2 |
        ```
        code
        ```
        """)
        XCTAssertEqual(b, [.titre(niveau: 1, texte: "Titre"), .paragraphe("Un paragraphe\nsur deux lignes."),
                           .puce(retrait: 0, texte: "puce **grasse**"), .puce(retrait: 1, texte: "sous-puce"),
                           .numero(retrait: 0, numero: "1", texte: "premier"), .tache(fait: true, texte: "fait"),
                           .citation("citation"), .trait, .tableau([["A", "B"], ["1", "2"]]), .code("code")])
    }

    func testLigneDecision() throws {
        let l = Decisions.ligne(question: "Sujet \"mercredi\"", choix: "Option 1", ref: "R1", liste: "Contenu",
                                heure: Dates.iso.date(from: "2026-11-03T20:00:00Z")!)
        let objet = try JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: String]
        XCTAssertEqual(objet?["classe"], "decision")
        XCTAssertEqual(objet?["extrait"], "Sujet \"mercredi\"")
        XCTAssertEqual(objet?["choix"], "Option 1")
    }
}
