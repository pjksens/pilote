// pilote publication : la publication programmée de vidéos (YouTube, Instagram, TikTok en brouillon) sur les comptes de Sacha.
// Voir Shared/Publication.swift (règles) et Shared/PublicationReseaux.swift (réseau, trousseau).
// --passe est lancé toutes les minutes par l'agent launchd io.github.pjksens.pilote.publication.
// Une session ne fait que proposer (programmer → « à valider ») ; Sacha valide dans l'app, ou une session valide avec
// l'empreinte de ce qu'elle lui a montré, seulement après son « oui » explicite.
import AppKit
import Foundation

enum PublicationCommande {
    struct CompteAffiche: Encodable {
        let id: String, nom: String, reseau: String, etat: String, lu: String, raison: String, expireLe: String, verifieLe: String
    }
    struct PublicationAffichee: Encodable {
        let publication: Publication
        let compteNom: String
        let statut: String
        let affichage: String
        let prevuParis: String
    }
    struct Liste: Encodable {
        let comptes: [CompteAffiche]
        let publications: [PublicationAffichee]
        let agentCharge: Bool
    }

    static func comptesAffiches(_ stock: Stockage) throws -> [CompteAffiche] {
        try ComptePublication.tous.map { c in
            let e = try Publications.etatCompte(stock, c.id)
            return CompteAffiche(id: c.id, nom: c.nom, reseau: c.reseau.rawValue, etat: e.etat, lu: e.lu, raison: e.raison,
                                 expireLe: e.expireLe, verifieLe: e.verifieLe)
        }
    }

    static func affichee(_ p: Publication) -> PublicationAffichee {
        PublicationAffichee(publication: p, compteNom: ComptePublication.trouver(p.compte)?.nom ?? p.compte, statut: Publications.statut(p),
                            affichage: Publications.affichage(p), prevuParis: Publications.heureParis(p.prevuLe))
    }

    static func liste(_ stock: Stockage, jours: Int = 30) throws -> Liste {
        Liste(comptes: try comptesAffiches(stock), publications: try Publications.liste(stock, jours: jours).map(affichee),
              agentCharge: Publications.agentCharge())
    }

    /// Ce qu'une session montre à Sacha avant qu'il dise oui : tout ce qui partira, mot pour mot.
    static func aMontrer(_ p: Publication) -> String {
        let c = ComptePublication.trouver(p.compte)?.nom ?? p.compte
        var l = ["Compte : \(c)", "Heure : \(Publications.heureParis(p.prevuLe))", "Vidéo : \(p.source)"]
        if !p.titre.isEmpty { l.append("Titre : \(p.titre)") }
        l.append((p.reseau == .youtube ? "Description : " : "Légende : ") + (p.texte.isEmpty ? "(vide)" : p.texte))
        if p.reseau == .tiktok { l.append("TikTok : brouillon dans la boîte TikTok 15 min avant l'heure ; \(Moi.tiers) publie depuis l'app et colle la légende") }
        l.append("Couverture : " + Publications.couvertureTexte(p))
        if p.ia { l.append("Contenu réaliste généré ou modifié par IA : oui (YouTube l'affiche)") }
        if !p.plugkit.isEmpty { l.append("Remplace le post PlugKit \(p.plugkit) : à la validation, PILOTE est prévenu de le retirer") }
        l.append("Empreinte : \(p.empreinte)")
        return l.joined(separator: "\n")
    }

    struct Proposees: Encodable {
        let publications: [PublicationAffichee]
        let avertissements: [String]
        let aMontrerASacha: [String]
        let suite: String
    }

    static func proposer(_ stock: Stockage, comptes: [String], fichier: String, titre: String, texte: String, le: String, ia: Bool,
                         par: String, couverture: String = "", couvertureA: Double? = nil, plugkit: String = "") throws -> Proposees {
        guard let d = Publications.lireDate(le) else {
            throw RefusPublication(raisons: ["heure illisible « \(le) » : « 2026-11-10 18:00 » (heure de Paris)"])
        }
        let r = try Publications.programmer(stock, DemandePublication(comptes: comptes, fichier: fichier, titre: titre, texte: texte,
                                                                      prevuLe: d, ia: ia, par: par, couverture: couverture,
                                                                      couvertureA: couvertureA, plugkit: plugkit), validee: false)
        return Proposees(publications: r.publications.map(affichee), avertissements: r.avertissements,
                         aMontrerASacha: r.publications.map(aMontrer),
                         suite: "Rien ne part : montrer chaque bloc à \(Moi.tiers) (vidéo comprise). Il valide dans Pilote › Publications, ou, sur son « oui » explicite à ce texte exact, `pilote publication valider <id> --empreinte <empreinte>`.")
    }

