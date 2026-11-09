// File d'envoi des mails validés (07/11, Sacha : « pour les mails à envoyer, il faut qu'ils soient envoyés automatiquement
// dès que je clique sur un bouton (ils sont envoyés à 5 min d'intervalle chacun, une session/script le fait à ma place
// depuis vous@exemple.fr). Pour les SMS/LinkedIn, je le fais à la main. »).
//
// Qui fait quoi :
// - le bouton de l'app (Aujourd'hui › « Envoyer les mails validés ») montre les mails « prepare » (canal mail), Sacha coche
//   et confirme : `mettreEnFile`. Seul un mail sans refus (condition cochée ou absente, objet, adresse, pas « ne plus
//   contacter », pas kryva.fr, Gmail connecté) entre dans la file ; SMS, LinkedIn et autres canaux : jamais.
// - l'agent launchd io.github.pjksens.pilote.file-envoi lance `pilote file-envoi --passe` toutes les 30 s, que l'app soit
//   ouverte ou non : `passe` envoie AU PLUS un mail, 5 min après le précédent, par EnvoiPilote.envoyer (le chemin de
//   `pilote envoie` et du bouton « Envoyer depuis Gmail » : mêmes refus, même finaliser : envoye + message_id + suite J+5).
// - chaque mail est relu juste avant : statut, texte, objet, fil ou adresse changés depuis la mise en file = il saute.
// - un échec d'envoi n'arrête pas les suivants ; 2 échecs de suite dans un lot arrêtent la file et préviennent (REVEIL pour
//   PILOTE par file-envoi-alertes.jsonl, que lit scripts/veille.py, et notification).
// Le fil d'un mail en « Re: » sans reponse_a (dernier mail reçu de la personne, dans Mail) est cherché à la mise en file,
// par l'app (qui a le droit de piloter Mail) : l'agent launchd ne pilote pas Mail (invite d'autorisation possible, sans
// personne devant). Il est rendu à EnvoiPilote.envoyer par `dernierRecu`, exactement là où `pilote envoie` le cherche.
import CryptoKit
import Foundation

/// Une ligne de la file : un mail, son heure prévue, ce qui lui est arrivé.
struct ElementFile: Identifiable, Equatable, Encodable {
    var id: String
    /// Un clic = un lot.
    var lot: String
    var rang: Int
    var evenementId: String
    var contactId: String
    /// Le nom lisible et l'adresse, tels qu'à la mise en file (la fiche peut changer depuis : on le verra au refus).
    var contact: String
    var a: String
    var objet: String
    /// Empreinte de la fiche à la mise en file (statut, canal, objet, texte, reponse_a, adresse) : changée = le mail saute.
    var empreinte: String
    /// Le fil trouvé à la mise en file pour un « Re: » sans reponse_a (Message-ID du dernier mail reçu) ; vide = aucun.
    var reponseA: String
    /// Heure prévue (ISO, UTC) ; vide une fois traité.
    var prevuLe: String
    /// attente, envoi (en cours), envoye, refuse, echec, annule, incertain (envoi interrompu : vérifier Gmail).
    var etat: String
    var raison: String
    var messageId: String
    var misLe: String
    var faitLe: String

    var enCours: Bool { FileEnvoi.etatsActifs.contains(etat) }
}

/// Un mail que le bouton propose. Coché par défaut s'il peut partir aujourd'hui.
struct CandidatFile: Identifiable, Equatable {
    var evenement: Evenement
    var contact: Contact
    /// Le jour où il part, comme l'app le range (vide = dès que possible).
    var jour: String
    /// Pourquoi il ne peut pas partir (vide : il peut). Mêmes raisons que `pilote envoie`.
    var refus: [String]
    var aujourdhui: String
    var id: String { evenement.id }
    var envoyable: Bool { refus.isEmpty }
    /// Prévu un jour suivant : proposé, pas coché (Sacha le coche s'il veut qu'il parte maintenant).
    var plusTard: Bool { !jour.isEmpty && jour > aujourdhui }
    var cocheParDefaut: Bool { envoyable && !plusTard }
}

/// Ce que la passe signale : une ligne pour PILOTE (veille.py) et une notification.
struct AlerteFile: Encodable, Equatable {
    var id: String
    var le: String
    var titre: String
    var texte: String
    /// File arrêtée ou envoi incertain : PILOTE doit agir.
    var grave: Bool
}

