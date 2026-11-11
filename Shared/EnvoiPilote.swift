// Envoi d'un mail préparé sans ouvrir l'app (05/11, étape 1 de PILOTE) : Sacha écrit « envoie » à PILOTE depuis son
// iPhone (Remote Control de Claude), PILOTE lance `pilote envoie <id>` (ou l'outil MCP `envoie`).
// Même chemin que le bouton « Envoyer depuis Gmail » de l'app (App/Vues/EnvoiMail.swift) : même objet (« Re: » si le mail
// répond à un autre), même repli sur le dernier mail reçu de la personne (Mail), même envoi (Gmail.envoyerMaintenant),
// même écriture du fil (`finaliser` : texte, objet, reponse_a, puis « envoye » avec le Message-ID).
// En plus du bouton, des refus francs (rien ne part) : statut, canal, objet, condition, « ne plus contacter », kryva.fr,
// Gmail non connecté. `essai` montre exactement ce qui partirait sans rien envoyer ni écrire.
import CryptoKit
import Foundation

/// Le mail tel qu'il partirait : ce que l'essai montre à Sacha.
struct MailPret: Encodable, Equatable {
    var evenementId: String
    var contactId: String
    var contact: String
    var de: String
    var a: String
    var objet: String
    var reponseA: String
    /// D'où vient le fil : reponse_a de la fiche, dernier mail reçu (Mail), ou aucun (nouveau fil).
    var filDepuis: String
    /// From, To, Subject, In-Reply-To, References, en clair (le mail réel les encode en UTF-8).
    var entetes: [String]
    var texte: String
    var avertissements: [String]
    /// Empreinte de (de, à, objet, reponse_a, texte) : passée à l'envoi, elle garantit que rien n'a changé depuis l'essai.
    var empreinte: String
}

struct ResultatEnvoi: Encodable {
    var essai: Bool
    var envoye: Bool
    var messageId: String
    var mail: MailPret
    var apercu: String
}

/// Refus : rien n'est parti, rien n'est écrit.
struct RefusEnvoi: Error, CustomStringConvertible {
    var evenementId: String
    var raisons: [String]
    var description: String {
        "Pas envoyé (message \(evenementId.prefix(8))), rien n'est parti : " + raisons.joined(separator: " ; ")
    }
}

/// Le mail EST parti mais la base n'a pas suivi : surtout ne pas le renvoyer.
struct ErreurApresEnvoi: Error, CustomStringConvertible {
    var evenementId: String
    var messageId: String
    var cause: String
    var description: String {
        "LE MAIL EST PARTI (Message-ID \(messageId)) mais Pilote n'a pas pu le noter (\(cause)). NE PAS LE RENVOYER : "
            + "le marquer à la main avec « pilote envoye \(evenementId) --malgre-condition »."
    }
}

/// Une ligne de `pilote a-envoyer` : un message « prepare » et ce que `pilote envoie` en dirait.
struct EnvoiEnAttente: Encodable, Equatable {
    var id: String
    var evenementId: String
    var contact: String
    var contactId: String
    var canal: String
    var objet: String
    var debut: String
    var condition: String
    /// « aucune », « à cocher », « cochée le … ».
    var conditionEtat: String
    /// Le jour où il part (comme l'app : écrit en tête du message, sinon la date de la fiche) ; vide = dès que possible.
    var jour: String
    /// `pilote envoie` l'accepterait maintenant (mail seulement).
    var envoyable: Bool
    var refus: [String]
}

/// Ce que l'envoi demande hors de la base. Vrai : Gmail et Mail de ce Mac. Tests et essai de bout en bout : des faux.
struct OutilsEnvoi {
    var expediteur: () -> String?
    var motDePassePresent: (String) -> Bool
    /// Message-ID du dernier mail reçu de l'adresse (repli quand l'objet est en « Re: » sans reponse_a).
    var dernierRecu: (_ adresse: String, _ objet: String) throws -> String?
    /// Envoie (a, objet, texte, reponse_a), renvoie le Message-ID du mail parti.
    var envoyer: (_ a: String, _ objet: String, _ texte: String, _ reponseA: String) throws -> String
}

enum EnvoiPilote {
    // MARK: Ce que le bouton fait

    /// L'objet comme l'app le préremplit : « Re: » ajouté si le mail répond à un autre (Gmail ne range une réponse dans le
    /// fil que si l'objet suit).
    static func objetDEnvoi(_ objet: String, reponseA: String) -> String {
        guard !reponseA.isEmpty, !objet.isEmpty, !Mail.estReponse(objet) else { return objet }
        return "Re: " + objet
    }

