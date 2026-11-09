// Publication programmée (08/11) : refus à la programmation, proposition puis validation par empreinte, la passe YouTube (envoi
// privé avec publishAt, relecture, publiée) et Instagram (conteneur 20 min avant, publication à l'heure, retard = pas publiée),
// essais ratés, reconnexion, vidéo changée, annulation. Le réseau est un faux, l'heure une horloge d'essai : ni trousseau ni réseau.
import XCTest

class FauxReseau: Plateformes {
    var televersees: [Publication] = []
    var sessions: [String] = []
    var etatsYouTube: [String: EtatVideoYouTube] = [:]
    var supprimees: [String] = []
    var preparees: [Publication] = []
    var conteneurs: [String: ConteneurInstagram] = [:]
    var publiees: [String] = []
    var erreurTeleversement: [ErreurPlateforme] = []
    var erreurPreparation: [ErreurPlateforme] = []

    func youtubeTeleverser(_ p: Publication, fichier: URL, noterSession: (String) throws -> Void) throws -> String {
        if !erreurTeleversement.isEmpty { throw erreurTeleversement.removeFirst() }
        try noterSession("https://upload.essai/\(p.id)")
        sessions.append(p.session)
        televersees.append(p)
        let id = "vid\(televersees.count)"
        etatsYouTube[id] = EtatVideoYouTube(confidentialite: "private", publierLe: p.prevuLe, envoi: "uploaded", raisonRefus: "")
        return id
    }
    func youtubeEtat(compte: String, video: String) throws -> EtatVideoYouTube? { etatsYouTube[video] }
    func youtubeSupprimer(compte: String, video: String) throws { supprimees.append(video); etatsYouTube[video] = nil }
    var miniatures: [(video: String, image: URL)] = []
    var erreurMiniature: [ErreurPlateforme] = []
    func youtubeMiniature(compte: String, video: String, image: URL) throws {
        if !erreurMiniature.isEmpty { throw erreurMiniature.removeFirst() }
        miniatures.append((video, image))
    }
    func instagramPreparer(_ p: Publication, fichier: URL) throws -> String {
        if !erreurPreparation.isEmpty { throw erreurPreparation.removeFirst() }
        preparees.append(p)
        let c = "cont\(preparees.count)"
        conteneurs[c] = ConteneurInstagram(code: "FINISHED", detail: "")
        return c
    }
    func instagramConteneur(compte: String, conteneur: String) throws -> ConteneurInstagram {
        conteneurs[conteneur] ?? ConteneurInstagram(code: "EXPIRED", detail: "")
    }
    func instagramPublier(compte: String, conteneur: String) throws -> (media: String, lien: String) {
        publiees.append(conteneur)
        conteneurs[conteneur] = ConteneurInstagram(code: "PUBLISHED", detail: "")
        return ("media-\(conteneur)", "https://www.instagram.com/reel/essai\(publiees.count)/")
    }
    var envoisTT: [Publication] = []
    var etatsTT: [String: EnvoiTikTok] = [:]
    var erreurEnvoiTT: [ErreurPlateforme] = []
    var erreurEtatTT: [ErreurPlateforme] = []
    func tiktokEnvoyer(_ p: Publication, fichier: URL) throws -> String {
        if !erreurEnvoiTT.isEmpty { throw erreurEnvoiTT.removeFirst() }
        envoisTT.append(p)
        let id = "pub\(envoisTT.count)"
        etatsTT[id] = EnvoiTikTok(statut: "PROCESSING_UPLOAD", raison: "", post: "")
        return id
    }
    func tiktokEtat(compte: String, envoi: String) throws -> EnvoiTikTok {
        if !erreurEtatTT.isEmpty { throw erreurEtatTT.removeFirst() }
        return etatsTT[envoi] ?? EnvoiTikTok(statut: "FAILED", raison: "absent", post: "")
    }
    func entretien(compte: String) throws -> String? { nil }
}