    static func lancer(_ stock: Stockage, _ args: [String]) throws {
        let sous = args.first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? (args.contains("--passe") ? "passe" : "liste")
        let reste = args.first == sous ? Array(args.dropFirst()) : args
        let copie = FileEnvoi.surCopie()
        switch sous {
        case "liste":
            sortir(try liste(stock, jours: option("--jours", reste).flatMap(Int.init) ?? 30))

        case "passe":
            let chemin = FileEnvoi.dossierDeLaBase.appendingPathComponent("publication.verrou").path
            let fd = open(chemin, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else { echouer("Verrou illisible : \(chemin)") }
            defer { close(fd) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
            guard try Publications.aFaire(stock) || reste.contains("--toujours") else { return }
            let b = try Publications.passe(stock, plateformes: PlateformesReelles()) { Publications.publier($0, essai: copie) }
            if !(b.envoyees.isEmpty && b.publiees.isEmpty && b.echecs.isEmpty && b.reconnexions.isEmpty) || reste.contains("--toujours") {
                FileHandle.standardOutput.write(Data("\(Dates.iso.string(from: Date())) ".utf8))
                sortir(b)
            }

        case "programmer":
            guard let comptes = option("--compte", reste) ?? option("--comptes", reste), let fichier = option("--fichier", reste),
                  let le = option("--le", reste) else {
                echouer("pilote publication programmer --compte yt-perso[,ig-kryva] --fichier VIDEO --le \"2026-11-10 18:00\" [--titre T] [--texte T | --texte-fichier F] [--couverture IMAGE] [--couverture-a SECONDES] [--ia] [--par NOM] [--plugkit ID_POST]")
            }
            var couvertureA: Double? = nil
            if let a = option("--couverture-a", reste) {
                guard let v = Double(a.replacingOccurrences(of: ",", with: ".")) else { echouer("--couverture-a : un nombre de secondes (ex. 2.5)") }
                couvertureA = v
            }
            var texte = option("--texte", reste) ?? ""
            if let f = option("--texte-fichier", reste) { texte = try String(contentsOfFile: (f as NSString).expandingTildeInPath, encoding: .utf8) }
            sortir(try proposer(stock, comptes: comptes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                fichier: fichier, titre: option("--titre", reste) ?? "", texte: texte, le: le,
                                ia: reste.contains("--ia"), par: option("--par", reste) ?? "session",
                                couverture: option("--couverture", reste) ?? "", couvertureA: couvertureA,
                                plugkit: option("--plugkit", reste) ?? ""))

        case "valider":
            guard let id = reste.first(where: { !$0.hasPrefix("--") }), let e = option("--empreinte", reste) else {
                echouer("pilote publication valider <id> --empreinte <empreinte montrée à \(Moi.tiers)> [--par NOM]")
            }
            let p = try Publications.valider(stock, id: id, empreinte: e, par: option("--par", reste) ?? "\(Moi.tiers) (via session)")
            if !copie { Publications.reveillerAgent() }
            sortir(affichee(p))

        case "annuler":
            guard let id = reste.first(where: { !$0.hasPrefix("--") }) else { echouer("pilote publication annuler <id> [--par NOM]") }
            sortir(affichee(try Publications.annuler(stock, id: id, par: option("--par", reste) ?? "session", plateformes: PlateformesReelles())))

        case "publiee":
            guard let id = reste.first(where: { !$0.hasPrefix("--") }) else { echouer("pilote publication publiee <id> [lien TikTok] [--par NOM]") }
            // Le lien est le second mot sans « -- » (la valeur de --par n'en est pas un).
            let mots = reste.enumerated().filter { i, m in !m.hasPrefix("--") && (i == 0 || reste[i - 1] != "--par") }.map(\.element)
            sortir(affichee(try Publications.marquerPubliee(stock, id: id, lien: mots.count > 1 ? mots[1] : "", par: option("--par", reste) ?? "session")))

        case "comptes":
            sortir(try comptesAffiches(stock))

        case "medias":
            // Lecture seule : ce qui est déjà sur le compte (YouTube : privées et programmées comprises ; Instagram : publications).
            guard let id = option("--compte", reste), let c = ComptePublication.trouver(id), c.reseau != .tiktok else {
                echouer("pilote publication medias --compte yt-perso | yt-kryva | ig-perso | ig-kryva (TikTok : l'API n'a pas la liste)")
            }
            let r = PlateformesReelles()
            sortir(try c.reseau == .youtube ? r.youtubeVideos(compte: c.id) : r.instagramMedias(compte: c.id))

        case "connecter":
            guard let id = reste.first(where: { !$0.hasPrefix("--") }), let c = ComptePublication.trouver(id) else {
                echouer("pilote publication connecter \(ComptePublication.tous.map(\.id).joined(separator: " | "))")
            }
            let heure = Publications.heureParis(Dates.iso.string(from: Date()))
            do {
                switch c.reseau {
                case .youtube:
                    FileHandle.standardError.write(Data("Page Google ouverte dans le navigateur : choisir la chaîne \(c.poignee), puis Autoriser.\n".utf8))
                    let fin = Publications.heureParis(Dates.iso.string(from: Date().addingTimeInterval(300)))
                    try? Publications.noterTentative(stock, compte: c.id, raison: "connexion en cours : page Google ouverte (\(heure)), choisir \(c.poignee) avant \(fin)")
                    sortir(try ConnexionPublication.youtube(stock, compte: c) { url in
                        _ = FileEnvoi.lancer("/usr/bin/open", [url.absoluteString])
                    })
                case .tiktok:
                    FileHandle.standardError.write(Data("Page TikTok ouverte dans le navigateur : être connecté au compte \(c.nom), puis Autoriser.\n".utf8))
                    let fin = Publications.heureParis(Dates.iso.string(from: Date().addingTimeInterval(300)))
                    try? Publications.noterTentative(stock, compte: c.id, raison: "connexion en cours : page TikTok ouverte (\(heure)), autoriser avec le compte \(c.nom) avant \(fin)")
                    sortir(try ConnexionPublication.tiktok(stock, compte: c) { url in
                        _ = FileEnvoi.lancer("/usr/bin/open", [url.absoluteString])
                    })
                case .instagram:
                    // Le jeton copié (presse-papiers), sinon celui que PILOTE a rangé en attente dans le trousseau.
                    let pp = NSPasteboard.general
                    let brut = pp.string(forType: .string) ?? ""
                    let copie = ConnexionPublication.jetonMeta(brut) != nil
                    let r = try ConnexionPublication.instagram(stock, compte: c, jeton: copie ? brut : (ConnexionPublication.jetonEnAttente(c.id) ?? ""))
                    // Le jeton ne reste pas dans le presse-papiers (s'il n'a pas changé entre-temps).
                    if copie, pp.string(forType: .string) == brut { pp.clearContents() }
                    sortir(r)
                }
            } catch {
                try? Publications.noterTentative(stock, compte: c.id, raison: "connexion ratée (\(heure)) : \(error)")
                throw error
            }

        case "client-tiktok":
            // La clé (publique) en argument ; le secret copié dans le presse-papiers (bouton « copier » du portail), jamais affiché.
            guard let cle = option("--cle", reste) else {
                echouer("pilote publication client-tiktok --cle <Client key> [--port N]   (le Client secret copié dans le presse-papiers)")
            }
            let port = option("--port", reste).flatMap(UInt16.init) ?? 0
            let pp = NSPasteboard.general
            let brut = pp.string(forType: .string) ?? ""
            try ClientTikTok.enregistrer(cle: cle, secret: brut, port: port)
            if pp.string(forType: .string) == brut { pp.clearContents() }
            struct Client: Encodable { let clientTiktok: Bool; let fichier: String; let port: String; let suite: String }
            sortir(Client(clientTiktok: (try? ClientTikTok.charger()) != nil, fichier: ClientTikTok.fichier?.path ?? "publication coupée (reglages.json)",
                          port: port == 0 ? "libre (adresse de retour avec *)" : "\(port)",
                          suite: "Presse-papiers vidé. \(Moi.tiers) : Pilote › Publications › « Connecter » sur chaque ligne TikTok."))

        case "acces":
            // Ce que Pilote a pour publier, sans rien montrer des jetons.
            struct Acces: Encodable { let compte: String; let jeton: String; let etat: String }
            let client = (try? ClientGoogle.charger()) != nil
            let clientTT = (try? ClientTikTok.charger()) != nil
            var l: [Acces] = []
            for c in ComptePublication.tous {
                let j: String
                do { j = try TrousseauPublication.lire(c.id) == nil ? "absent" : "présent" } catch { j = "\(error)" }
                l.append(Acces(compte: c.id, jeton: j, etat: try Publications.etatCompte(stock, c.id).etat))
            }
            struct Bilan: Encodable { let clientGoogle: Bool; let clientTiktok: Bool; let comptes: [Acces]; let agentCharge: Bool }
            sortir(Bilan(clientGoogle: client, clientTiktok: clientTT, comptes: l, agentCharge: Publications.agentCharge()))

        case "verifier":
            sortir(try verifier(stock))

        case "essai-youtube", "essai-instagram", "essai-tiktok":
            // Règle de Sacha (08/11) : aucun envoi d'essai sur ses vrais comptes, même privé, sans son accord explicite.
            guard reste.contains("--accord-sacha") else {
                echouer("Essai d'envoi refusé sans --accord-sacha : \(Moi.tiers) doit d'abord accepter cet envoi (règle du 08/11). Vérification sans envoi : pilote publication verifier")
            }
            switch sous {
            case "essai-youtube": try essaiYouTube(stock, reste)
            case "essai-instagram": try essaiInstagram(stock, reste)
            default: try essaiTikTok(stock, reste)
            }

        default:
            echouer("pilote publication [liste | --passe | programmer | valider | annuler | comptes | connecter | client-tiktok | acces | verifier | essai-youtube | essai-instagram | essai-tiktok]")
        }
    }

    // MARK: Essais réels (rien de public)

    struct EssaiYouTube: Encodable {
        let video: String
        let envoyee: Bool
        let relue: [String: String]
        let conforme: Bool
        let supprimee: Bool
        let etapes: [String]
    }

    struct Verification: Encodable { let compte: String; let attendu: String; let lu: String; let conforme: Bool; let erreur: String }

    /// Lecture seule : pour chaque compte qui a un jeton, demande à la plateforme à qui il appartient (YouTube channels.list
    /// mine=true, Instagram /me, TikTok user/info) et le compare au compte attendu. Rien n'est envoyé ni publié. TikTok sans
    /// pseudo connu : comparé au compte (open_id) lu à la connexion.
    static func verifier(_ stock: Stockage) throws -> [Verification] {
        let r = PlateformesReelles()
        var l: [Verification] = []
        for c in ComptePublication.tous {
            guard let j = try? TrousseauPublication.lire(c.id), !j.acces.isEmpty else {
                l.append(Verification(compte: c.id, attendu: c.poignee, lu: "", conforme: false, erreur: "pas connecté"))
                continue
            }
            do {
                let lu: String
                switch c.reseau {
                case .youtube: let ch = try r.youtubeChaine(compte: c.id); lu = "\(ch.titre) (\(ch.poignee))"
                    l.append(Verification(compte: c.id, attendu: c.attendu, lu: "\(lu) \(ch.id)", conforme: c.reconnait(id: ch.id, poignee: ch.poignee), erreur: ""))
                case .instagram:
                    let moi = try r.instagramMoi(jeton: j.acces, compteIG: c.idFixe.isEmpty ? j.externeId : c.idFixe)
                    var quota = ""
                    if PlateformesReelles.connexionUnifiee(j.acces), !moi.id.isEmpty {
                        let q = try r.instagramQuota(compteIG: moi.id, jeton: j.acces); quota = " · quota \(q.utilise)/\(q.total)"
                    }
                    lu = "@\(moi.nom) \(moi.id)\(quota)"
                    l.append(Verification(compte: c.id, attendu: c.attendu, lu: lu,
                                          conforme: c.correspond(moi.nom) && c.reconnait(id: moi.id, poignee: moi.nom), erreur: ""))
                case .tiktok:
                    let moi = try r.tiktokMoi(compte: c.id)
                    let e = try Publications.etatCompte(stock, c.id)
                    lu = "\(moi.affiche) (@\(moi.nom))"
                    let conforme = c.poignee.isEmpty ? (!e.externeId.isEmpty && e.externeId == moi.id) : c.correspond(moi.nom)
                    l.append(Verification(compte: c.id, attendu: c.poignee.isEmpty ? "le compte relié : \(e.lu.isEmpty ? c.nomAffiche : e.lu)" : c.poignee, lu: lu,
                                          conforme: conforme, erreur: ""))
                }
                if l.last?.conforme == true {
                    var e = try Publications.etatCompte(stock, c.id)
                    e.verifieLe = Dates.iso.string(from: Date())
                    try Publications.noterCompte(stock, e)
                }
            } catch {
                l.append(Verification(compte: c.id, attendu: c.poignee, lu: "", conforme: false, erreur: "\(error)"))
            }
        }
        return l
    }

    /// Envoie une vidéo d'essai en PRIVÉ sur la chaîne du compte avec publishAt dans 30 jours, la relit par l'API, puis la supprime
    /// (sauf --garder). Rien n'entre dans la base.
    static func essaiYouTube(_ stock: Stockage, _ args: [String]) throws {
        guard let f = option("--fichier", args) else { echouer("pilote publication essai-youtube --fichier VIDEO [--garder]") }
        let compte = "yt-perso"
        let u = URL(fileURLWithPath: (f as NSString).expandingTildeInPath)
        let prevu = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 30 * 86400).rounded(.down))
        let p = Publication(id: "essai", compte: compte, source: u.path, fichier: u.path, titre: "Test Pilote (privé, à supprimer)",
                            texte: "Essai technique de Pilote : vidéo privée, supprimée juste après.", prevuLe: Dates.iso.string(from: prevu),
                            etat: "planifie", phase: "", raison: "", empreinte: "", empreinteFichier: "", taille: 0, ia: false,
                            proposePar: "essai", validePar: "", valideLe: "", ref: "", lien: "", conteneur: "", session: "", tentatives: 0,
                            verifieLe: "", creeLe: "", majLe: "", faitLe: "")
        let r = PlateformesReelles()
        var etapes: [String] = []
        let chaine = try r.youtubeChaine(compte: compte)
        let attendue = ComptePublication.trouver(compte)!
        guard attendue.reconnait(id: chaine.id, poignee: chaine.poignee) else { echouer("Jeton de \(chaine.poignee) (\(chaine.id)), pas de \(attendue.attendu) : essai arrêté.") }
        etapes.append("chaîne \(chaine.titre) (\(chaine.poignee))")
        let video = try r.youtubeTeleverser(p, fichier: u) { _ in etapes.append("session d'envoi ouverte") }
        etapes.append("envoyée : \(video)")
        let e = try r.youtubeEtat(compte: compte, video: video)
        let lu = Dates.iso.date(from: e?.publierLe ?? "")
        let conforme = e?.confidentialite == "private" && lu.map { abs($0.timeIntervalSince(prevu)) <= 60 } == true
        etapes.append("relue : \(e?.confidentialite ?? "absente"), publishAt \(e?.publierLe ?? "aucun"), envoi \(e?.envoi ?? "?")")
        var supprimee = false
        if !args.contains("--garder") {
            try r.youtubeSupprimer(compte: compte, video: video)
            // YouTube met quelques secondes à oublier la vidéo (08/11 : relue tout de suite, encore là) : 5 relectures sur ~20 s.
            for essai in 0..<5 where !supprimee {
                if essai > 0 { Thread.sleep(forTimeInterval: 4) }
                supprimee = (try? r.youtubeEtat(compte: compte, video: video)) == .some(nil)
            }
            etapes.append(supprimee ? "supprimée (relue : n'existe plus)" : "suppression demandée, pas encore confirmée par la relecture")
        }
        sortir(EssaiYouTube(video: video, envoyee: true,
                            relue: ["privacy_status": e?.confidentialite ?? "", "publish_at": e?.publierLe ?? "", "upload_status": e?.envoi ?? "",
                                    "publish_at_demande": p.prevuLe],
                            conforme: conforme, supprimee: supprimee, etapes: etapes))
    }