struct BilanPasse: Encodable {
    var envoyes: [String] = []
    var refuses: [String] = []
    var echecs: [String] = []
    var arretee = false
    /// Pourquoi la passe s'arrête là (rien en file, prochain à HH:MM…).
    var suite = ""
}

enum FileEnvoi {
    static let intervalle: TimeInterval = 300
    static let etatsActifs: Set<String> = ["attente", "envoi"]
    static let etiquette = "io.github.pjksens.pilote.file-envoi"

    // MARK: Lecture

    static func element(_ l: [String: Any]) -> ElementFile {
        func t(_ k: String) -> String { l[k] as? String ?? "" }
        return ElementFile(id: t("id"), lot: t("lot"), rang: l["rang"] as? Int ?? 0, evenementId: t("evenement_id"),
                           contactId: t("contact_id"), contact: t("contact"), a: t("a"), objet: t("objet"),
                           empreinte: t("empreinte"), reponseA: t("reponse_a"), prevuLe: t("prevu_le"), etat: t("etat"),
                           raison: t("raison"), messageId: t("message_id"), misLe: t("mis_le"), faitLe: t("fait_le"))
    }

    /// Ordre de la file : lot par lot (heure du clic), puis l'ordre du lot. rowid (ordre d'insertion, aucune ligne n'est
    /// jamais effacée) départage deux clics dans la même seconde : trier par l'uuid du lot les mélangeait au hasard.
    private static let ordre = "ORDER BY mis_le, rowid"

    static func enAttente(_ stock: Stockage) throws -> [ElementFile] {
        try stock.base.lignes("SELECT * FROM file_envoi WHERE etat = 'attente' \(ordre)").map(element)
    }

    static func actifs(_ stock: Stockage) throws -> [ElementFile] {
        try stock.base.lignes("SELECT * FROM file_envoi WHERE etat IN ('attente', 'envoi') \(ordre)").map(element)
    }

    static func lot(_ stock: Stockage, _ lot: String) throws -> [ElementFile] {
        try stock.base.lignes("SELECT * FROM file_envoi WHERE lot = ? ORDER BY rang", [lot]).map(element)
    }

    /// Ce que l'app montre : tout ce qui est encore en file, et les lots mis en file aujourd'hui (heure de Paris).
    static func duJour(_ stock: Stockage, aujourdhui: String = Dates.aujourdhui()) throws -> [ElementFile] {
        try stock.base.lignes("SELECT * FROM file_envoi \(ordre)").map(element).filter { x in
            x.enCours || Dates.date(x.misLe).map { Dates.jour.string(from: $0) == aujourdhui } == true
        }
    }

    /// La dernière tentative d'envoi réelle (parti, échec, interrompu) : l'intervalle se compte depuis elle.
    static func derniereTentative(_ stock: Stockage) throws -> Date? {
        let l = try stock.base.lignes("SELECT max(fait_le) AS f FROM file_envoi WHERE etat IN ('envoye', 'echec', 'incertain')")
        return (l.first?["f"] as? String).flatMap(Dates.iso.date)
    }

    // MARK: Empreinte de la fiche

