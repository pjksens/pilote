// Tests du Radar : le calcul du ratio (règles du guide « Le Radar »), le rangement des relevés, la boîte à idées, les sources.
import XCTest

final class RadarCalculTests: XCTestCase {
    let t0 = Dates.iso.date(from: "2026-10-29T12:00:00Z")!

    func post(_ id: String, vues: Int?, age: Double, likes: Int? = nil, compte: String = "k:instagram:a", plateforme: String = "instagram") -> RadarCalcul.Post {
        RadarCalcul.Post(id: id, compteId: compte, plateforme: plateforme, publieLe: t0.addingTimeInterval(-age * 3600), releveLe: t0,
                         vues: vues, likes: likes, commentaires: nil)
    }

    /// 5 références anciennes (hors fenêtre) du guide : 10k, 12k, 15k, 18k, 50k.
    var refsGuide: [RadarCalcul.Post] {
        [10_000, 12_000, 15_000, 18_000, 50_000].enumerated().map { post("r\($0.offset)", vues: $0.element, age: 100 + Double($0.offset) * 24) }
    }

    func testMedianeImpaireEtPaire() {
        XCTAssertEqual(RadarCalcul.mediane([5, 1, 3]), 3)
        XCTAssertEqual(RadarCalcul.mediane([1, 2, 3, 10]), 2.5)
        XCTAssertNil(RadarCalcul.mediane([]))
    }

    func testExempleDuGuideRatioQuatre() {
        let candidat = post("c", vues: 60_000, age: 20)
        let e = RadarCalcul.evaluer(candidat, parmi: refsGuide + [candidat])
        XCTAssertEqual(e.mediane, 15_000)
        XCTAssertEqual(e.ratio, 4.0)
        XCTAssertEqual(e.references, 5)
        XCTAssertTrue(e.estPiste)
    }

    func testLeCandidatNEstJamaisSaPropreReference() {
        let candidat = post("c", vues: 60_000, age: 20)
        // même identifiant présent deux fois dans la liste : toujours exclu
        let e = RadarCalcul.evaluer(candidat, parmi: refsGuide + [candidat, candidat])
        XCTAssertEqual(e.references, 5)
        XCTAssertEqual(e.mediane, 15_000)
    }

    func testUnIdentifiantEnDoubleNeCompteQuUneFois() {
        let candidat = post("c", vues: 60_000, age: 20)
        let e = RadarCalcul.evaluer(candidat, parmi: refsGuide + [refsGuide[0], refsGuide[0], candidat])
        XCTAssertEqual(e.references, 5)
    }

    func testMoinsDeCinqReferencesPasDeRatio() {
        let candidat = post("c", vues: 60_000, age: 20)
        let e = RadarCalcul.evaluer(candidat, parmi: Array(refsGuide.prefix(4)) + [candidat])
        XCTAssertNil(e.ratio)
        XCTAssertEqual(e.references, 4)
        XCTAssertNotNil(e.raison)
    }

    func testMedianeNulleRatioIndetermine() {
        let candidat = post("c", vues: 1_000, age: 20)
        let zeros = (0..<5).map { post("z\($0)", vues: 0, age: 100 + Double($0)) }
        let e = RadarCalcul.evaluer(candidat, parmi: zeros + [candidat])
        XCTAssertNil(e.ratio, "diviser par 0 n'est pas « infini » : indéterminé")
    }

    func testVuesInconnuesNeSontPasDesZeros() {
        let inconnu = post("x", vues: nil, age: 20)
        XCTAssertNil(RadarCalcul.evaluer(inconnu, parmi: refsGuide + [inconnu]).ratio)
        // un post sans vues ne compte pas parmi les références des autres
        let candidat = post("c", vues: 60_000, age: 20)
        let e = RadarCalcul.evaluer(candidat, parmi: refsGuide + [inconnu, candidat])
        XCTAssertEqual(e.references, 5)
        XCTAssertEqual(e.mediane, 15_000)
    }

    func testAutreCompteOuAutrePlateformeNeCompteJamais() {
        let candidat = post("c", vues: 60_000, age: 20)
        let intrus = [post("i1", vues: 1, age: 50, compte: "k:instagram:b"), post("i2", vues: 1, age: 50, plateforme: "tiktok")]
        let e = RadarCalcul.evaluer(candidat, parmi: refsGuide + intrus + [candidat])
        XCTAssertEqual(e.references, 5)
        XCTAssertEqual(e.mediane, 15_000)
    }

    func testReferencesLimiteesAuxTrenteJours() {
        let candidat = post("c", vues: 60_000, age: 20)
        let vieux = post("v", vues: 1, age: 31 * 24)
        let e = RadarCalcul.evaluer(candidat, parmi: refsGuide + [vieux, candidat])
        XCTAssertEqual(e.references, 5)
        XCTAssertEqual(e.mediane, 15_000)
    }

    func testFenetreSixSoixanteDouzeHeures() {
        func retenu(_ age: Double) -> Bool {
            let c = post("c", vues: 60_000, age: age)
            return !RadarCalcul.classer([RadarCalcul.evaluer(c, parmi: refsGuide + [c])]).retenus.isEmpty
        }
        XCTAssertFalse(retenu(5.9))
        XCTAssertTrue(retenu(6))
        XCTAssertTrue(retenu(72))
        XCTAssertFalse(retenu(72.01))
    }

