// Mail.app par AppleScript : la partie sans interface (Foundation seule), partagée par l'app et l'outil `pilote`.
// 05/11 (étape 1 de PILOTE, envoi sur « envoie ») : `pilote envoie` doit retrouver le fil exactement comme le bouton
// « Envoyer depuis Gmail » de l'app (repli `dernierRecu`). Le reste (brouillons, réponses, ouvrir) reste dans
// App/Integrations/Mail.swift, en extension de ce type. Lecture seulement ici : rien n'est envoyé par Mail.
import Foundation

struct MessageMail: Identifiable, Hashable, Codable {
    let id: String          // Message-ID
    let correspondant: String
    let adresse: String
    let objet: String
    let date: Date
    let lu: Bool
    let envoye: Bool        // true si c'est Sacha qui l'a envoyé
}

enum Mail {
    static let champ = "\u{1F}"
    static let ligne = "\u{1E}"

    /// Lance osascript hors du fil principal (l'autorisation « Pilote veut contrôler Mail » est demandée une fois).
    /// `delaiMax` (outil en ligne de commande) : osascript est arrêté au-delà, pour qu'une invite d'autorisation restée
    /// sans réponse sur le Mac ne bloque pas une session lancée depuis l'iPhone. L'app n'en met pas.
    /// Seul passage vers Mail.app : coupé tant que reglages.json ne dit pas `mail: true` (et toujours en démo).
    static func executer(_ script: String, delaiMax: TimeInterval? = nil) async throws -> String {
        if Demo.actif { throw Demo.Refus() }
        guard Reglages.courants.mail == true else { throw IntegrationCoupee(reglage: "mail") }
        return try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let sortie = Pipe(), erreur = Pipe()
            p.standardOutput = sortie
            p.standardError = erreur
            try p.run()
            var arret: DispatchWorkItem?
            if let delaiMax {
                let a = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + delaiMax, execute: a)
                arret = a
            }
            let data = sortie.fileHandleForReading.readDataToEndOfFile()
            let err = erreur.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            arret?.cancel()
            if p.terminationReason == .uncaughtSignal { throw ErreurMail.echec("Mail n'a pas répondu à temps") }
            guard p.terminationStatus == 0 else {
                let message = String(data: err, encoding: .utf8) ?? ""
                if message.contains("-1743") { throw ErreurMail.nonAutorise }
                throw ErreurMail.echec(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    enum ErreurMail: LocalizedError {
        case nonAutorise
        case echec(String)
        case pasDeGmail
        var errorDescription: String? {
            switch self {
            case .nonAutorise: return L("Pilote n'a pas accès à Mail. Réglages Système › Confidentialité › Automatisation › Pilote › Mail.")
            case .echec(let m) where m.contains("4401"): return L("Le mail d'origine n'est pas dans Mail : envoi en réponse impossible.")
            case .echec: return L("Mail n'a pas répondu.")
            case .pasDeGmail: return L("Aucun compte Gmail dans Mail.app. Ajoutez-le dans Mail › Réglages › Comptes.")
            }
        }
    }

    static let formatMessage = """
    set d to date received of m
    set out to out & (message id of m) & US & (sender of m) & US & (subject of m) & US & (year of d) & US & ((month of d) as integer) & US & (day of d) & US & (time of d) & US & (read status of m) & US & SENS & RS
    """

    /// Le dernier mail reçu de cette adresse (boîtes de réception), pour répondre dans le fil quand `reponse_a` manque.
    /// Priorité au mail du même sujet (sans « Re: »), sinon le plus récent. nil si rien.
    static func dernierRecu(de adresse: String, objet: String, delaiMax: TimeInterval? = nil) async throws -> String? {
        let a = adresse.lowercased().replacingOccurrences(of: "\"", with: "")
        guard a.contains("@") else { return nil }
        let script = """
        set US to character id 31
        set RS to character id 30
        set SENS to "r"
        with timeout of 60 seconds
        tell application "Mail"
          set out to ""
          repeat with m in (messages of inbox whose sender contains "\(a)")
            \(formatMessage)
          end repeat
          return out
        end tell
        end timeout
        """
        let recus = analyser(try await executer(script, delaiMax: delaiMax)).filter { $0.adresse == a }.sorted { $0.date > $1.date }
        let sujet = sansPrefixe(objet)
        return (recus.first { sansPrefixe($0.objet) == sujet } ?? recus.first)?.id
    }

    static func echapper(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// « Re: RE : Fwd: Objet » → « objet » : pour comparer deux sujets d'un même fil.
    static func sansPrefixe(_ objet: String) -> String {
        var s = objet.trimmingCharacters(in: .whitespaces)
        while let r = s.range(of: #"^(re|tr|fw|fwd)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            s.removeSubrange(r)
        }
        return s.lowercased()
    }

    /// Un objet qui commence par « Re: » : le mail est une réponse.
    static func estReponse(_ objet: String) -> Bool {
        objet.range(of: #"^\s*re\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// « Prénom Nom <adresse> » → adresse en minuscules.
    static func adresse(_ expediteur: String) -> String {
        if let debut = expediteur.lastIndex(of: "<"), let fin = expediteur.lastIndex(of: ">"), debut < fin {
            return String(expediteur[expediteur.index(after: debut)..<fin]).lowercased()
        }
        return expediteur.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func nom(_ expediteur: String) -> String {
        guard let debut = expediteur.lastIndex(of: "<") else { return expediteur }
        let n = expediteur[..<debut].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        return n.isEmpty ? adresse(expediteur) : n
    }

    static func analyser(_ sortie: String) -> [MessageMail] {
        sortie.components(separatedBy: ligne).compactMap { bloc in
            let f = bloc.trimmingCharacters(in: .newlines).components(separatedBy: champ)
            guard f.count >= 9, let an = Int(f[3]), let mois = Int(f[4]), let jour = Int(f[5]), let secondes = Int(f[6]) else { return nil }
            var c = DateComponents(year: an, month: mois, day: jour)
            c.second = secondes
            let date = Calendar.current.date(from: c) ?? Date()
            return MessageMail(id: f[0], correspondant: nom(f[1]), adresse: adresse(f[1]), objet: f[2], date: date,
                               lu: f[7] == "true", envoye: f[8] == "e")
        }
    }
}