final class PublicationTests: XCTestCase {
    var chemin: URL!
    var dossier: URL!
    var s: Stockage!
    var reseau: FauxReseau!
    var alertes: [AlertePublication] = []
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)   // novembre 2026
    var horloge: Date!
    static var videos: [String: URL] = [:]

    override func setUpWithError() throws {
        chemin = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-pub-\(UUID().uuidString).sqlite")
        dossier = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-pub-\(UUID().uuidString)", isDirectory: true)
        s = Stockage(base: try Base(chemin: chemin))
        reseau = FauxReseau()
        alertes = []
        horloge = t0
        for c in ComptePublication.tous {
            try Publications.compteConnecte(s, compte: c.id, lu: c.poignee, externeId: "id-\(c.id)", expireLe: "", maintenant: t0)
        }
        try s.base.definirReglage("publication.entretien", Dates.iso.string(from: t0))
    }

    override func tearDown() {
        for suffixe in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: chemin.path + suffixe) }
        try? FileManager.default.removeItem(at: dossier)
    }

    /// Une petite vidéo réelle (ffmpeg), faite une fois par lancement.
    func video(_ nom: String, largeur: Int = 360, hauteur: Int = 640, duree: Int = 4) throws -> URL {
        let cle = "\(nom)-\(largeur)x\(hauteur)-\(duree)"
        if let u = Self.videos[cle], FileManager.default.fileExists(atPath: u.path) { return u }
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let ffmpeg else { throw XCTSkip("ffmpeg absent : pas de vidéo d'essai") }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-pub-\(cle).mp4")
        try? FileManager.default.removeItem(at: u)
        let r = FileEnvoi.lancer(ffmpeg, ["-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=\(largeur)x\(hauteur):rate=10:duration=\(duree)",
                                          "-c:v", "libx264", "-pix_fmt", "yuv420p", "-metadata", "comment=\(nom)", "-y", u.path])
        XCTAssertEqual(r.code, 0, r.erreur)
        Self.videos[cle] = u
        return u
    }

    @discardableResult
    func programmer(_ comptes: [String], dans: TimeInterval = 3600, titre: String = "Mon Short", texte: String = "Texte #essai",
                    fichier: URL? = nil, validee: Bool = true, couverture: String = "", couvertureA: Double? = nil) throws -> [Publication] {
        try programmees(comptes, dans: dans, titre: titre, texte: texte, fichier: fichier, validee: validee,
                        couverture: couverture, couvertureA: couvertureA).publications
    }

    func programmees(_ comptes: [String], dans: TimeInterval = 3600, titre: String = "Mon Short", texte: String = "Texte #essai",
                     fichier: URL? = nil, validee: Bool = true, couverture: String = "", couvertureA: Double? = nil) throws -> Publications.Programmees {
        let f = try fichier ?? video("a")
        return try Publications.programmer(s, DemandePublication(comptes: comptes, fichier: f.path, titre: titre, texte: texte,
                                                                 prevuLe: t0.addingTimeInterval(dans), par: "essai",
                                                                 couverture: couverture, couvertureA: couvertureA),
                                           validee: validee, dossier: dossier, maintenant: t0)
    }

    /// Une image d'essai (jpg) : la 1re image d'une vidéo.
    func image(_ nom: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-pub-\(nom).jpg")
        if !FileManager.default.fileExists(atPath: u.path) {
            XCTAssertTrue(Publications.imageDeLaVideo(try video("image-\(nom)"), a: 0, vers: u))
        }
        return u
    }

    @discardableResult
    func passe(a t: Date) throws -> BilanPublication {
        horloge = t
        return try Publications.passe(s, plateformes: reseau, maintenant: { [unowned self] in self.horloge }) { [unowned self] in self.alertes.append($0) }
    }

    func p(_ id: String) throws -> Publication { try XCTUnwrap(Publications.trouver(s, id)) }

    // MARK: Programmation

    func testRefusClairs() throws {
        func refus(_ bloc: () throws -> Void) -> [String] {
            do { try bloc(); return [] } catch let e as RefusPublication { return e.raisons } catch { return ["\(error)"] }
        }
        XCTAssertTrue(refus { try programmer(["yt-perso"], dans: 5 * 60) }.joined().contains("15 min"))
        XCTAssertTrue(refus { try programmer(["yt-perso"], dans: 200 * 86400) }.joined().contains("6 mois"))
        XCTAssertTrue(refus { try programmer(["yt-perso"], titre: "  ") }.joined().contains("titre YouTube vide"))
        XCTAssertTrue(refus { try programmer(["yt-perso"], titre: String(repeating: "a", count: 101)) }.joined().contains("101"))
        XCTAssertTrue(refus { try programmer(["yt-perso"], titre: "<b>") }.joined().contains("< et >"))
        XCTAssertTrue(refus { try programmer(["tiktok"]) }.joined().contains("compte inconnu"))
        XCTAssertTrue(refus { try programmer(["ig-perso"], texte: String(repeating: "a", count: 2201)) }.joined().contains("2 200"))
        XCTAssertTrue(refus { try programmer(["ig-perso"], texte: String(repeating: "#a ", count: 31)) }.joined().contains("30 hashtags"))
        XCTAssertTrue(refus { try programmer(["ig-perso"], fichier: try video("court", duree: 2)) }.joined().contains("moins de 3 s"))
        XCTAssertTrue(refus { try programmer(["yt-perso"], fichier: URL(fileURLWithPath: "/nexiste/pas.mp4")) }.joined().contains("introuvable"))
        // Rien n'a été écrit.
        XCTAssertTrue(try Publications.liste(s, maintenant: t0).isEmpty)
        // Doublon : même vidéo, même compte.
        try programmer(["yt-perso"])
        XCTAssertTrue(refus { try programmer(["yt-perso"], dans: 7200) }.joined().contains("déjà programmée"))
        // Une autre vidéo passe, avec un avertissement si elle n'est pas verticale.
        let r = try Publications.programmer(s, DemandePublication(comptes: ["yt-kryva"], fichier: try video("large", largeur: 640, hauteur: 360).path,
                                                                  titre: "Large", texte: "", prevuLe: t0.addingTimeInterval(3600), par: "essai"),
                                            validee: true, dossier: dossier, maintenant: t0)
        XCTAssertTrue(r.avertissements.joined().contains("pas verticale"))
    }

    func testUneLigneParCompteEtCopieValidee() throws {
        let l = try programmer(["yt-perso", "ig-kryva"], titre: "Titre", texte: "Légende")
        XCTAssertEqual(l.count, 2)
        XCTAssertEqual(l.map(\.etat), ["planifie", "planifie"])
        XCTAssertEqual(l[0].fichier, l[1].fichier)
        XCTAssertTrue(l[0].fichier.hasPrefix(dossier.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: l[0].fichier))
        XCTAssertEqual(l.first { $0.compte == "ig-kryva" }?.titre, "", "Instagram n'a pas de titre")
        XCTAssertEqual(l.first { $0.compte == "yt-perso" }?.titre, "Titre")
    }

    func testProposeeAttendLaValidationParEmpreinte() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"], validee: false).first)
        XCTAssertEqual(x.etat, "a_valider")
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertTrue(reseau.televersees.isEmpty, "une proposition ne part jamais")
        XCTAssertThrowsError(try Publications.valider(s, id: x.id, empreinte: "0000", par: "Sacha", maintenant: t0))
        // Texte changé après ce qui a été montré : l'empreinte ne correspond plus.
        try s.base.executer("UPDATE publications SET texte = 'autre' WHERE id = ?", [x.id])
        XCTAssertThrowsError(try Publications.valider(s, id: x.id, empreinte: x.empreinte, par: "Sacha", maintenant: t0))
        try s.base.executer("UPDATE publications SET texte = ? WHERE id = ?", [x.texte, x.id])
        let v = try Publications.valider(s, id: x.id, empreinte: x.empreinte, par: "Sacha", maintenant: t0)
        XCTAssertEqual(v.etat, "planifie")
        XCTAssertEqual(v.validePar, "Sacha")
    }

    // MARK: PlugKit

    func alertesPlugKit(_ id: String) throws -> [String] {
        let f = Publications.fichierAlertes(s)
        guard let t = try? String(contentsOf: f, encoding: .utf8) else { return [] }
        return t.split(separator: "\n").map(String.init).filter { $0.contains("plugkit-retrait-\(id.prefix(8))") }
    }

    func testPlugKitValidationEcritLeReveilPuisEnvoie() throws {
        let f = try video("a")
        let x = try XCTUnwrap(Publications.programmer(s, DemandePublication(comptes: ["yt-perso"], fichier: f.path, titre: "Mon Short",
                                                                            texte: "Texte", prevuLe: t0.addingTimeInterval(7200),
                                                                            par: "PlugKit cmw86abc123 (PILOTE)"),
                                                      validee: false, dossier: dossier, maintenant: t0).publications.first)
        XCTAssertEqual(x.plugkit, "cmw86abc123", "l'id du post PlugKit est rangé dans la carte")
        XCTAssertEqual(x.plugkitReveilLe, "")
        XCTAssertTrue(try alertesPlugKit(x.id).isEmpty, "rien pour PILOTE avant la validation")
        let v = try Publications.valider(s, id: x.id, empreinte: x.empreinte, par: "Sacha", maintenant: t0)
        XCTAssertEqual(v.etat, "planifie")
        XCTAssertFalse(v.plugkitReveilLe.isEmpty)
        let lignes = try alertesPlugKit(x.id)
        XCTAssertEqual(lignes.count, 1)
        XCTAssertTrue(lignes[0].contains("cmw86abc123") && lignes[0].contains("\"grave\":true"), lignes[0])
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(reseau.televersees.count, 1, "REVEIL écrit : la vidéo part")
    }

    func testPlugKitSansReveilRienNePartPuisRattrape() throws {
        let f = try video("a")
        let x = try XCTUnwrap(Publications.programmer(s, DemandePublication(comptes: ["yt-perso"], fichier: f.path, titre: "Mon Short",
                                                                            texte: "Texte", prevuLe: t0.addingTimeInterval(7200),
                                                                            par: "PILOTE", plugkit: "cmw86zzz999"),
                                                      validee: false, dossier: dossier, maintenant: t0).publications.first)
        XCTAssertEqual(x.plugkit, "cmw86zzz999")
        // Validée sans la ligne (cas d'une carte d'avant) : la passe écrit la ligne d'abord, puis envoie.
        try s.base.executer("UPDATE publications SET etat = 'planifie' WHERE id = ?", [x.id])
        XCTAssertTrue(try alertesPlugKit(x.id).isEmpty)
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(try alertesPlugKit(x.id).count, 1)
        XCTAssertFalse(try p(x.id).plugkitReveilLe.isEmpty)
        XCTAssertEqual(reseau.televersees.count, 1)
        // Programmée d'office comme validée : refusée (la validation doit écrire la ligne).
        XCTAssertThrowsError(try Publications.programmer(s, DemandePublication(comptes: ["yt-perso"], fichier: f.path, titre: "Autre",
                                                                               texte: "Texte", prevuLe: t0.addingTimeInterval(9000),
                                                                               par: "PlugKit cmw86yyy (PILOTE)"),
                                                         validee: true, dossier: dossier, maintenant: t0))
    }

    func testPlugKitIdLuDansProposePar() {
        XCTAssertEqual(Publications.idPlugKit(dans: "PlugKit cmw8695jibinfqr01tfeaebhf (PILOTE)"), "cmw8695jibinfqr01tfeaebhf")
        XCTAssertEqual(Publications.idPlugKit(dans: "PILOTE"), "")
        XCTAssertEqual(Publications.idPlugKit(dans: "PlugKit"), "")
    }

    // MARK: YouTube

    func testYouTubeEnvoiPriveRelecturePuisPubliee() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"], dans: 3600).first)
        let b = try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(b.envoyees, [x.id])
        XCTAssertEqual(reseau.televersees.first?.prevuLe, x.prevuLe, "publishAt = l'heure validée")
        var y = try p(x.id)
        XCTAssertEqual(y.etat, "envoye")
        XCTAssertEqual(y.ref, "vid1")
        XCTAssertEqual(y.lien, "https://www.youtube.com/shorts/vid1")
        XCTAssertTrue(y.raison.contains("relue chez YouTube"))
        // Avant l'heure : rien ; une seule vidéo, jamais deux.
        try passe(a: t0.addingTimeInterval(1800))
        XCTAssertEqual(reseau.televersees.count, 1)
        // YouTube l'a rendue publique.
        reseau.etatsYouTube["vid1"]?.confidentialite = "public"
        try passe(a: t0.addingTimeInterval(3600 + 200))
        y = try p(x.id)
        XCTAssertEqual(y.etat, "publie")
        XCTAssertTrue(alertes.contains { $0.titre.contains("publiée") && !$0.grave })
        XCTAssertFalse(FileManager.default.fileExists(atPath: y.fichier), "la copie est effacée une fois publiée")
    }

    func testCopieEffaceeDesQueYouTubeLaTientSaufSiUneAutreCarteEnABesoin() throws {
        func existe(_ f: String) -> Bool { FileManager.default.fileExists(atPath: f) }
        func etat(_ id: String, _ e: String) throws { try s.base.executer("UPDATE publications SET etat = ?, ref = 'r1' WHERE id = ?", [e, id]) }
        let l = try programmer(["yt-perso", "ig-kryva"], dans: 3600)
        let yt = try XCTUnwrap(l.first { $0.compte == "yt-perso" }), ig = try XCTUnwrap(l.first { $0.compte == "ig-kryva" })
        XCTAssertEqual(yt.fichier, ig.fichier, "une seule copie pour les deux cartes")
        let vignette = try XCTUnwrap(Publications.vignette(yt))
        // YouTube envoyée, Instagram encore à faire : la copie reste.
        try etat(yt.id, "envoye")
        try Publications.nettoyerCopies(s, maintenant: t0)
        XCTAssertTrue(existe(yt.fichier), "Instagram « planifie » relit encore la copie")
        // Instagram « envoye » (conteneur prêt, pas publié) : la copie reste encore.
        try etat(ig.id, "envoye")
        try Publications.nettoyerCopies(s, maintenant: t0)
        XCTAssertTrue(existe(yt.fichier), "Instagram « envoye » n'est pas fini")
        // Instagram publiée : seule reste YouTube « envoye », qui n'en a plus besoin.
        try etat(ig.id, "publie")
        try Publications.nettoyerCopies(s, maintenant: t0)
        XCTAssertFalse(existe(yt.fichier), "YouTube « envoye » : la vidéo est chez YouTube, la copie part")
        XCTAssertEqual(Publications.vignette(yt), vignette, "la vignette du planning reste")
        // La règle, carte par carte.
        let lim = Dates.iso.string(from: t0.addingTimeInterval(-7 * 86400)), recent = Dates.iso.string(from: t0)
        XCTAssertFalse(Publications.copieUtile(etat: "envoye", compte: "yt-kryva", majLe: recent, limiteEchec: lim))
        XCTAssertTrue(Publications.copieUtile(etat: "envoye", compte: "tt-perso", majLe: recent, limiteEchec: lim), "brouillon TikTok pas publié")
        XCTAssertTrue(Publications.copieUtile(etat: "envoye", compte: "ig-perso", majLe: recent, limiteEchec: lim))
        XCTAssertTrue(Publications.copieUtile(etat: "envoye", compte: "inconnu", majLe: recent, limiteEchec: lim), "compte inconnu : on garde")
        XCTAssertTrue(Publications.copieUtile(etat: "planifie", compte: "yt-perso", majLe: recent, limiteEchec: lim))
        XCTAssertTrue(Publications.copieUtile(etat: "reconnexion", compte: "yt-perso", majLe: recent, limiteEchec: lim))
        XCTAssertTrue(Publications.copieUtile(etat: "echec", compte: "yt-perso", majLe: recent, limiteEchec: lim), "échec récent : reprogrammable")
        XCTAssertFalse(Publications.copieUtile(etat: "echec", compte: "yt-perso", majLe: "2026-01-01T00:00:00Z", limiteEchec: lim))
        XCTAssertFalse(Publications.copieUtile(etat: "publie", compte: "ig-perso", majLe: recent, limiteEchec: lim))
        XCTAssertFalse(Publications.copieUtile(etat: "annule", compte: "tt-perso", majLe: recent, limiteEchec: lim))
    }

    func testYouTubeRelueNonConformeAlerte() throws {
        final class Faux2: FauxReseau {
            override func youtubeEtat(compte: String, video: String) throws -> EtatVideoYouTube? {
                EtatVideoYouTube(confidentialite: "public", publierLe: "", envoi: "uploaded", raisonRefus: "")
            }
        }
        reseau = Faux2()
        try programmer(["yt-perso"])
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertTrue(alertes.contains { $0.grave && $0.texte.contains("vérifier dans YouTube Studio") })
    }

    func testYouTubeToujoursPriveTroisHeuresApres() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"]).first)
        try passe(a: t0.addingTimeInterval(60))
        try passe(a: t0.addingTimeInterval(3600 + 200))
        XCTAssertEqual(try p(x.id).etat, "envoye")
        try passe(a: t0.addingTimeInterval(3600 + 3 * 3600 + 60))
        XCTAssertEqual(try p(x.id).etat, "echec")
        XCTAssertTrue(alertes.contains { $0.grave })
    }

    func testYouTubeEssaiRateEspaceEtCinqEssaisAuPlus() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"], dans: 86400).first)
        reseau.erreurTeleversement = [.passagere("réseau coupé")]
        try passe(a: t0.addingTimeInterval(60))
        var y = try p(x.id)
        XCTAssertEqual(y.etat, "planifie")
        XCTAssertEqual(y.tentatives, 1)
        // Tout de suite après : on attend (1 min).
        try passe(a: t0.addingTimeInterval(90))
        XCTAssertTrue(reseau.televersees.isEmpty)
        try passe(a: t0.addingTimeInterval(130))
        y = try p(x.id)
        XCTAssertEqual(y.etat, "envoye")
        XCTAssertEqual(reseau.televersees.count, 1)

        let z = try XCTUnwrap(programmer(["yt-kryva"], dans: 86400, fichier: try video("b")).first)
        reseau.erreurTeleversement = Array(repeating: .passagere("serveur"), count: 5)
        var t = t0.addingTimeInterval(200)
        for _ in 0..<5 {
            try passe(a: t)
            t = t.addingTimeInterval(1800)
        }
        XCTAssertEqual(try p(z.id).etat, "echec")
        XCTAssertTrue(try p(z.id).raison.contains("5 essais"))
    }

    func testYouTubeTropTardPasEnvoyee() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"], dans: 3600).first)
        // Mac éteint jusqu'à 1 min avant l'heure.
        try passe(a: t0.addingTimeInterval(3600 - 60))
        XCTAssertTrue(reseau.televersees.isEmpty)
        XCTAssertEqual(try p(x.id).etat, "echec")
        XCTAssertTrue(alertes.contains { $0.grave && $0.texte.contains("à reprogrammer") })
    }

    func testQuotaYouTubeAttendLaRemiseAZero() throws {
        // t0 + 60 s ; remise du quota = minuit à Los Angeles après cet instant.
        let x = try XCTUnwrap(programmer(["yt-perso"], dans: 3 * 86400).first)
        let w = try XCTUnwrap(programmer(["yt-kryva"], dans: 3 * 86400 + 600, fichier: try video("c")).first)
        reseau.erreurTeleversement = [.quota("quotaExceeded")]
        let t1 = t0.addingTimeInterval(60)
        try passe(a: t1)
        XCTAssertEqual(try p(x.id).etat, "planifie", "pas d'échec : la vidéo attend")
        XCTAssertTrue(try p(x.id).raison.hasPrefix(Publications.raisonQuotaYouTube))
        XCTAssertEqual(try p(x.id).tentatives, 0, "pas compté comme un essai raté")
        XCTAssertTrue(reseau.televersees.isEmpty, "l'autre vidéo YouTube n'est pas tentée dans la même passe")
        XCTAssertFalse(alertes.contains { $0.grave })
        let remise = Publications.remiseQuotaYouTube(apres: t1)
        XCTAssertGreaterThan(remise, t1); XCTAssertLessThanOrEqual(remise.timeIntervalSince(t1), 86400)
        // Avant la remise : x attend toujours ; w (pas encore marquée) est tentée et part.
        try passe(a: remise.addingTimeInterval(-120))
        XCTAssertEqual(try p(x.id).etat, "planifie")
        XCTAssertEqual(try p(w.id).etat, "envoye")
        // Après la remise : x part.
        try passe(a: remise.addingTimeInterval(60))
        XCTAssertEqual(try p(x.id).etat, "envoye")
    }

    func testQuotaYouTubeJusquALHeureEchec() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"], dans: 3600).first)
        reseau.erreurTeleversement = [.quota("quotaExceeded")]
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(try p(x.id).etat, "planifie")
        try passe(a: t0.addingTimeInterval(3600 - 60))
        XCTAssertEqual(try p(x.id).etat, "echec")
        XCTAssertTrue(try p(x.id).raison.contains("quota"))
    }

    func testUploadLimitExceededNEstPasLeQuota() {
        func rep(_ code: Int, _ raison: String) -> ReponseHTTP {
            ReponseHTTP(code: code, entetes: [:], corps: Data("{\"error\":{\"errors\":[{\"reason\":\"\(raison)\"}],\"message\":\"x\"}}".utf8))
        }
        XCTAssertEqual(PlateformesReelles.erreurYouTube(rep(400, "uploadLimitExceeded"), "envoi"), .limiteChaine("uploadLimitExceeded"))
        XCTAssertEqual(PlateformesReelles.erreurYouTube(rep(403, "uploadLimitExceeded"), "envoi"), .limiteChaine("uploadLimitExceeded"))
        XCTAssertEqual(PlateformesReelles.erreurYouTube(rep(403, "quotaExceeded"), "envoi"), .quota("quotaExceeded"))
    }

    func testYouTubeLaPlusProcheDAbordEtDansLes3Jours() throws {
        // Validées de la plus lointaine à la plus proche (comme Sacha le 09/11) : seules celles à moins de 3 jours partent,
        // la plus proche d'abord.
        let loin = try XCTUnwrap(programmer(["yt-perso"], dans: 8 * 86400, fichier: try video("a")).first)
        let j2 = try XCTUnwrap(programmer(["yt-perso"], dans: 2 * 86400, fichier: try video("b")).first)
        let j1 = try XCTUnwrap(programmer(["yt-perso"], dans: 86400, fichier: try video("c")).first)
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(reseau.televersees.map(\.id), [j1.id, j2.id])
        XCTAssertEqual(try p(loin.id).etat, "planifie")
        XCTAssertTrue(Publications.affichage(try p(loin.id)).contains("3 jours avant"))
        // 5 jours plus tard, elle est à moins de 3 jours : elle part.
        try passe(a: t0.addingTimeInterval(5 * 86400 + 120))
        XCTAssertEqual(try p(loin.id).etat, "envoye")
    }

    func testPlafondDe6EnvoisParChaineSur24h() throws {
        var perso: [Publication] = []
        for i in 0..<8 {
            perso.append(try XCTUnwrap(programmer(["yt-perso"], dans: 3600 * Double(10 + 6 * i), fichier: try video("p\(i)")).first))
        }
        let kryva = try XCTUnwrap(programmer(["yt-kryva"], dans: 3600 * 20, fichier: try video("k")).first)
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(reseau.televersees.filter { $0.compte == "yt-perso" }.map(\.id), perso.prefix(6).map(\.id), "les 6 plus proches")
        XCTAssertEqual(try p(kryva.id).etat, "envoye", "l'autre chaîne a son propre plafond")
        XCTAssertEqual(try p(perso[6].id).etat, "planifie")
        XCTAssertTrue(try p(perso[6].id).raison.hasPrefix(Publications.raisonPlafondYouTube))
        XCTAssertEqual(try p(perso[7].id).raison, Publications.raisonTourYouTube, "attend derrière la 7e")
        XCTAssertEqual(try Publications.envoisYouTube(s, compte: "yt-perso", depuis: t0).count, 6)
        // Une vidéo annulée après son envoi garde sa place (YouTube ne la rend pas) : toujours 6 sur 24 h.
        _ = try Publications.annuler(s, id: perso[0].id, par: "Sacha", plateformes: reseau, maintenant: t0.addingTimeInterval(1800))
        try passe(a: t0.addingTimeInterval(3600))
        XCTAssertEqual(reseau.televersees.filter { $0.compte == "yt-perso" }.count, 6)
        // 24 h après ces 6 envois : la 7e (prévue à 46 h) puis la 8e (52 h) partent.
        try passe(a: t0.addingTimeInterval(86400 - 60))
        XCTAssertEqual(try p(perso[6].id).etat, "planifie")
        try passe(a: t0.addingTimeInterval(86400 + 180))
        XCTAssertEqual(reseau.televersees.filter { $0.compte == "yt-perso" }.map(\.id).suffix(2).map { $0 }, [perso[6].id, perso[7].id])
    }

    func testLimiteDeLaChaineBloqueSeulementCetteChaine() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"], dans: 2 * 86400, fichier: try video("a")).first)
        let y = try XCTUnwrap(programmer(["yt-perso"], dans: 2 * 86400 + 3600, fichier: try video("b")).first)
        let z = try XCTUnwrap(programmer(["yt-kryva"], dans: 2 * 86400 + 600, fichier: try video("c")).first)
        reseau.erreurTeleversement = [.limiteChaine("uploadLimitExceeded")]
        let t1 = t0.addingTimeInterval(60)
        try passe(a: t1)
        XCTAssertEqual(try p(x.id).etat, "planifie")
        XCTAssertTrue(try p(x.id).raison.hasPrefix(Publications.raisonLimiteChaine))
        XCTAssertFalse(try p(x.id).raison.contains(Publications.raisonQuotaYouTube))
        XCTAssertEqual(try p(x.id).tentatives, 0)
        XCTAssertEqual(try p(y.id).etat, "planifie", "pas tentée derrière x")
        XCTAssertEqual(try p(z.id).etat, "envoye", "l'autre chaîne continue")
        XCTAssertFalse(alertes.contains { $0.grave }, "x peut encore partir à temps")
        XCTAssertTrue(alertes.contains { $0.titre.contains("limite") })
        let remise = try XCTUnwrap(s.base.reglage(Publications.cleLimiteChaine("yt-perso")).flatMap(Dates.iso.date))
        XCTAssertEqual(remise.timeIntervalSince(t1), 3600, accuracy: 1, "aucun envoi connu sur yt-perso : nouvel essai dans 1 h")
        // Avant la remise : rien ne part sur yt-perso ; après : x puis y.
        try passe(a: remise.addingTimeInterval(-60))
        XCTAssertEqual(reseau.televersees.filter { $0.compte == "yt-perso" }.count, 0)
        try passe(a: remise.addingTimeInterval(60))
        XCTAssertEqual(reseau.televersees.filter { $0.compte == "yt-perso" }.map(\.id), [x.id, y.id])
    }

    func testLimiteDeLaChaineTropTardAlerteEtEchec() throws {
        // 2 envois réussis à t0 + 60 s, puis refus : remise = 1er envoi + 24 h 10, après l'heure de x.
        _ = try programmer(["yt-perso"], dans: 2 * 3600, fichier: try video("b"))
        _ = try programmer(["yt-perso"], dans: 3 * 3600, fichier: try video("c"))
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(reseau.televersees.count, 2)
        let x = try XCTUnwrap(programmer(["yt-perso"], dans: 6 * 3600).first)
        reseau.erreurTeleversement = [.limiteChaine("uploadLimitExceeded")]
        try passe(a: t0.addingTimeInterval(120))
        let remise = try XCTUnwrap(s.base.reglage(Publications.cleLimiteChaine("yt-perso")).flatMap(Dates.iso.date))
        XCTAssertEqual(remise.timeIntervalSince(t0), 60 + 86400 + 600, accuracy: 1)
        XCTAssertTrue(alertes.contains { $0.grave && $0.texte.contains("à reprogrammer") })
        try passe(a: t0.addingTimeInterval(6 * 3600 - 60))
        XCTAssertEqual(try p(x.id).etat, "echec")
        XCTAssertTrue(try p(x.id).raison.contains("limite d'envois de la chaîne"))
        XCTAssertTrue(try p(x.id).raison.contains("uploadLimitExceeded"))
    }

    func testReconnexionPuisReprise() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"], dans: 86400).first)
        let w = try XCTUnwrap(programmer(["yt-perso"], dans: 2 * 86400, fichier: try video("c")).first)
        reseau.erreurTeleversement = [.reconnexion("Google refuse le jeton")]
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(try p(x.id).etat, "reconnexion")
        XCTAssertEqual(try p(w.id).etat, "reconnexion", "les autres vidéos du compte attendent aussi")
        XCTAssertEqual(try Publications.etatCompte(s, "yt-perso").etat, "a_reconnecter")
        XCTAssertEqual(alertes.filter { $0.titre.contains("reconnecter") }.count, 1, "une alerte par compte")
        try Publications.compteConnecte(s, compte: "yt-perso", lu: "@sachaprljk", externeId: "x", expireLe: "", maintenant: t0.addingTimeInterval(120))
        XCTAssertEqual(try p(x.id).etat, "planifie")
        try passe(a: t0.addingTimeInterval(180))
        XCTAssertEqual(try p(x.id).etat, "envoye")
        XCTAssertEqual(try p(w.id).etat, "envoye")
    }

    func testCompteJamaisConnecteAttendSansReseau() throws {
        try s.base.executer("DELETE FROM comptes_publication WHERE compte = 'yt-kryva'")
        let x = try XCTUnwrap(programmer(["yt-kryva"], dans: 86400).first)
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertTrue(reseau.televersees.isEmpty)
        let y = try p(x.id)
        XCTAssertEqual(y.etat, "planifie")
        XCTAssertEqual(y.raison, "compte pas encore connecté à Pilote")
    }

    func testVideoChangeeApresValidationRienNePart() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"]).first)
        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: x.fichier))
        h.seekToEndOfFile()
        h.write(Data("abime".utf8))
        try h.close()
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertTrue(reseau.televersees.isEmpty)
        XCTAssertEqual(try p(x.id).etat, "echec")
        XCTAssertTrue(try p(x.id).raison.contains("a changé"))
    }

    func testAnnulerYouTubeEnvoyeeSupprimeLaVideoPrivee() throws {
        let x = try XCTUnwrap(programmer(["yt-perso"]).first)
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertThrowsError(try Publications.annuler(s, id: x.id, par: "Sacha", plateformes: nil), "sans l'outil, pas d'annulation à moitié")
        let a = try Publications.annuler(s, id: x.id, par: "Sacha", plateformes: reseau)
        XCTAssertEqual(a.etat, "annule")
        XCTAssertEqual(reseau.supprimees, ["vid1"])
        // Une publiée ne s'annule pas ici.
        let z = try XCTUnwrap(programmer(["yt-kryva"], fichier: try video("d")).first)
        try s.base.executer("UPDATE publications SET etat = 'publie' WHERE id = ?", [z.id])
        XCTAssertThrowsError(try Publications.annuler(s, id: z.id, par: "Sacha", plateformes: reseau))
    }

    // MARK: Noter « publiée » à la main (TikTok)

    private func refus(_ bloc: () throws -> Void) -> [String] {
        do { try bloc(); return [] } catch let e as RefusPublication { return e.raisons } catch { return ["\(error)"] }
    }

    func testMarquerpublieeTikTokEnvoye() throws {
        let x = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "").first)
        try s.base.executer("UPDATE publications SET etat = 'envoye', phase = 'boite', ref = 'pub1' WHERE id = ?", [x.id])
        let t = t0.addingTimeInterval(7200)
        let y = try Publications.marquerPubliee(s, id: x.id, lien: "https://www.tiktok.com/@sachapjk/video/7300", par: "essai", maintenant: t)
        XCTAssertEqual(y.etat, "publie")
        XCTAssertEqual(y.phase, "")
        XCTAssertEqual(y.lien, "https://www.tiktok.com/@sachapjk/video/7300")
        XCTAssertEqual(y.faitLe, Dates.iso.string(from: t))
        XCTAssertEqual(y.raison, "publiée par Sacha depuis l'app TikTok (notée à la main par essai)")
        // Déjà publiée : refus.
        XCTAssertTrue(refus { try Publications.marquerPubliee(s, id: x.id, par: "essai") }.joined().contains("déjà"))
    }

    func testMarquerpublieeSansLienEstPermis() throws {
        let x = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "").first)
        try s.base.executer("UPDATE publications SET etat = 'envoye', phase = 'boite' WHERE id = ?", [x.id])
        let y = try Publications.marquerPubliee(s, id: x.id, par: "Sacha (app)", maintenant: t0)
        XCTAssertEqual(y.etat, "publie")
        XCTAssertEqual(y.lien, "")
    }

    func testMarquerpublieeRefuseYouTubeEtPasEnvoyeEtLienEtranger() throws {
        let yt = try XCTUnwrap(programmer(["yt-perso"]).first)
        try s.base.executer("UPDATE publications SET etat = 'envoye' WHERE id = ?", [yt.id])
        XCTAssertTrue(refus { try Publications.marquerPubliee(s, id: yt.id, par: "essai") }.joined().contains("pas une publication TikTok"))
        XCTAssertEqual(try p(yt.id).etat, "envoye")

        let tt = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "", fichier: try video("d")).first)
        XCTAssertEqual(tt.etat, "planifie")
        XCTAssertTrue(refus { try Publications.marquerPubliee(s, id: tt.id, par: "essai") }.joined().contains("planifie"))
        XCTAssertEqual(try p(tt.id).etat, "planifie")

        try s.base.executer("UPDATE publications SET etat = 'envoye', phase = 'boite' WHERE id = ?", [tt.id])
        for mauvais in ["https://youtube.com/watch?v=1", "http://www.tiktok.com/@a/video/1", "https://www.tiktok.com.evil.fr/x", "tiktok.com/@a"] {
            XCTAssertFalse(refus { try Publications.marquerPubliee(s, id: tt.id, lien: mauvais, par: "essai") }.isEmpty, mauvais)
        }
        XCTAssertEqual(try p(tt.id).etat, "envoye")
        XCTAssertTrue(refus { try Publications.marquerPubliee(s, id: "inconnu", par: "essai") }.joined().contains("introuvable"))
    }

    // MARK: Instagram

    func testInstagramConteneurAvantPuisPublieALHeure() throws {
        let x = try XCTUnwrap(programmer(["ig-perso"], dans: 3600, texte: "Légende exacte").first)
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertTrue(reseau.preparees.isEmpty, "rien avant 20 min de l'heure")
        try passe(a: t0.addingTimeInterval(3600 - 19 * 60))
        XCTAssertEqual(reseau.preparees.first?.texte, "Légende exacte")
        XCTAssertEqual(try p(x.id).etat, "envoye")
        XCTAssertTrue(reseau.publiees.isEmpty, "jamais publiée avant l'heure")
        try passe(a: t0.addingTimeInterval(3600 - 60))
        XCTAssertTrue(reseau.publiees.isEmpty)
        try passe(a: t0.addingTimeInterval(3600 + 20))
        let y = try p(x.id)
        XCTAssertEqual(y.etat, "publie")
        XCTAssertEqual(reseau.publiees, ["cont1"])
        XCTAssertTrue(y.lien.hasPrefix("https://www.instagram.com/reel/"))
        // Une passe de plus ne republie pas.
        try passe(a: t0.addingTimeInterval(3600 + 80))
        XCTAssertEqual(reseau.publiees.count, 1)
    }

    func testInstagramEncoreEnTraitementAttend() throws {
        let x = try XCTUnwrap(programmer(["ig-kryva"], dans: 3600).first)
        try passe(a: t0.addingTimeInterval(3600 - 15 * 60))
        reseau.conteneurs["cont1"] = ConteneurInstagram(code: "IN_PROGRESS", detail: "")
        try passe(a: t0.addingTimeInterval(3600 + 10))
        XCTAssertEqual(try p(x.id).etat, "envoye")
        reseau.conteneurs["cont1"] = ConteneurInstagram(code: "FINISHED", detail: "")
        try passe(a: t0.addingTimeInterval(3600 + 70))
        XCTAssertEqual(try p(x.id).etat, "publie")
    }

    func testInstagramMacEnVeillePasPublieeEnRetard() throws {
        let x = try XCTUnwrap(programmer(["ig-perso"], dans: 3600).first)
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        XCTAssertEqual(try p(x.id).etat, "envoye")
        // Le Mac dort de l'heure moins 10 min à l'heure plus 45 min.
        try passe(a: t0.addingTimeInterval(3600 + 45 * 60))
        XCTAssertTrue(reseau.publiees.isEmpty, "jamais publiée à une heure que Sacha n'a pas choisie")
        XCTAssertEqual(try p(x.id).etat, "echec")
        XCTAssertTrue(alertes.contains { $0.grave && $0.texte.contains("min de retard") })
    }

    func testInstagramConteneurRefuse() throws {
        let x = try XCTUnwrap(programmer(["ig-perso"], dans: 3600).first)
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        reseau.conteneurs["cont1"] = ConteneurInstagram(code: "ERROR", detail: "format")
        try passe(a: t0.addingTimeInterval(3600 + 10))
        XCTAssertEqual(try p(x.id).etat, "echec")
        XCTAssertTrue(reseau.publiees.isEmpty)
    }

    func testInstagramPasseInterrompueEnPublicationRelueSansDoublon() throws {
        let x = try XCTUnwrap(programmer(["ig-perso"], dans: 3600).first)
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        // Une passe morte juste après media_publish : la ligne est restée en « envoi / publication ».
        reseau.conteneurs["cont1"] = ConteneurInstagram(code: "PUBLISHED", detail: "")
        try s.base.executer("UPDATE publications SET etat = 'envoi', phase = 'publication' WHERE id = ?", [x.id])
        try passe(a: t0.addingTimeInterval(3600 + 10))
        XCTAssertEqual(try p(x.id).etat, "publie")
        XCTAssertTrue(reseau.publiees.isEmpty, "pas de deuxième media_publish")
    }

    func testJetonQuiExpireSansRenouvellementAlerte() throws {
        final class Faux3: FauxReseau {
            override func entretien(compte: String) throws -> String? { throw ErreurPlateforme.passagere("réseau coupé") }
        }
        reseau = Faux3()
        try Publications.compteConnecte(s, compte: "ig-perso", lu: "@sachaprljk", externeId: "x",
                                        expireLe: Dates.iso.string(from: t0.addingTimeInterval(5 * 86400)), maintenant: t0)
        try Publications.compteConnecte(s, compte: "ig-kryva", lu: "@kryva.fr", externeId: "y",
                                        expireLe: Dates.iso.string(from: t0.addingTimeInterval(30 * 86400)), maintenant: t0)
        try s.base.definirReglage("publication.entretien", Dates.iso.string(from: t0.addingTimeInterval(-2 * 86400)))
        try passe(a: t0.addingTimeInterval(60))
        let a = alertes.filter { $0.titre.contains("expiré") }
        XCTAssertEqual(a.map { $0.id.contains("ig-perso") }, [true], "seul le jeton à moins de 7 jours alerte")
        XCTAssertTrue(a.allSatisfy(\.grave))
        XCTAssertEqual(try Publications.etatCompte(s, "ig-perso").etat, "connecte", "un échec passager ne déconnecte pas")
    }

    // MARK: TikTok (brouillon dans la boîte, Sacha publie depuis l'app)

    func testTikTokBrouillonQuinzeMinutesAvantPuisPublieParSacha() throws {
        try Publications.compteConnecte(s, compte: "tt-perso", lu: "sacha • pjk (@sachapjk)", externeId: "open-1", expireLe: "", maintenant: t0)
        let r = try Publications.programmer(s, DemandePublication(comptes: ["tt-perso"], fichier: try video("a").path, titre: "Titre ignoré",
                                                                  texte: "Légende TT #essai", prevuLe: t0.addingTimeInterval(3600), par: "essai"),
                                            validee: true, dossier: dossier, maintenant: t0)
        let x = try XCTUnwrap(r.publications.first)
        XCTAssertEqual(x.titre, "", "TikTok n'a pas de titre")
        XCTAssertTrue(r.avertissements.contains { $0.contains("brouillon") })
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertTrue(reseau.envoisTT.isEmpty, "rien avant 15 min de l'heure")
        try passe(a: t0.addingTimeInterval(3600 - 14 * 60))
        XCTAssertEqual(reseau.envoisTT.map(\.texte), ["Légende TT #essai"])
        var y = try p(x.id)
        XCTAssertEqual(y.etat, "envoye")
        XCTAssertEqual(y.ref, "pub1")
        // TikTok traite encore.
        try passe(a: t0.addingTimeInterval(3600 - 13 * 60))
        XCTAssertTrue(try p(x.id).raison.contains("TikTok traite"))
        // Le brouillon arrive dans la boîte : alerte grave avec la légende à coller.
        reseau.etatsTT["pub1"] = EnvoiTikTok(statut: "SEND_TO_USER_INBOX", raison: "", post: "")
        try passe(a: t0.addingTimeInterval(3600 - 12 * 60))
        y = try p(x.id)
        XCTAssertEqual(y.phase, "boite")
        let a = alertes.filter { $0.titre.contains("brouillon TikTok") }
        XCTAssertEqual(a.count, 1)
        XCTAssertTrue(a.allSatisfy { $0.grave && $0.texte.contains("Légende TT #essai") })
        // Relu toutes les 15 min seulement, sans nouvelle alerte.
        try passe(a: t0.addingTimeInterval(3600 - 6 * 60))
        try passe(a: t0.addingTimeInterval(3600 + 5 * 60))
        XCTAssertEqual(alertes.filter { $0.titre.contains("brouillon TikTok") }.count, 1)
        XCTAssertEqual(try p(x.id).etat, "envoye")
        // Sacha publie depuis l'app.
        reseau.etatsTT["pub1"] = EnvoiTikTok(statut: "PUBLISH_COMPLETE", raison: "", post: "7300")
        try passe(a: t0.addingTimeInterval(3600 + 20 * 60))
        y = try p(x.id)
        XCTAssertEqual(y.etat, "publie")
        XCTAssertEqual(y.lien, "https://www.tiktok.com/@sachapjk/video/7300")
        XCTAssertTrue(alertes.contains { $0.titre.contains("TikTok publié") && !$0.grave })
        XCTAssertEqual(reseau.envoisTT.count, 1, "un seul envoi")
    }

    func testTikTokRefuseeParTikTok() throws {
        let x = try XCTUnwrap(programmer(["tt-kryva"], dans: 3600, titre: "").first)
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        reseau.etatsTT["pub1"] = EnvoiTikTok(statut: "FAILED", raison: "file_format_check_failed", post: "")
        try passe(a: t0.addingTimeInterval(3600 - 9 * 60))
        let y = try p(x.id)
        XCTAssertEqual(y.etat, "echec")
        XCTAssertTrue(y.raison.contains("file_format_check_failed"))
        XCTAssertTrue(alertes.contains { $0.grave })
    }

    func testTikTokBrouillonOublieTroisJoursPuisEchec() throws {
        let x = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "").first)
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        reseau.etatsTT["pub1"] = EnvoiTikTok(statut: "SEND_TO_USER_INBOX", raison: "", post: "")
        try passe(a: t0.addingTimeInterval(3600 - 9 * 60))
        try passe(a: t0.addingTimeInterval(3600 + 2 * 86400))
        XCTAssertEqual(try p(x.id).etat, "envoye")
        try passe(a: t0.addingTimeInterval(3600 + 3 * 86400 + 60))
        let y = try p(x.id)
        XCTAssertEqual(y.etat, "echec")
        XCTAssertTrue(y.raison.contains("3 jours"))
    }

    func testTikTokRelecturesRateesPendantLAttenteNeFontPasEchouer() throws {
        let x = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "").first)
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        reseau.etatsTT["pub1"] = EnvoiTikTok(statut: "SEND_TO_USER_INBOX", raison: "", post: "")
        try passe(a: t0.addingTimeInterval(3600 - 9 * 60))
        // Six coupures réseau espacées, chacune suivie d'une relecture réussie : jamais 5 essais ratés d'affilée.
        var t = t0.addingTimeInterval(3600)
        for _ in 0..<6 {
            reseau.erreurEtatTT = [.passagere("réseau coupé")]
            try passe(a: t)
            try passe(a: t.addingTimeInterval(16 * 60))
            t = t.addingTimeInterval(3 * 3600)
        }
        XCTAssertEqual(try p(x.id).etat, "envoye")
    }

    func testTikTokMacEteintTropLongtempsPasEnvoye() throws {
        let x = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "").first)
        try passe(a: t0.addingTimeInterval(3600 + 6 * 3600 + 60))
        XCTAssertTrue(reseau.envoisTT.isEmpty)
        let y = try p(x.id)
        XCTAssertEqual(y.etat, "echec")
        XCTAssertTrue(y.raison.contains("à reprogrammer"))
    }

    func testTikTokEnRetardRaisonnableEnvoieQuandMeme() throws {
        let x = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "").first)
        try passe(a: t0.addingTimeInterval(3600 + 2 * 3600))
        XCTAssertEqual(reseau.envoisTT.count, 1, "un brouillon n'est pas public : il peut partir en retard")
        XCTAssertEqual(try p(x.id).etat, "envoye")
    }

    func testTikTokTropDeBrouillonsEnAttenteEchecClair() throws {
        let x = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "").first)
        reseau.erreurEnvoiTT = [.definitive("TikTok : trop de brouillons en attente (5 par 24 h)")]
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        let y = try p(x.id)
        XCTAssertEqual(y.etat, "echec")
        XCTAssertTrue(y.raison.contains("5 par 24 h"))
    }

    func testTikTokEnvoiCoupeRepartALaPasseSuivante() throws {
        let x = try XCTUnwrap(programmer(["tt-perso"], dans: 3600, titre: "").first)
        try s.base.executer("UPDATE publications SET etat = 'envoi', phase = 'televersement' WHERE id = ?", [x.id])
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        XCTAssertEqual(try p(x.id).etat, "envoye")
        XCTAssertEqual(reseau.envoisTT.count, 1)
    }

    func testTikTokCompteJamaisConnecteAttend() throws {
        try s.base.executer("DELETE FROM comptes_publication WHERE compte = 'tt-kryva'")
        let x = try XCTUnwrap(programmer(["tt-kryva"], dans: 3600, titre: "").first)
        try passe(a: t0.addingTimeInterval(3600 - 10 * 60))
        XCTAssertTrue(reseau.envoisTT.isEmpty)
        XCTAssertEqual(try p(x.id).etat, "planifie")
        try passe(a: t0.addingTimeInterval(3600 + 6 * 3600 + 60))
        XCTAssertEqual(try p(x.id).etat, "echec")
    }

    // MARK: Couvertures

    func testCouvertureInstantDonneLImageEtThumbOffset() throws {
        let r = try programmees(["yt-perso", "ig-perso", "tt-perso"], couvertureA: 1.5)
        let (yt, ig, tt) = (r.publications[0], r.publications[1], r.publications[2])
        XCTAssertEqual(yt.couvertureMs, 1500)
        XCTAssertTrue(FileManager.default.fileExists(atPath: yt.couverture), "l'image de la vidéo à 1,5 s est écrite à côté")
        XCTAssertEqual(yt.couverture, ig.couverture)
        XCTAssertEqual(yt.couvertureEtat, "a_poser")
        XCTAssertEqual(ig.couvertureEtat, "", "Instagram : rien à poser après coup, thumb_offset part avec la vidéo")
        XCTAssertEqual(tt.couvertureEtat, "")
        XCTAssertFalse(yt.empreinteCouverture.isEmpty)
        XCTAssertEqual(Publications.empreinte(yt), yt.empreinte)
        XCTAssertTrue(r.avertissements.joined().contains("TikTok : l'API ne prend pas de couverture"))
        XCTAssertTrue(r.avertissements.joined().contains("Instagram : couverture = l'image de la vidéo à 1.5 s"))
        // Instagram : l'instant part dans le conteneur.
        try passe(a: t0.addingTimeInterval(3600 - Publications.preparationIG + 1))
        XCTAssertEqual(reseau.preparees.first?.couvertureMs, 1500)
    }

    func testSansCouvertureEmpreinteInchangee() throws {
        let p = try XCTUnwrap(try programmer(["yt-perso"]).first)
        XCTAssertFalse(p.aCouverture)
        XCTAssertEqual(p.empreinte, Publications.empreinte(compte: p.compte, titre: p.titre, texte: p.texte, prevuLe: p.prevuLe,
                                                           ia: p.ia, empreinteFichier: p.empreinteFichier),
                       "les publications validées avant les couvertures gardent leur empreinte")
        XCTAssertEqual(p.couvertureEtat, "")
    }

    func testCouvertureRefusClairs() throws {
        func refus(_ bloc: () throws -> Void) -> String {
            do { try bloc(); return "" } catch let e as RefusPublication { return e.raisons.joined(separator: " ; ") } catch { return "\(error)" }
        }
        XCTAssertTrue(refus { try programmer(["yt-perso"], couverture: "/nexiste/pas.jpg") }.contains("image de couverture introuvable"))
        XCTAssertTrue(refus { try programmer(["yt-perso"], couvertureA: 99) }.contains("hors de la vidéo"))
        XCTAssertTrue(refus { try programmer(["yt-perso"], couvertureA: -1) }.contains("hors de la vidéo"))
        let gif = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-pub-couv.gif")
        try Data("GIF89a".utf8).write(to: gif)
        XCTAssertTrue(refus { try programmer(["yt-perso"], couverture: gif.path) }.contains(".jpg ou .png"))
        XCTAssertTrue(try Publications.liste(s, maintenant: t0).isEmpty)
    }

    func testMiniatureYouTubePoseeApresLeTraitement() throws {
        let img = try image("couv")
        let r = try programmees(["yt-perso", "ig-perso"], couverture: img.path)
        XCTAssertTrue(r.avertissements.joined().contains("Instagram : l'API ne prend une image de couverture que depuis un serveur public"))
        let p0 = r.publications[0]
        XCTAssertEqual(try Publications.empreinteFichier(URL(fileURLWithPath: p0.couverture)), try Publications.empreinteFichier(img))
        try passe(a: t0.addingTimeInterval(60))
        XCTAssertEqual(try p(p0.id).etat, "envoye")
        // Pas encore traitée : on attend.
        try passe(a: t0.addingTimeInterval(120))
        XCTAssertTrue(reseau.miniatures.isEmpty)
        XCTAssertEqual(try p(p0.id).couvertureEtat, "a_poser")
        reseau.etatsYouTube["vid1"]?.traitement = "succeeded"
        try passe(a: t0.addingTimeInterval(180))
        XCTAssertEqual(reseau.miniatures.map(\.video), ["vid1"])
        XCTAssertEqual(reseau.miniatures.first?.image.path, p0.couverture)
        XCTAssertEqual(try p(p0.id).couvertureEtat, "posee")
        try passe(a: t0.addingTimeInterval(240))
        XCTAssertEqual(reseau.miniatures.count, 1, "posée une seule fois")
    }

    func testMiniatureRefuseeNeBloquePasLaVideo() throws {
        let p0 = try XCTUnwrap(try programmer(["yt-perso"], couverture: try image("couv").path).first)
        try passe(a: t0.addingTimeInterval(60))
        reseau.etatsYouTube["vid1"]?.traitement = "succeeded"
        reseau.erreurMiniature = [.definitive("YouTube refuse la miniature personnalisée (403)")]
        try passe(a: t0.addingTimeInterval(120))
        let q = try p(p0.id)
        XCTAssertEqual(q.etat, "envoye", "la vidéo reste programmée")
        XCTAssertTrue(q.couvertureEtat.hasPrefix("refusee : YouTube refuse la miniature"))
        XCTAssertEqual(try Publications.etatCompte(s, "yt-perso").etat, "connecte", "jamais une reconnexion pour une miniature")
        XCTAssertTrue(alertes.contains { $0.titre.contains("miniature") && !$0.grave })
        // Essais passagers : 3 au plus.
        let p1 = try XCTUnwrap(try programmer(["yt-kryva"], couverture: try image("couv").path).first)
        try passe(a: t0.addingTimeInterval(180))
        let video = try p(p1.id).ref
        reseau.etatsYouTube[video]?.traitement = "succeeded"
        reseau.erreurMiniature = [.passagere("HTTP 503"), .passagere("HTTP 503"), .passagere("HTTP 503")]
        for i in 1...3 { try passe(a: t0.addingTimeInterval(180 + 60 * Double(i))) }
        XCTAssertTrue(try p(p1.id).couvertureEtat.hasPrefix("refusee : HTTP 503"))
    }

    func testMiniatureChangeeApresValidationPasPosee() throws {
        let img = try image("couv-change")
        let p0 = try XCTUnwrap(try programmer(["yt-perso"], couverture: img.path).first)
        try passe(a: t0.addingTimeInterval(60))
        try Data("autre".utf8).write(to: URL(fileURLWithPath: p0.couverture))
        reseau.etatsYouTube["vid1"]?.traitement = "succeeded"
        try passe(a: t0.addingTimeInterval(120))
        XCTAssertTrue(reseau.miniatures.isEmpty)
        XCTAssertTrue(try p(p0.id).couvertureEtat.contains("changé depuis la validation"))
    }

    func testVignetteDuPlanning() throws {
        let a = try XCTUnwrap(try programmer(["yt-perso"]).first)
        let v = try XCTUnwrap(Publications.vignette(a))
        XCTAssertTrue(v.lastPathComponent.hasSuffix("-vignette.jpg"))
        let b = try XCTUnwrap(try programmer(["ig-perso"], fichier: try video("b"), couvertureA: 0.5).first)
        XCTAssertEqual(Publications.vignette(b)?.path, b.couverture)
    }

    func testNomTikTokAttenduSansCasseNiSignes() throws {
        let perso = try XCTUnwrap(ComptePublication.trouver("tt-perso"))
        let kryva = try XCTUnwrap(ComptePublication.trouver("tt-kryva"))
        XCTAssertTrue(perso.afficheCorrespond("sacha • pjk"))
        XCTAssertTrue(perso.afficheCorrespond("Sacha PJK"))
        XCTAssertFalse(perso.afficheCorrespond("KRYVA - App pour artisans BTP"))
        XCTAssertTrue(kryva.afficheCorrespond("KRYVA – App pour artisans BTP"))
        XCTAssertFalse(kryva.afficheCorrespond(""))
    }

    func testChaineYouTubeReconnueParSonIdMemeRenommee() throws {
        let c = try XCTUnwrap(ComptePublication.trouver("yt-perso"))
        XCTAssertTrue(c.reconnait(id: "UC0000000000000000000001", poignee: "@sachaprljk"))
        XCTAssertTrue(c.reconnait(id: "UC0000000000000000000001", poignee: "@nouveaunom"), "Sacha peut renommer la chaîne")
        XCTAssertFalse(c.reconnait(id: "UCautre", poignee: "@sachaprljk"), "une autre chaîne avec la même poignée : refusée")
        let k = try XCTUnwrap(ComptePublication.trouver("yt-kryva"))
        XCTAssertTrue(k.reconnait(id: "UCx", poignee: "@KRYVA_app"), "sans id connu : la poignée")
        XCTAssertFalse(k.reconnait(id: "UCx", poignee: "@sachaprljk"))
    }

    func testComptesInstagramEtTikTokReconnus() throws {
        let ig = try XCTUnwrap(ComptePublication.trouver("ig-perso"))
        XCTAssertTrue(ig.reconnait(id: "17840000000000001", poignee: "sachaprljk") && ig.correspond("sachaprljk"))
        XCTAssertFalse(ig.reconnait(id: "17840000000000002", poignee: "sachaprljk"), "l'id de kryva.fr : refusé")
        let k = try XCTUnwrap(ComptePublication.trouver("ig-kryva"))
        XCTAssertTrue(k.reconnait(id: "17840000000000002", poignee: "kryva.fr") && k.correspond("kryva.fr"))
        XCTAssertTrue(try XCTUnwrap(ComptePublication.trouver("tt-perso")).correspond("@sachaprljk"))
        XCTAssertFalse(try XCTUnwrap(ComptePublication.trouver("tt-kryva")).correspond("sachaprljk"))
    }

    func testJetonMetaReconnuEtHoteChoisi() {
        let ig = "IG" + String(repeating: "a", count: 60), ea = "EABE" + String(repeating: "b", count: 246)
        XCTAssertEqual(ConnexionPublication.jetonMeta("  \(ea)\n"), ea)
        XCTAssertEqual(ConnexionPublication.jetonMeta(ig), ig)
        XCTAssertNil(ConnexionPublication.jetonMeta("bonjour"))
        XCTAssertNil(ConnexionPublication.jetonMeta("EA court"))
        XCTAssertTrue(PlateformesReelles.connexionUnifiee(ea), "connexion unifiée : graph.facebook.com")
        XCTAssertFalse(PlateformesReelles.connexionUnifiee(ig), "connexion Instagram : graph.instagram.com")
    }

    func testTikTokMorceauxEtPoignee() {
        XCTAssertTrue(PlateformesReelles.morceauxTikTok(taille: 1_000) == (1_000, 1))
        XCTAssertTrue(PlateformesReelles.morceauxTikTok(taille: 64_000_000) == (64_000_000, 1))
        XCTAssertTrue(PlateformesReelles.morceauxTikTok(taille: 64_000_001) == (10_000_000, 6), "le dernier morceau prend le reste")
        // 5xx sur un morceau : TikTok dit ce qu'il a reçu ; le même morceau est renvoyé (doc « retry submitting this chunk »).
        XCTAssertEqual(PlateformesReelles.octetsRecusTikTok("bytes 0-99999999/749602001"), 100_000_000)
        XCTAssertEqual(PlateformesReelles.octetsRecusTikTok("Bytes 0-0/10"), 1)
        XCTAssertNil(PlateformesReelles.octetsRecusTikTok(nil))
        XCTAssertNil(PlateformesReelles.octetsRecusTikTok("bytes */749602001"))
        XCTAssertEqual(PlateformesReelles.attenteMorceauTikTok(essai: 1), 3)
        XCTAssertEqual(PlateformesReelles.attenteMorceauTikTok(essai: 5), 48)
        XCTAssertEqual((1..<PlateformesReelles.essaisMorceauTikTok).map { PlateformesReelles.attenteMorceauTikTok(essai: $0) }.reduce(0, +), 93,
                       "un peu plus d'une minute et demie d'attente au plus par morceau")
        XCTAssertTrue(PlateformesReelles.morceauxTikTok(taille: 105_000_000) == (10_000_000, 10))
        XCTAssertEqual(Publications.poigneeTikTok("sacha • pjk (@sachapjk)"), "sachapjk")
        XCTAssertNil(Publications.poigneeTikTok(""))
        XCTAssertNil(Publications.poigneeTikTok("KRYVA (@)"))
    }

    // MARK: Divers

    func testRienAFaireSansPublication() throws {
        XCTAssertFalse(try Publications.aFaire(s, maintenant: t0.addingTimeInterval(60)))
        try programmer(["yt-perso"], validee: false)
        XCTAssertFalse(try Publications.aFaire(s, maintenant: t0.addingTimeInterval(60)), "une proposition n'oblige pas à ouvrir le trousseau")
        try programmer(["ig-perso"])
        XCTAssertTrue(try Publications.aFaire(s, maintenant: t0.addingTimeInterval(60)))
    }

    func testLectureDeLHeureDeParis() throws {
        let d = try XCTUnwrap(Publications.lireDate("2026-11-10 18:00"))
        XCTAssertEqual(Dates.iso.string(from: d), "2026-11-10T17:00:00Z")
        XCTAssertNil(Publications.lireDate("demain"))
    }
}