    func testTriRatioPuisVuesParHeure() {
        // deux posts de même ratio exact (×2) : le plus rapide (vues/h) passe devant
        let lent = post("lent", vues: 30_000, age: 60)
        let rapide = post("rapide", vues: 30_000, age: 10)
        let faible = post("faible", vues: 45_000, age: 12)
        let tous = refsGuide + [lent, rapide, faible]
        let r = RadarCalcul.classer(RadarCalcul.evaluer(tous)).retenus
        XCTAssertEqual(r.map(\.post.id), ["faible", "rapide", "lent"])
    }

    func testLeTopNeGardeQueLesRatiosAuDessusDeUnEtNEstJamaisComplete() {
        let bon = post("bon", vues: 60_000, age: 20)
        let egal = post("egal", vues: 15_000, age: 30)      // ratio exactement 1 : pas une piste
        let faible = post("faible", vues: 3_000, age: 40)
        let r = RadarCalcul.classer(RadarCalcul.evaluer(refsGuide + [bon, egal, faible])).retenus
        let top = RadarCalcul.top(r)
        XCTAssertEqual(r.count, 3, "classés : tous ceux qui ont un ratio dans la fenêtre")
        XCTAssertTrue(top.allSatisfy { ($0.ratio ?? 0) > 1 })
        XCTAssertFalse(top.contains { $0.post.id == "egal" || $0.post.id == "faible" })
        XCTAssertLessThan(top.count, 3, "pas de Top 3 rempli artificiellement")
    }

    func testGainSurVingtQuatreHeures() {
        let a = (le: t0, vues: 1_000)
        func gain(ecartH: Double, apres: Int = 5_000) -> Int? { RadarCalcul.gain24h(avant: a, apres: (le: t0.addingTimeInterval(ecartH * 3600), vues: apres)) }
        XCTAssertNil(gain(ecartH: 21.9))
        XCTAssertEqual(gain(ecartH: 22), 4_000)
        XCTAssertEqual(gain(ecartH: 26), 4_000)
        XCTAssertNil(gain(ecartH: 26.1))
        XCTAssertNil(gain(ecartH: 24, apres: 900), "compteur qui baisse : incohérent, pas de gain")
    }

    func testLikesPourMilleVuesEtVuesParHeure() {
        let e = RadarCalcul.evaluer(post("c", vues: 20_000, age: 10, likes: 800), parmi: [])
        XCTAssertEqual(e.likesPour1000Vues, 40)
        XCTAssertEqual(e.vuesParHeure, 2_000)
        XCTAssertNil(RadarCalcul.evaluer(post("d", vues: 0, age: 10, likes: 5), parmi: []).likesPour1000Vues)
        XCTAssertNil(RadarCalcul.evaluer(post("e", vues: 100, age: 10, likes: nil), parmi: []).likesPour1000Vues)
    }
}