    static func empreinte(_ e: Evenement, _ c: Contact) -> String {
        let s = [e.statut, e.canal, e.objet, e.texte, e.reponseA, c.email.trimmingCharacters(in: .whitespaces).lowercased()]
            .joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // MARK: Ce que le bouton propose

    /// Les mails « prepare » pas déjà en file, avec ce que `pilote envoie` en dirait. Les autres canaux n'y sont jamais.
    static func candidats(_ stock: Stockage, outils: OutilsEnvoi, aujourdhui: String = Dates.aujourdhui()) throws -> [CandidatFile] {
        let enFile = Set(try actifs(stock).map(\.evenementId))
        let de = outils.expediteur()?.trimmingCharacters(in: .whitespaces)
        let present = de.map { !$0.isEmpty && outils.motDePassePresent($0) } ?? false
        return try stock.aEnvoyer().filter { e, _ in e.canal == "mail" && !enFile.contains(e.id) }.map { e, c in
            CandidatFile(evenement: e, contact: c,
                         jour: Libelles.jourDuMessage(texte: e.texte, le: e.le, dateFiche: c.prochaineDate, aujourdhui: aujourdhui, condition: e.conditionPourJour, reponseA: e.reponseA),
                         refus: EnvoiPilote.refus(e, c, expediteur: de, motDePassePresent: present), aujourdhui: aujourdhui)
        }
    }

    /// Faut-il chercher le fil dans Mail avant la mise en file ? (objet en « Re: » sans reponse_a, comme EnvoiPilote.preparer)
    static func filACherche(_ e: Evenement) -> Bool { e.reponseA.isEmpty && Mail.estReponse(e.objet) }

    // MARK: Mise en file (le clic de Sacha)

    /// Met en file les mails cochés, dans l'ordre donné. Relus ici : un mail refusé maintenant n'entre pas (ligne « refuse »
    /// avec la raison, visible dans la file) ; un mail déjà en file n'y entre pas deux fois. `fils` : evenementId → Message-ID
    /// trouvé dans Mail pour les « Re: » sans reponse_a. Le premier part dès la prochaine passe (5 min après le dernier envoi
    /// s'il est plus récent), puis un toutes les 5 min.
    @discardableResult
    static func mettreEnFile(_ stock: Stockage, ids: [String], fils: [String: String] = [:], outils: OutilsEnvoi,
                             maintenant: Date = Date(), intervalle: TimeInterval = FileEnvoi.intervalle) throws -> [ElementFile] {
        let lot = String(UUID().uuidString.lowercased().prefix(8))
        let mis = Dates.iso.string(from: maintenant)
        let de = outils.expediteur()?.trimmingCharacters(in: .whitespaces)
        let present = de.map { !$0.isEmpty && outils.motDePassePresent($0) } ?? false
        var vus = Set(try actifs(stock).map(\.evenementId))
        try stock.base.transaction {
            var rang = 0
            for id in ids where !vus.contains(id) {
                vus.insert(id)
                let e = try stock.evenement(id)
                let c = try e.flatMap { try stock.contact($0.contactId) }
                var raisons = EnvoiPilote.refus(e, c, expediteur: de, motDePassePresent: present)
                if let e, e.canal != "mail" { raisons = ["canal « \(e.canal) » : seuls les mails passent par la file (SMS, LinkedIn : à la main)"] }
                let fil = e.map { filACherche($0) ? (fils[id] ?? "") : "" } ?? ""
                try stock.base.executer("""
                    INSERT INTO file_envoi (id, lot, rang, evenement_id, contact_id, contact, a, objet, empreinte, reponse_a,
                                            prevu_le, etat, raison, message_id, mis_le, fait_le)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?)
                    """, [UUID().uuidString.lowercased(), lot, rang, id, c?.id ?? "", c.map(EnvoiPilote.nomContact) ?? "(introuvable)",
                          c?.email.trimmingCharacters(in: .whitespaces) ?? "", e?.objet ?? "",
                          (e.flatMap { e in c.map { empreinte(e, $0) } }) ?? "", fil,
                          raisons.isEmpty ? mis : "", raisons.isEmpty ? "attente" : "refuse",
                          raisons.isEmpty ? "" : "pas mis en file : " + raisons.joined(separator: " ; "), mis, raisons.isEmpty ? "" : mis])
                rang += 1
            }
            try replanifier(stock, maintenant: maintenant, intervalle: intervalle)
        }
        return try self.lot(stock, lot)
    }

    /// Recalcule les heures prévues de ce qui attend : le premier 5 min après la dernière tentative (ou maintenant), puis un
    /// toutes les 5 min. Appelé après chaque mail traité : un mail qui saute rend sa place au suivant.
    static func replanifier(_ stock: Stockage, maintenant: Date, intervalle: TimeInterval) throws {
        var prochain = maintenant
        if let d = try derniereTentative(stock), d.addingTimeInterval(intervalle) > prochain { prochain = d.addingTimeInterval(intervalle) }
        for x in try enAttente(stock) {
            try stock.base.executer("UPDATE file_envoi SET prevu_le = ? WHERE id = ?", [Dates.iso.string(from: prochain), x.id])
            prochain = prochain.addingTimeInterval(intervalle)
        }
    }

    // MARK: Arrêter

    /// « Arrêter la file » : tout ce qui attend est annulé (reste « prepare », rien ne part). Un mail en cours d'envoi finit.
    @discardableResult
    static func arreter(_ stock: Stockage, raison: String, maintenant: Date = Date()) throws -> Int {
        let n = try enAttente(stock).count
        try stock.base.executer("UPDATE file_envoi SET etat = 'annule', raison = ?, prevu_le = '', fait_le = ? WHERE etat = 'attente'",
                                [raison, Dates.iso.string(from: maintenant)])
        return n
    }

    // MARK: La passe (agent launchd, toutes les 30 s)

    private static func noter(_ stock: Stockage, _ x: ElementFile, etat: String, raison: String = "", messageId: String = "", le: Date) throws {
        try stock.base.executer("UPDATE file_envoi SET etat = ?, raison = ?, message_id = ?, prevu_le = '', fait_le = ? WHERE id = ?",
                                [etat, raison, messageId, Dates.iso.string(from: le), x.id])
    }

    private static func heure(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// Une passe : reprend un envoi interrompu, puis traite ce qui est dû (au plus un envoi réel : le suivant attend 5 min).
    /// `garde` (essais seulement) : une raison de refuser l'adresse avant tout envoi. `alerter` : REVEIL + notification.
    static func passe(_ stock: Stockage, outils: OutilsEnvoi, maintenant: () -> Date = Date.init,
                      intervalle: TimeInterval = FileEnvoi.intervalle, garde: ((String) -> String?)? = nil,
                      alerter: (AlerteFile) -> Void) throws -> BilanPasse {
        var bilan = BilanPasse()

        // 1. Un « envoi » resté d'une passe morte (le verrou de l'outil garantit qu'aucune autre ne tourne).
        for x in try stock.base.lignes("SELECT * FROM file_envoi WHERE etat = 'envoi' \(ordre)").map(element) {
            let t = maintenant()
            if let e = try stock.evenement(x.evenementId), e.statut == "envoye" || !e.messageId.isEmpty {
                try noter(stock, x, etat: "envoye", raison: "parti (noté après une passe interrompue)", messageId: e.messageId, le: t)
                continue
            }
            try noter(stock, x, etat: "incertain", raison: "envoi interrompu (Mac éteint ou outil arrêté pendant l'envoi) : vérifier dans Gmail › Messages envoyés ; il reste « prepare », ne pas le remettre en file s'il est parti", le: t)
            let n = try arreter(stock, raison: "file arrêtée : l'envoi à \(x.contact) a été interrompu, à vérifier avant de reprendre", maintenant: t)
            bilan.arretee = true
            alerter(AlerteFile(id: "\(x.lot)-incertain-\(x.rang)", le: Dates.iso.string(from: t), titre: "Pilote · file d'envoi arrêtée",
                               texte: "Envoi à \(x.contact) <\(x.a)> (« \(x.objet) ») interrompu : parti ou non, à vérifier dans Gmail › Messages envoyés. File arrêtée, \(n) mail(s) annulé(s), toujours « prepare » : \(Moi.nom) reclique « Envoyer les mails validés » après vérification.",
                               grave: true))
        }

        // 2. Ce qui est dû.
        while let x = try enAttente(stock).first {
            let t = maintenant()
            if let prevu = Dates.iso.date(from: x.prevuLe), t < prevu { bilan.suite = "prochain vers \(heure(prevu)) : \(x.contact)"; break }
            if let d = try derniereTentative(stock), t < d.addingTimeInterval(intervalle) {
                bilan.suite = "prochain vers \(heure(d.addingTimeInterval(intervalle))) : \(x.contact)"
                break
            }
            // Réservé par cette passe seulement (une autre connexion aurait pu le prendre ou l'annuler entre-temps).
            let jeton = "passe-" + UUID().uuidString.lowercased()
            try stock.base.executer("UPDATE file_envoi SET etat = 'envoi', raison = ? WHERE id = ? AND etat = 'attente'", [jeton, x.id])
            guard (try stock.base.lignes("SELECT raison FROM file_envoi WHERE id = ?", [x.id]).first?["raison"] as? String) == jeton else { continue }

            // Relu juste avant l'envoi.
            let e = try stock.evenement(x.evenementId)
            let c = try e.flatMap { try stock.contact($0.contactId) }
            let de = outils.expediteur()?.trimmingCharacters(in: .whitespaces)
            let present = de.map { !$0.isEmpty && outils.motDePassePresent($0) } ?? false
            var raisons = EnvoiPilote.refus(e, c, expediteur: de, motDePassePresent: present)
            if raisons.isEmpty, let e, let c, empreinte(e, c) != x.empreinte {
                raisons = ["le mail a changé depuis la mise en file (texte, objet, fil, adresse ou statut) : il saute ; le remettre en file après relecture"]
            }
            if raisons.isEmpty, let c, let g = garde?(c.email.trimmingCharacters(in: .whitespaces)) { raisons = [g] }
            if !raisons.isEmpty {
                try noter(stock, x, etat: "refuse", raison: raisons.joined(separator: " ; "), le: t)
                bilan.refuses.append(x.contact)
                try replanifier(stock, maintenant: t, intervalle: intervalle)
                continue
            }

            // Le chemin de `pilote envoie` : refus relus, préparation, envoi Gmail, finaliser (envoye, message_id, suite J+5).
            let fil = x.reponseA
            let outilsX = OutilsEnvoi(expediteur: outils.expediteur, motDePassePresent: outils.motDePassePresent,
                                      dernierRecu: { _, _ in fil.isEmpty ? nil : fil }, envoyer: outils.envoyer)
            do {
                let r = try EnvoiPilote.envoyer(x.evenementId, stock: stock, outils: outilsX, essai: false)
                try noter(stock, x, etat: "envoye", raison: r.mail.avertissements.joined(separator: " ; "), messageId: r.messageId, le: maintenant())
                bilan.envoyes.append(x.contact)
            } catch let r as RefusEnvoi {
                try noter(stock, x, etat: "refuse", raison: r.raisons.joined(separator: " ; "), le: maintenant())
                bilan.refuses.append(x.contact)
                try replanifier(stock, maintenant: maintenant(), intervalle: intervalle)
                continue
            } catch let a as ErreurApresEnvoi {
                let t2 = maintenant()
                try noter(stock, x, etat: "envoye", raison: a.description, messageId: a.messageId, le: t2)
                bilan.envoyes.append(x.contact)
                let n = try arreter(stock, raison: "file arrêtée : le mail à \(x.contact) est parti mais Pilote n'a pas pu le noter", maintenant: t2)
                bilan.arretee = true
                alerter(AlerteFile(id: "\(x.lot)-apres-envoi-\(x.rang)", le: Dates.iso.string(from: t2), titre: "Pilote · file d'envoi arrêtée",
                                   texte: "\(a.description) File arrêtée, \(n) mail(s) annulé(s), toujours « prepare ».", grave: true))
                break
            } catch {
                let t2 = maintenant()
                try noter(stock, x, etat: "echec", raison: EnvoiPilote.messageErreur(error), le: t2)
                bilan.echecs.append(x.contact)
                let derniers = try stock.base.lignes("""
                    SELECT etat FROM file_envoi WHERE lot = ? AND etat IN ('envoye', 'echec') ORDER BY fait_le DESC, rang DESC LIMIT 2
                    """, [x.lot]).compactMap { $0["etat"] as? String }
                if derniers == ["echec", "echec"] {
                    let n = try arreter(stock, raison: "file arrêtée : 2 échecs d'envoi de suite (Gmail)", maintenant: t2)
                    bilan.arretee = true
                    alerter(AlerteFile(id: "\(x.lot)-deux-echecs", le: Dates.iso.string(from: t2), titre: "Pilote · file d'envoi arrêtée",
                                       texte: "2 échecs d'envoi de suite, file arrêtée (\(n) mail(s) annulé(s), toujours « prepare »). Dernier : \(x.contact) : \(EnvoiPilote.messageErreur(error)) Vérifier Gmail (mot de passe d'application, réseau, Messages envoyés) avant de recliquer « Envoyer les mails validés ».",
                                       grave: true))
                    break
                }
                alerter(AlerteFile(id: "\(x.lot)-echec-\(x.rang)", le: Dates.iso.string(from: t2), titre: "Pilote · un mail n'est pas parti",
                                   texte: "\(x.contact) : \(EnvoiPilote.messageErreur(error)) La file continue.", grave: false))
            }
            try replanifier(stock, maintenant: maintenant(), intervalle: intervalle)
        }
        if bilan.suite.isEmpty { bilan.suite = try enAttente(stock).isEmpty ? "rien en file" : "suite à la prochaine passe" }
        try annoncerLotsFinis(stock, maintenant: maintenant(), alerter: alerter)
        return bilan
    }

    /// Un lot dont plus rien n'attend : son bilan part une fois (PILOTE suit les fiches, Sacha voit la notification).
    private static func annoncerLotsFinis(_ stock: Stockage, maintenant: Date, alerter: (AlerteFile) -> Void) throws {
        let lots = try stock.base.lignes("""
            SELECT lot, min(mis_le) AS mis FROM file_envoi GROUP BY lot
            HAVING sum(etat IN ('attente', 'envoi')) = 0 AND sum(etat IN ('envoye', 'echec', 'incertain', 'annule')) > 0
            """).compactMap { l -> (String, String)? in (l["lot"] as? String).map { ($0, l["mis"] as? String ?? "") } }
        for (lot, mis) in lots {
            let cle = "file_envoi.annonce.\(lot)"
            guard try stock.base.lignes("SELECT valeur FROM reglages WHERE cle = ?", [cle]).isEmpty else { continue }
            let l = try self.lot(stock, lot)
            func noms(_ etats: Set<String>, raison: Bool = false) -> [String] {
                l.filter { etats.contains($0.etat) }.map { x in
                    let r = x.raison.replacingOccurrences(of: "pas mis en file : ", with: "")
                    return raison && !r.isEmpty ? "\(x.contact) (\(r.count > 90 ? String(r.prefix(90)) + "…" : r))" : x.contact
                }
            }
            let partis = noms(["envoye"]), refuses = noms(["refuse"], raison: true), echecs = noms(["echec", "incertain"], raison: true)
            let annules = noms(["annule"])
            var morceaux = ["\(partis.count) envoyé(s)" + (partis.isEmpty ? "" : " : " + partis.joined(separator: ", "))]
            if !refuses.isEmpty { morceaux.append("\(refuses.count) sauté(s) : " + refuses.joined(separator: " ; ")) }
            if !echecs.isEmpty { morceaux.append("\(echecs.count) pas parti(s) : " + echecs.joined(separator: " ; ")) }
            if !annules.isEmpty { morceaux.append("\(annules.count) annulé(s) (file arrêtée) : " + annules.joined(separator: ", ")) }
            let quand = Dates.iso.date(from: mis).map(heure) ?? "?"
            alerter(AlerteFile(id: "\(lot)-fin", le: Dates.iso.string(from: maintenant),
                               titre: partis.count == l.count ? "Pilote · mails envoyés" : "Pilote · file d'envoi terminée",
                               texte: "File d'envoi du clic de \(quand) terminée : " + morceaux.joined(separator: ". ")
                                + ". Les fiches des mails partis sont à jour (envoyé + suite J+5).",
                               grave: !echecs.isEmpty))
            try stock.base.executer("INSERT OR REPLACE INTO reglages (cle, valeur) VALUES (?, ?)", [cle, Dates.iso.string(from: maintenant)])
        }
    }
}

extension Base {
    /// 07/11 : la file d'envoi des mails validés. Table locale (hors synchro KRYVA), ajoutée vide : rien d'existant ne change.
    func migrerFileEnvoi() throws {
        try executer("""
        CREATE TABLE IF NOT EXISTS file_envoi (
          id TEXT PRIMARY KEY,
          lot TEXT NOT NULL,
          rang INTEGER NOT NULL DEFAULT 0,
          evenement_id TEXT NOT NULL,
          contact_id TEXT NOT NULL DEFAULT '',
          contact TEXT NOT NULL DEFAULT '',
          a TEXT NOT NULL DEFAULT '',
          objet TEXT NOT NULL DEFAULT '',
          empreinte TEXT NOT NULL DEFAULT '',
          reponse_a TEXT NOT NULL DEFAULT '',
          prevu_le TEXT NOT NULL DEFAULT '',
          etat TEXT NOT NULL DEFAULT 'attente',
          raison TEXT NOT NULL DEFAULT '',
          message_id TEXT NOT NULL DEFAULT '',
          mis_le TEXT NOT NULL,
          fait_le TEXT NOT NULL DEFAULT ''
        )
        """)
        try executer("CREATE INDEX IF NOT EXISTS file_envoi_etat ON file_envoi(etat, mis_le)")
    }
}

extension FileEnvoi {
    /// PILOTE_BASE vise une autre base que la vraie (essais) : seuls cas où l'outil accepte de mettre en file lui-même.
    static func surCopie(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if env["PILOTE_DEMO"] == "1" { return true }
        guard let autre = env["PILOTE_BASE"], !autre.isEmpty else { return false }
        let vraie = Base.dossier.appendingPathComponent("pilote.sqlite").resolvingSymlinksInPath().path
        return URL(fileURLWithPath: autre).resolvingSymlinksInPath().path != vraie
    }

    /// Le dossier de la base utilisée : alertes et verrou à côté d'elle (une copie d'essai n'écrit rien chez la vraie).
    static var dossierDeLaBase: URL { Base.cheminParDefaut.deletingLastPathComponent() }
    static var fichierAlertes: URL { dossierDeLaBase.appendingPathComponent("file-envoi-alertes.jsonl") }

    /// Ajoute la ligne JSON de l'alerte au fichier lu par scripts/veille.py ; une erreur si elle n'a pas pu être écrite.
    static func ecrire(_ a: AlerteFile, dans url: URL) throws {
        let ligne = String(decoding: try JSONEncoder().encode(a), as: UTF8.self) + "\n"
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw ErreurBase(description: "fichier d'alertes impossible à créer : \(url.path)")
            }
        }
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(ligne.utf8))
        try h.synchronize()
    }

    /// Une ligne JSON par alerte (lue par scripts/veille.py : REVEIL pour PILOTE) et une notification sur le Mac.
    static func publier(_ a: AlerteFile, essai: Bool) {
        if Demo.actif { return }
        try? ecrire(a, dans: fichierAlertes)
        if essai && ProcessInfo.processInfo.environment["PILOTE_SANS_NOTIF"] != nil { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)", "-e", "end run",
                       (essai ? "[essai] " : "") + a.titre, a.texte]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}

