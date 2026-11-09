// Tests du planning : notes « But / Docs / Fini quand », semaine du lundi, colonnes des chevauchements,
// et « Terminé » (état gardé, ligne du contrat ajoutée une seule fois à entrants.jsonl, jamais de réécriture).
import XCTest

final class PlanningTests: XCTestCase {
    private var dossier: URL!

    override func setUpWithError() throws {
        dossier = FileManager.default.temporaryDirectory.appendingPathComponent("planning-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dossier)
    }

    private func date(_ s: String) -> Date { Dates.iso.date(from: s)! }

    private func tache(ref: String = "ABC-123", titre: String = "Appeler les 9 inscrits",
                       debut: String = "2026-11-03T11:00:00Z", calendrier: String = "Appels") -> TachePlanning {
        TachePlanning(genre: .tache, ref: ref, idLocal: "local-" + ref, titre: titre, debut: date(debut),
                      fin: date(debut).addingTimeInterval(TachePlanning.dureeTache),
                      calendrier: calendrier, journee: false, url: nil, notes: NotesPlanning())
    }

    // MARK: Notes

    func testNotesDuContrat() {
        let n = NotesPlanning.lire("""
        But : 3 démos prises
        Docs :
        Fiches : file:///Users/sacha/Projets/Liste des inscrits.pdf
        https://kryva.fr/admin/inscrits
        - ~/Documents/kryva/script appel.md
        Fini quand : les 9 ont été appelés
        """)
        XCTAssertEqual(n.but, "3 démos prises")
        XCTAssertEqual(n.finiQuand, "les 9 ont été appelés")
        XCTAssertEqual(n.docs.count, 3)
        XCTAssertEqual(n.docs[0].libelle, "Fiches")
        XCTAssertEqual(n.docs[0].url.path, "/Users/sacha/Projets/Liste des inscrits.pdf")
        XCTAssertEqual(n.docs[1].url.absoluteString, "https://kryva.fr/admin/inscrits")
        XCTAssertEqual(n.docs[1].libelle, "kryva.fr")
        XCTAssertTrue(n.docs[2].url.isFileURL)
        XCTAssertEqual(n.docs[2].libelle, "script appel.md")
        XCTAssertFalse(n.docs[2].url.path.hasPrefix("~"))
    }

    func testNotesSouplesEtIncompletes() {
        let n = NotesPlanning.lire("BUT: rendre la V1\nDocs : https://exemple.fr/a\nune ligne sans lien")
        XCTAssertEqual(n.but, "rendre la V1")
        XCTAssertEqual(n.docs.map(\.url.absoluteString), ["https://exemple.fr/a"])
        XCTAssertNil(n.finiQuand)
        XCTAssertEqual(NotesPlanning.lire(""), NotesPlanning())
        // Un lien hors de « Docs » n'est pas un document.
        XCTAssertTrue(NotesPlanning.lire("Voir https://exemple.fr").docs.isEmpty)
    }

    // MARK: Semaine et colonnes

    func testSemaineDuLundiAuDimanche() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let dimanche = date("2026-11-08T20:00:00Z")      // dim. 8/11, 21 h à Paris
        let lundi = Semaine.lundi(de: dimanche, fuseau: paris)
        XCTAssertEqual(lundi, date("2026-11-01T23:00:00Z")) // lun. 2/11, 0 h à Paris
        XCTAssertEqual(Semaine.lundi(de: lundi, fuseau: paris), lundi)
        let jours = Semaine.jours(de: date("2026-11-04T10:00:00Z"), fuseau: paris)
        XCTAssertEqual(jours.count, 7)
        XCTAssertEqual(jours.first, lundi)
        XCTAssertEqual(jours.last, date("2026-11-07T23:00:00Z"))
    }

