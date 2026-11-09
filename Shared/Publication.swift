// Publication programmée de vidéos courtes sur les comptes de Sacha (08/11, Sacha : « on va créer un PlugKit directement dans
// Pilote », pour Instagram et YouTube). Les données restent sur le Mac ; seuls ses comptes : YouTube PJK (@sachaprljk, ex-@sachhaaa),
// YouTube KRYVA (@kryva_app), Instagram @sachaprljk et @kryva.fr, TikTok perso et KRYVA (08/11, Sacha : « on fait aussi Tiktok »).
//
// Qui fait quoi :
// - Sacha programme dans l'app (écran Publications) : vidéo, comptes, titre, texte, date. Son clic « Programmer » vaut validation
//   du texte et de la vidéo exacts. Une session (outil `pilote publication programmer`, MCP programme_publication) ne fait que
//   PROPOSER (état a_valider) : rien ne part avant « Valider » dans l'app, ou `valider` avec l'empreinte montrée à Sacha.
// - La vidéo validée est copiée dans le dossier de la base (publications/) : c'est CE fichier qui part (relu par son empreinte
//   juste avant l'envoi), et l'agent launchd n'a pas besoin d'accès au Bureau, aux Documents ni à iCloud Drive.
// - L'agent launchd io.github.pjksens.pilote.publication lance `pilote publication --passe` toutes les minutes (verrou) :
//   YouTube : envoi tout de suite en privé avec publishAt = l'heure prévue ; YouTube publie seul, Mac éteint compris. Après
//     l'heure, Pilote relit la vidéo : publique = « publiée ».
//   Instagram : pas de programmation chez Instagram. 20 min avant l'heure, Pilote crée le conteneur REELS et y envoie la vidéo
//     (rien de public) ; à l'heure, media_publish. Le Mac doit être allumé et éveillé : en veille, launchd ne lance rien ; au réveil,
//     plus de 30 min de retard = pas publiée, échec « à reprogrammer » (jamais une publication à une heure que Sacha n'a pas choisie).
// - Un jeton refusé = compte « à reconnecter » (un bouton dans l'app) ; les vidéos de ce compte attendent la reconnexion.
//   TikTok : sans audit, l'API ne publie qu'en « moi seul » sur un compte privé (inutilisable). Pilote envoie donc la vidéo en
//     BROUILLON dans la boîte TikTok du compte (API Content Posting, « upload » : rien de public) 15 min avant l'heure, et alerte
//     Sacha avec la légende à coller ; c'est lui qui publie depuis l'app TikTok. Pilote relit ensuite l'envoi : « publiée » quand
//     TikTok dit que Sacha l'a postée ; brouillon pas fini 3 jours après = échec (rappel).
// Le réseau est derrière le protocole Plateformes (Shared/PublicationReseaux.swift pour le vrai, un faux dans les tests).
import AVFoundation
import CryptoKit
import Foundation
import ImageIO

enum ReseauPublication: String, Codable { case youtube, instagram, tiktok }

struct ComptePublication: Identifiable, Equatable, Encodable {
    let id: String
    let reseau: ReseauPublication
    /// Le nom montré à Sacha.
    let nom: String
    /// Ce que la connexion doit lire chez la plateforme (customUrl de la chaîne, username Instagram ou TikTok) : un autre compte
    /// est refusé. TikTok : vide tant que le pseudo exact n'est pas connu ; la connexion garde alors l'open_id lu, comparé ensuite.
    let poignee: String
    /// L'identifiant fixe du compte chez la plateforme, quand il est connu (id de chaîne YouTube) : il prime sur la poignée,
    /// qui change quand Sacha renomme le compte (08/11 : @sachhaaa devenue @sachaprljk, même chaîne).
    var idFixe: String = ""
    /// TikTok : le nom affiché attendu (le pseudo n'est pas connu d'avance).
    var nomAffiche: String = ""

    static let tous: [ComptePublication] = [
        ComptePublication(id: "yt-perso", reseau: .youtube, nom: "YouTube · PJK (@sachaprljk)", poignee: "@sachaprljk",
                          idFixe: "UC0000000000000000000001"),
        ComptePublication(id: "yt-kryva", reseau: .youtube, nom: "YouTube · KRYVA (@kryva_app)", poignee: "@kryva_app"),
        // Instagram : id connus (le jeton d'utilisateur système du portefeuille Kryva ne liste pas ses comptes).
        ComptePublication(id: "ig-perso", reseau: .instagram, nom: "Instagram · @sachaprljk", poignee: "sachaprljk",
                          idFixe: "17840000000000001"),
        ComptePublication(id: "ig-kryva", reseau: .instagram, nom: "Instagram · @kryva.fr", poignee: "kryva.fr",
                          idFixe: "17840000000000002"),
        ComptePublication(id: "tt-perso", reseau: .tiktok, nom: "TikTok · sacha • pjk", poignee: "sachaprljk", nomAffiche: "sacha • pjk"),
        ComptePublication(id: "tt-kryva", reseau: .tiktok, nom: "TikTok · KRYVA", poignee: "kryva.fr", nomAffiche: "KRYVA - App pour artisans BTP"),
    ]

    static func trouver(_ id: String) -> ComptePublication? { tous.first { $0.id == id.lowercased() } }