// MARK: L'agent launchd et l'outil (vus depuis l'app)

extension FileEnvoi {
    /// L'outil que lance l'agent (même chemin que dans le .plist).
    static var outil: URL { Identite.depot.appendingPathComponent("pilote") }
    private static var cible: String { "gui/\(getuid())/\(etiquette)" }

    @discardableResult
    static func lancer(_ chemin: String, _ arguments: [String]) -> (code: Int32, sortie: String, erreur: String) {
        if Demo.actif { return (1, "", Demo.Refus().description) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: chemin)
        p.arguments = arguments
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return (-1, "", "\(error)") }
        let so = o.fileHandleForReading.readDataToEndOfFile(), se = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: so, as: UTF8.self), String(decoding: se, as: UTF8.self))
    }

    /// L'agent est-il chargé ? (sinon rien ne part une fois l'app fermée)
    static func agentCharge() -> Bool { lancer("/bin/launchctl", ["print", cible]).code == 0 }

    /// Réveille l'agent pour que le premier mail parte tout de suite (sinon il part à sa passe suivante, 30 s au plus).
    static func reveillerAgent() -> String? {
        guard agentCharge() else {
            return "Mails en file, mais l'envoi automatique n'est pas installé (agent \(etiquette)) : rien ne partira. Arrêter la file et prévenir PILOTE."
        }
        _ = lancer("/bin/launchctl", ["kickstart", cible])
        return nil
    }

    /// L'outil peut-il lire le mot de passe Gmail sans fenêtre ? nil = oui ; sinon la raison (rien ne partirait).
    static func accesOutil() -> String? {
        guard FileManager.default.isExecutableFile(atPath: outil.path) else { return "Outil d'envoi introuvable (\(outil.path))." }
        let r = lancer(outil.path, ["file-envoi", "--acces"])
        if r.code == 0 { return nil }
        let e = r.erreur.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? "L'outil d'envoi ne répond pas (code \(r.code))." : e
    }
}