final class RadarStockageTests: XCTestCase {
    let t0 = Dates.iso.date(from: "2026-10-29T12:00:00Z")!
    var chemin: URL!

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-radar-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
    }

    func neuf() throws -> Stockage { Stockage(base: try Base(chemin: chemin)) }

    func obs(_ id: String, vues: Int?, age: Double, compte: String = "renovo", plateforme: String = "instagram", source: String = "manuelle", releve: Date? = nil) -> RadarObservation {
        let r = releve ?? t0
        return RadarObservation(plateforme: plateforme, compte: compte, identifiantPost: id, url: "https://www.instagram.com/reel/\(id)/", legende: "légende \(id)",
                                publieLe: r.addingTimeInterval(-age * 3600), releveLe: r, vues: vues, likes: vues.map { $0 / 25 }, commentaires: nil, source: source)
    }

    /// Un compte avec 5 références anciennes (10k…50k) et un post à 60k vues publié depuis 20 h.
    func garnir(_ s: Stockage, espace: String = "kryva", source: String = "manuelle") throws {
        for (i, v) in [10_000, 12_000, 15_000, 18_000, 50_000].enumerated() {
            try s.radarObserve(obs("R\(i)", vues: v, age: 100 + Double(i) * 24, source: source), espace: espace, maintenant: t0)
        }
        try s.radarObserve(obs("HOT", vues: 60_000, age: 20, source: source), espace: espace, maintenant: t0)
    }

    func testClassementDeBoutEnBout() throws {
        let s = try neuf()
        try garnir(s)
        let c = try s.radarClassement(espace: "kryva", maintenant: t0)
        XCTAssertEqual(c.top.map(\.postId), ["instagram:HOT"])
        XCTAssertEqual(c.top.first?.ratio, 4.0)
        XCTAssertEqual(c.top.first?.rang, 1)
        XCTAssertEqual(c.ecartes.count, 5, "les 5 références sont au-delà de 72 h")
        XCTAssertTrue(c.ecartes.allSatisfy { ($0.raison ?? "").contains("plus de 72 h") })
        XCTAssertEqual(try s.radarClassement(espace: "perso", maintenant: t0).nbPosts, 0, "les espaces sont séparés")
    }

    func testRejouerUnRelevéNeCréeRien() throws {
        let s = try neuf()
        XCTAssertTrue(try s.radarObserve(obs("A", vues: 10, age: 10), espace: "kryva", maintenant: t0))
        XCTAssertFalse(try s.radarObserve(obs("A", vues: 10, age: 10), espace: "kryva", maintenant: t0))
        let n = try s.base.lignes("SELECT COUNT(*) AS n FROM radar_releves").first?["n"] as? Int
        XCTAssertEqual(n, 1)
    }

    func testLesRelevésSeCumulentSansEcraserLeDernierFaitFoi() throws {
        let s = try neuf()
        try garnir(s)
        let plus_tard = t0.addingTimeInterval(24 * 3600)
        try s.radarObserve(obs("HOT", vues: 90_000, age: 44, releve: plus_tard), espace: "kryva", maintenant: plus_tard)
        let n = try s.base.lignes("SELECT COUNT(*) AS n FROM radar_releves WHERE post_id = 'instagram:HOT'").first?["n"] as? Int
        XCTAssertEqual(n, 2, "l'ancien relevé est conservé")
        let c = try s.radarClassement(espace: "kryva", maintenant: plus_tard)
        XCTAssertEqual(c.top.first?.vues, 90_000)
        XCTAssertEqual(c.top.first?.ageHeures, 44)
    }

    func testValeursRefuseesPlutotQueDeviner() throws {
        let s = try neuf()
        XCTAssertThrowsError(try s.radarObserve(obs("A", vues: -5, age: 10), espace: "kryva", maintenant: t0))
        XCTAssertThrowsError(try s.radarObserve(obs("A", vues: 5, age: -3), espace: "kryva", maintenant: t0), "publié après son relevé")
        XCTAssertThrowsError(try s.radarObserve(obs("A", vues: 5, age: 3, releve: t0.addingTimeInterval(3600)), espace: "kryva", maintenant: t0), "relevé dans le futur")
        XCTAssertThrowsError(try s.radarObserve(obs("A", vues: 5, age: 3, plateforme: "youtube"), espace: "kryva", maintenant: t0))
        XCTAssertThrowsError(try s.radarObserve(obs("A", vues: 5, age: 3), espace: "inconnu", maintenant: t0))
    }

    func testCompteSuspenduNeSortPasDuTiroirSansOrdre() throws {
        let s = try neuf()
        try garnir(s)
        try s.radarChangeEtatCompte("kryva:instagram:renovo", etat: "suspendu")
        try s.radarObserve(obs("NOUV", vues: 5, age: 10), espace: "kryva", maintenant: t0)
        XCTAssertEqual(try s.radarCompte("kryva:instagram:renovo")?.etat, "suspendu")
        XCTAssertEqual(try s.radarClassement(espace: "kryva", maintenant: t0).nbPosts, 0)
        try s.radarAjouteCompte(espace: "kryva", plateforme: "instagram", identifiant: "renovo")
        XCTAssertEqual(try s.radarCompte("kryva:instagram:renovo")?.etat, "actif")
    }

    func testIdentifiantsNormalises() {
        XCTAssertEqual(Stockage.radarNormaliseIdentifiant("@Renovo"), "renovo")
        XCTAssertEqual(Stockage.radarNormaliseIdentifiant(" https://www.instagram.com/Renovo/ "), "renovo")
        XCTAssertEqual(Stockage.radarIdentifiantPost("https://www.instagram.com/reel/AbC123/?igsh=x"), "AbC123")
        XCTAssertEqual(Stockage.radarIdentifiantPost("https://www.tiktok.com/@u/video/7123456"), "7123456")
        XCTAssertEqual(Stockage.radarIdentifiantPost("AbC123"), "AbC123")
    }

    func testLaSimulationNeSeMelangeJamaisAuxVraisChiffres() throws {
        let s = try neuf()
        try garnir(s, source: "factice")
        XCTAssertEqual(try s.radarClassement(espace: "kryva", maintenant: t0).nbPosts, 0)
        let sim = try s.radarClassement(espace: "kryva", simulation: true, maintenant: t0)
        XCTAssertEqual(sim.top.count, 1)
        XCTAssertTrue(sim.avertissements.contains { $0.contains("SIMULATION") })
        XCTAssertEqual(try s.radarPurgeSimulation(), 6)
        XCTAssertEqual(try s.radarClassement(espace: "kryva", simulation: true, maintenant: t0).nbPosts, 0)
    }

    func testBoiteAIdees() throws {
        let s = try neuf()
        try garnir(s)
        let (idee, nouvelle) = try s.radarEnregistreIdee(postId: "instagram:HOT", espace: "kryva", concept: "devis rapide", maintenant: t0)
        XCTAssertTrue(nouvelle)
        XCTAssertEqual(idee.sourceFigee.vues, 60_000)
        XCTAssertEqual(idee.sourceFigee.ratio, 4.0)
        XCTAssertEqual(idee.sourceFigee.createur, "renovo")
        XCTAssertEqual(idee.statut, "a_ecrire")
        XCTAssertEqual(idee.revision, 0)

        // enregistrer deux fois : pas de doublon, le brouillon n'est pas touché
        let ecrite = try s.radarEcritIdee(id: idee.id, brouillon: "Ma version", statut: "en_cours", revision: 0, maintenant: t0)
        XCTAssertEqual(ecrite.revision, 1)
        let (encore, nouvelle2) = try s.radarEnregistreIdee(postId: "instagram:HOT", espace: "kryva", maintenant: t0)
        XCTAssertFalse(nouvelle2)
        XCTAssertEqual(encore.id, idee.id)
        XCTAssertEqual(encore.brouillon, "Ma version")
        XCTAssertEqual(try s.radarIdees().count, 1)

        // la source reste figée même si le post évolue
        let plus_tard = t0.addingTimeInterval(24 * 3600)
        try s.radarObserve(obs("HOT", vues: 500_000, age: 44, releve: plus_tard), espace: "kryva", maintenant: plus_tard)
        XCTAssertEqual(try s.radarIdee(idee.id)?.sourceFigee.vues, 60_000)

        // conflit d'édition : rien d'écrit, message clair
        XCTAssertThrowsError(try s.radarEcritIdee(id: idee.id, brouillon: "écrase", revision: 0, maintenant: t0)) { e in
            guard case ErreurRadar.conflit = e else { return XCTFail("conflit attendu, reçu \(e)") }
        }
        XCTAssertEqual(try s.radarIdee(idee.id)?.brouillon, "Ma version")
        XCTAssertThrowsError(try s.radarEcritIdee(id: idee.id, brouillon: nil, statut: "zzz", revision: 1, maintenant: t0))
        XCTAssertThrowsError(try s.radarEnregistreIdee(postId: "instagram:INCONNU", espace: "kryva", maintenant: t0))
    }

    func testLIdeeSurvitAuxPurgesEtLePostResteLie() throws {
        let s = try neuf()
        try garnir(s)
        let (idee, _) = try s.radarEnregistreIdee(postId: "instagram:HOT", espace: "kryva", maintenant: t0)
        try s.radarPurgeSimulation()
        XCTAssertNotNil(try s.radarIdee(idee.id))
        XCTAssertEqual(try s.radarClassement(espace: "kryva", maintenant: t0).top.first?.ideeId, idee.id)
    }

    func testAvertissementReleveAncien() throws {
        let s = try neuf()
        try garnir(s)
        let c = try s.radarClassement(espace: "kryva", maintenant: t0.addingTimeInterval(50 * 3600))
        XCTAssertTrue(c.avertissements.contains { $0.contains("Dernier relevé il y a 50 h") })
    }
}

