import XCTest
import SQLite3

/// 04/11 : le suivi de chaque vidéo postée. Les chiffres viennent de stats.sqlite (lecture seule), les verdicts de la base de Pilote.
final class SuiviVideoTests: XCTestCase {
    private var dossier: URL!

    override func setUpWithError() throws {
        dossier = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-suivi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dossier) }

    // MARK: Calculs purs

    func testLesPaliersSontCalculesDepuisLaPublication() {
        XCTAssertEqual(SuiviVideo.delaiHeures(publieLe: "2026-10-30T18:30", releveLe: "2026-11-01T18:30"), 48)
        XCTAssertEqual(PalierReleve.depuis(heures: 48), .h48)
        XCTAssertEqual(PalierReleve.depuis(heures: 24), .h48)
        XCTAssertEqual(PalierReleve.depuis(heures: 96), .h48)
        XCTAssertEqual(PalierReleve.depuis(heures: 168), .j7)
        XCTAssertEqual(PalierReleve.depuis(heures: 3), .autre)
        XCTAssertEqual(PalierReleve.depuis(heures: 100), .autre)
        XCTAssertEqual(PalierReleve.depuis(heures: nil), .autre)
        XCTAssertNil(SuiviVideo.delaiHeures(publieLe: "n'importe quoi", releveLe: "2026-11-01T18:30"))
        XCTAssertEqual(ReleveVideo(delaiHeures: 3).delaiTexte, "3 h")
        XCTAssertEqual(ReleveVideo(delaiHeures: 48).delaiTexte, "2 j")
        XCTAssertEqual(ReleveVideo(delaiHeures: nil).delaiTexte, "?")
    }

    func testLesBornesDUnePeriodeDeConversions() {
        XCTAssertEqual(SuiviVideo.bornes("2026-10-21..27")?.fin, "2026-10-27")
        XCTAssertEqual(SuiviVideo.bornes("2026-09-28..10-27")?.fin, "2026-10-27")
        XCTAssertEqual(SuiviVideo.bornes("2026-10-21")?.debut, "2026-10-21")
        XCTAssertEqual(SuiviVideo.bornes("2026-10-21")?.fin, "2026-10-21")
        XCTAssertNil(SuiviVideo.bornes("semaine 43"))
        XCTAssertNil(SuiviVideo.bornes("2026-10-21..abc"))
    }

    private let conversions: [ConversionLigne] = [
        ConversionLigne(periode: "2026-09-28..10-27", source: "tiktok", clics: 163, inscriptions: nil),
        ConversionLigne(periode: "2026-10-21..27", source: "tiktok", clics: 100, inscriptions: nil),
        ConversionLigne(periode: "2026-10-21..27", source: "instagram", clics: 198, inscriptions: nil),
        ConversionLigne(periode: "2026-10-21..27", source: ConversionLigne.total, clics: 402, inscriptions: 17),
        ConversionLigne(periode: "2026-09-28..10-27", source: ConversionLigne.total, clics: 983, inscriptions: nil),
    ]

    func testLesConversionsPrennentLaPeriodeLaPlusCourteQuiCouvreLaPublication() {
        let l = SuiviVideo.conversions(publieLe: "2026-10-24T18:00", compteId: "tiktok_perso", toutes: conversions)
        XCTAssertEqual(l.map(\.source), ["tiktok", ConversionLigne.total])
        XCTAssertEqual(l.first?.clics, 100)                 // la semaine, pas le mois
        XCTAssertEqual(l.last?.inscriptions, 17)
        // Avant la semaine : seul le mois couvre le jour.
        let avant = SuiviVideo.conversions(publieLe: "2026-10-10T18:00", compteId: "tiktok_perso", toutes: conversions)
        XCTAssertEqual(avant.first?.clics, 163)
        // Instagram KRYVA = la source « instagram » ; un compte sans source ne garde que le total.
        XCTAssertEqual(SuiviVideo.conversions(publieLe: "2026-10-24T18:00", compteId: "insta_kryva", toutes: conversions).first?.clics, 198)
        XCTAssertEqual(SuiviVideo.conversions(publieLe: "2026-10-24T18:00", compteId: "linkedin_kryva", toutes: conversions).map(\.source), [ConversionLigne.total])
    }

    func testUnPostRecentSansPeriodeRelevéNAPasDeConversions() {
        XCTAssertTrue(SuiviVideo.conversions(publieLe: "2026-10-30T18:30", compteId: "tiktok_perso", toutes: conversions).isEmpty)
    }

    func testLeSujetDuPlanningSeRetrouveParJourEtCompte() {
        let planning = [Video(id: "a", jour: "2026-10-30", compte: "perso", sujet: "Pyramide Claude Code", statut: "publiee"),
                        Video(id: "b", jour: "2026-10-30", compte: "kryva", sujet: "Devis en direct", statut: "publiee"),
                        Video(id: "c", jour: "2026-10-31", compte: "perso", sujet: "Annulée", statut: "annulee")]
        XCTAssertEqual(SuiviVideo.sujetPlanning(publieLe: "2026-10-30T18:30", famille: "perso", planning: planning), "Pyramide Claude Code")
        XCTAssertEqual(SuiviVideo.sujetPlanning(publieLe: "2026-10-30T18:30", famille: "kryva", planning: planning), "Devis en direct")
        XCTAssertNil(SuiviVideo.sujetPlanning(publieLe: "2026-10-31T18:30", famille: "perso", planning: planning))
        XCTAssertNil(SuiviVideo.sujetPlanning(publieLe: "2026-11-02T18:30", famille: "perso", planning: planning))
    }

    // MARK: Lecture de stats.sqlite et verdicts

    /// Une copie minimale du schéma de reseaux-stats/stats.py, avec trois posts : un à 48 h et 7 j, un seul relevé à 3 h, un archivé.
    private func creerStats() throws -> URL {
        let chemin = dossier.appendingPathComponent("stats.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(chemin.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE comptes (id TEXT PRIMARY KEY, reseau TEXT NOT NULL, compte TEXT NOT NULL, pseudo TEXT);
        CREATE TABLE videos (id INTEGER PRIMARY KEY, compte_id TEXT NOT NULL, ref TEXT NOT NULL, titre TEXT, format TEXT, publie_le TEXT,
          duree_s REAL, promo_eur REAL DEFAULT 0, visible INTEGER DEFAULT 1, fichier TEXT, notes TEXT, UNIQUE(compte_id, ref));
        CREATE TABLE releves (id INTEGER PRIMARY KEY, video_id INTEGER NOT NULL, releve_le TEXT NOT NULL, source TEXT NOT NULL,
          vues INTEGER, likes INTEGER, commentaires INTEGER, partages INTEGER, enregistrements INTEGER, temps_moyen_s REAL,
          vue_entier_pct REAL, r3s_pct REAL, abonnes_gagnes INTEGER, pour_toi_pct REAL, recherche_pct REAL);
        CREATE TABLE conversions (jour TEXT NOT NULL, source TEXT NOT NULL, clics INTEGER, inscriptions INTEGER);
        INSERT INTO comptes VALUES ('tiktok_perso','TikTok','perso','@sacha'), ('insta_kryva','Instagram','KRYVA','@kryva');
        INSERT INTO videos (id, compte_id, ref, titre, format, publie_le, duree_s, visible) VALUES
          (1,'tiktok_perso','T1','Pyramide','Testé','2026-10-30T18:30',42.0,1),
          (2,'insta_kryva','I1','Devis ép. 3','Devis en direct','2026-10-30T18:30',55.0,1),
          (3,'insta_kryva','I0','Vieux post','', '2026-10-09T15:43',30.0,0);
        INSERT INTO releves (video_id, releve_le, source, vues, temps_moyen_s, vue_entier_pct, r3s_pct, abonnes_gagnes) VALUES
          (1,'2026-10-30T21:30','tiktok-studio',120,NULL,NULL,NULL,0),
          (1,'2026-11-01T19:00','tiktok-studio',680,5.46,6.1,71.0,1),
          (1,'2026-11-06T18:30','tiktok-studio',900,5.9,6.4,70.0,2),
          (2,'2026-10-30T21:30','insta-web',50,NULL,NULL,NULL,NULL);
        INSERT INTO conversions VALUES ('2026-10-21..27','tiktok',163,NULL), ('2026-10-21..27','total',402,17);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(db)))
        return chemin
    }

    private func stock() throws -> Stockage {
        Stockage(base: try Base(chemin: dossier.appendingPathComponent("pilote.sqlite")))
    }

    func testLesPostsSontLusAvecLeursReleves48hEt7j() throws {
        let stats = try creerStats()
        let s = try stock()
        _ = try s.enregistrerVideo(["jour": "2026-10-30", "compte": "perso", "sujet": "Ma pyramide Claude Code", "statut": "publiee"])
        let charge = SuiviVideo.charger(stock: s, chemin: stats)
        XCTAssertNil(charge.erreur)
        XCTAssertEqual(charge.posts.count, 3)
        let t1 = try XCTUnwrap(charge.posts.first { $0.ref == "T1" })
        XCTAssertEqual(t1.releves.count, 3)
        XCTAssertEqual(t1.releve(.h48)?.vues, 680)             // le relevé à ~48 h, pas celui à 3 h
        XCTAssertEqual(t1.releve(.j7)?.vues, 900)              // 7 j (168 h après la publication)
        XCTAssertEqual(t1.releveRetention?.tempsMoyenS, 5.9)   // le dernier relevé qui donne la rétention
        XCTAssertEqual(t1.dernier?.vues, 900)
        XCTAssertEqual(t1.sujetPlanning, "Ma pyramide Claude Code")
        XCTAssertTrue(t1.conversions.isEmpty)                  // publié le 30/10 : aucune période de conversions ne le couvre encore
        XCTAssertEqual(t1.famille, "perso")
        let i1 = try XCTUnwrap(charge.posts.first { $0.ref == "I1" })
        XCTAssertNil(i1.releve(.h48))                          // un seul relevé, à 3 h : pas de 48 h
        XCTAssertEqual(i1.famille, "kryva")
        let vieux = try XCTUnwrap(charge.posts.first { $0.ref == "I0" })
        XCTAssertFalse(vieux.visible)
        XCTAssertEqual(charge.posts.first?.publieLe, "2026-10-30T18:30")   // du plus récent au plus ancien
    }

    func testStatsSqliteNEstJamaisModifie() throws {
        let stats = try creerStats()
        let avant = try Data(contentsOf: stats)
        let s = try stock()
        _ = SuiviVideo.charger(stock: s, chemin: stats)
        try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "palier": "48h", "verdict": "marche"], chemin: stats)
        XCTAssertEqual(try Data(contentsOf: stats), avant)
    }

    func testLeVerdictSEcritSeCompleteEtSeRetrouveSurLaVideo() throws {
        let stats = try creerStats()
        let s = try stock()
        let v = try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "palier": "48h", "verdict": "moyen",
                                          "pourquoi": "680 vues à 48 h, 71 % restés après 3 s mais 6 % vont au bout.", "par": "Réseaux"], chemin: stats)
        XCTAssertEqual(v.verdict, "moyen")
        // Compléter : seuls les champs fournis changent.
        try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "palier": "48h", "lecon": "Hook bon, milieu trop long.", "decrochage_s": 12], chemin: stats)
        let apres = try XCTUnwrap(SuiviVideo.charger(stock: s, chemin: stats).posts.first { $0.ref == "T1" }?.verdict)
        XCTAssertEqual(apres.verdict, "moyen")
        XCTAssertEqual(apres.pourquoi, "680 vues à 48 h, 71 % restés après 3 s mais 6 % vont au bout.")
        XCTAssertEqual(apres.lecon, "Hook bon, milieu trop long.")
        XCTAssertEqual(apres.decrochageS, 12)
        XCTAssertEqual(apres.par, "Réseaux")
        XCTAssertFalse(apres.ecritLe.isEmpty)
        // Effacer le décrochage.
        try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "palier": "48h", "decrochage_s": NSNull()], chemin: stats)
        XCTAssertNil(try s.verdicts()["tiktok_perso|T1"]?.first?.decrochageS)
    }

    func testUnVerdictMalFormeOuUneVideoInconnueEstRefuse() throws {
        let stats = try creerStats()
        let s = try stock()
        XCTAssertThrowsError(try s.enregistrerVerdict(["ref": "T1", "verdict": "marche"], chemin: stats))
        XCTAssertThrowsError(try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "palier": "48h", "verdict": "super"], chemin: stats))
        XCTAssertThrowsError(try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "FAUTE", "palier": "48h", "verdict": "marche"], chemin: stats))
        XCTAssertThrowsError(try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "palier": "3h", "verdict": "marche"], chemin: stats))
        XCTAssertThrowsError(try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "verdict": "marche"], chemin: stats))   // ni palier ni relevé de base
        XCTAssertTrue(try s.verdicts().isEmpty)
    }

    func testLaListeFiltreCompteArchiveesEtSansVerdict() throws {
        let stats = try creerStats()
        let s = try stock()
        try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "palier": "48h", "verdict": "marche"], chemin: stats)
        let apres = date("2026-11-07T10:00")
        XCTAssertEqual(try SuiviVideo.liste(stock: s, chemin: stats, maintenant: apres).map(\.ref).sorted(), ["I1", "T1"])          // l'archivée est cachée
        XCTAssertEqual(try SuiviVideo.liste(stock: s, archivees: true, chemin: stats, maintenant: apres).count, 3)
        XCTAssertEqual(try SuiviVideo.liste(stock: s, compte: "kryva", chemin: stats, maintenant: apres).map(\.ref), ["I1"])        // famille
        XCTAssertEqual(try SuiviVideo.liste(stock: s, compte: "tiktok_perso", chemin: stats, maintenant: apres).map(\.ref), ["T1"])  // compte_id
        // « Sans verdict » = un relevé (48 h ou 7 j) dont le verdict reste à écrire : le 7 j de T1 ; I1 n'a aucun relevé de palier.
        XCTAssertEqual(try SuiviVideo.liste(stock: s, sansVerdict: true, chemin: stats, maintenant: apres).map(\.ref), ["T1"])
        let t1 = try XCTUnwrap(try SuiviVideo.liste(stock: s, ref: "T1", chemin: stats, maintenant: apres).first)
        XCTAssertEqual(t1.verdict48h?.verdict, "marche")
        XCTAssertNil(t1.verdict7j)
        XCTAssertEqual(t1.etat48h, .fait)
        XCTAssertEqual(t1.etat7j, .aJuger)
        try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "palier": "7j", "verdict": "moyen", "analyse": "Fond : le milieu perd la moitié."], chemin: stats)
        XCTAssertTrue(try SuiviVideo.liste(stock: s, sansVerdict: true, chemin: stats, maintenant: apres).isEmpty)
    }

    // MARK: Un verdict par relevé, relevés dus

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Paris"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: s)!
    }

    private func post(_ publie: String, releves: [Double] = [], verdicts: [String] = []) -> PostVideo {
        var p = PostVideo(compteId: "tiktok_perso", ref: "X", publieLe: publie)
        p.releves = releves.map { ReleveVideo(delaiHeures: $0) }
        p.verdicts = verdicts.map { VerdictVideo(compteId: "tiktok_perso", ref: "X", palier: $0, verdict: "marche") }
        return p
    }

    func testLesEtatsDUnPalierSuiventLHorlogeEtLesRelevesFaits() {
        let p = post("2026-11-01T18:00")
        XCTAssertEqual(SuiviVideo.etat(p, .h48, maintenant: date("2026-11-02T18:00")), .aAttendre)   // 24 h
        XCTAssertEqual(SuiviVideo.etat(p, .h48, maintenant: date("2026-11-03T19:00")), .aReleve)     // 49 h
        XCTAssertEqual(SuiviVideo.etat(p, .h48, maintenant: date("2026-11-05T19:00")), .manque)      // 97 h : la fenêtre est passée
        XCTAssertEqual(SuiviVideo.etat(p, .j7, maintenant: date("2026-11-08T19:00")), .aReleve)      // 169 h
        XCTAssertEqual(SuiviVideo.etat(p, .j7, maintenant: date("2026-11-11T19:00")), .manque)       // 241 h
        // Relevé fait à 49 h : il reste le verdict ; une fois écrit, c'est fait.
        let fait = post("2026-11-01T18:00", releves: [49])
        XCTAssertEqual(SuiviVideo.etat(fait, .h48, maintenant: date("2026-11-03T19:00")), .aJuger)
        XCTAssertEqual(SuiviVideo.etat(post("2026-11-01T18:00", releves: [49], verdicts: ["48h"]), .h48, maintenant: date("2026-11-03T19:00")), .fait)
        // Un coup d'œil à 30 h ne remplace pas le relevé à 48 h.
        XCTAssertEqual(SuiviVideo.etat(post("2026-11-01T18:00", releves: [30]), .h48, maintenant: date("2026-11-03T19:00")), .aReleve)
        // Le 48 h fait ne dit rien du 7 j.
        XCTAssertEqual(SuiviVideo.etat(post("2026-11-01T18:00", releves: [49], verdicts: ["48h"]), .j7, maintenant: date("2026-11-08T19:00")), .aReleve)
        // Une date de publication illisible ne déclenche rien.
        XCTAssertEqual(SuiviVideo.etat(post("?"), .h48, maintenant: date("2026-11-03T19:00")), .aAttendre)
    }

    func testUneLectureTropPrecoceNeFaitPasUn48h() {
        var p = post("2026-11-01T18:00", verdicts: ["autre"])
        p.verdicts[0].verdict = "trop_tot"
        XCTAssertEqual(p.verdictPrecoce?.verdict, "trop_tot")
        XCTAssertEqual(p.verdict?.verdict, "trop_tot")                                                        // visible comme dernier recours
        XCTAssertNil(p.verdict(.h48))
        XCTAssertEqual(SuiviVideo.etat(p, .h48, maintenant: date("2026-11-03T19:00")), .aReleve)               // le vrai 48 h reste à faire
    }

    func testLesRelevesDusParDefautEtEnRattrapage() {
        let maintenant = date("2026-11-04T10:00")
        var recent = post("2026-11-02T08:00")                       // 50 h : relevé 48 h à faire
        recent.ref = "RECENT"
        var aJuger = post("2026-10-30T18:30", releves: [48.5])      // relevé 48 h fait, verdict à écrire
        aJuger.ref = "JUGER"
        var ancien = post("2026-09-20T18:00")                       // 45 jours, jamais relevé
        ancien.ref = "ANCIEN"
        var archive = post("2026-11-02T08:00"); archive.ref = "ARCHIVE"; archive.visible = false
        let dus = SuiviVideo.dus([ancien, aJuger, recent, archive], maintenant: maintenant)
        XCTAssertEqual(dus.map { $0.ref + ":" + $0.palier + ":" + $0.etat.rawValue }, ["RECENT:48h:a_relever", "JUGER:48h:a_juger"])   // à relever d'abord ; archivés et anciens ignorés
        XCTAssertEqual(dus.first?.dueLe, "2026-11-04T08:00")
        XCTAssertEqual(dus.first?.limiteLe, "2026-11-06T08:00")
        // Rattrapage : l'ancien post a manqué ses deux relevés ; le 7 j du récent est « à attendre ».
        let tout = SuiviVideo.dus([ancien, aJuger, recent, archive], maintenant: maintenant, tout: true).map { $0.ref + ":" + $0.palier + ":" + $0.etat.rawValue }
        XCTAssertEqual(tout.prefix(2), ["RECENT:48h:a_relever", "JUGER:48h:a_juger"])
        XCTAssertTrue(tout.contains("ANCIEN:48h:manque"))
        XCTAssertTrue(tout.contains("ANCIEN:7j:manque"))
        XCTAssertTrue(tout.contains("RECENT:7j:a_attendre"))
        XCTAssertFalse(tout.contains { $0.hasPrefix("ARCHIVE") })
    }

    func testLePalierDUnVerdictSeDeduitDuReleveDeBaseEtChaquePalierGardeLeSien() throws {
        let stats = try creerStats()
        let s = try stock()
        try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "verdict": "moyen", "base_releve_le": "2026-11-01T19:00"], chemin: stats)   // 48,5 h
        try s.enregistrerVerdict(["compte_id": "tiktok_perso", "ref": "T1", "verdict": "marche", "base_releve_le": "2026-11-06T18:30",
                                  "analyse": "Fond au 7 j."], chemin: stats)                                                                            // 168 h
        let vs = try XCTUnwrap(s.verdicts()["tiktok_perso|T1"])
        XCTAssertEqual(vs.map(\.palier), ["48h", "7j"])
        XCTAssertEqual(vs.map(\.verdict), ["moyen", "marche"])
        XCTAssertEqual(vs.last?.analyse, "Fond au 7 j.")
        let t1 = try XCTUnwrap(SuiviVideo.charger(stock: s, chemin: stats).posts.first { $0.ref == "T1" })
        XCTAssertEqual(t1.verdict(.h48)?.verdict, "moyen")
        XCTAssertEqual(t1.verdict?.verdict, "marche")        // le plus avancé : celui du 7 j
    }

    func testLAncienneTableDeVerdictsPasseAUnVerdictParPalier() throws {
        let chemin = dossier.appendingPathComponent("ancienne.sqlite")
        do {
            let b = try Base(chemin: chemin)
            try b.executer("DROP TABLE video_verdicts")
            try b.executer("""
                CREATE TABLE video_verdicts (compte_id TEXT NOT NULL, ref TEXT NOT NULL, verdict TEXT NOT NULL DEFAULT '', pourquoi TEXT NOT NULL DEFAULT '',
                  lecon TEXT NOT NULL DEFAULT '', decrochage_s REAL, decrochage_note TEXT NOT NULL DEFAULT '', base_releve_le TEXT NOT NULL DEFAULT '',
                  ecrit_le TEXT NOT NULL DEFAULT '', par TEXT NOT NULL DEFAULT '', PRIMARY KEY (compte_id, ref))
                """)
            try b.executer("INSERT INTO video_verdicts (compte_id, ref, verdict, pourquoi) VALUES ('tiktok_perso', 'T1', 'moyen', 'avant')")
        }
        let b2 = try Base(chemin: chemin)
        let l = try b2.lignes("SELECT palier, verdict, pourquoi FROM video_verdicts")
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l.first?["palier"] as? String, "48h")
        XCTAssertEqual(l.first?["pourquoi"] as? String, "avant")
        XCTAssertTrue(try b2.lignes("SELECT name FROM sqlite_master WHERE name = 'video_verdicts_ancienne'").isEmpty)
    }

    func testFichierAbsentDonneUneErreurClaire() throws {
        let s = try stock()
        let charge = SuiviVideo.charger(stock: s, chemin: dossier.appendingPathComponent("absent.sqlite"))
        XCTAssertTrue(charge.posts.isEmpty)
        XCTAssertNotNil(charge.erreur)
        XCTAssertThrowsError(try SuiviVideo.liste(stock: s, chemin: dossier.appendingPathComponent("absent.sqlite")))
    }
}