    struct EssaiTikTok: Encodable { let compte: String; let envoi: String; let statut: String; let raison: String; let etapes: [String] }

    /// Envoie la vidéo en BROUILLON dans la boîte TikTok du compte (rien de public), puis relit l'envoi jusqu'à la boîte
    /// (5 min au plus). Le brouillon reste dans l'app TikTok : Sacha le supprime ou le garde. Rien n'entre dans la base.
    static func essaiTikTok(_ stock: Stockage, _ args: [String]) throws {
        guard let id = option("--compte", args), let c = ComptePublication.trouver(id), c.reseau == .tiktok,
              let f = option("--fichier", args) else {
            echouer("pilote publication essai-tiktok --compte tt-perso|tt-kryva --fichier VIDEO --accord-sacha")
        }
        let u = URL(fileURLWithPath: (f as NSString).expandingTildeInPath)
        let r = PlateformesReelles()
        var etapes: [String] = []
        let moi = try r.tiktokMoi(compte: c.id)
        let e = try Publications.etatCompte(stock, c.id)
        guard c.poignee.isEmpty ? e.externeId == moi.id : c.correspond(moi.nom) else {
            echouer("Jeton de @\(moi.nom), pas du compte attendu (\(c.nom)) : essai arrêté.")
        }
        etapes.append("compte \(moi.affiche) (@\(moi.nom))")
        let p = Publication(id: "essai", compte: c.id, source: u.path, fichier: u.path, titre: "", texte: "", prevuLe: Dates.iso.string(from: Date()),
                            etat: "planifie", phase: "", raison: "", empreinte: "", empreinteFichier: "", taille: 0, ia: false,
                            proposePar: "essai", validePar: "", valideLe: "", ref: "", lien: "", conteneur: "", session: "", tentatives: 0,
                            verifieLe: "", creeLe: "", majLe: "", faitLe: "")
        let envoi = try r.tiktokEnvoyer(p, fichier: u)
        etapes.append("vidéo envoyée en brouillon : \(envoi)")
        var etat = EnvoiTikTok(statut: "", raison: "", post: "")
        let limite = Date().addingTimeInterval(300)
        repeat {
            Thread.sleep(forTimeInterval: 10)
            etat = try r.tiktokEtat(compte: c.id, envoi: envoi)
        } while !["SEND_TO_USER_INBOX", "FAILED", "PUBLISH_COMPLETE"].contains(etat.statut) && Date() < limite
        etapes.append("statut : \(etat.statut) \(etat.raison)")
        etapes.append("rien de public : le brouillon attend dans l'app TikTok (à supprimer par \(Moi.tiers) s'il ne sert pas)")
        sortir(EssaiTikTok(compte: c.id, envoi: envoi, statut: etat.statut, raison: etat.raison, etapes: etapes))
    }