final class RadarSourcesTests: XCTestCase {
    let t0 = Dates.iso.date(from: "2026-10-29T12:00:00Z")!

    func testSaisieManuelleAgeEnHeuresEtValeursAbsentes() throws {
        let json = """
        {"espace":"kryva","releve_le":"2026-10-29T12:00:00Z","posts":[
          {"plateforme":"instagram","compte":"@Renovo","id":"A","age_h":20,"vues":1000,"likes":null},
          {"plateforme":"TikTok","compte":"chantiertv","url":"https://www.tiktok.com/@chantiertv/video/777","publie_le":"2026-10-28T12:00:00Z"},
          {"plateforme":"instagram","compte":"renovo","id":"B","age_h":5,"vues":"12k"},
          {"plateforme":"instagram","compte":"renovo","id":"C","vues":5},
          {"plateforme":"youtube","compte":"x","id":"D","age_h":5},
          {"plateforme":"instagram","compte":"renovo","age_h":5}
        ]}
        """
        let lot = try SourceManuelle.lire(json: Data(json.utf8), maintenant: t0)
        XCTAssertEqual(lot.observations.count, 2)
        XCTAssertEqual(lot.erreurs.count, 4)
        let a = lot.observations[0]
        XCTAssertEqual(a.publieLe, t0.addingTimeInterval(-20 * 3600))
        XCTAssertEqual(a.vues, 1000)
        XCTAssertNil(a.likes, "null reste inconnu, jamais 0")
        XCTAssertNil(a.commentaires)
        let b = lot.observations[1]
        XCTAssertEqual(b.plateforme, "tiktok")
        XCTAssertNil(b.vues)
        XCTAssertEqual(b.releveLe, t0)
    }

    func testSaisieManuelleRefuseUnEspaceInconnu() {
        XCTAssertThrowsError(try SourceManuelle.lire(json: Data("{\"espace\":\"x\",\"posts\":[]}".utf8)))
        XCTAssertThrowsError(try SourceManuelle.lire(json: Data("{\"posts\":[]}".utf8)))
        XCTAssertThrowsError(try SourceManuelle.lire(json: Data("[]".utf8)))
    }

