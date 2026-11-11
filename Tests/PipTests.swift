// Liaison Pilote ↔ Pip (10/11) : le lien, la règle des 2 minutes, le contact lié, le résumé qui entre dans le fil.
import XCTest

final class PipTests: XCTestCase {
    var chemin: URL!
    var racine: URL!

    override func setUpWithError() throws {
        let id = UUID().uuidString
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-pip-\(id).sqlite")
        racine = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-pip-\(id)")
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
        try? FileManager.default.removeItem(at: racine)
    }

    private let midi = Dates.iso.date(from: "2026-11-11T11:00:00Z")!

    private func reunion(titre: String = "Visio Atelier Lune", lien: String? = "https://meet.google.com/abc-defg-hij", debut: Date? = nil,
                         journee: Bool = false, participants: [ParticipantPip] = []) -> ReunionPip {
        let d = debut ?? midi
        return ReunionPip(id: "EV1", titre: titre, debut: d, fin: d.addingTimeInterval(1800), journee: journee,
                          lien: lien.flatMap { URL(string: $0) }, participants: participants)
    }

    // MARK: Le lien

    func testLienEncodeTout() {
        let url = Pip.lien(titre: "Atelier & Lune = 50 % + « visio »", ref: "pilote:contact:ab-12", ouvrir: true)
        XCTAssertEqual(url.scheme, "heypip")
        XCTAssertEqual(url.host, "meeting")
        // Relu comme Pip le lit (URLComponents) : le titre et la ref reviennent intacts, rien ne s'est coupé sur & = +.
        let champs = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(champs.first { $0.name == "name" }?.value, "Atelier & Lune = 50 % + « visio »")
        XCTAssertEqual(champs.first { $0.name == "ref" }?.value, "pilote:contact:ab-12")
        XCTAssertEqual(champs.first { $0.name == "open" }?.value, "1")
        XCTAssertEqual(champs.count, 3)
    }