    struct EssaiInstagram: Encodable { let compte: String; let conteneur: String; let statut: String; let detail: String; let etapes: [String] }

    /// Crée un conteneur REELS et y envoie la vidéo depuis le Mac, attend qu'Instagram la traite (5 min au plus). JAMAIS
    /// media_publish : un conteneur non publié n'est visible de personne et expire seul.
    static func essaiInstagram(_ stock: Stockage, _ args: [String]) throws {
        guard let id = option("--compte", args), let c = ComptePublication.trouver(id), c.reseau == .instagram,
              let f = option("--fichier", args) else {
            echouer("pilote publication essai-instagram --compte ig-perso|ig-kryva --fichier VIDEO")
        }
        let u = URL(fileURLWithPath: (f as NSString).expandingTildeInPath)
        let p = Publication(id: "essai", compte: c.id, source: u.path, fichier: u.path, titre: "", texte: "Essai Pilote (jamais publié)",
                            prevuLe: Dates.iso.string(from: Date()), etat: "planifie", phase: "", raison: "", empreinte: "",
                            empreinteFichier: "", taille: 0, ia: false, proposePar: "essai", validePar: "", valideLe: "", ref: "",
                            lien: "", conteneur: "", session: "", tentatives: 0, verifieLe: "", creeLe: "", majLe: "", faitLe: "")
        let r = PlateformesReelles()
        var etapes: [String] = []
        let conteneur = try r.instagramPreparer(p, fichier: u)
        etapes.append("conteneur créé et vidéo envoyée depuis le Mac : \(conteneur)")
        var etat = ConteneurInstagram(code: "", detail: "")
        let limite = Date().addingTimeInterval(300)
        repeat {
            Thread.sleep(forTimeInterval: 10)
            etat = try r.instagramConteneur(compte: c.id, conteneur: conteneur)
        } while (etat.code == "IN_PROGRESS" || etat.code.isEmpty) && Date() < limite
        etapes.append("statut : \(etat.code) \(etat.detail)")
        etapes.append("media_publish PAS appelé (rien de public)")
        sortir(EssaiInstagram(compte: c.id, conteneur: conteneur, statut: etat.code, detail: etat.detail, etapes: etapes))
    }
}