    func testInstagramDiscoveryNeGardeQueLesReelsEtLaisseLesVuesAbsentes() throws {
        let reponse = """
        {"business_discovery":{"media":{"data":[
          {"id":"1","caption":"un reel","permalink":"https://www.instagram.com/reel/AAA/","timestamp":"2026-10-28T10:00:00+0000","media_product_type":"REELS","like_count":40,"comments_count":3,"view_count":1500},
          {"id":"2","permalink":"https://www.instagram.com/reel/BBB/","timestamp":"2026-10-28T09:00:00+0000","media_product_type":"REELS","like_count":4},
          {"id":"3","permalink":"https://www.instagram.com/p/CCC/","timestamp":"2026-10-27T09:00:00+0000","media_product_type":"FEED","view_count":99999}
        ]}}}
        """
        let o = try InstagramDiscovery.observations(reponse: Data(reponse.utf8), compte: "renovo", releveLe: t0)
        XCTAssertEqual(o.count, 2)
        XCTAssertEqual(o[0].identifiantPost, "AAA")
        XCTAssertEqual(o[0].vues, 1500)
        XCTAssertEqual(o[0].publieLe, Dates.iso.date(from: "2026-10-28T10:00:00Z"))
        XCTAssertNil(o[1].vues, "view_count absent = inconnu")
        XCTAssertThrowsError(try InstagramDiscovery.observations(reponse: Data("{\"error\":{\"message\":\"nope\"}}".utf8), compte: "x", releveLe: t0))
        XCTAssertThrowsError(try InstagramDiscovery.observations(reponse: Data("{}".utf8), compte: "x", releveLe: t0))
    }

    func testSourceFacticeDeterministeEtMarquee() throws {
        let compte = RadarCompte(id: "kryva:instagram:renovo", espace: "kryva", plateforme: "instagram", identifiant: "renovo", nom: "", url: "",
                                 etat: "actif", verifieLe: "", notes: "", creeLe: "")
        let a = try SourceFactice().releve(comptes: [compte], maintenant: t0)
        let b = try SourceFactice().releve(comptes: [compte], maintenant: t0)
        XCTAssertEqual(a.observations.map(\.vues), b.observations.map(\.vues))
        XCTAssertEqual(a.observations.count, SourceFactice.ages.count)
        XCTAssertTrue(a.observations.allSatisfy { $0.source == "factice" })
    }

    func testSourcesEnAttenteRefusentDePartir() {
        XCTAssertFalse(SourcesRadar.enAttente.contains("scrapecreators"), "ScrapeCreators est branchée (clé et confirmation requises)")
        for nom in SourcesRadar.enAttente {
            XCTAssertThrowsError(try SourcesRadar.parNom(nom).releve(comptes: [], maintenant: t0)) { e in
                guard case ErreurRadar.sourceNonConfiguree = e else { return XCTFail("\(nom) devait refuser : \(e)") }
            }
        }
        XCTAssertThrowsError(try SourcesRadar.parNom("n_importe_quoi"))
    }
}

// MARK: Import indulgent (ce que la session Réseaux dépose : lien, date, tableau CSV)

final class RadarImportTests: XCTestCase {
    let t0 = Dates.iso.date(from: "2026-10-29T12:00:00Z")!

    func testLienEtDateAlorsQuePlateformeEtCompteSontDeduits() throws {
        let json = """
        [{"compte":"@Chantiertv","lien":"https://www.tiktok.com/@chantiertv/video/777","date":"2026-10-09T14:08","vues":"12 345","likes":300,"commentaires":""},
         {"lien":"https://www.tiktok.com/@autre/video/888","date":"2026-10-09T14:08:00+02:00","vues":10}]
        """
        let lot = try SourceManuelle.lire(json: Data(json.utf8), espaceParDefaut: "perso", maintenant: t0)
        XCTAssertEqual(lot.erreurs, [])
        XCTAssertEqual(lot.observations.count, 2)
        let a = lot.observations[0]
        XCTAssertEqual(a.plateforme, "tiktok")
        XCTAssertEqual(a.compte, "Chantiertv")
        XCTAssertEqual(a.vues, 12_345)
        XCTAssertNil(a.commentaires, "chaîne vide = inconnu")
        XCTAssertEqual(a.publieLe, Dates.iso.date(from: "2026-10-09T12:08:00Z"), "sans fuseau : heure de Paris (UTC+2 en octobre avant le 25)")
        XCTAssertEqual(lot.observations[1].compte, "autre", "compte TikTok déduit du lien")
        XCTAssertEqual(lot.observations[1].publieLe, Dates.iso.date(from: "2026-10-09T12:08:00Z"))
    }