    func testColonnesDesChevauchements() {
        let h = { (s: String) in self.date("2026-11-03T\(s):00Z") }
        // Seules : une colonne chacune.
        let seules = Disposition.colonnes([(h("07:00"), h("08:00")), (h("08:00"), h("09:00"))])
        XCTAssertEqual(seules.map(\.colonne), [0, 0])
        XCTAssertEqual(seules.map(\.sur), [1, 1])
        // A 9-11 chevauche B 10-12 et C 11-12 ; C reprend la colonne de A.
        let groupe = Disposition.colonnes([(h("09:00"), h("11:00")), (h("10:00"), h("12:00")), (h("11:00"), h("12:00"))])
        XCTAssertEqual(groupe.map(\.colonne), [0, 1, 0])
        XCTAssertEqual(groupe.map(\.sur), [2, 2, 2])
        // L'ordre donné est gardé dans le résultat.
        let melange = Disposition.colonnes([(h("10:00"), h("12:00")), (h("09:00"), h("11:00"))])
        XCTAssertEqual(melange.map(\.colonne), [1, 0])
    }

    // MARK: Terminé

    func testLigneAuFormatExactDuContrat() {
        let ligne = TachesTerminees.ligne(tache(), heure: date("2026-11-03T10:15:30Z"))
        XCTAssertEqual(ligne, #"{"canal":"pilote","classe":"tache_terminee","extrait":"Appeler les 9 inscrits","heure":"2026-11-03T11:15:30+01:00","qui":"Sacha","ref":"ABC-123","calendrier":"Appels","debut":"2026-11-03T12:00:00+01:00"}"#)
    }

    func testLigneEchappeeSurUneSeuleLigne() throws {
        let t = tache(titre: "Rendre \"Maison Exemple\"\net la suite / 2")
        let ligne = TachesTerminees.ligne(t, heure: Date())
        XCTAssertFalse(ligne.contains("\n"))
        let objet = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ligne.utf8)) as? [String: String])
        XCTAssertEqual(objet["extrait"], t.titre)
        XCTAssertEqual(Set(objet.keys), ["canal", "classe", "extrait", "heure", "qui", "ref", "calendrier", "debut"])
    }

    func testTerminerAjouteUneSeuleLigneSansReecrire() throws {
        let entrants = dossier.appendingPathComponent("entrants.jsonl")
        let avant = #"{"canal":"whatsapp","classe":"travail","extrait":"déjà là"}"# + "\n"
        try avant.write(to: entrants, atomically: true, encoding: .utf8)

        let tt = TachesTerminees(dossier: dossier)
        let t = tache()
        XCTAssertTrue(try tt.terminer(t, a: date("2026-11-03T10:15:30Z")))
        XCTAssertFalse(try tt.terminer(t, a: date("2026-11-03T10:20:00Z")), "deuxième clic : rien")

        let contenu = try String(contentsOf: entrants, encoding: .utf8)
        XCTAssertTrue(contenu.hasPrefix(avant), "les lignes existantes restent, intactes")
        let lignes = contenu.split(separator: "\n")
        XCTAssertEqual(lignes.count, 2)
        XCTAssertEqual(String(lignes[1]), TachesTerminees.ligne(t, heure: date("2026-11-03T10:15:30Z")))

        // L'état survit à une nouvelle lecture (relance de l'app).
        let relu = TachesTerminees(dossier: dossier).lire()
        XCTAssertEqual(relu, [t.id: "2026-11-03T11:15:30+01:00"])
        XCTAssertEqual(t.id, "ABC-123|2026-11-03T12:00:00+01:00")
    }

    func testAutreOccurrenceDuMemeEvenement() throws {
        let tt = TachesTerminees(dossier: dossier)
        XCTAssertTrue(try tt.terminer(tache(debut: "2026-11-03T07:00:00Z")))
        XCTAssertTrue(try tt.terminer(tache(debut: "2026-11-04T07:00:00Z")), "même événement, autre jour : autre tâche")
        let lignes = try String(contentsOf: tt.fichierEntrants, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lignes.count, 2)
        XCTAssertEqual(tt.lire().count, 2)
    }

    func testListesEtCalendriersDuContratSeulement() {
        XCTAssertEqual(CalendriersPlanning.listesTaches.map(\.nom), ["Appels", "KRYVA", "Freelance", "Contenu", "Papiers"])
        XCTAssertEqual(CalendriersPlanning.calendriersEvenements.map(\.nom), ["Salle", "Rendez-vous", "Perso"])
        XCTAssertTrue(CalendriersPlanning.tache("Appels"))
        XCTAssertFalse(CalendriersPlanning.tache("Salle"), "Salle est un calendrier d'événements, pas une liste de tâches")
        XCTAssertTrue(CalendriersPlanning.evenement("Rendez-vous"))
        XCTAssertFalse(CalendriersPlanning.evenement("KRYVA"), "un calendrier d'événements « KRYVA » ne s'affiche pas")
        XCTAssertFalse(CalendriersPlanning.tache("Rappels") || CalendriersPlanning.evenement("Calendrier"))
    }

    func testDocumentEstLURLSinonLePremierLien() {
        let notes = NotesPlanning.lire("Docs :\nhttps://exemple.fr/fiche\nhttps://exemple.fr/liste")
        let sansURL = TachePlanning(genre: .tache, ref: "R", idLocal: "L", titre: "T", debut: Date(), fin: Date(), calendrier: "KRYVA",
                                    journee: true, url: nil, notes: notes)
        XCTAssertEqual(sansURL.document?.absoluteString, "https://exemple.fr/fiche")
        let avecURL = TachePlanning(genre: .tache, ref: "R", idLocal: "L", titre: "T", debut: Date(), fin: Date(), calendrier: "KRYVA",
                                    journee: true, url: URL(string: "file:///tmp/a.pdf"), notes: notes)
        XCTAssertEqual(avecURL.document?.absoluteString, "file:///tmp/a.pdf")
    }

    // MARK: Rappels cochés ailleurs (iPhone)

    func testDepuisPoseUneFoisPuisStable() throws {
        let tt = TachesTerminees(dossier: dossier)
        let premier = try tt.depuis(date("2026-11-02T18:00:00Z"))
        XCTAssertEqual(premier, date("2026-11-02T18:00:00Z"))
        XCTAssertEqual(try tt.depuis(date("2026-11-05T09:00:00Z")), premier, "le point de départ ne bouge plus")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tt.fichierEntrants.path), "poser le point de départ n'écrit aucune ligne")
    }

    func testNouvellesCochesSeulementApresLeDepartEtUneFois() throws {
        let depuis = date("2026-11-02T18:00:00Z")
        let avant = tache(ref: "AVANT"), apres = tache(ref: "APRES"), dejaSignale = tache(ref: "DEJA")
        var evenement = tache(ref: "EVT")
        evenement = TachePlanning(genre: .evenement, ref: evenement.ref, idLocal: "x", titre: "Salle", debut: evenement.debut,
                                  fin: evenement.fin, calendrier: "Salle", journee: false, url: nil, notes: NotesPlanning())
        let cochees: [(tache: TachePlanning, le: Date)] = [
            (avant, date("2026-11-02T17:59:59Z")), (apres, date("2026-11-03T10:00:00Z")),
            (dejaSignale, date("2026-11-03T10:05:00Z")), (evenement, date("2026-11-03T10:06:00Z")),
        ]
        let nouvelles = TachesTerminees.nouvellesCoches(cochees, etat: [dejaSignale.id: "2026-11-03T11:05:00+01:00"], depuis: depuis)
        XCTAssertEqual(nouvelles.map(\.tache.ref), ["APRES"])

        // La ligne porte l'heure de la coche (pas l'heure de lecture), puis la coche n'est plus nouvelle.
        let tt = TachesTerminees(dossier: dossier)
        for n in nouvelles { try tt.terminer(n.tache, a: n.le) }
        let ligne = try String(contentsOf: tt.fichierEntrants, encoding: .utf8)
        XCTAssertTrue(ligne.contains(#""heure":"2026-11-03T11:00:00+01:00""#))
        XCTAssertFalse(TachesTerminees.nouvellesCoches(cochees, etat: tt.lire(), depuis: depuis).contains { $0.tache.ref == "APRES" })
    }
}