    /// La poignée lue correspond-elle ? (casse et @ ignorés)
    /// Le nom affiché attendu (TikTok, pseudo inconnu) : comparé à la première connexion, sans casse, accents ni signes.
    func afficheCorrespond(_ lu: String) -> Bool {
        func n(_ s: String) -> String {
            String(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        }
        return !nomAffiche.isEmpty && n(lu) == n(nomAffiche)
    }

    func correspond(_ lue: String) -> Bool {
        func n(_ s: String) -> String { s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@ ")) }
        return n(lue) == n(poignee)
    }

    /// Le compte lu est-il bien celui-ci ? Par l'identifiant fixe s'il est connu, sinon par la poignée.
    func reconnait(id: String, poignee lue: String) -> Bool {
        idFixe.isEmpty ? correspond(lue) : id == idFixe
    }

    /// Ce qui est attendu, pour les messages (« @sachaprljk », avec l'id si connu).
    var attendu: String { idFixe.isEmpty ? poignee : "\(poignee) (\(idFixe))" }
}

/// L'état d'un compte, tel que Pilote le connaît (les jetons sont dans le trousseau, jamais ici).
struct EtatComptePublication: Equatable, Encodable {
    var compte: String
    /// jamais, connecte, a_reconnecter
    var etat: String
    /// Le nom lu chez la plateforme à la connexion, et son identifiant (chaîne, compte Instagram).
    var lu: String
    var externeId: String
    var raison: String
    var connecteLe: String
    /// Instagram : fin de validité du jeton (renouvelé seul chaque jour quand il approche).
    var expireLe: String
    var verifieLe: String
}

struct Publication: Identifiable, Equatable, Encodable {
    var id: String
    var compte: String
    /// Le fichier choisi par Sacha (affichage) ; `fichier` : la copie validée qui part.
    var source: String
    var fichier: String
    /// YouTube : le titre. Instagram, TikTok : vide.
    var titre: String
    /// YouTube : la description. Instagram : la légende. TikTok : la légende que Sacha colle dans l'app (l'API n'en prend pas).
    var texte: String
    /// Heure prévue (ISO, UTC).
    var prevuLe: String
    /// a_valider, planifie, envoi, envoye, publie, echec, reconnexion, annule
    var etat: String
    /// Pendant « envoi » : televersement (YouTube, TikTok), preparation ou publication (Instagram).
    /// TikTok « envoye » : boite = le brouillon est dans la boîte TikTok et Sacha a été prévenu.
    var phase: String
    var raison: String
    /// Empreinte de ce qui est validé (compte, titre, texte, heure, contenu généré par IA, empreinte du fichier).
    var empreinte: String
    var empreinteFichier: String
    var taille: Int
    /// YouTube status.containsSyntheticMedia (contenu réaliste modifié ou généré).
    var ia: Bool
    var proposePar: String
    var validePar: String
    var valideLe: String
    /// L'id chez la plateforme (vidéo YouTube, média Instagram, envoi TikTok « publish_id ») et son lien.
    var ref: String
    var lien: String
    /// Instagram : le conteneur créé avant l'heure. YouTube : l'adresse de la session d'envoi (reprise après coupure).
    var conteneur: String
    var session: String
    var tentatives: Int
    var verifieLe: String
    var creeLe: String
    var majLe: String
    var faitLe: String
    /// La couverture validée : l'image copiée (choisie par Sacha, ou l'image de la vidéo à `couvertureMs`), son empreinte,
    /// l'instant choisi dans la vidéo en millisecondes (-1 : aucun). YouTube : miniature posée après le traitement ;
    /// Instagram : `thumb_offset` (l'API ne prend une image que sur un serveur public) ; TikTok : à choisir dans l'app.
    var couverture: String = ""
    var empreinteCouverture: String = ""
    var couvertureMs: Int = -1
    /// YouTube : a_poser, posee, refusee : raison. Vide : rien à poser.
    var couvertureEtat: String = ""
    var couvertureEssais: Int = 0
    /// Venue d'un post PlugKit (son id) : à sa validation, une ligne REVEIL demande à PILOTE de retirer ce post
    /// (sinon double publication) ; rien ne part chez la plateforme tant que cette ligne n'est pas écrite (`plugkitReveilLe`).
    var plugkit: String = ""
    var plugkitReveilLe: String = ""

    /// `session` (l'adresse d'envoi YouTube en cours) ne sort jamais de la base.
    enum CodingKeys: String, CodingKey {
        case id, compte, source, fichier, titre, texte, prevuLe, etat, phase, raison, empreinte, empreinteFichier, taille, ia
        case proposePar, validePar, valideLe, ref, lien, conteneur, tentatives, verifieLe, creeLe, majLe, faitLe
        case couverture, couvertureMs, couvertureEtat, plugkit, plugkitReveilLe
    }

    var aCouverture: Bool { !couverture.isEmpty || couvertureMs >= 0 }

    var reseau: ReseauPublication { ComptePublication.trouver(compte)?.reseau ?? .youtube }
    var actif: Bool { Publications.etatsActifs.contains(etat) }
    var prevu: Date? { Dates.iso.date(from: prevuLe) }
}

/// Une demande de programmation : une vidéo, un ou plusieurs comptes (une ligne par compte).
struct DemandePublication {
    var comptes: [String]
    var fichier: String
    var titre: String
    var texte: String
    var prevuLe: Date
    var ia: Bool = false
    var par: String
    /// Couverture : une image (jpg, png) et/ou un instant de la vidéo en secondes.
    var couverture: String = ""
    var couvertureA: Double? = nil
    /// L'id du post PlugKit que cette publication remplace (vide : pris dans `par` s'il dit « PlugKit <id> »).
    var plugkit: String = ""
}

struct RefusPublication: Error, CustomStringConvertible {
    let raisons: [String]
    var description: String { "Refusé, rien n'est programmé : " + raisons.joined(separator: " ; ") }
}

/// Ce que dit la plateforme d'une erreur : la suite à donner en dépend.
enum ErreurPlateforme: Error, CustomStringConvertible, Equatable {
    /// Jeton refusé, expiré ou retiré : le compte est à reconnecter (les vidéos attendent).
    case reconnexion(String)
    /// Refus de la plateforme pour cette vidéo (format, texte, heure) : échec, avec la raison.
    case definitive(String)
    /// Réseau, serveur : réessayé à la passe suivante (5 fois au plus).
    case passagere(String)
    /// Quota du jour du projet atteint (YouTube quotaExceeded, remis à zéro à minuit heure du Pacifique) : la vidéo attend
    /// la remise à zéro, sans compter d'essai raté ; échec seulement si l'heure de publication arrive avant.
    case quota(String)
    /// YouTube uploadLimitExceeded : la limite d'envois de la CHAÎNE (pas le quota du projet ; YouTube n'en donne pas le chiffre).
    /// Les vidéos de cette chaîne attendent ; les autres chaînes continuent.
    case limiteChaine(String)

    var description: String {
        switch self {
        case .reconnexion(let m), .definitive(let m), .passagere(let m), .quota(let m), .limiteChaine(let m): return m
        }
    }
}

struct EtatVideoYouTube: Equatable {
    /// private, public, unlisted
    var confidentialite: String
    var publierLe: String
    /// uploaded, processed, failed, rejected, deleted
    var envoi: String
    var raisonRefus: String
    /// processingDetails.processingStatus : processing, succeeded, failed, terminated.
    var traitement: String = ""
}

struct ConteneurInstagram: Equatable {
    /// IN_PROGRESS, FINISHED, PUBLISHED, ERROR, EXPIRED
    var code: String
    var detail: String
}

struct EnvoiTikTok: Equatable {
    /// PROCESSING_UPLOAD, PROCESSING_DOWNLOAD, SEND_TO_USER_INBOX (brouillon dans la boîte), PUBLISH_COMPLETE (Sacha l'a
    /// postée), FAILED
    var statut: String
    var raison: String
    /// L'id du post public, quand TikTok le donne.
    var post: String
}

protocol Plateformes {
    /// Envoie la vidéo en privé, publishAt = p.prevuLe. Reprend la session `p.session` si elle existe ; `noterSession` garde
    /// l'adresse d'une nouvelle session avant le premier octet. Rend l'id de la vidéo.
    func youtubeTeleverser(_ p: Publication, fichier: URL, noterSession: (String) throws -> Void) throws -> String
    /// nil : la vidéo n'existe plus (supprimée).
    func youtubeEtat(compte: String, video: String) throws -> EtatVideoYouTube?
    func youtubeSupprimer(compte: String, video: String) throws
    /// Pose la miniature (couverture) d'une vidéo traitée.
    func youtubeMiniature(compte: String, video: String, image: URL) throws
    /// Crée le conteneur REELS et y envoie la vidéo (rien de public). Rend l'id du conteneur.
    func instagramPreparer(_ p: Publication, fichier: URL) throws -> String
    func instagramConteneur(compte: String, conteneur: String) throws -> ConteneurInstagram
    /// media_publish : rend l'id du média et son lien.
    func instagramPublier(compte: String, conteneur: String) throws -> (media: String, lien: String)
    /// Envoie la vidéo en brouillon dans la boîte TikTok du compte (rien de public). Rend le publish_id.
    func tiktokEnvoyer(_ p: Publication, fichier: URL) throws -> String
    func tiktokEtat(compte: String, envoi: String) throws -> EnvoiTikTok
    /// Une fois par jour : le jeton marche-t-il encore ? (Instagram : renouvelé s'il approche de sa fin.) Rend la nouvelle fin de
    /// validité si elle a changé.
    func entretien(compte: String) throws -> String?
}

struct AlertePublication: Encodable, Equatable {
    var id: String
    var le: String
    var titre: String
    var texte: String
    var grave: Bool
}

struct BilanPublication: Encodable {
    var envoyees: [String] = []
    var publiees: [String] = []
    var echecs: [String] = []
    var reconnexions: [String] = []
    var suite = ""
}

enum Publications {
    static let etiquette = "io.github.pjksens.pilote.publication"
    static let etatsActifs: Set<String> = ["a_valider", "planifie", "envoi", "envoye", "reconnexion"]
    /// Au moins 15 min entre la programmation (ou la validation) et l'heure ; au plus 6 mois.
    static let avanceMin: TimeInterval = 15 * 60
    static let avanceMax: TimeInterval = 183 * 86400
    /// Instagram : conteneur créé 20 min avant l'heure ; plus de 30 min de retard = pas publiée.
    static let preparationIG: TimeInterval = 20 * 60
    static let retardMax: TimeInterval = 30 * 60
    /// YouTube : l'heure doit être encore devant au moment de l'envoi (2 min au moins).
    static let margeYouTube: TimeInterval = 2 * 60
    /// YouTube : relue 3 min après l'heure, puis toutes les 10 min ; toujours privée 3 h après = échec.
    static let relectureYouTube: TimeInterval = 10 * 60
    static let delaiPublicYouTube: TimeInterval = 3 * 3600
    static let tentativesMax = 5
    /// Raison notée quand le quota YouTube du jour est atteint (la vidéo attend sa remise à zéro).
    static let raisonQuotaYouTube = "quota YouTube du jour atteint"
    /// YouTube uploadLimitExceeded. YouTube ne publie pas le chiffre (« une limite par jour et par chaîne, ordinateur, mobile
    /// et API », aide YouTube 57407). Le 09/11, yt-perso a été refusée au 10e envoi en 6 min ; supprimer une vidéo envoyée
    /// n'a pas rendu de place ; yt-kryva en a pris 5 juste après.
    static let raisonLimiteChaine = "limite d'envois de la chaîne YouTube atteinte"
    /// Plafond de Pilote, sous la limite de YouTube : 6 envois par chaîne sur 24 h glissantes (vidéos annulées comprises).
    static let envoisMaxYouTube = 6
    static let raisonPlafondYouTube = "plafond de Pilote : \(envoisMaxYouTube) envois par chaîne sur 24 h"
    /// YouTube : une vidéo part chez YouTube au plus 3 jours avant son heure, et jamais avant une plus proche de la même chaîne.
    static let horizonYouTube: TimeInterval = 3 * 86400
    static let raisonTourYouTube = "attend son tour : une vidéo plus proche de cette chaîne n'est pas encore partie"

    /// Les envois YouTube réussis de ce compte depuis `depuis`, du plus ancien au plus récent (annulées comprises).
    static func envoisYouTube(_ stock: Stockage, compte: String, depuis: Date) throws -> [Date] {
        try stock.base.lignes("SELECT televerse_le FROM publications WHERE compte = ? AND televerse_le > ? ORDER BY televerse_le",
                              [compte, Dates.iso.string(from: depuis)])
            .compactMap { ($0["televerse_le"] as? String).flatMap(Dates.iso.date) }
    }

    /// Limite de la chaîne atteinte à `t` : nouvel essai 24 h (+10 min) après le plus ancien envoi de Pilote des dernières 24 h,
    /// 1 h au moins. Sans envoi connu (Studio, ou fenêtre de YouTube plus longue) : un essai par heure (l'ouverture de
    /// l'envoi est refusée avant que la vidéo parte : un essai ne coûte rien).
    static func remiseLimiteChaine(_ stock: Stockage, compte: String, apres t: Date) throws -> Date {
        let plusAncien = try envoisYouTube(stock, compte: compte, depuis: t.addingTimeInterval(-86400)).first
        return max(t.addingTimeInterval(3600), plusAncien?.addingTimeInterval(86400 + 600) ?? t)
    }
    static func cleLimiteChaine(_ compte: String) -> String { "publication.limite.\(compte)" }

    /// Le quota YouTube revient à minuit, heure du Pacifique (9 h à Paris en hiver) : la 1re remise après `le`.
    static func remiseQuotaYouTube(apres le: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal.nextDate(after: le, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) ?? le.addingTimeInterval(86400)
    }
    static let extensions: Set<String> = ["mp4", "mov", "m4v"]
    static let extensionsImage: Set<String> = ["jpg", "jpeg", "png"]
    /// YouTube thumbnails.set : 50 Mo au plus (jpeg, png).
    static let tailleMaxCouverture = 50 * 1024 * 1024
    static let tailleMaxIG = 300 * 1024 * 1024
    /// TikTok : brouillon envoyé 15 min avant l'heure ; plus de 6 h de retard = pas envoyé (à reprogrammer) ; relu chaque minute
    /// jusqu'à la boîte, puis toutes les 15 min ; brouillon pas publié 3 jours après l'heure = échec (rappel à Sacha).
    static let preparationTT: TimeInterval = 15 * 60
    static let retardTT: TimeInterval = 6 * 3600
    static let relectureTT: TimeInterval = 15 * 60
    static let attenteBoiteTT: TimeInterval = 3 * 86400
    static let traitementTT: TimeInterval = 2 * 3600
    static let tailleMaxTT = 4 * 1024 * 1024 * 1024

    // MARK: Lecture

    static func publication(_ l: [String: Any]) -> Publication {
        func t(_ k: String) -> String { l[k] as? String ?? "" }
        func n(_ k: String) -> Int { l[k] as? Int ?? 0 }
        return Publication(id: t("id"), compte: t("compte"), source: t("source"), fichier: t("fichier"), titre: t("titre"),
                           texte: t("texte"), prevuLe: t("prevu_le"), etat: t("etat"), phase: t("phase"), raison: t("raison"),
                           empreinte: t("empreinte"), empreinteFichier: t("empreinte_fichier"), taille: n("taille"),
                           ia: n("ia") != 0, proposePar: t("propose_par"), validePar: t("valide_par"), valideLe: t("valide_le"),
                           ref: t("ref"), lien: t("lien"), conteneur: t("conteneur"), session: t("session"),
                           tentatives: n("tentatives"), verifieLe: t("verifie_le"), creeLe: t("cree_le"), majLe: t("maj_le"),
                           faitLe: t("fait_le"), couverture: t("couverture"), empreinteCouverture: t("empreinte_couverture"),
                           couvertureMs: l["couverture_ms"] as? Int ?? -1, couvertureEtat: t("couverture_etat"),
                           couvertureEssais: n("couverture_essais"), plugkit: t("plugkit"), plugkitReveilLe: t("plugkit_reveil_le"))
    }

    /// Tout, de la plus proche à la plus lointaine ; les terminées (publiées, échecs, annulées) de plus de `jours` jours ôtées.
    static func liste(_ stock: Stockage, jours: Int = 30, maintenant: Date = Date()) throws -> [Publication] {
        let limite = Dates.iso.string(from: maintenant.addingTimeInterval(-Double(jours) * 86400))
        return try stock.base.lignes("""
            SELECT * FROM publications WHERE etat IN ('a_valider', 'planifie', 'envoi', 'envoye', 'reconnexion') OR prevu_le >= ?
            ORDER BY prevu_le, rowid
            """, [limite]).map(publication)
    }

    /// Le planning : tout ce qui est prévu entre deux dates (annulées comprises : la vue choisit).
    static func entre(_ stock: Stockage, _ debut: Date, _ fin: Date) throws -> [Publication] {
        try stock.base.lignes("SELECT * FROM publications WHERE prevu_le >= ? AND prevu_le < ? ORDER BY prevu_le, rowid",
                              [Dates.iso.string(from: debut), Dates.iso.string(from: fin)]).map(publication)
    }

    static func trouver(_ stock: Stockage, _ id: String) throws -> Publication? {
        let l = try stock.base.lignes("SELECT * FROM publications WHERE id = ? OR id LIKE ? ORDER BY rowid LIMIT 2", [id, id + "%"])
        guard l.count == 1 || (l.first?["id"] as? String) == id else { return nil }
        return l.first.map(publication)
    }

    static func etatCompte(_ stock: Stockage, _ compte: String) throws -> EtatComptePublication {
        if let l = try stock.base.lignes("SELECT * FROM comptes_publication WHERE compte = ?", [compte]).first {
            func t(_ k: String) -> String { l[k] as? String ?? "" }
            return EtatComptePublication(compte: compte, etat: t("etat"), lu: t("lu"), externeId: t("externe_id"), raison: t("raison"),
                                         connecteLe: t("connecte_le"), expireLe: t("expire_le"), verifieLe: t("verifie_le"))
        }
        return EtatComptePublication(compte: compte, etat: "jamais", lu: "", externeId: "", raison: "", connecteLe: "", expireLe: "", verifieLe: "")
    }

    static func comptes(_ stock: Stockage) throws -> [EtatComptePublication] {
        try ComptePublication.tous.map { try etatCompte(stock, $0.id) }
    }

    static func noterCompte(_ stock: Stockage, _ e: EtatComptePublication) throws {
        try stock.base.executer("""
            INSERT INTO comptes_publication (compte, etat, lu, externe_id, raison, connecte_le, expire_le, verifie_le)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(compte) DO UPDATE SET etat = excluded.etat, lu = excluded.lu, externe_id = excluded.externe_id,
              raison = excluded.raison, connecte_le = excluded.connecte_le, expire_le = excluded.expire_le, verifie_le = excluded.verifie_le
            """, [e.compte, e.etat, e.lu, e.externeId, e.raison, e.connecteLe, e.expireLe, e.verifieLe])
    }

    /// Le compte vient d'être (re)connecté : les vidéos qui attendaient la reconnexion repartent.
    /// Note où en est une connexion (en cours, ou la raison de son échec) sans changer l'état du compte : l'app l'affiche
    /// même si on a changé d'écran pendant l'attente.
    static func noterTentative(_ stock: Stockage, compte: String, raison: String) throws {
        var e = try etatCompte(stock, compte)
        e.raison = raison
        try noterCompte(stock, e)
    }

    static func compteConnecte(_ stock: Stockage, compte: String, lu: String, externeId: String, expireLe: String, maintenant: Date = Date()) throws {
        let m = Dates.iso.string(from: maintenant)
        try noterCompte(stock, EtatComptePublication(compte: compte, etat: "connecte", lu: lu, externeId: externeId, raison: "",
                                                     connecteLe: m, expireLe: expireLe, verifieLe: m))
        try stock.base.executer("""
            UPDATE publications SET etat = 'planifie', raison = 'compte reconnecté : reprise', tentatives = 0, maj_le = ?
            WHERE compte = ? AND etat = 'reconnexion' AND ref = ''
            """, [m, compte])
        try stock.base.executer("""
            UPDATE publications SET etat = 'envoye', raison = 'compte reconnecté : reprise', tentatives = 0, maj_le = ?
            WHERE compte = ? AND etat = 'reconnexion' AND ref != ''
            """, [m, compte])
    }

    // MARK: Empreintes

    static func empreinteFichier(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var sha = SHA256()
        while let d = try h.read(upToCount: 8 << 20), !d.isEmpty { sha.update(data: d) }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Sans couverture, l'empreinte reste celle d'avant le 08/11 (les publications déjà validées restent valables).
    static func empreinte(compte: String, titre: String, texte: String, prevuLe: String, ia: Bool, empreinteFichier: String,
                          empreinteCouverture: String = "", couvertureMs: Int = -1) -> String {
        var champs = [compte, titre, texte, prevuLe, ia ? "ia" : "", empreinteFichier]
        if !empreinteCouverture.isEmpty || couvertureMs >= 0 { champs += [empreinteCouverture, String(couvertureMs)] }
        let s = champs.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    static func empreinte(_ p: Publication) -> String {
        empreinte(compte: p.compte, titre: p.titre, texte: p.texte, prevuLe: p.prevuLe, ia: p.ia, empreinteFichier: p.empreinteFichier,
                  empreinteCouverture: p.empreinteCouverture, couvertureMs: p.couvertureMs)
    }

    // MARK: Vérifications

    struct InfosVideo: Equatable { var duree: Double; var largeur: Int; var hauteur: Int }

    /// Durée et taille d'image (rotation comprise). nil : illisible par AVFoundation.
    static func infosVideo(_ url: URL) -> InfosVideo? {
        let a = AVURLAsset(url: url)
        let duree = CMTimeGetSeconds(a.duration)
        guard duree.isFinite, duree > 0, let piste = a.tracks(withMediaType: .video).first else { return nil }
        let r = piste.naturalSize.applying(piste.preferredTransform)
        return InfosVideo(duree: duree, largeur: Int(abs(r.width).rounded()), hauteur: Int(abs(r.height).rounded()))
    }

    /// L'image de la vidéo à `a` secondes, écrite en JPEG (`taille` : le plus grand côté, 0 = taille réelle). false : illisible.
    @discardableResult
    static func imageDeLaVideo(_ video: URL, a: Double, vers: URL, taille: CGFloat = 0) -> Bool {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        if taille > 0 { g.maximumSize = CGSize(width: taille, height: taille) }
        guard let image = try? g.copyCGImage(at: CMTime(seconds: a, preferredTimescale: 600), actualTime: nil),
              let dest = CGImageDestinationCreateWithURL(vers as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// Ce qui sert de couverture, en clair (montré à Sacha avant qu'il valide).
    static func couvertureTexte(_ p: Publication) -> String {
        let instant = p.couvertureMs >= 0 ? String(format: "%.1f s", Double(p.couvertureMs) / 1000).replacingOccurrences(of: ".", with: ",") : ""
        guard p.aCouverture else { return "aucune choisie (la plateforme prend la sienne)" }
        switch p.reseau {
        case .youtube:
            let etat = p.couvertureEtat == "posee" ? " ; posée chez YouTube"
                : p.couvertureEtat.hasPrefix("refusee") ? " ; " + p.couvertureEtat.replacingOccurrences(of: "refusee : ", with: "pas posée : ")
                : " ; posée après le traitement de la vidéo"
            return (instant.isEmpty || !p.couverture.hasSuffix("-\(p.couvertureMs).jpg") ? "image \(URL(fileURLWithPath: p.couverture).lastPathComponent)"
                    : "l'image de la vidéo à \(instant)") + etat
        case .instagram:
            return instant.isEmpty ? "1re image de la vidéo (l'API Instagram ne prend pas l'image choisie)" : "l'image de la vidéo à \(instant)"
        case .tiktok:
            return "à choisir dans TikTok en publiant le brouillon" + (instant.isEmpty ? "" : " (l'image de la vidéo à \(instant))")
        }
    }

    /// La petite image d'une publication pour le planning : sa couverture, sinon l'image de la vidéo à 1 s (gardée à côté).
    static func vignette(_ p: Publication) -> URL? {
        if !p.couverture.isEmpty, FileManager.default.fileExists(atPath: p.couverture) { return URL(fileURLWithPath: p.couverture) }
        let video = URL(fileURLWithPath: p.fichier)
        guard !p.empreinteFichier.isEmpty else { return nil }
        let v = video.deletingLastPathComponent().appendingPathComponent("\(p.empreinteFichier.prefix(16))-vignette.jpg")
        if FileManager.default.fileExists(atPath: v.path) { return v }   // gardée même quand la copie est effacée
        guard FileManager.default.fileExists(atPath: video.path) else { return nil }
        let a = min(1, (infosVideo(video)?.duree ?? 2) / 2)
        return imageDeLaVideo(video, a: a, vers: v, taille: 480) ? v : nil
    }

    /// Les raisons de refuser (vides = OK) et les avertissements (montrés, n'empêchent rien).
    static func verifier(compte: String, titre: String, texte: String, prevuLe: Date, fichier: URL, taille: Int, infos: InfosVideo?,
                         maintenant: Date) -> (refus: [String], avertissements: [String]) {
        var refus: [String] = [], avert: [String] = []
        guard let c = ComptePublication.trouver(compte) else {
            return (["compte inconnu « \(compte) » (\(ComptePublication.tous.map(\.id).joined(separator: ", ")))"], [])
        }
        if prevuLe < maintenant.addingTimeInterval(avanceMin) { refus.append("heure trop proche ou passée : au moins 15 min à l'avance") }
        if prevuLe > maintenant.addingTimeInterval(avanceMax) { refus.append("heure à plus de 6 mois") }
        if !extensions.contains(fichier.pathExtension.lowercased()) { refus.append("format « .\(fichier.pathExtension) » : .mp4 ou .mov seulement") }
        if taille <= 0 { refus.append("fichier vide") }
        if infos == nil { refus.append("vidéo illisible (fichier abîmé ou pas une vidéo)") }
        switch c.reseau {
        case .youtube:
            let t = titre.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { refus.append("titre YouTube vide") }
            if t.count > 100 { refus.append("titre YouTube de \(t.count) caractères (100 au plus)") }
            if titre.contains("<") || titre.contains(">") || texte.contains("<") || texte.contains(">") {
                refus.append("YouTube refuse les signes < et > dans le titre et la description")
            }
            if texte.utf8.count > 5000 { refus.append("description YouTube trop longue (5 000 octets au plus)") }
            if let i = infos {
                if i.duree > 180 { avert.append("vidéo de \(Int(i.duree)) s : au-delà de 3 min, YouTube n'en fait pas un Short") }
                if i.hauteur <= i.largeur { avert.append("vidéo pas verticale (\(i.largeur)×\(i.hauteur)) : YouTube n'en fera pas un Short") }
            }
        case .instagram:
            if !titre.trimmingCharacters(in: .whitespaces).isEmpty { avert.append("Instagram n'a pas de titre : seule la légende part") }
            if texte.count > 2200 { refus.append("légende Instagram de \(texte.count) caractères (2 200 au plus)") }
            if texte.split(separator: "#", omittingEmptySubsequences: false).count - 1 > 30 { refus.append("plus de 30 hashtags (Instagram refuse)") }
            if texte.split(separator: "@", omittingEmptySubsequences: false).count - 1 > 20 { refus.append("plus de 20 mentions @ (Instagram refuse)") }
            if taille > tailleMaxIG { refus.append("vidéo de plus de 300 Mo (Instagram refuse)") }
            if let i = infos {
                if i.duree < 3 { refus.append("vidéo de moins de 3 s (Instagram refuse)") }
                if i.duree > 900 { refus.append("vidéo de plus de 15 min (Instagram refuse)") }
                if i.hauteur <= i.largeur { avert.append("vidéo pas verticale (\(i.largeur)×\(i.hauteur)) : recadrée en Reel") }
            }
        case .tiktok:
            if !titre.trimmingCharacters(in: .whitespaces).isEmpty { avert.append("TikTok n'a pas de titre : seule la légende compte") }
            // TikTok : l'API du brouillon ne prend pas la légende ; Sacha la colle dans l'app (2 200 caractères au plus).
            if texte.count > 2200 { refus.append("légende TikTok de \(texte.count) caractères (2 200 au plus)") }
            if taille > tailleMaxTT { refus.append("vidéo de plus de 4 Go (TikTok refuse)") }
            avert.append("TikTok : Pilote envoie un brouillon dans la boîte TikTok 15 min avant l'heure ; \(Moi.nom) le publie depuis l'app (légende à coller)")
            if let i = infos {
                if i.duree > 600 { avert.append("vidéo de \(Int(i.duree)) s : au-delà de 10 min, TikTok peut la refuser") }
                if i.hauteur <= i.largeur { avert.append("vidéo pas verticale (\(i.largeur)×\(i.hauteur))") }
            }
        }
        return (refus, avert)
    }

    // MARK: Programmer (Sacha dans l'app : validée ; une session : proposée, à valider)

    struct Programmees: Encodable {
        var publications: [Publication]
        var avertissements: [String]
    }

    /// Le dossier où partent les copies validées (à côté de la base : une copie d'essai n'écrit rien chez la vraie).
    static var dossierVideos: URL { Base.cheminParDefaut.deletingLastPathComponent().appendingPathComponent("publications", isDirectory: true) }

    @discardableResult
    static func programmer(_ stock: Stockage, _ d: DemandePublication, validee: Bool, dossier: URL = Publications.dossierVideos,
                           maintenant: Date = Date()) throws -> Programmees {
        let source = URL(fileURLWithPath: Chemins.complet(d.fichier)).standardizedFileURL
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw RefusPublication(raisons: ["vidéo introuvable ou illisible : \(source.path)"])
        }
        let comptes = Array(NSOrderedSet(array: d.comptes.map { $0.lowercased() })) as? [String] ?? d.comptes
        guard !comptes.isEmpty else { throw RefusPublication(raisons: ["aucun compte choisi"]) }
        let taille = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
        let infos = infosVideo(source)
        let sha = try empreinteFichier(source)
        // La seconde près suffit (l'heure est montrée à la minute) : l'empreinte ne dépend pas des millisecondes.
        let prevu = Date(timeIntervalSince1970: d.prevuLe.timeIntervalSince1970.rounded(.down))
        let prevuLe = Dates.iso.string(from: prevu)
        var refus: [String] = [], avert: [String] = []
        for c in comptes {
            let v = verifier(compte: c, titre: d.titre, texte: d.texte, prevuLe: prevu, fichier: source, taille: taille, infos: infos, maintenant: maintenant)
            let nom = ComptePublication.trouver(c)?.nom ?? c
            refus += v.refus.map { comptes.count > 1 ? "\(nom) : \($0)" : $0 }
            avert += v.avertissements.map { comptes.count > 1 ? "\(nom) : \($0)" : $0 }
            let deja = try stock.base.lignes("""
                SELECT prevu_le FROM publications WHERE compte = ? AND empreinte_fichier = ?
                AND etat IN ('a_valider', 'planifie', 'envoi', 'envoye', 'reconnexion', 'publie')
                """, [c, sha])
            if let p = deja.first?["prevu_le"] as? String {
                refus.append("\(nom) : cette vidéo y est déjà programmée ou publiée (\(heureParis(p)))")
            }
        }
        // La couverture : une image et/ou un instant de la vidéo.
        let imageSource = d.couverture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil
            : URL(fileURLWithPath: Chemins.complet(d.couverture)).standardizedFileURL
        let couvertureMs = d.couvertureA.map { Int(($0 * 1000).rounded()) } ?? -1
        if let i = imageSource {
            let taille = (try? FileManager.default.attributesOfItem(atPath: i.path)[.size] as? Int) ?? 0
            if !FileManager.default.isReadableFile(atPath: i.path) { refus.append("image de couverture introuvable : \(i.path)") }
            else if !extensionsImage.contains(i.pathExtension.lowercased()) { refus.append("couverture « .\(i.pathExtension) » : .jpg ou .png seulement") }
            else if taille <= 0 || taille > tailleMaxCouverture { refus.append("image de couverture vide ou de plus de 50 Mo") }
            else if taille > 2 * 1024 * 1024 && comptes.contains(where: { ComptePublication.trouver($0)?.reseau == .youtube }) {
                avert.append("couverture de plus de 2 Mo : YouTube Studio limite les miniatures à 2 Mo, l'API peut la refuser")
            }
        }
        if let a = d.couvertureA {
            if a < 0 || (infos.map { a >= $0.duree } ?? false) {
                refus.append("instant de couverture \(a) s hors de la vidéo (\(infos.map { "0 à \(Int($0.duree)) s" } ?? "durée illisible"))")
            }
        }
        if imageSource != nil || couvertureMs >= 0 {
            let reseaux = Set(comptes.compactMap { ComptePublication.trouver($0)?.reseau })
            if reseaux.contains(.instagram) {
                avert.append(couvertureMs >= 0
                    ? "Instagram : couverture = l'image de la vidéo à \(String(format: "%.1f", Double(couvertureMs) / 1000)) s\(imageSource != nil ? " (l'image choisie ne passe pas : l'API ne la prend que depuis un serveur public)" : "")"
                    : "Instagram : l'API ne prend une image de couverture que depuis un serveur public ; donner un instant de la vidéo, sinon Instagram prend la 1re image")
            }
            if reseaux.contains(.youtube) {
                avert.append("YouTube : miniature posée après le traitement de la vidéo ; si la chaîne n'a pas le droit aux miniatures personnalisées, YouTube garde la sienne (Pilote prévient)")
            }
            if reseaux.contains(.tiktok) { avert.append("TikTok : l'API ne prend pas de couverture ; \(Moi.nom) la choisit dans TikTok en publiant le brouillon") }
        }
        refus = Array(NSOrderedSet(array: refus)) as? [String] ?? refus
        guard refus.isEmpty else { throw RefusPublication(raisons: refus) }

        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let copie = dossier.appendingPathComponent("\(sha.prefix(16)).\(source.pathExtension.lowercased())")
        if !FileManager.default.fileExists(atPath: copie.path) {
            let tmp = copie.appendingPathExtension("copie")
            try? FileManager.default.removeItem(at: tmp)
            // Même disque (APFS) : clone, sans place en plus ; sinon copie.
            if clonefile(source.path, tmp.path, 0) != 0 { try FileManager.default.copyItem(at: source, to: tmp) }
            guard try empreinteFichier(tmp) == sha else {
                try? FileManager.default.removeItem(at: tmp)
                throw RefusPublication(raisons: ["la vidéo a changé pendant la copie : réessayer quand elle est finie d'écrire"])
            }
            try FileManager.default.moveItem(at: tmp, to: copie)
        }
        // La couverture copiée à côté de la vidéo : l'image choisie, sinon l'image de la vidéo à l'instant choisi.
        var couverture = "", shaCouverture = ""
        if let i = imageSource {
            let sha = try empreinteFichier(i)
            let c = dossier.appendingPathComponent("\(sha.prefix(16)).\(i.pathExtension.lowercased() == "png" ? "png" : "jpg")")
            if !FileManager.default.fileExists(atPath: c.path) { try FileManager.default.copyItem(at: i, to: c) }
            guard try empreinteFichier(c) == sha else { throw RefusPublication(raisons: ["l'image de couverture a changé pendant la copie : réessayer"]) }
            couverture = c.path; shaCouverture = sha
        } else if couvertureMs >= 0 {
            let c = dossier.appendingPathComponent("\(sha.prefix(16))-\(couvertureMs).jpg")
            if !FileManager.default.fileExists(atPath: c.path) {
                guard imageDeLaVideo(copie, a: Double(couvertureMs) / 1000, vers: c) else {
                    throw RefusPublication(raisons: ["image de la vidéo à \(Double(couvertureMs) / 1000) s illisible : choisir un autre instant"])
                }
            }
            couverture = c.path; shaCouverture = try empreinteFichier(c)
        }
        let m = Dates.iso.string(from: maintenant)
        let plugkit = d.plugkit.isEmpty ? idPlugKit(dans: d.par) : d.plugkit
        if validee && !plugkit.isEmpty {
            throw RefusPublication(raisons: ["venue de PlugKit (\(plugkit)) : elle se programme « à valider », la validation écrit le REVEIL de retrait pour PILOTE"])
        }
        var ids: [String] = []
        try stock.base.transaction {
            for c in comptes {
                let id = UUID().uuidString.lowercased()
                let titre = ComptePublication.trouver(c)?.reseau == .youtube ? d.titre.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let e = empreinte(compte: c, titre: titre, texte: d.texte, prevuLe: prevuLe, ia: d.ia, empreinteFichier: sha,
                                  empreinteCouverture: shaCouverture, couvertureMs: couvertureMs)
                let aPoser = !couverture.isEmpty && ComptePublication.trouver(c)?.reseau == .youtube
                try stock.base.executer("""
                    INSERT INTO publications (id, compte, source, fichier, titre, texte, prevu_le, etat, phase, raison, empreinte,
                      empreinte_fichier, taille, ia, propose_par, valide_par, valide_le, ref, lien, conteneur, session, tentatives,
                      verifie_le, cree_le, maj_le, fait_le, couverture, empreinte_couverture, couverture_ms, couverture_etat, plugkit)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', '', ?, ?, ?, ?, ?, ?, ?, '', '', '', '', 0, '', ?, ?, '', ?, ?, ?, ?, ?)
                    """, [id, c, source.path, copie.path, titre, d.texte, prevuLe, validee ? "planifie" : "a_valider", e, sha, taille,
                          d.ia, d.par, validee ? d.par : "", validee ? m : "", m, m, couverture, shaCouverture, couvertureMs,
                          aPoser ? "a_poser" : "", plugkit])
                ids.append(id)
            }
        }
        return Programmees(publications: try ids.compactMap { try trouver(stock, $0) }, avertissements: avert)
    }

    /// Une publication proposée (a_valider) est validée : seulement avec l'empreinte de ce qui a été montré à Sacha.
    @discardableResult
    static func valider(_ stock: Stockage, id: String, empreinte e: String, par: String, maintenant: Date = Date()) throws -> Publication {
        guard let p = try trouver(stock, id) else { throw RefusPublication(raisons: ["publication introuvable : \(id)"]) }
        guard p.etat == "a_valider" else { throw RefusPublication(raisons: ["déjà « \(p.etat) » : rien à valider"]) }
        guard e == p.empreinte, empreinte(p) == p.empreinte else {
            throw RefusPublication(raisons: ["l'empreinte ne correspond pas : la publication a changé depuis ce qui a été montré, la remontrer à \(Moi.nom)"])
        }
        if let d = p.prevu, d < maintenant.addingTimeInterval(avanceMin) {
            throw RefusPublication(raisons: ["heure trop proche ou passée (\(heureParis(p.prevuLe))) : la reprogrammer"])
        }
        let m = Dates.iso.string(from: maintenant)
        // Venue de PlugKit : la ligne pour PILOTE (retirer le post) d'abord ; pas écrite, pas validée.
        var reveil = ""
        if !p.plugkit.isEmpty {
            do { try ecrireReveilPlugKit(stock, p, le: maintenant) } catch {
                throw RefusPublication(raisons: ["la ligne pour PILOTE (retirer le post PlugKit \(p.plugkit)) n'a pas pu être écrite (\(error)) : rien n'est validé, réessayer"])
            }
            reveil = m
        }
        try stock.base.executer("""
            UPDATE publications SET etat = 'planifie', valide_par = ?, valide_le = ?, maj_le = ?,
              plugkit_reveil_le = CASE WHEN ? = '' THEN plugkit_reveil_le ELSE ? END
            WHERE id = ? AND etat = 'a_valider'
            """, [par, m, m, reveil, reveil, p.id])
        return try trouver(stock, p.id) ?? p
    }

    /// « PlugKit <id> (…) » dans `propose_par` : l'id du post PlugKit.
    static func idPlugKit(dans par: String) -> String {
        let mots = par.split(separator: " ")
        guard mots.count >= 2, mots[0] == "PlugKit" else { return "" }
        let id = String(mots[1])
        return id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) ? id : ""
    }

    /// Le fichier d'alertes à côté de la base utilisée (lu par scripts/veille.py ; une copie d'essai a le sien).
    static func fichierAlertes(_ stock: Stockage) -> URL {
        stock.base.chemin.deletingLastPathComponent().appendingPathComponent("file-envoi-alertes.jsonl")
    }

    /// La ligne REVEIL pour PILOTE : retirer de PlugKit le post que cette publication remplace.
    static func ecrireReveilPlugKit(_ stock: Stockage, _ p: Publication, le maintenant: Date) throws {
        let nom = ComptePublication.trouver(p.compte)?.nom ?? p.compte
        try FileEnvoi.ecrire(AlerteFile(
            id: "plugkit-retrait-\(p.id.prefix(8))", le: Dates.iso.string(from: maintenant), titre: "Pilote · retirer le post PlugKit",
            texte: "\(Moi.nom) a validé dans Pilote la publication \(p.id.prefix(8)) (\(nom), \(heureParis(p.prevuLe)), « \(apercu(p)) ») : "
                + "retirer le post PlugKit \(p.plugkit) avant son heure, sinon double publication. Pilote l'envoie à la plateforme dès maintenant.",
            grave: true), dans: fichierAlertes(stock))
    }

    /// Annuler. YouTube déjà envoyée : la vidéo (privée) est supprimée chez YouTube d'abord (il faut `plateformes`).
    @discardableResult
    static func annuler(_ stock: Stockage, id: String, par: String, plateformes: Plateformes?, maintenant: Date = Date()) throws -> Publication {
        guard let p = try trouver(stock, id) else { throw RefusPublication(raisons: ["publication introuvable : \(id)"]) }
        var raison = "annulée par \(par)"
        switch p.etat {
        case "a_valider", "planifie", "reconnexion", "echec":
            if p.reseau == .youtube && !p.ref.isEmpty {
                guard let plateformes else { throw RefusPublication(raisons: ["vidéo déjà chez YouTube : l'annulation passe par l'outil (pilote publication annuler)"]) }
                try plateformes.youtubeSupprimer(compte: p.compte, video: p.ref)
                raison += " (vidéo privée supprimée de YouTube)"
            } else if p.reseau == .tiktok && !p.ref.isEmpty {
                raison += " (un brouillon peut rester dans la boîte TikTok : l'ignorer ou le supprimer dans l'app)"
            }
        case "envoye":
            switch p.reseau {
            case .youtube:
                guard let plateformes else { throw RefusPublication(raisons: ["vidéo déjà chez YouTube : l'annulation passe par l'outil (pilote publication annuler)"]) }
                try plateformes.youtubeSupprimer(compte: p.compte, video: p.ref)
                raison += " (vidéo privée supprimée de YouTube avant l'heure)"
            case .instagram: raison += " (le conteneur Instagram, jamais publié, expire seul)"
            case .tiktok: raison += " (le brouillon reste dans la boîte TikTok : l'ignorer ou le supprimer dans l'app)"
            }
        case "envoi": throw RefusPublication(raisons: ["envoi en cours : réessayer dans une minute"])
        case "publie":
            let app = [ReseauPublication.youtube: "YouTube Studio", .instagram: "Instagram", .tiktok: "TikTok"][p.reseau] ?? ""
            throw RefusPublication(raisons: ["déjà publiée : la retirer dans l'app \(app)"])
        default: throw RefusPublication(raisons: ["déjà « \(p.etat) »"])
        }
        let m = Dates.iso.string(from: maintenant)
        try stock.base.executer("UPDATE publications SET etat = 'annule', raison = ?, maj_le = ?, fait_le = ? WHERE id = ?", [raison, m, m, p.id])
        try nettoyerCopies(stock)
        return try trouver(stock, p.id) ?? p
    }

    /// Une copie qui ne sert plus à aucune publication en cours (ni à un échec, qu'on peut reprogrammer 7 jours) est effacée.
    /// Une copie partagée reste tant qu'une seule de ses cartes en a besoin.
    static func nettoyerCopies(_ stock: Stockage, maintenant: Date = Date()) throws {
        let limite = Dates.iso.string(from: maintenant.addingTimeInterval(-7 * 86400))
        var gardees = Set<String>(), toutes = Set<String>()
        for l in try stock.base.lignes("SELECT fichier, etat, compte, maj_le FROM publications") {
            guard let f = l["fichier"] as? String, !f.isEmpty else { continue }
            toutes.insert(f)
            if copieUtile(etat: l["etat"] as? String ?? "", compte: l["compte"] as? String ?? "",
                          majLe: l["maj_le"] as? String ?? "", limiteEchec: limite) { gardees.insert(f) }
        }
        for f in toutes.subtracting(gardees) where FileManager.default.fileExists(atPath: f) {
            try? FileManager.default.removeItem(atPath: f)
        }
    }

    /// La carte a-t-elle encore besoin de sa copie ?
    /// YouTube « envoye » : non (09/11, accord de Sacha). La vidéo est chez YouTube (privée, publishAt) ; si YouTube la refuse,
    /// on la reprogramme depuis la source. Instagram « envoye » (conteneur pas encore publié) et TikTok « envoye » (brouillon dans
    /// la boîte) gardent la leur : rien n'y est fini.
    static func copieUtile(etat: String, compte: String, majLe: String, limiteEchec: String) -> Bool {
        switch etat {
        case "a_valider", "planifie", "envoi", "reconnexion": return true
        case "envoye": return ComptePublication.trouver(compte)?.reseau != .youtube
        case "echec": return majLe >= limiteEchec
        default: return false
        }
    }

    // MARK: Affichage

    static func heureParis(_ iso: String) -> String {
        guard let d = Dates.iso.date(from: iso) else { return iso }
        return heureParis(d)
    }

    static func heureParis(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "EEE d/MM 'à' HH:mm"
        return f.string(from: d)
    }

    /// Lit « 2026-11-10 18:00 » (heure de Paris), « 2026-11-10T18:00 » ou une date ISO complète.
    static func lireDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let d = Dates.iso.date(from: t) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = format
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    /// Le statut en un mot (prevu, envoye, publie, echec, a_reconnecter, a_valider, envoi, annule) et la phrase montrée à Sacha.
    static func statut(_ p: Publication) -> String {
        switch p.etat {
        case "planifie": return "prevu"
        case "reconnexion": return "a_reconnecter"
        default: return p.etat
        }
    }

    static func affichage(_ p: Publication) -> String {
        let h = heureParis(p.prevuLe)
        switch p.etat {
        case "a_valider": return "à valider par \(Moi.nom) (prévue \(h))"
        case "planifie":
            switch p.reseau {
            case .youtube:
                return p.raison.isEmpty ? "prévue \(h) : part chez YouTube dans les 3 jours avant, la plus proche d'abord" : "prévue \(h) : \(p.raison)"
            case .instagram: return "prévue \(h) : Pilote la publiera à l'heure (Mac allumé et éveillé)"
            case .tiktok: return "prévue \(h) : brouillon envoyé dans la boîte TikTok 15 min avant (Mac allumé), \(Moi.nom) publie depuis l'app"
            }
        case "envoi": return "envoi en cours"
        case "envoye":
            switch p.reseau {
            case .youtube: return "programmée chez YouTube pour \(h) (YouTube publie seul, Mac éteint compris)"
            case .instagram: return "vidéo chez Instagram, publication \(h)"
            case .tiktok:
                return p.phase == "boite" ? "brouillon dans la boîte TikTok : à publier dans l'app (légende à coller), prévue \(h)"
                    : "envoyée à TikTok, brouillon en préparation"
            }
        case "publie": return "publiée" + (p.faitLe.isEmpty ? "" : " (vu \(heureParis(p.faitLe)))")
        case "echec": return "échec : \(p.raison)"
        case "reconnexion": return "compte à reconnecter : \(p.raison)"
        case "annule": return "annulée"
        default: return p.etat
        }
    }

    /// Noter à la main qu'une publication TikTok (brouillon dans la boîte) a été publiée par Sacha dans l'app TikTok.
    /// Refus : introuvable, pas TikTok, pas « envoye », ou lien qui n'est pas une adresse https://www.tiktok.com/…
    @discardableResult
    static func marquerPubliee(_ stock: Stockage, id: String, lien: String = "", par: String, maintenant: Date = Date()) throws -> Publication {
        guard let p = try trouver(stock, id) else { throw RefusPublication(raisons: ["publication introuvable : \(id)"]) }
        guard p.reseau == .tiktok else { throw RefusPublication(raisons: ["ce n'est pas une publication TikTok : seule la passe ou l'app du réseau fait foi pour les autres"]) }
        guard p.etat == "envoye" else {
            throw RefusPublication(raisons: [p.etat == "publie" ? "déjà « publie » : rien à noter" : "pas un brouillon dans la boîte TikTok (état « \(p.etat) ») : seule une publication « envoye » peut être notée publiée"])
        }
        let l = lien.trimmingCharacters(in: .whitespacesAndNewlines)
        if !l.isEmpty {
            guard l.hasPrefix("https://www.tiktok.com/"), l.count > "https://www.tiktok.com/".count,
                  let u = URL(string: l), u.scheme == "https", u.host == "www.tiktok.com" else {
                throw RefusPublication(raisons: ["le lien doit être une adresse https://www.tiktok.com/… : \(l)"])
            }
        }
        let m = Dates.iso.string(from: maintenant)
        try noter(stock, p.id, ["etat": "publie", "phase": "", "lien": l, "fait_le": m, "verifie_le": m,
                                "raison": "publiée par \(Moi.nom) depuis l'app TikTok (notée à la main par \(par))"], le: maintenant)
        return try trouver(stock, p.id) ?? p
    }

    // MARK: La passe (agent launchd, toutes les minutes)

    private static func noter(_ stock: Stockage, _ id: String, _ champs: [String: Any], le: Date) throws {
        var sets = champs.keys.sorted().map { "\($0) = ?" }
        var valeurs: [Any?] = champs.keys.sorted().map { champs[$0] }
        sets.append("maj_le = ?")
        valeurs.append(Dates.iso.string(from: le))
        valeurs.append(id)
        try stock.base.executer("UPDATE publications SET \(sets.joined(separator: ", ")) WHERE id = ?", valeurs)
    }

    /// Y a-t-il quelque chose à faire ? (sinon la passe sort sans trousseau ni réseau)
    static func aFaire(_ stock: Stockage, maintenant: Date = Date()) throws -> Bool {
        if try !stock.base.lignes("SELECT 1 FROM publications WHERE etat IN ('planifie', 'envoi', 'envoye') LIMIT 1").isEmpty { return true }
        return try entretienDu(stock, maintenant: maintenant)
    }

    private static func entretienDu(_ stock: Stockage, maintenant: Date) throws -> Bool {
        let connectes = try comptes(stock).filter { $0.etat == "connecte" }
        guard !connectes.isEmpty else { return false }
        let dernier = stock.base.reglage("publication.entretien").flatMap(Dates.iso.date)
        return dernier.map { maintenant.timeIntervalSince($0) >= 86400 } ?? true
    }

    static func passe(_ stock: Stockage, plateformes: Plateformes, maintenant: () -> Date = Date.init,
                      alerter: (AlertePublication) -> Void) throws -> BilanPublication {
        var bilan = BilanPublication()
        var signales = Set<String>()
        /// Les comptes pas (ou plus) connectés : leurs vidéos attendent, sans réseau.
        var horsLigne = Set(try comptes(stock).filter { $0.etat != "connecte" }.map(\.compte))
        /// Quota YouTube atteint pendant cette passe : les autres envois YouTube attendent (le quota est celui du projet).
        var quotaYouTubeAtteint = false
        /// YouTube, par compte : une vidéo plus proche attend encore (limite, plafond, quota, essai raté) ; les suivantes
        /// attendent derrière elle (jamais J+8 avant J+0).
        var youtubeEnAttente = Set<String>()
        func attend(_ p: Publication) { if p.reseau == .youtube && p.etat == "planifie" { youtubeEnAttente.insert(p.compte) } }

        func echec(_ p: Publication, _ raison: String, _ t: Date) throws {
            try noter(stock, p.id, ["etat": "echec", "phase": "", "raison": raison, "fait_le": Dates.iso.string(from: t)], le: t)
            bilan.echecs.append(p.id)
            let nom = ComptePublication.trouver(p.compte)?.nom ?? p.compte
            alerter(AlertePublication(id: "publication-\(p.id.prefix(8))-echec", le: Dates.iso.string(from: t),
                                      titre: "Pilote · publication pas faite",
                                      texte: "Publication \(nom) prévue \(heureParis(p.prevuLe)) (« \(apercu(p)) ») : \(raison)",
                                      grave: true))
        }

        func aReconnecter(_ p: Publication, _ raison: String, _ t: Date) throws {
            try noter(stock, p.id, ["etat": "reconnexion", "phase": "", "raison": raison], le: t)
            horsLigne.insert(p.compte)
            var c = try etatCompte(stock, p.compte)
            if c.etat != "a_reconnecter" { c.etat = "a_reconnecter"; c.raison = raison; c.verifieLe = Dates.iso.string(from: t); try noterCompte(stock, c) }
            bilan.reconnexions.append(p.id)
            guard !signales.contains(p.compte) else { return }
            signales.insert(p.compte)
            let nom = ComptePublication.trouver(p.compte)?.nom ?? p.compte
            alerter(AlertePublication(id: "publication-\(p.compte)-reconnexion-\(Dates.jour.string(from: t))", le: Dates.iso.string(from: t),
                                      titre: "Pilote · compte à reconnecter",
                                      texte: "\(nom) : \(raison). \(Moi.nom) : Pilote › Publications › « Reconnecter » (un clic). Les vidéos de ce compte attendent.",
                                      grave: true))
        }

        /// Une erreur de plateforme : reconnexion, échec, ou nouvel essai plus tard (5 au plus).
        func traiter(_ erreur: Error, _ p: Publication, _ t: Date, retour: String) throws {
            switch erreur {
            case ErreurPlateforme.reconnexion(let m): try aReconnecter(p, m, t)
            case ErreurPlateforme.definitive(let m): try echec(p, m, t)
            case ErreurPlateforme.quota(let m):
                if p.reseau == .youtube { quotaYouTubeAtteint = true }
                let remise = remiseQuotaYouTube(apres: t)
                try noter(stock, p.id, ["etat": retour, "phase": "", "raison": "\(raisonQuotaYouTube) (\(m)) : nouvel essai après \(heureParis(Dates.iso.string(from: remise)))"], le: t)
            case ErreurPlateforme.limiteChaine(let m):
                youtubeEnAttente.insert(p.compte)
                let remise = try remiseLimiteChaine(stock, compte: p.compte, apres: t)
                let r = Dates.iso.string(from: remise)
                try stock.base.definirReglage(cleLimiteChaine(p.compte), r)
                try noter(stock, p.id, ["etat": retour, "phase": "",
                                        "raison": "\(raisonLimiteChaine) (\(m), pas le quota) : nouvel essai après \(heureParis(r))"], le: t)
                let nom = ComptePublication.trouver(p.compte)?.nom ?? p.compte
                let tropTard = p.prevu.map { remise > $0.addingTimeInterval(-margeYouTube) } ?? true
                alerter(AlertePublication(id: "publication-\(p.compte)-limite-\(Dates.jour.string(from: t))", le: Dates.iso.string(from: t),
                                          titre: "Pilote · limite d'envois YouTube",
                                          texte: "\(nom) : YouTube refuse les envois (limite de la chaîne, pas le quota) jusqu'à \(heureParis(r)) environ."
                                            + (tropTard ? " « \(apercu(p)) » prévue \(heureParis(p.prevuLe)) ne partira pas à temps : à reprogrammer." : " Les vidéos de cette chaîne attendent."),
                                          grave: tropTard))
            case let e as RefusPublication: try echec(p, e.raisons.joined(separator: " ; "), t)
            default:
                let m = (erreur as? ErreurPlateforme)?.description ?? "\(erreur)"
                let n = p.tentatives + 1
                if n >= tentativesMax {
                    try echec(p, "\(n) essais ratés, dernier : \(m)", t)
                } else {
                    try noter(stock, p.id, ["etat": retour, "phase": "", "tentatives": n, "raison": "essai \(n) raté (\(m)) : nouvel essai à la prochaine passe"], le: t)
                }
            }
        }

        /// Le fichier validé, relu par son empreinte.
        func fichierValide(_ p: Publication) throws -> URL {
            let u = URL(fileURLWithPath: p.fichier)
            guard FileManager.default.isReadableFile(atPath: u.path) else {
                throw RefusPublication(raisons: ["la copie validée de la vidéo a disparu (\(u.lastPathComponent)) : reprogrammer"])
            }
            guard try empreinteFichier(u) == p.empreinteFichier else {
                throw RefusPublication(raisons: ["la vidéo a changé depuis sa validation : rien n'est parti, reprogrammer"])
            }
            guard empreinte(p) == p.empreinte else {
                throw RefusPublication(raisons: ["la publication a changé depuis sa validation (titre, texte ou heure) : rien n'est parti"])
            }
            return u
        }

        /// YouTube : la miniature validée, posée une fois la vidéo traitée. Jamais d'échec ni de reconnexion pour elle :
        /// refusée, la vidéo part avec l'image choisie par YouTube et Sacha est prévenu.
        func poserMiniature(_ p: Publication, _ t: Date) throws {
            func refusee(_ raison: String) throws {
                try noter(stock, p.id, ["couverture_etat": "refusee : \(raison)"], le: t)
                alerter(AlertePublication(id: "publication-\(p.id.prefix(8))-miniature", le: Dates.iso.string(from: t),
                                          titre: "Pilote · miniature YouTube pas posée",
                                          texte: "« \(apercu(p)) » : \(raison). La vidéo reste programmée avec l'image choisie par YouTube.",
                                          grave: false))
            }
            let image = URL(fileURLWithPath: p.couverture)
            guard FileManager.default.isReadableFile(atPath: image.path), (try? empreinteFichier(image)) == p.empreinteCouverture else {
                try refusee("l'image de couverture a disparu ou changé depuis la validation"); return
            }
            do {
                guard let e = try plateformes.youtubeEtat(compte: p.compte, video: p.ref) else { return }
                if ["failed", "terminated"].contains(e.traitement) { try refusee("YouTube n'a pas pu traiter la vidéo (\(e.traitement))"); return }
                guard e.traitement == "succeeded" || e.envoi == "processed" else { return }
                try plateformes.youtubeMiniature(compte: p.compte, video: p.ref, image: image)
                try noter(stock, p.id, ["couverture_etat": "posee"], le: t)
            } catch ErreurPlateforme.quota {
                quotaYouTubeAtteint = true  // miniature reposée après la remise à zéro du quota
            } catch let ErreurPlateforme.passagere(m) {
                if p.couvertureEssais + 1 >= 3 { try refusee(m) } else { try noter(stock, p.id, ["couverture_essais": p.couvertureEssais + 1], le: t) }
            } catch {
                try refusee("\(error)")
            }
        }

        // 1. Une passe morte en plein envoi (le verrou garantit qu'aucune autre ne tourne).
        for p in try stock.base.lignes("SELECT * FROM publications WHERE etat = 'envoi'").map(publication) {
            let t = maintenant()
            switch (p.reseau, p.phase) {
            case (.instagram, "publication"):
                do {
                    let c = try plateformes.instagramConteneur(compte: p.compte, conteneur: p.conteneur)
                    if c.code == "PUBLISHED" {
                        try noter(stock, p.id, ["etat": "publie", "phase": "", "raison": "publiée (notée après une passe interrompue ; lien à relire dans Instagram)",
                                                "fait_le": Dates.iso.string(from: t)], le: t)
                        bilan.publiees.append(p.id)
                    } else {
                        try noter(stock, p.id, ["etat": "envoye", "phase": ""], le: t)
                    }
                } catch { try traiter(error, p, t, retour: "envoye") }
            case (.instagram, _):
                try noter(stock, p.id, ["etat": "planifie", "phase": "", "conteneur": ""], le: t)
            case (.tiktok, _):
                // Envoi coupé avant la fin : rien dans la boîte (TikTok attend toute la vidéo) ; renvoyé à la passe suivante.
                try noter(stock, p.id, ["etat": "planifie", "phase": ""], le: t)
            default:
                // YouTube : la session d'envoi est gardée ; l'envoi reprend où il s'était arrêté (jamais deux vidéos).
                try noter(stock, p.id, ["etat": "planifie", "phase": ""], le: t)
            }
        }

        // 2. Ce qui est dû, de la plus proche à la plus lointaine.
        for p in try stock.base.lignes("SELECT * FROM publications WHERE etat IN ('planifie', 'envoye') ORDER BY prevu_le, rowid").map(publication) {
            let t = maintenant()
            guard let prevu = p.prevu else { try echec(p, "heure illisible (\(p.prevuLe))", t); continue }
            if horsLigne.contains(p.compte) && p.etat == "planifie" {
                let c = try etatCompte(stock, p.compte)
                if c.etat == "jamais" {
                    if p.raison != "compte pas encore connecté à Pilote" {
                        try noter(stock, p.id, ["raison": "compte pas encore connecté à Pilote"], le: t)
                    }
                    if p.reseau == .instagram && t > prevu.addingTimeInterval(retardMax) {
                        try echec(p, "compte jamais connecté à Pilote à l'heure prévue : pas publiée, à reprogrammer", t)
                    } else if p.reseau == .youtube && t > prevu.addingTimeInterval(-margeYouTube) {
                        try echec(p, "compte jamais connecté à Pilote avant l'heure prévue : pas publiée, à reprogrammer", t)
                    } else if p.reseau == .tiktok && t > prevu.addingTimeInterval(retardTT) {
                        try echec(p, "compte TikTok jamais connecté à Pilote : brouillon pas envoyé, à reprogrammer", t)
                    }
                    continue
                }
                try aReconnecter(p, c.raison.isEmpty ? "jeton refusé" : c.raison, t)
                continue
            }
            // Après un essai raté (réseau, serveur) : 1, 2, 4, 8 min avant le suivant.
            if p.tentatives > 0, let m = Dates.iso.date(from: p.majLe),
               t < m.addingTimeInterval(min(60 * pow(2, Double(p.tentatives - 1)), 1800)) { attend(p); continue }
            // Venue de PlugKit sans sa ligne REVEIL pour PILOTE : on l'écrit d'abord ; impossible, rien ne part.
            if p.etat == "planifie" && !p.plugkit.isEmpty && p.plugkitReveilLe.isEmpty {
                do {
                    try ecrireReveilPlugKit(stock, p, le: t)
                    try noter(stock, p.id, ["plugkit_reveil_le": Dates.iso.string(from: t)], le: t)
                } catch {
                    let r = "en attente : la ligne pour PILOTE (retirer le post PlugKit \(p.plugkit)) n'a pas pu être écrite"
                    if p.raison != r { try noter(stock, p.id, ["raison": r], le: t) }
                    attend(p)
                    continue
                }
            }
            switch (p.reseau, p.etat) {
            case (.youtube, "planifie"):
                if t > prevu.addingTimeInterval(-margeYouTube) {
                    let pourquoi = p.raison.hasPrefix(raisonQuotaYouTube) ? "quota YouTube du jour (projet) atteint jusqu'à l'heure prévue"
                        : p.raison.hasPrefix(raisonLimiteChaine) ? "limite d'envois de la chaîne YouTube (uploadLimitExceeded) atteinte jusqu'à l'heure prévue"
                        : p.raison.hasPrefix(raisonPlafondYouTube) ? "plafond de Pilote (\(envoisMaxYouTube) envois par chaîne sur 24 h) atteint jusqu'à l'heure prévue"
                        : "pas envoyée à YouTube avant l'heure (Mac éteint, compte pas connecté ou vidéo plus proche bloquée)"
                    try echec(p, "\(pourquoi) : pas publiée, à reprogrammer", t)
                    continue
                }
                // Plus de 3 jours avant l'heure : elle partira plus tard (la plus proche d'abord, quel que soit l'ordre de validation).
                if prevu.timeIntervalSince(t) > horizonYouTube { attend(p); continue }
                // Une vidéo plus proche de cette chaîne attend encore : celle-ci attend derrière.
                if youtubeEnAttente.contains(p.compte) {
                    if p.raison.isEmpty { try noter(stock, p.id, ["raison": raisonTourYouTube], le: t) }
                    continue
                }
                // Quota du jour atteint (par cette vidéo ou une autre de cette passe) : attendre sa remise à zéro.
                if quotaYouTubeAtteint { attend(p); continue }
                if p.raison.hasPrefix(raisonQuotaYouTube), let m = Dates.iso.date(from: p.majLe), t < remiseQuotaYouTube(apres: m) { attend(p); continue }
                // Limite de la chaîne atteinte : rien avant la remise notée.
                if let r = stock.base.reglage(cleLimiteChaine(p.compte)), let remise = Dates.iso.date(from: r), t < remise {
                    if !p.raison.hasPrefix(raisonLimiteChaine) {
                        try noter(stock, p.id, ["raison": "\(raisonLimiteChaine) : nouvel essai après \(heureParis(r))"], le: t)
                        if remise > prevu.addingTimeInterval(-margeYouTube) {
                            alerter(AlertePublication(id: "publication-\(p.id.prefix(8))-limite", le: Dates.iso.string(from: t),
                                                      titre: "Pilote · limite d'envois YouTube",
                                                      texte: "\(ComptePublication.trouver(p.compte)?.nom ?? p.compte) : « \(apercu(p)) » prévue \(heureParis(p.prevuLe)) ne partira pas à temps (limite de la chaîne jusqu'à \(heureParis(r)) environ) : à reprogrammer.",
                                                      grave: true))
                        }
                    }
                    attend(p); continue
                }
                // Plafond de Pilote : 6 envois par chaîne sur 24 h glissantes.
                let recents = try envoisYouTube(stock, compte: p.compte, depuis: t.addingTimeInterval(-86400))
                if recents.count >= envoisMaxYouTube {
                    let libre = Dates.iso.string(from: recents[recents.count - envoisMaxYouTube].addingTimeInterval(86400 + 60))
                    let r = "\(raisonPlafondYouTube) : nouvel essai après \(heureParis(libre))"
                    if p.raison != r { try noter(stock, p.id, ["raison": r], le: t) }
                    attend(p); continue
                }
                do {
                    let u = try fichierValide(p)
                    try noter(stock, p.id, ["etat": "envoi", "phase": "televersement"], le: t)
                    let video = try plateformes.youtubeTeleverser(p, fichier: u) { s in
                        try noter(stock, p.id, ["session": s], le: maintenant())
                    }
                    let t2 = maintenant()
                    try noter(stock, p.id, ["etat": "envoye", "phase": "", "ref": video, "lien": "https://www.youtube.com/shorts/\(video)",
                                            "session": "", "tentatives": 0, "televerse_le": Dates.iso.string(from: t2),
                                            "raison": "envoyée en privé, publication programmée chez YouTube"], le: t2)
                    bilan.envoyees.append(p.id)
                    // Relue tout de suite : l'heure de publication et le privé doivent être ceux validés.
                    if let e = try? plateformes.youtubeEtat(compte: p.compte, video: video) {
                        let heureLue = Dates.iso.date(from: e.publierLe)
                        if e.confidentialite != "private" || heureLue.map({ abs($0.timeIntervalSince(prevu)) > 60 }) ?? true {
                            try noter(stock, p.id, ["raison": "à vérifier : YouTube dit « \(e.confidentialite) », publication « \(e.publierLe.isEmpty ? "aucune" : heureParis(e.publierLe)) »",
                                                    "verifie_le": Dates.iso.string(from: t2)], le: t2)
                            alerter(AlertePublication(id: "publication-\(p.id.prefix(8))-relue", le: Dates.iso.string(from: t2),
                                                      titre: "Pilote · YouTube à vérifier",
                                                      texte: "Vidéo \(video) envoyée, mais YouTube dit « \(e.confidentialite) » et heure « \(e.publierLe) » au lieu de privée jusqu'à \(heureParis(prevu)) : vérifier dans YouTube Studio.",
                                                      grave: true))
                        } else {
                            try noter(stock, p.id, ["verifie_le": Dates.iso.string(from: t2),
                                                    "raison": "relue chez YouTube : privée, publication \(heureParis(prevu))"], le: t2)
                        }
                    }
                } catch {
                    try traiter(error, try trouver(stock, p.id) ?? p, maintenant(), retour: "planifie")
                    if let q = try trouver(stock, p.id) { attend(q) }
                }

            case (.youtube, "envoye"):
                if p.couvertureEtat == "a_poser" { try poserMiniature(p, t) }
                guard t >= prevu.addingTimeInterval(180) else { continue }
                if let v = Dates.iso.date(from: p.verifieLe), v > prevu, t.timeIntervalSince(v) < relectureYouTube { continue }
                do {
                    let e = try plateformes.youtubeEtat(compte: p.compte, video: p.ref)
                    guard let e else { try echec(p, "la vidéo n'existe plus chez YouTube (supprimée ?)", t); continue }
                    if e.confidentialite == "public" {
                        try noter(stock, p.id, ["etat": "publie", "raison": "publique chez YouTube", "verifie_le": Dates.iso.string(from: t),
                                                "fait_le": Dates.iso.string(from: t)], le: t)
                        bilan.publiees.append(p.id)
                        alerter(AlertePublication(id: "publication-\(p.id.prefix(8))-publiee", le: Dates.iso.string(from: t),
                                                  titre: "Pilote · vidéo publiée",
                                                  texte: "\(ComptePublication.trouver(p.compte)?.nom ?? p.compte) : « \(apercu(p)) » est publique (\(p.lien)).",
                                                  grave: false))
                    } else if ["failed", "rejected", "deleted"].contains(e.envoi) {
                        try echec(p, "YouTube a refusé la vidéo (\(e.envoi)\(e.raisonRefus.isEmpty ? "" : " : " + e.raisonRefus))", t)
                    } else if t > prevu.addingTimeInterval(delaiPublicYouTube) {
                        try echec(p, "toujours « \(e.confidentialite) » 3 h après l'heure prévue : vérifier dans YouTube Studio", t)
                    } else {
                        try noter(stock, p.id, ["verifie_le": Dates.iso.string(from: t), "raison": "heure passée, YouTube ne l'a pas encore rendue publique (\(e.envoi))"], le: t)
                    }
                } catch { try traiter(error, p, t, retour: "envoye") }

            case (.instagram, "planifie"):
                guard t >= prevu.addingTimeInterval(-preparationIG) else { continue }
                if t > prevu.addingTimeInterval(retardMax) {
                    try echec(p, "pas publiée : \(Int(t.timeIntervalSince(prevu) / 60)) min de retard à l'heure prévue (Mac éteint ou en veille ?) ; à reprogrammer", t)
                    continue
                }
                do {
                    let u = try fichierValide(p)
                    try noter(stock, p.id, ["etat": "envoi", "phase": "preparation"], le: t)
                    let c = try plateformes.instagramPreparer(p, fichier: u)
                    let t2 = maintenant()
                    try noter(stock, p.id, ["etat": "envoye", "phase": "", "conteneur": c, "tentatives": 0,
                                            "raison": "vidéo envoyée chez Instagram (rien de public), publication à l'heure"], le: t2)
                    bilan.envoyees.append(p.id)
                } catch { try traiter(error, try trouver(stock, p.id) ?? p, maintenant(), retour: "planifie") }

            case (.instagram, "envoye"):
                guard t >= prevu else { continue }
                if t > prevu.addingTimeInterval(retardMax) {
                    try echec(p, "pas publiée : \(Int(t.timeIntervalSince(prevu) / 60)) min de retard (Mac éteint ou en veille à l'heure ?) ; à reprogrammer", t)
                    continue
                }
                do {
                    let c = try plateformes.instagramConteneur(compte: p.compte, conteneur: p.conteneur)
                    switch c.code {
                    case "FINISHED":
                        try noter(stock, p.id, ["etat": "envoi", "phase": "publication"], le: t)
                        let r = try plateformes.instagramPublier(compte: p.compte, conteneur: p.conteneur)
                        let t2 = maintenant()
                        try noter(stock, p.id, ["etat": "publie", "phase": "", "ref": r.media, "lien": r.lien, "raison": "publiée par Pilote",
                                                "fait_le": Dates.iso.string(from: t2)], le: t2)
                        bilan.publiees.append(p.id)
                        alerter(AlertePublication(id: "publication-\(p.id.prefix(8))-publiee", le: Dates.iso.string(from: t2),
                                                  titre: "Pilote · Reel publié",
                                                  texte: "\(ComptePublication.trouver(p.compte)?.nom ?? p.compte) : « \(apercu(p)) » est publié\(r.lien.isEmpty ? "" : " (\(r.lien))").",
                                                  grave: false))
                    case "PUBLISHED":
                        try noter(stock, p.id, ["etat": "publie", "phase": "", "raison": "déjà publiée (conteneur publié)", "fait_le": Dates.iso.string(from: t)], le: t)
                        bilan.publiees.append(p.id)
                    case "IN_PROGRESS", "":
                        try noter(stock, p.id, ["raison": "Instagram traite encore la vidéo : publication dès qu'elle est prête"], le: t)
                    default:
                        try echec(p, "Instagram a refusé la vidéo (\(c.code)\(c.detail.isEmpty ? "" : " : " + c.detail))", t)
                    }
                } catch { try traiter(error, try trouver(stock, p.id) ?? p, maintenant(), retour: "envoye") }

            case (.tiktok, "planifie"):
                guard t >= prevu.addingTimeInterval(-preparationTT) else { continue }
                if t > prevu.addingTimeInterval(retardTT) {
                    try echec(p, "brouillon pas envoyé : \(Int(t.timeIntervalSince(prevu) / 3600)) h de retard (Mac éteint ?) ; à reprogrammer", t)
                    continue
                }
                do {
                    let u = try fichierValide(p)
                    try noter(stock, p.id, ["etat": "envoi", "phase": "televersement"], le: t)
                    let envoi = try plateformes.tiktokEnvoyer(p, fichier: u)
                    let t2 = maintenant()
                    try noter(stock, p.id, ["etat": "envoye", "phase": "", "ref": envoi, "tentatives": 0, "verifie_le": "",
                                            "raison": "vidéo envoyée à TikTok : brouillon en préparation"], le: t2)
                    bilan.envoyees.append(p.id)
                } catch { try traiter(error, try trouver(stock, p.id) ?? p, maintenant(), retour: "planifie") }

            case (.tiktok, "envoye"):
                // Relu à chaque passe jusqu'à la boîte, puis toutes les 15 min (Sacha publie quand il veut).
                if let v = Dates.iso.date(from: p.verifieLe), t.timeIntervalSince(v) < (p.phase == "boite" ? relectureTT : 50) { continue }
                do {
                    let e = try plateformes.tiktokEtat(compte: p.compte, envoi: p.ref)
                    let nom = ComptePublication.trouver(p.compte)?.nom ?? p.compte
                    switch e.statut {
                    case "SEND_TO_USER_INBOX":
                        if p.phase != "boite" {
                            try noter(stock, p.id, ["phase": "boite", "verifie_le": Dates.iso.string(from: t), "tentatives": 0,
                                                    "raison": "brouillon dans la boîte TikTok : à publier dans l'app (légende à coller)"], le: t)
                            alerter(AlertePublication(id: "publication-\(p.id.prefix(8))-brouillon", le: Dates.iso.string(from: t),
                                                      titre: "Pilote · brouillon TikTok à publier",
                                                      texte: "\(nom) : la vidéo prévue \(heureParis(p.prevuLe)) est dans la boîte TikTok (notification dans l'app TikTok). \(Moi.nom) : l'ouvrir, coller la légende (bouton « Copier la légende » dans Pilote › Publications), choisir la couverture (\(couvertureTexte(p))), publier. Légende : « \(p.texte) »",
                                                      grave: true))
                        } else if t > prevu.addingTimeInterval(attenteBoiteTT) {
                            try echec(p, "brouillon toujours pas publié 3 jours après l'heure prévue : le publier ou le supprimer dans l'app TikTok", t)
                        } else {
                            // Une relecture réussie remet le compte des essais à zéro (le brouillon peut attendre 3 jours).
                            try noter(stock, p.id, ["verifie_le": Dates.iso.string(from: t), "tentatives": 0], le: t)
                        }
                    case "PUBLISH_COMPLETE":
                        let lu = try etatCompte(stock, p.compte).lu
                        let lien = e.post.isEmpty ? "" : (poigneeTikTok(lu).map { "https://www.tiktok.com/@\($0)/video/\(e.post)" } ?? "")
                        try noter(stock, p.id, ["etat": "publie", "phase": "", "lien": lien, "raison": "publiée par \(Moi.nom) depuis l'app TikTok",
                                                "verifie_le": Dates.iso.string(from: t), "fait_le": Dates.iso.string(from: t)], le: t)
                        bilan.publiees.append(p.id)
                        alerter(AlertePublication(id: "publication-\(p.id.prefix(8))-publiee", le: Dates.iso.string(from: t),
                                                  titre: "Pilote · TikTok publié",
                                                  texte: "\(nom) : « \(apercu(p)) » est publiée\(lien.isEmpty ? "" : " (\(lien))").", grave: false))
                    case "FAILED":
                        try echec(p, "TikTok a refusé la vidéo\(e.raison.isEmpty ? "" : " (\(e.raison))") : rien dans la boîte, à reprogrammer", t)
                    default:
                        if t > prevu.addingTimeInterval(retardTT + traitementTT) {
                            try echec(p, "TikTok traite encore la vidéo bien après l'envoi (\(e.statut)) : rien dans la boîte, à reprogrammer", t)
                        } else {
                            try noter(stock, p.id, ["verifie_le": Dates.iso.string(from: t), "tentatives": 0,
                                                    "raison": "TikTok traite la vidéo (\(e.statut.isEmpty ? "?" : e.statut))"], le: t)
                        }
                    }
                } catch { try traiter(error, try trouver(stock, p.id) ?? p, maintenant(), retour: "envoye") }
            default: break
            }
        }

        // 3. Une fois par jour : chaque compte connecté est essayé (jeton refusé = « à reconnecter » avant la prochaine vidéo).
        let t = maintenant()
        if try entretienDu(stock, maintenant: t) {
            for var c in try comptes(stock) where c.etat == "connecte" {
                do {
                    if let fin = try plateformes.entretien(compte: c.compte) { c.expireLe = fin }
                    c.verifieLe = Dates.iso.string(from: t)
                    try noterCompte(stock, c)
                } catch ErreurPlateforme.reconnexion(let m) {
                    c.etat = "a_reconnecter"; c.raison = m; c.verifieLe = Dates.iso.string(from: t)
                    try noterCompte(stock, c)
                    bilan.reconnexions.append(c.compte)
                    alerter(AlertePublication(id: "publication-\(c.compte)-reconnexion-\(Dates.jour.string(from: t))", le: Dates.iso.string(from: t),
                                              titre: "Pilote · compte à reconnecter",
                                              texte: "\(ComptePublication.trouver(c.compte)?.nom ?? c.compte) : \(m). \(Moi.nom) : Pilote › Publications › « Reconnecter » (un clic).",
                                              grave: true))
                } catch {
                    // Réseau ou refus passager : réessayé demain. Mais un jeton qui expire dans moins de 7 jours sans avoir pu
                    // être renouvelé (Instagram, 60 jours) ne doit pas tomber en silence : alerte grave chaque jour.
                    if let fin = Dates.iso.date(from: c.expireLe), fin.timeIntervalSince(t) < 7 * 86400 {
                        alerter(AlertePublication(id: "publication-\(c.compte)-expiration-\(Dates.jour.string(from: t))", le: Dates.iso.string(from: t),
                                                  titre: "Pilote · jeton bientôt expiré",
                                                  texte: "\(ComptePublication.trouver(c.compte)?.nom ?? c.compte) : le jeton expire le \(heureParis(c.expireLe)) et son renouvellement échoue (\(error)). \(Moi.nom) : Pilote › Publications › « Reconnecter » avant cette date.",
                                                  grave: true))
                    }
                }
            }
            try stock.base.definirReglage("publication.entretien", Dates.iso.string(from: t))
        }
        try nettoyerCopies(stock, maintenant: t)
        let restantes = try stock.base.lignes("SELECT prevu_le FROM publications WHERE etat IN ('planifie', 'envoye') ORDER BY prevu_le LIMIT 1")
        bilan.suite = (restantes.first?["prevu_le"] as? String).map { "prochaine \(heureParis($0))" } ?? "rien de prévu"
        return bilan
    }

    /// « Sacha (@sacha.pjk) » → « sacha.pjk » : le pseudo TikTok lu à la connexion (pour le lien du post).
    static func poigneeTikTok(_ lu: String) -> String? {
        guard let a = lu.range(of: "(@", options: .backwards), let b = lu[a.upperBound...].firstIndex(of: ")") else { return nil }
        let p = String(lu[a.upperBound..<b])
        return p.isEmpty ? nil : p
    }

    static func apercu(_ p: Publication) -> String {
        let s = (p.titre.isEmpty ? p.texte : p.titre).replacingOccurrences(of: "\n", with: " ")
        return s.count > 60 ? String(s.prefix(60)) + "…" : s
    }
}

extension Base {
    /// 08/11 : la publication programmée (YouTube, Instagram, TikTok en brouillon). Tables locales (hors synchro KRYVA), ajoutées vides.
    func migrerPublications() throws {
        try executer("""
        CREATE TABLE IF NOT EXISTS publications (
          id TEXT PRIMARY KEY,
          compte TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT '',
          fichier TEXT NOT NULL,
          titre TEXT NOT NULL DEFAULT '',
          texte TEXT NOT NULL DEFAULT '',
          prevu_le TEXT NOT NULL,
          etat TEXT NOT NULL,
          phase TEXT NOT NULL DEFAULT '',
          raison TEXT NOT NULL DEFAULT '',
          empreinte TEXT NOT NULL,
          empreinte_fichier TEXT NOT NULL,
          taille INTEGER NOT NULL DEFAULT 0,
          ia INTEGER NOT NULL DEFAULT 0,
          propose_par TEXT NOT NULL DEFAULT '',
          valide_par TEXT NOT NULL DEFAULT '',
          valide_le TEXT NOT NULL DEFAULT '',
          ref TEXT NOT NULL DEFAULT '',
          lien TEXT NOT NULL DEFAULT '',
          conteneur TEXT NOT NULL DEFAULT '',
          session TEXT NOT NULL DEFAULT '',
          tentatives INTEGER NOT NULL DEFAULT 0,
          verifie_le TEXT NOT NULL DEFAULT '',
          cree_le TEXT NOT NULL,
          maj_le TEXT NOT NULL,
          fait_le TEXT NOT NULL DEFAULT ''
        )
        """)
        try executer("CREATE INDEX IF NOT EXISTS publications_etat ON publications(etat, prevu_le)")
        // 08/11 : la couverture validée (image copiée, instant de la vidéo) et où en est sa pose chez la plateforme.
        let colonnes = Set(try lignes("PRAGMA table_info(publications)").compactMap { $0["name"] as? String })
        for c in ["couverture", "empreinte_couverture", "couverture_etat"] where !colonnes.contains(c) {
            try ajouterColonne("ALTER TABLE publications ADD COLUMN \(c) TEXT NOT NULL DEFAULT ''")
        }
        if !colonnes.contains("couverture_ms") { try ajouterColonne("ALTER TABLE publications ADD COLUMN couverture_ms INTEGER NOT NULL DEFAULT -1") }
        if !colonnes.contains("couverture_essais") { try ajouterColonne("ALTER TABLE publications ADD COLUMN couverture_essais INTEGER NOT NULL DEFAULT 0") }
        // 08/11 : l'id du post PlugKit remplacé (pris dans propose_par « PlugKit <id> (…) » pour les cartes d'avant) et
        // l'heure de la ligne REVEIL pour PILOTE (retirer ce post) ; sans elle, rien ne part.
        for c in ["plugkit", "plugkit_reveil_le"] where !colonnes.contains(c) {
            try ajouterColonne("ALTER TABLE publications ADD COLUMN \(c) TEXT NOT NULL DEFAULT ''")
        }
        // 09/11 : l'heure de l'envoi réussi chez YouTube (plafond par chaîne sur 24 h). Avant : la relecture faite juste après
        // l'envoi (verifie_le), sinon maj_le ; un peu large, jamais trop court.
        if !colonnes.contains("televerse_le") {
            try ajouterColonne("ALTER TABLE publications ADD COLUMN televerse_le TEXT NOT NULL DEFAULT ''")
            let yt = ComptePublication.tous.filter { $0.reseau == .youtube }.map(\.id)
            try executer("""
                UPDATE publications SET televerse_le = CASE WHEN verifie_le <> '' THEN verifie_le ELSE maj_le END
                WHERE ref <> '' AND compte IN (\(yt.map { _ in "?" }.joined(separator: ", ")))
                """, yt)
        }
        if !colonnes.contains("plugkit") {
            for l in try lignes("SELECT id, propose_par FROM publications WHERE propose_par LIKE 'PlugKit %'") {
                let id = Publications.idPlugKit(dans: l["propose_par"] as? String ?? "")
                if !id.isEmpty { try executer("UPDATE publications SET plugkit = ? WHERE id = ?", [id, l["id"] as? String ?? ""]) }
            }
        }
        try executer("""
        CREATE TABLE IF NOT EXISTS comptes_publication (
          compte TEXT PRIMARY KEY,
          etat TEXT NOT NULL DEFAULT 'jamais',
          lu TEXT NOT NULL DEFAULT '',
          externe_id TEXT NOT NULL DEFAULT '',
          raison TEXT NOT NULL DEFAULT '',
          connecte_le TEXT NOT NULL DEFAULT '',
          expire_le TEXT NOT NULL DEFAULT '',
          verifie_le TEXT NOT NULL DEFAULT ''
        )
        """)
    }
}

// MARK: Alertes, agent launchd (comme la file d'envoi : mêmes fichiers d'alerte, lus par scripts/veille.py)

extension Publications {
    /// Une alerte grave (pas publiée, compte à reconnecter, à vérifier) va dans file-envoi-alertes.jsonl (relu par veille.py :
    /// REVEIL pour PILOTE) et en notification ; « publiée » en notification seulement.
    static func publier(_ a: AlertePublication, essai: Bool) {
        if a.grave {
            FileEnvoi.publier(AlerteFile(id: a.id, le: a.le, titre: a.titre, texte: a.texte, grave: true), essai: essai)
            return
        }
        if essai && ProcessInfo.processInfo.environment["PILOTE_SANS_NOTIF"] != nil { return }
        _ = FileEnvoi.lancer("/usr/bin/osascript", ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
                                                     "-e", "end run", (essai ? "[essai] " : "") + a.titre, a.texte])
    }

    private static var cible: String { "gui/\(getuid())/\(etiquette)" }
    static func agentCharge() -> Bool { FileEnvoi.lancer("/bin/launchctl", ["print", cible]).code == 0 }
    /// Réveille l'agent : une vidéo YouTube part tout de suite au lieu d'attendre la minute suivante.
    static func reveillerAgent() { _ = FileEnvoi.lancer("/bin/launchctl", ["kickstart", cible]) }
}