    func testLienSansOuvrirNiRef() {
        let champs = URLComponents(url: Pip.lien(titre: "Point", ref: "", ouvrir: false), resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(champs.map(\.name), ["name"])
    }

    // MARK: Quelles réunions

    func testVisio() {
        for u in ["https://meet.google.com/abc", "https://us02web.zoom.us/j/123", "https://teams.microsoft.com/l/meetup-join/x",
                  "https://whereby.com/salle", "https://facetime.apple.com/join#v=1"] {
            XCTAssertTrue(Pip.estVisio(URL(string: u)), u)
        }
        XCTAssertFalse(Pip.estVisio(URL(string: "https://www.notion.so/page")))
        XCTAssertFalse(Pip.estVisio(URL(string: "https://evilzoom.us.example.com/x")))
        XCTAssertFalse(Pip.estVisio(URL(string: "https://notzoom.us/x")))
        XCTAssertFalse(Pip.estVisio(nil))
    }

    func testLienVisioDansLesNotes() {
        XCTAssertEqual(Pip.lienVisio(dans: "Rejoindre : https://meet.google.com/abc-defg-hij pour la visio")?.absoluteString,
                       "https://meet.google.com/abc-defg-hij")
        XCTAssertNil(Pip.lienVisio(dans: "Dossier : https://www.notion.so/page"))
    }

    func testDeuxMinutesAvant() {
        let r = reunion()
        let deja: Set<String> = []
        XCTAssertFalse(Pip.aLancer(r, a: midi.addingTimeInterval(-121), dejaLancees: deja))   // trop tôt
        XCTAssertTrue(Pip.aLancer(r, a: midi.addingTimeInterval(-120), dejaLancees: deja))    // 2 min pile
        XCTAssertTrue(Pip.aLancer(r, a: midi.addingTimeInterval(-30), dejaLancees: deja))
        XCTAssertTrue(Pip.aLancer(r, a: midi.addingTimeInterval(300), dejaLancees: deja))     // 5 min après : encore
        XCTAssertFalse(Pip.aLancer(r, a: midi.addingTimeInterval(301), dejaLancees: deja))    // plus : Sacha est déjà dedans
    }

    func testUneSeuleFois() {
        let r = reunion()
        XCTAssertFalse(Pip.aLancer(r, a: midi.addingTimeInterval(-60), dejaLancees: [Pip.cle(r)]))
        // Déplacée à une autre heure : Pip s'ouvre de nouveau.
        let deplacee = reunion(debut: midi.addingTimeInterval(3600))
        XCTAssertNotEqual(Pip.cle(r), Pip.cle(deplacee))
        XCTAssertTrue(Pip.aLancer(deplacee, a: midi.addingTimeInterval(3540), dejaLancees: [Pip.cle(r)]))
    }

    func testPasDeLancementSansVisioNiPourUneJournee() {
        XCTAssertFalse(Pip.aLancer(reunion(lien: nil), a: midi.addingTimeInterval(-60), dejaLancees: []))
        XCTAssertFalse(Pip.aLancer(reunion(lien: "https://www.notion.so/page"), a: midi.addingTimeInterval(-60), dejaLancees: []))
        XCTAssertFalse(Pip.aLancer(reunion(journee: true), a: midi.addingTimeInterval(-60), dejaLancees: []))
    }

    // MARK: Le contact lié

    private func contact(_ nom: String, entreprise: String = "", email: String = "") -> Contact {
        Contact(id: UUID().uuidString.lowercased(), nom: nom, entreprise: entreprise, email: email)
    }

    func testContactParEmail() {
        let a = contact("Marie Lune", email: "marie@atelier-lune.fr")
        let b = contact("Paul Autre", email: "paul@exemple.fr")
        let r = reunion(participants: [ParticipantPip(nom: "", email: "Marie@Atelier-Lune.fr")])
        XCTAssertEqual(Pip.contactLie(a: r, parmi: [b, a])?.id, a.id)
    }

    func testContactParNomComplet() {
        let a = contact("Marie Lune")
        let b = contact("Jean")                                 // un seul mot : jamais un lien
        XCTAssertEqual(Pip.contactLie(a: reunion(titre: "Point avec Marie Lune", participants: []), parmi: [b, a])?.id, a.id)
        XCTAssertEqual(Pip.contactLie(a: reunion(participants: [ParticipantPip(nom: "marie  LUNE", email: "")]), parmi: [a])?.id, a.id)
        XCTAssertNil(Pip.contactLie(a: reunion(titre: "Point avec Jean"), parmi: [b]))
    }

    func testContactParEntrepriseEtAccents() {
        let a = contact("Éloïse Dupré", entreprise: "Boulangerie Soleil")
        XCTAssertEqual(Pip.contactLie(a: reunion(titre: "Visio Boulangerie Soleil"), parmi: [a])?.id, a.id)
        XCTAssertEqual(Pip.contactLie(a: reunion(titre: "Visio eloise dupre"), parmi: [a])?.id, a.id)
        XCTAssertNil(Pip.contactLie(a: reunion(titre: "Visio Boulangerie"), parmi: [a]))   // morceau de nom : pas assez
        let court = contact("Tom Petit", entreprise: "ABC")
        XCTAssertNil(Pip.contactLie(a: reunion(titre: "Visio ABC"), parmi: [court]))        // entreprise de moins de 4 lettres
    }

    func testPlusieursContactsOnNeDevinePas() {
        let a = contact("Marie Lune", entreprise: "Atelier Lune")
        let b = contact("Luc Lune", entreprise: "Atelier Lune")
        XCTAssertNil(Pip.contactLie(a: reunion(titre: "Visio Atelier Lune"), parmi: [a, b]))
        // L'e-mail tranche avant le reste.
        let c = contact("Marie Lune", email: "marie@atelier-lune.fr")
        let r = reunion(titre: "Visio Atelier Lune", participants: [ParticipantPip(nom: "", email: "marie@atelier-lune.fr")])
        XCTAssertEqual(Pip.contactLie(a: r, parmi: [a, b, c])?.id, c.id)
    }

    func testNePlusContacterEstIgnore() {
        var a = contact("Marie Lune")
        a.nePlusContacter = true
        XCTAssertNil(Pip.contactLie(a: reunion(titre: "Visio Marie Lune"), parmi: [a]))
    }

    func testRef() {
        let a = contact("Marie Lune")
        XCTAssertEqual(Pip.contactId(deRef: Pip.ref(contact: a, reunion: reunion())), a.id)
        let sans = Pip.ref(contact: nil, reunion: reunion())
        XCTAssertEqual(sans, "pilote:rdv:EV1")
        XCTAssertTrue(Pip.estDePilote(sans))
        XCTAssertNil(Pip.contactId(deRef: sans))
        XCTAssertFalse(Pip.estDePilote("autre-app:contact:1"))
    }

    // MARK: Le dossier de Pip

    func testRacine() {
        let maison = URL(fileURLWithPath: "/Users/exemple")
        XCTAssertEqual(PipRetour.racine(reglagePip: nil, maison: maison).path, "/Users/exemple/Documents/Pip")
        XCTAssertEqual(PipRetour.racine(reglagePip: "  ", maison: maison).path, "/Users/exemple/Documents/Pip")
        XCTAssertEqual(PipRetour.racine(reglagePip: "/tmp/pip-test", maison: maison).path, "/tmp/pip-test")
    }

    // MARK: La ligne « Prochaine action »

    func testSeparerLaProchaineAction() {
        let r = PipRetour.separer("## Résumé\nOn a vu le devis.\n\n**Prochaine action :** Envoyer le devis jeudi.\n")
        XCTAssertEqual(r.action, "Envoyer le devis jeudi.")
        XCTAssertEqual(r.corps, "## Résumé\nOn a vu le devis.")
        XCTAssertEqual(PipRetour.separer("Summary.\nNext action: Send the quote").action, "Send the quote")
        XCTAssertEqual(PipRetour.separer("Resumen.\n- Próxima acción: enviar el presupuesto").action, "enviar el presupuesto")
        XCTAssertEqual(PipRetour.separer("A.\nProchaine action : première\nB.\nProchaine action : dernière").action, "dernière")  // la dernière gagne
    }

    func testSansLigneAction() {
        let r = PipRetour.separer("Juste un résumé.\nLa prochaine action sera discutée.\n")
        XCTAssertNil(r.action)
        XCTAssertEqual(r.corps, "Juste un résumé.\nLa prochaine action sera discutée.")
        XCTAssertNil(PipRetour.separer("Prochaine action :   \n").action)    // ligne vide : rien
    }

    func testTexteDuFilCoupeLesLongsResumes() {
        let long = (1...400).map { "Ligne \($0) du résumé de la réunion." }.joined(separator: "\n")
        let t = PipRetour.texteDuFil(ResumePip(dossier: "2026-11-11_1100_x", nom: "X", ref: "pilote:rdv:1", debut: nil, resume: long, prochaineAction: "Faire"))
        XCTAssertLessThan(t.count, 4200)
        XCTAssertTrue(t.contains("…"))
        XCTAssertTrue(t.hasSuffix("Prochaine action : Faire"))
        XCTAssertTrue(t.hasPrefix("Résumé de la réunion « X » (Pip, dossier 2026-11-11_1100_x)"))
    }

    // MARK: Les dossiers de réunion

    @discardableResult
    private func reunionChezPip(_ nom: String, ref: String?, resume: String?, ageDuResume: TimeInterval = 600,
                                debut: String = "2026-11-11T10:00:00Z", maintenant: Date) throws -> URL {
        let d = racine.appendingPathComponent(nom)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try "# \(nom)\n".write(to: d.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        if let ref {
            let json = "{\"name\":\"Visio Atelier Lune\",\"ref\":\"\(ref)\",\"startedAt\":\"\(debut)\"}"
            try json.write(to: d.appendingPathComponent("meeting.json"), atomically: true, encoding: .utf8)
        }
        if let resume {
            let f = d.appendingPathComponent("summary.md")
            try resume.write(to: f, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: maintenant.addingTimeInterval(-ageDuResume)], ofItemAtPath: f.path)
        }
        return d
    }

    func testSeulsLesResumesPretsDePiloteSontLus() throws {
        let maintenant = Date()
        try reunionChezPip("a-pret", ref: "pilote:contact:c1", resume: "Résumé.\nProchaine action : Rappeler.", maintenant: maintenant)
        try reunionChezPip("b-pas-de-pilote", ref: "autre:xyz", resume: "Résumé d'une autre app.", maintenant: maintenant)
        try reunionChezPip("c-sans-fiche", ref: nil, resume: "Réunion lancée à la main chez Pip.", maintenant: maintenant)
        try reunionChezPip("d-encore-ecrit", ref: "pilote:contact:c1", resume: "En cours…", ageDuResume: 20, maintenant: maintenant)
        try reunionChezPip("e-sans-resume", ref: "pilote:contact:c1", resume: nil, maintenant: maintenant)
        try reunionChezPip("f-vide", ref: "pilote:contact:c1", resume: "  \n", maintenant: maintenant)
        // « current » (lien vers la réunion en cours chez Pip) n'est jamais lu deux fois.
        try FileManager.default.createSymbolicLink(at: racine.appendingPathComponent("current"), withDestinationURL: racine.appendingPathComponent("a-pret"))
        let lus = PipRetour.aImporter(racine: racine, a: maintenant)
        XCTAssertEqual(lus.map(\.dossier), ["a-pret"])
        XCTAssertEqual(lus.first?.prochaineAction, "Rappeler.")
        XCTAssertEqual(lus.first?.resume, "Résumé.")
        XCTAssertEqual(lus.first?.debut, Dates.iso.date(from: "2026-11-11T10:00:00Z"))
    }

    func testDossierAbsent() {
        XCTAssertTrue(PipRetour.aImporter(racine: racine.appendingPathComponent("nexiste-pas")).isEmpty)
    }

    // MARK: Le fil

    func testLeResumeEntreDansLeFilUneSeuleFois() throws {
        let s = Stockage(base: try Base(chemin: chemin))
        let c = try s.enregistrer(["nom": "Marie Lune", "espace": "freelance", "etape": "contacte",
                                   "prochaine_action": "Sacha : visio du 11/11", "prochaine_date": "2026-11-11"])
        let maintenant = Date()
        try reunionChezPip("2026-11-11_1100_visio", ref: "pilote:contact:\(c.id)",
                           resume: "On a vu le devis.\n\nProchaine action : Sacha envoie le devis jeudi.", maintenant: maintenant)
        let prets = PipRetour.aImporter(racine: racine, a: maintenant)

        let premier = try s.importerResumesPip(prets)
        XCTAssertEqual(premier.count, 1)
        XCTAssertEqual(premier.first?.contact?.id, c.id)
        let fil = try s.evenements(c.id)
        XCTAssertEqual(fil.count, 1)
        XCTAssertEqual(fil[0].canal, "visio")
        XCTAssertEqual(fil[0].type, "rdv")
        XCTAssertEqual(fil[0].par, "Pip")
        XCTAssertEqual(fil[0].statut, "fait")
        XCTAssertEqual(fil[0].le, "2026-11-11T10:00:00Z")                     // l'heure de la réunion, pas celle de l'import
        XCTAssertTrue(fil[0].texte.contains("On a vu le devis."))
        XCTAssertTrue(fil[0].texte.hasSuffix("Prochaine action : Sacha envoie le devis jeudi."))
        XCTAssertFalse(fil[0].texte.contains("/Users"))                        // jamais un chemin

        // Relancé : rien de nouveau, pas de doublon.
        let second = try s.importerResumesPip(PipRetour.aImporter(racine: racine, a: maintenant))
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(try s.evenements(c.id).count, 1)

        // La fiche garde son étape et sa prochaine action : la proposition de Pip n'écrase rien.
        let apres = try s.contact(c.id)!
        XCTAssertEqual(apres.etape, "contacte")
        XCTAssertEqual(apres.prochaineAction, "Sacha : visio du 11/11")
        XCTAssertEqual(apres.prochaineDate, "2026-11-11")
    }

    func testSansContactLeResumeVaAuJournal() throws {
        let s = Stockage(base: try Base(chemin: chemin))
        let maintenant = Date()
        try reunionChezPip("2026-11-11_1100_inconnu", ref: "pilote:rdv:EV9", resume: "Résumé sans contact.", maintenant: maintenant)
        try reunionChezPip("2026-11-11_1200_supprime", ref: "pilote:contact:fiche-supprimee", resume: "Fiche disparue.", maintenant: maintenant)
        let nouveaux = try s.importerResumesPip(PipRetour.aImporter(racine: racine, a: maintenant))
        XCTAssertEqual(nouveaux.count, 2)
        XCTAssertTrue(nouveaux.allSatisfy { $0.contact == nil })
        XCTAssertEqual(try s.base.lignes("SELECT * FROM journal WHERE source_ref LIKE 'pip:%'").count, 2)
        XCTAssertTrue(try s.importerResumesPip(PipRetour.aImporter(racine: racine, a: maintenant)).isEmpty)   // pas de doublon
        XCTAssertEqual(try s.base.lignes("SELECT * FROM journal WHERE source_ref LIKE 'pip:%'").count, 2)
    }
}