    func testDateSansHeureRefusee() throws {
        let lot = try SourceManuelle.lire(json: Data(#"{"espace":"kryva","posts":[{"plateforme":"instagram","compte":"a","id":"x","date":"2026-10-09","vues":1}]}"#.utf8))
        XCTAssertEqual(lot.observations.count, 0)
        XCTAssertTrue(lot.erreurs.first?.contains("sans heure") == true)
    }

    func testSourceNommeeEtSourceFacticeInterdite() throws {
        let ok = try SourceManuelle.lire(json: Data(#"{"espace":"kryva","source":"reseaux-lecture-publique","posts":[{"plateforme":"instagram","compte":"a","id":"x","age_h":5}]}"#.utf8), maintenant: t0)
        XCTAssertEqual(ok.source, "reseaux-lecture-publique")
        XCTAssertEqual(ok.observations.first?.source, "reseaux-lecture-publique")
        XCTAssertEqual(try SourceManuelle.lire(json: Data(#"{"espace":"kryva","posts":[]}"#.utf8)).source, "manuelle")
        XCTAssertThrowsError(try SourceManuelle.lire(json: Data(#"{"espace":"kryva","source":"factice","posts":[]}"#.utf8)))
        XCTAssertThrowsError(try SourceManuelle.lire(json: Data(#"{"espace":"kryva","source":"Mauvais Nom!","posts":[]}"#.utf8)))
    }

    func testCsvAvecPointVirguleEtGuillemets() throws {
        let csv = #"""
        Compte;Lien;Date;Vues;Likes;Commentaires;Titre
        renovo;https://www.instagram.com/reel/AAA/;2026-10-28T09:30;15 000;400;12;"Un ; titre avec ""guillemets"""
        renovo;https://www.instagram.com/reel/BBB/;2026-10-28T10:30;;;;
        """#
        let lot = try SourceManuelle.lire(csv: csv, espaceParDefaut: "kryva", releveLe: t0, source: "reseaux-main")
        XCTAssertEqual(lot.erreurs, [])
        XCTAssertEqual(lot.observations.count, 2)
        XCTAssertEqual(lot.observations[0].vues, 15_000)
        XCTAssertEqual(lot.observations[0].legende, "Un ; titre avec \"guillemets\"")
        XCTAssertNil(lot.observations[1].vues, "case vide = inconnu, jamais 0")
        XCTAssertNil(lot.observations[1].likes)
        XCTAssertEqual(lot.observations[1].source, "reseaux-main")
        XCTAssertThrowsError(try SourceManuelle.lire(csv: csv, espaceParDefaut: nil))
    }

    func testDatesAvecFractionEtDecalageSansDeuxPoints() {
        XCTAssertEqual(RadarDates.lire("2025-05-27T18:41:50.000Z"), Dates.iso.date(from: "2025-05-27T18:41:50Z"))
        XCTAssertEqual(RadarDates.lire("2026-10-27T12:34:56+0000"), Dates.iso.date(from: "2026-10-27T12:34:56Z"))
        XCTAssertNil(RadarDates.lire("hier"))
        XCTAssertTrue(RadarDates.estSansHeure("2026-10-09"))
        XCTAssertFalse(RadarDates.estSansHeure("2026-10-09T10:00"))
    }
}

// MARK: ScrapeCreators (réseau simulé : aucun appel réel dans les tests)

final class TransportScripte: TransportRadar {
    var reponses: [(Int, String)]
    var appels: [URL] = []
    var entetesVus: [[String: String]] = []
    init(_ r: [(Int, String)]) { reponses = r }
    func get(_ url: URL, entetes: [String: String]) throws -> (statut: Int, corps: Data) {
        appels.append(url); entetesVus.append(entetes)
        guard !reponses.isEmpty else { throw URLError(.notConnectedToInternet) }
        let r = reponses.removeFirst()
        return (r.0, Data(r.1.utf8))
    }
}

final class RadarScrapeCreatorsTests: XCTestCase {
    let t0 = Dates.iso.date(from: "2026-10-29T12:00:00Z")!
    let cleSecrete = "sk_test_NE_DOIT_JAMAIS_APPARAITRE"

    func compte(_ plateforme: String = "instagram", _ ident: String = "renovo") -> RadarCompte {
        RadarCompte(id: "kryva:\(plateforme):\(ident)", espace: "kryva", plateforme: plateforme, identifiant: ident, nom: "", url: "",
                    etat: "actif", verifieLe: "", notes: "", creeLe: "")
    }

    /// Réponse « reels » Instagram : (code, âge en heures, vues, likes).
    func ig(_ items: [(String, Double, Int?, Int?)], charged: Int = 1, restant: Int = 99, maxId: String? = "SUITE") -> String {
        var racine: [String: Any] = ["success": true, "credits_charged": charged, "credits_remaining": restant]
        racine["items"] = items.map { (code, age, vues, likes) -> [String: Any] in
            var m: [String: Any] = ["code": code, "taken_at": Int(t0.timeIntervalSince1970 - age * 3600), "comment_count": 3]
            if let vues { m["play_count"] = vues }
            if let likes { m["like_count"] = likes }
            return m
        }
        if let maxId { racine["max_id"] = maxId }
        return String(decoding: try! JSONSerialization.data(withJSONObject: racine), as: UTF8.self)
    }

    func source(_ t: TransportScripte, cle: String? = nil, plafond: Int = 30, pages: Int = 2) -> SourceScrapeCreators {
        var s = SourceScrapeCreators()
        s.transport = t
        let c = cle ?? cleSecrete
        s.cle = { c }
        s.plafondCredits = plafond
        s.pagesMax = pages
        return s
    }

    func testSansCleAucunAppelReseau() {
        let t = TransportScripte([(200, ig([]))])
        var s = source(t)
        s.cle = { nil }
        XCTAssertThrowsError(try s.releve(comptes: [compte()], maintenant: t0)) { e in
            guard case ErreurRadar.sourceNonConfiguree(let m) = e else { return XCTFail("\(e)") }
            XCTAssertTrue(m.contains("saisie à la main"))
        }
        XCTAssertTrue(t.appels.isEmpty)
    }

    func testLectureDeLaCleDansLeFichier() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("cle-\(UUID().uuidString).env").path
        defer { try? FileManager.default.removeItem(atPath: f) }
        try "# commentaire\nAUTRE=1\nexport SCRAPECREATORS_API_KEY=\"abc123\"\n".write(toFile: f, atomically: true, encoding: .utf8)
        XCTAssertEqual(CleRadar.lire(fichier: f), "abc123")
        try "SCRAPECREATORS_API_KEY=\n".write(toFile: f, atomically: true, encoding: .utf8)
        XCTAssertNil(CleRadar.lire(fichier: f), "valeur vide = pas de clé")
        try "AUTRE=1\n".write(toFile: f, atomically: true, encoding: .utf8)
        XCTAssertNil(CleRadar.lire(fichier: f))
        XCTAssertNil(CleRadar.lire(fichier: f + ".absent"))
    }

    func testInstagramDeuxPagesCreditsEtEnTeteDeCle() throws {
        let t = TransportScripte([(200, ig([("AAA", 5, 1000, 40), ("BBB", 30, 800, nil)], restant: 99)),
                                  (200, ig([("CCC", 400, 500, 10)], restant: 98))])
        let r = try source(t).releve(comptes: [compte()], maintenant: t0)
        XCTAssertEqual(t.appels.count, 2, "la 1re page ne descend pas sous 30 jours : on lit la 2e")
        XCTAssertEqual(r.creditsDepenses, 2)
        XCTAssertEqual(r.creditsRestants, 98)
        XCTAssertEqual(r.erreurs, [])
        XCTAssertEqual(r.observations.count, 3)
        let a = r.observations[0]
        XCTAssertEqual(a.identifiantPost, "AAA")
        XCTAssertEqual(a.url, "https://www.instagram.com/reel/AAA/")
        XCTAssertEqual(a.vues, 1000)
        XCTAssertEqual(a.source, "scrapecreators")
        XCTAssertEqual(a.publieLe, t0.addingTimeInterval(-5 * 3600))
        XCTAssertNil(r.observations[1].likes, "like_count absent = inconnu")
        XCTAssertEqual(t.entetesVus.first?["x-api-key"], cleSecrete)
        XCTAssertTrue(t.appels[0].absoluteString.hasPrefix("https://api.scrapecreators.com/v1/instagram/user/reels?handle=renovo"))
        XCTAssertTrue(t.appels[1].absoluteString.contains("max_id=SUITE"))
        XCTAssertFalse(t.appels.map(\.absoluteString).joined().contains(cleSecrete), "la clé ne voyage jamais dans l'adresse")
    }

    func testPasDeDeuxiemePageQuandLaPremiereDepasseTrenteJours() throws {
        let t = TransportScripte([(200, ig([("AAA", 5, 1000, 1), ("OLD", 800, 10, 1)])), (200, ig([]))])
        let r = try source(t).releve(comptes: [compte()], maintenant: t0)
        XCTAssertEqual(t.appels.count, 1)
        XCTAssertEqual(r.creditsDepenses, 1)
    }

    func testPlafondDeCreditsArreteLeReleve() throws {
        let page = ig([("A", 5, 1, 1), ("OLD", 800, 1, 1)])
        let t = TransportScripte([(200, page), (200, page), (200, page)])
        let comptes = [compte("instagram", "a"), compte("instagram", "b"), compte("instagram", "c")]
        let r = try source(t, plafond: 2).releve(comptes: comptes, maintenant: t0)
        XCTAssertEqual(t.appels.count, 2)
        XCTAssertEqual(r.creditsDepenses, 2)
        XCTAssertTrue(r.erreurs.contains { $0.contains("plafond de 2 crédits") && $0.contains("c ") })
    }

    func testZeroCreditArreteSansRienPayer() throws {
        let t = TransportScripte([(200, ig([("A", 5, 1, 1), ("OLD", 800, 1, 1)], restant: 0)), (200, ig([]))])
        let r = try source(t).releve(comptes: [compte("instagram", "a"), compte("instagram", "b")], maintenant: t0)
        XCTAssertEqual(t.appels.count, 1, "solde à 0 : pas d'autre appel")
        XCTAssertEqual(r.creditsRestants, 0)
        XCTAssertTrue(r.erreurs.contains { $0.contains("Plus de crédits") && $0.contains("saisie à la main") })
        XCTAssertEqual(r.observations.count, 2, "ce qui était déjà payé est gardé")

        let t2 = TransportScripte([(402, #"{"success":false,"message":"no credits"}"#), (200, ig([]))])
        let r2 = try source(t2).releve(comptes: [compte("instagram", "a"), compte("instagram", "b")], maintenant: t0)
        XCTAssertEqual(t2.appels.count, 1)
        XCTAssertEqual(r2.creditsDepenses, 0, "une erreur ne coûte rien")
        XCTAssertTrue(r2.erreurs.contains { $0.contains("Plus de crédits") })
    }

    func testCleRefuseeArreteTout() throws {
        let t = TransportScripte([(401, #"{"message":"bad key"}"#), (200, ig([]))])
        let r = try source(t).releve(comptes: [compte("instagram", "a"), compte("instagram", "b")], maintenant: t0)
        XCTAssertEqual(t.appels.count, 1)
        XCTAssertTrue(r.erreurs.contains { $0.contains("clé ScrapeCreators refusée") })
        XCTAssertFalse(r.erreurs.joined().contains(cleSecrete))
    }

    func testUnCompteEnErreurNArretePasLesAutres() throws {
        let t = TransportScripte([(404, #"{"success":false,"message":"profil introuvable"}"#), (200, ig([("B1", 5, 7, 1), ("OLD", 800, 1, 1)]))])
        let r = try source(t).releve(comptes: [compte("instagram", "inconnu"), compte("instagram", "b")], maintenant: t0)
        XCTAssertEqual(t.appels.count, 2)
        XCTAssertEqual(r.observations.count, 2)
        XCTAssertTrue(r.erreurs.first?.contains("inconnu") == true && r.erreurs.first?.contains("404") == true)
    }

    func testReseauInjoignableEstUneErreurParCompteSansReessai() throws {
        let t = TransportScripte([])
        let r = try source(t).releve(comptes: [compte("instagram", "a"), compte("instagram", "b")], maintenant: t0)
        XCTAssertEqual(t.appels.count, 2, "un essai par compte, aucun nouvel essai")
        XCTAssertEqual(r.erreurs.count, 2)
        XCTAssertEqual(r.creditsDepenses, 0)
    }

    func testUnePageQuiCouteTropArreteLeReleve() throws {
        let t = TransportScripte([(200, ig([("A", 5, 1, 1)], charged: 10, restant: 90)), (200, ig([]))])
        let r = try source(t).releve(comptes: [compte("instagram", "a"), compte("instagram", "b")], maintenant: t0)
        XCTAssertEqual(t.appels.count, 1)
        XCTAssertEqual(r.creditsDepenses, 10)
        XCTAssertEqual(r.observations.count, 1, "la page payée est gardée")
        XCTAssertTrue(r.erreurs.contains { $0.contains("a coûté 10 crédits") })
    }

    func testCompteursNegatifsOuAbsentsSontInconnus() throws {
        let t = TransportScripte([(200, ig([("A", 5, nil, -1), ("OLD", 800, 5, 1)]))])
        let r = try source(t).releve(comptes: [compte()], maintenant: t0)
        XCTAssertNil(r.observations[0].vues)
        XCTAssertNil(r.observations[0].likes)
    }

    func testTikTokListeEtAdresse() throws {
        let corps = """
        {"success":true,"credits_charged":1,"credits_remaining":97,"max_cursor":1748286476000,"has_more":1,"aweme_list":[
          {"aweme_id":"111","desc":"Une vidéo","create_time":\(Int(t0.timeIntervalSince1970 - 10 * 3600)),"statistics":{"play_count":5000,"digg_count":300,"comment_count":12}},
          {"aweme_id":"222","desc":"Sans stats","create_time":\(Int(t0.timeIntervalSince1970 - 900 * 3600))}
        ]}
        """
        let t = TransportScripte([(200, corps)])
        let r = try source(t).releve(comptes: [compte("tiktok", "chantiertv")], maintenant: t0)
        let u = t.appels[0].absoluteString
        XCTAssertTrue(u.contains("/v3/tiktok/profile/videos?handle=chantiertv") && u.contains("sort_by=latest") && u.contains("include_pinned=false"))
        XCTAssertEqual(r.observations.count, 2)
        XCTAssertEqual(r.observations[0].url, "https://www.tiktok.com/@chantiertv/video/111")
        XCTAssertEqual(r.observations[0].vues, 5000)
        XCTAssertEqual(r.observations[0].likes, 300)
        XCTAssertNil(r.observations[1].vues, "pas de statistiques = inconnu")
        XCTAssertEqual(t.appels.count, 1, "le plus ancien dépasse 30 jours : pas de page suivante")
        XCTAssertEqual(r.creditsRestants, 97)
    }

    func testCoutMaximalAnnonceAvantTout(){
        XCTAssertEqual(SourceScrapeCreators.creditsMax(comptes: 10, pagesMax: 2, plafond: 30), 20)
        XCTAssertEqual(SourceScrapeCreators.creditsMax(comptes: 10, pagesMax: 5, plafond: 30), 30)
        XCTAssertTrue(SourceScrapeCreators().depenseDesCredits)
        XCTAssertFalse(SourceFactice().depenseDesCredits)
    }

    func testLeResultatSeRangeAvecLesCredits() throws {
        let chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-radar-\(UUID().uuidString).sqlite")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + s) } }
        let stock = Stockage(base: try Base(chemin: chemin))
        _ = try stock.radarNoteScan(espace: "kryva", source: "scrapecreators", debut: t0, nbComptes: 1, nbPosts: 3, erreurs: [], credits: 2)
        _ = try stock.radarNoteScan(espace: "kryva", source: "manuelle", debut: t0.addingTimeInterval(-60), nbComptes: 1, nbPosts: 3, erreurs: [])
        let scans = try stock.radarScans()
        XCTAssertEqual(scans.first?.credits, 2)
        XCTAssertNil(scans.last?.credits, "source gratuite : pas de crédits, et pas 0")
    }
}