    /// Après l'envoi réel, exactement l'écriture de l'app : le fil garde le texte exact parti, l'objet, le mail auquel il
    /// répond, puis « envoye » avec le Message-ID (toujours noté : jamais d'erreur après un envoi réel, d'où malgreCondition).
    static func finaliser(_ stock: Stockage, evenementId: String, texte: String, objet: String, reponseA: String, messageId: String) throws {
        try stock.modifierEvenement(evenementId, ["texte": texte, "objet": objet, "reponse_a": reponseA])
        try stock.marquer(evenementId: evenementId, statut: "envoye", messageId: messageId, malgreCondition: true)
    }

    // MARK: Refus

    /// `francais` : le nom part dans la base (file d'envoi) : le « (sans nom) » reste en français.
    static func nomContact(_ c: Contact, francais: Bool = false) -> String {
        let n = c.nom.trimmingCharacters(in: .whitespaces), e = c.entreprise.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return e.isEmpty ? (francais ? "(sans nom)" : L("(sans nom)")) : e }
        return e.isEmpty || e == n ? n : "\(n) (\(e))"
    }

    /// Une seule adresse lisible : un « @ », pas d'espace, de virgule ni de point-virgule.
    static func adresseLisible(_ a: String) -> Bool {
        a.filter { $0 == "@" }.count == 1 && !a.contains(where: { " ,;<>\"\t\n".contains($0) })
            && !a.hasPrefix("@") && !a.hasSuffix("@")
    }

    /// Le texte d'un refus : dans la langue de l'app (la feuille « Envoyer les mails validés »), ou, avec `francais`, toujours
    /// en français (ce qui s'écrit dans la base ou part vers un agent). Sans catalogue (l'outil `pilote`) : le français aussi.
    private static func traducteur(_ francais: Bool) -> (LocalizedStringResource) -> String {
        francais ? { r in var r = r; r.locale = Locale(identifier: "fr"); return Loc.prenomRegle(String(localized: r)) } : { r in L(r) }
    }

    /// Le refus propre au canal : seuls les mails partent d'ici. nil pour un mail. Pour un SMS ou un DM, c'est la seule raison
    /// qui compte (`aEnvoyer`) : un champ à part, plus un texte relu par son début.
    static func refusCanal(_ e: Evenement, francais: Bool = false) -> String? {
        guard e.canal != "mail" else { return nil }
        let t = traducteur(francais)
        return t("canal « \(e.canal) », pas « mail » : pilote n'envoie que les mails (les autres s'envoient à la main, puis « envoye »)")
    }

    /// Pourquoi ce message ne peut pas partir (vide : il peut). Lu sur la base à jour, juste avant l'envoi.
    static func refus(_ e: Evenement?, _ c: Contact?, expediteur: String?, motDePassePresent: Bool, francais: Bool = false) -> [String] {
        let t = traducteur(francais)
        guard let e else { return [t("message introuvable (ou supprimé)")] }
        var r: [String] = []
        if e.statut == "envoye" || !e.messageId.isEmpty {
            r.append(e.le.isEmpty ? t("déjà envoyé : il ne repart pas")
                                  : t("déjà envoyé (\(Dates.court(e.le, francais: francais))) : il ne repart pas"))
        } else if e.statut != "prepare" {
            r.append(t("statut « \(e.statut) », pas « prepare » : seul un message dont Sacha a validé le texte exact peut partir"))
        }
        if e.sens != "sortant" { r.append(t("ce n'est pas un message sortant (sens « \(e.sens) »)")) }
        if let canal = refusCanal(e, francais: francais) { r.append(canal) }
        if e.objet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            r.append(t("objet vide : un mail part toujours avec un objet (modifie_evenement, champ objet)"))
        }
        if e.texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { r.append(t("texte vide")) }
        if e.conditionEnAttente {
            r.append(t("condition pas cochée (« \(e.condition.trimmingCharacters(in: .whitespacesAndNewlines)) ») : la cocher d'abord (pilote condition-remplie, ou modifie_evenement avec condition_remplie), seulement quand elle est vraie"))
        }
        if let c {
            if c.nePlusContacter { r.append(t("\(nomContact(c, francais: francais)) est « ne plus contacter » : aucun envoi, jamais")) }
            let a = c.email.trimmingCharacters(in: .whitespaces)
            if a.isEmpty { r.append(t("pas d'adresse mail sur la fiche de \(nomContact(c, francais: francais))")) }
            else if !adresseLisible(a) { r.append(t("adresse mail illisible sur la fiche (« \(a) ») : une seule adresse attendue")) }
            else if EnvoisKryva.estInterdit(a) { r.append(t("destinataire dans un domaine interdit (\(a)) : refusé")) }
        } else {
            r.append(t("contact introuvable (ou supprimé)"))
        }
        if let de = expediteur?.trimmingCharacters(in: .whitespaces), !de.isEmpty {
            if EnvoisKryva.estInterdit(de) { r.append(t("expéditeur dans un domaine interdit (\(de)) : jamais d'envoi depuis ce domaine")) }
            else if !motDePassePresent {
                r.append(t("mot de passe d'application Gmail absent du trousseau (\(de)) : « Connecter Gmail » dans l'app, une fois"))
            }
        } else {
            r.append(t("Gmail n'est pas connecté à Pilote (aucune adresse d'envoi) : « Connecter Gmail » dans l'app, une fois"))
        }
        return r
    }

    // MARK: Préparer

    static func empreinte(de: String, a: String, objet: String, reponseA: String, texte: String) -> String {
        let s = [de, a, objet, reponseA, texte].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    /// Ce que le bouton préremplit puis envoie : à = l'adresse de la fiche, objet (« Re: » si réponse), texte tel quel,
    /// reponse_a de la fiche, sinon (objet en « Re: ») le dernier mail reçu de la personne. Échec du repli = comme l'app :
    /// le mail part hors du fil, mais l'essai le dit (avertissement).
    static func preparer(_ e: Evenement, _ c: Contact, de: String, aujourdhui: String = Dates.aujourdhui(),
                         dernierRecu: (_ adresse: String, _ objet: String) throws -> String?) -> MailPret {
        let a = c.email.trimmingCharacters(in: .whitespaces)
        var reponseA = e.reponseA
        var filDepuis = reponseA.isEmpty ? "aucun : nouveau fil" : "reponse_a de la fiche"
        var avertissements: [String] = []
        if reponseA.isEmpty, Mail.estReponse(e.objet) {
            do {
                if let id = try dernierRecu(a, e.objet), !id.isEmpty {
                    reponseA = id
                    filDepuis = "dernier mail reçu de \(a) dans Mail"
                } else {
                    avertissements.append("objet en « Re: » mais aucun mail reçu de \(a) dans Mail : le mail part hors du fil")
                }
            } catch {
                let cause = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                avertissements.append("objet en « Re: » mais Mail n'a pas pu être lu (\(cause)) : le mail part hors du fil")
            }
        }
        let objet = objetDEnvoi(e.objet, reponseA: reponseA)
        // Le jour prévu, comme l'app le range (« À envoyer » aujourd'hui ou « plus tard ») : pas un refus, mais l'essai le dit.
        let jour = Libelles.jourDuMessage(texte: e.texte, le: e.le, dateFiche: c.prochaineDate, aujourdhui: aujourdhui, condition: e.conditionPourJour, reponseA: e.reponseA)
        if !jour.isEmpty, jour > aujourdhui {
            avertissements.append("prévu le \(Dates.jjmm(jour)) (l'app le range dans « plus tard ») : il partirait dès maintenant")
        }
        return MailPret(evenementId: e.id, contactId: c.id, contact: nomContact(c), de: de, a: a, objet: objet, reponseA: reponseA,
                        filDepuis: filDepuis, entetes: Gmail.entetesLisibles(de: de, a: a, objet: objet, reponseA: reponseA),
                        texte: e.texte, avertissements: avertissements,
                        empreinte: empreinte(de: de, a: a, objet: objet, reponseA: reponseA, texte: e.texte))
    }

    static func apercu(_ m: MailPret, essai: Bool) -> String {
        var l = [essai ? "ESSAI : rien n'est envoyé ni écrit. Voici exactement ce qui partirait." : "Parti depuis Gmail."]
        l += ["De : \(Gmail.nomExpediteur) <\(m.de)>", "À : \(m.a) · \(m.contact)", "Objet : \(m.objet)"]
        l.append(m.reponseA.isEmpty ? "Fil : aucun (nouveau fil)" : "Fil : In-Reply-To et References <\(m.reponseA.trimmingCharacters(in: CharacterSet(charactersIn: "<>")))> (\(m.filDepuis))")
        l += m.avertissements.map { "Attention : \($0)" }
        l += ["----- texte -----", m.texte, "----- fin -----", "Empreinte : \(m.empreinte)"]
        return l.joined(separator: "\n")
    }

    // MARK: Identifiant

    /// L'id complet d'après l'id entier ou l'id court de `a-envoyer` (6 caractères au moins, un seul message).
    static func resoudre(_ donne: String, stock: Stockage) throws -> String {
        let t = donne.trimmingCharacters(in: .whitespaces).lowercased()
        guard t.count >= 6, t.allSatisfy({ $0.isHexDigit || $0 == "-" }) else {
            throw RefusEnvoi(evenementId: donne, raisons: ["identifiant « \(donne) » illisible : l'id (ou l'id court, 6 caractères au moins) donné par a-envoyer"])
        }
        let l = try stock.base.lignes("SELECT id FROM evenements WHERE id LIKE ? AND supprime_le = '' LIMIT 3", [t + "%"])
            .compactMap { $0["id"] as? String }
        guard l.count == 1, let id = l.first else {
            throw RefusEnvoi(evenementId: donne, raisons: [l.isEmpty ? "message introuvable (ou supprimé)"
                                                                   : "id court ambigu (\(l.count) messages commencent par « \(t) ») : donner l'id complet"])
        }
        return id
    }

    // MARK: Envoyer

    /// essai : le mail préparé, rien d'envoyé ni d'écrit. Sinon : refus relus juste avant, envoi, puis l'écriture de l'app.
    /// `empreinte` (celle de l'essai montré à Sacha) : si le mail a changé depuis, refus.
    static func envoyer(_ donne: String, stock: Stockage, outils: OutilsEnvoi, essai: Bool, empreinte attendue: String? = nil) throws -> ResultatEnvoi {
        let id = try resoudre(donne, stock: stock)
        let e = try stock.evenement(id)
        let c = try e.flatMap { try stock.contact($0.contactId) }
        let de = outils.expediteur()?.trimmingCharacters(in: .whitespaces)
        let present = de.map { !$0.isEmpty && outils.motDePassePresent($0) } ?? false
        let raisons = refus(e, c, expediteur: de, motDePassePresent: present, francais: true)   // pour un agent et la base : français
        guard raisons.isEmpty, let e, let c, let de else { throw RefusEnvoi(evenementId: id, raisons: raisons) }
        let mail = preparer(e, c, de: de, dernierRecu: outils.dernierRecu)
        if let attendue = attendue?.trimmingCharacters(in: .whitespaces), !attendue.isEmpty, attendue != mail.empreinte {
            throw RefusEnvoi(evenementId: id, raisons: ["le mail a changé depuis l'essai (empreinte \(attendue), maintenant \(mail.empreinte)) : refaire l'essai et le remontrer à \(Moi.nom)"])
        }
        if essai { return ResultatEnvoi(essai: true, envoye: false, messageId: "", mail: mail, apercu: apercu(mail, essai: true)) }
        let messageId = try outils.envoyer(mail.a, mail.objet, mail.texte, mail.reponseA)
        do {
            try finaliser(stock, evenementId: id, texte: mail.texte, objet: mail.objet, reponseA: mail.reponseA, messageId: messageId)
        } catch {
            throw ErreurApresEnvoi(evenementId: id, messageId: messageId, cause: "\(error)")
        }
        return ResultatEnvoi(essai: false, envoye: true, messageId: messageId, mail: mail, apercu: apercu(mail, essai: false))
    }

    /// Le message d'une erreur d'`envoyer`, pour l'outil et le MCP. Un échec de curl en cours d'envoi peut arriver APRÈS que
    /// Gmail a accepté le mail (délai dépassé) : on dit de vérifier les envoyés avant de réessayer.
    static func messageErreur(_ error: Error) -> String {
        switch error {
        case let r as RefusEnvoi: return r.description
        case let a as ErreurApresEnvoi: return a.description
        case Gmail.ErreurGmail.echec(let m):
            return "Échec de l'envoi par Gmail (\(m)). Vérifier dans Gmail › Messages envoyés avant de réessayer : le message reste « prepare »."
        default:
            return "Pas envoyé, rien n'est parti : " + ((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    // MARK: Liste

    static func etatCondition(_ e: Evenement) -> String {
        if e.condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "aucune" }
        return e.conditionOkLe.isEmpty ? "à cocher" : "cochée le \(Dates.court(e.conditionOkLe, francais: true))"
    }

    /// Les messages « prepare » (tous canaux), du plus ancien au plus récent, avec ce que `pilote envoie` en dirait.
    static func aEnvoyer(_ stock: Stockage, outils: OutilsEnvoi, aujourdhui: String = Dates.aujourdhui()) throws -> [EnvoiEnAttente] {
        let de = outils.expediteur()?.trimmingCharacters(in: .whitespaces)
        let present = de.map { !$0.isEmpty && outils.motDePassePresent($0) } ?? false
        return try stock.aEnvoyer().map { e, c in
            var r = refus(e, c, expediteur: de, motDePassePresent: present)
            if e.canal != "mail" { r = refusCanal(e).map { [$0] } ?? [] }   // un SMS ou un DM : seule la raison du canal compte
            let debut = e.texte.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            return EnvoiEnAttente(id: String(e.id.prefix(8)), evenementId: e.id, contact: nomContact(c), contactId: c.id, canal: e.canal,
                                 objet: e.objet, debut: debut.count > 100 ? String(debut.prefix(100)) + "…" : debut,
                                 condition: e.condition, conditionEtat: etatCondition(e),
                                 jour: Libelles.jourDuMessage(texte: e.texte, le: e.le, dateFiche: c.prochaineDate, aujourdhui: aujourdhui, condition: e.conditionPourJour, reponseA: e.reponseA),
                                 envoyable: r.isEmpty, refus: r)
        }
    }
}

// MARK: Les outils réels, et le faux des essais

private final class Boite<T>: @unchecked Sendable { var r: Result<T, Error>? }

/// Attend une fonction asynchrone depuis l'outil en ligne de commande (synchrone). Jamais depuis le fil principal de l'app.
func attendreAsync<T>(_ f: @escaping @Sendable () async throws -> T) throws -> T {
    let b = Boite<T>(), s = DispatchSemaphore(value: 0)
    Task.detached {
        do { b.r = .success(try await f()) } catch { b.r = .failure(error) }
        s.signal()
    }
    s.wait()
    return try b.r!.get()
}

extension OutilsEnvoi {
    /// Le vrai : l'adresse et le mot de passe rangés par l'app (« Connecter Gmail »), Mail de ce Mac pour le repli, envoi Gmail.
    static let mac = OutilsEnvoi(
        expediteur: { Gmail.adresse },
        motDePassePresent: { Gmail.motDePassePresent($0) },
        dernierRecu: { a, o in try attendreAsync { try await Mail.dernierRecu(de: a, objet: o, delaiMax: 75) } },
        envoyer: { a, o, t, r in try Gmail.envoyerSansFenetre(a: a, objet: o, texte: t, reponseA: r) })

    /// PILOTE_ENVOI_FAUX=<fichier> : essais de bout en bout. Rien ne part : le mail composé (Gmail.composer, le même que le
    /// vrai) est ajouté au fichier. Seulement avec PILOTE_BASE sur une autre base que la vraie (sinon erreur, rien ne se fait).
    /// Avec lui : PILOTE_FAUX_DE (expéditeur, défaut vous@exemple.fr), PILOTE_FAUX_MDP=absent (mot de passe absent),
    /// PILOTE_FAUX_DERNIER_RECU (Message-ID rendu par le repli Mail, défaut aucun) ; ni trousseau, ni Mail, ni réseau.
    static func selonEnvironnement(_ env: [String: String] = ProcessInfo.processInfo.environment) throws -> OutilsEnvoi {
        guard let fichier = env["PILOTE_ENVOI_FAUX"], !fichier.isEmpty else { return .mac }
        let vraie = Base.dossier.appendingPathComponent("pilote.sqlite").resolvingSymlinksInPath().path
        guard let autre = env["PILOTE_BASE"], !autre.isEmpty,
              URL(fileURLWithPath: autre).resolvingSymlinksInPath().path != vraie else {
            throw ErreurBase(description: "PILOTE_ENVOI_FAUX seulement avec PILOTE_BASE sur une copie de la base (jamais la vraie) : rien n'a été fait.")
        }
        let de = env["PILOTE_FAUX_DE"] ?? "vous@exemple.fr"
        return OutilsEnvoi(
            expediteur: { de.isEmpty ? nil : de },
            motDePassePresent: { _ in env["PILOTE_FAUX_MDP"] != "absent" },
            dernierRecu: { _, _ in env["PILOTE_FAUX_DERNIER_RECU"] },
            envoyer: { a, o, t, r in
                if EnvoisKryva.estInterdit(de) { throw Gmail.ErreurGmail.depuisKryva(de) }
                let id = "essai-" + Gmail.nouveauMessageId()
                let mail = Gmail.composer(de: de, a: a, objet: o, texte: t, reponseA: r, messageId: id)
                let url = URL(fileURLWithPath: fichier)
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                let h = try FileHandle(forWritingTo: url)
                defer { try? h.close() }
                h.seekToEndOfFile()
                h.write(Data("===== FAUX ENVOI \(id) (rien n'est parti) =====\r\n\(mail)".utf8))
                return id
            })
    }
}
