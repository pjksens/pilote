// Mail.app (tous les comptes : iCloud, Google, sacha@, contact@, social@) par AppleScript.
// Lecture et brouillons seulement : Pilote n'envoie jamais un mail par Mail.
// 05/11 : le cœur sans interface (MessageMail, executer, dernierRecu, sansPrefixe, estReponse, adresse, nom, analyser)
// est dans Shared/MailScript.swift, partagé avec l'outil `pilote` (envoi sur « envoie »). Ici, ce qui ouvre des fenêtres.
import AppKit
import Foundation

extension Mail {
    /// Messages reçus ces derniers jours, toutes boîtes de réception confondues.
    static func recus(jours: Int) async throws -> [MessageMail] {
        if Demo.actif { return [] }
        guard Reglages.courants.mail == true else { throw IntegrationCoupee(reglage: "mail") }
        let script = """
        set US to character id 31
        set RS to character id 30
        set SENS to "r"
        with timeout of 90 seconds
        tell application "Mail"
          set cutoff to (current date) - \(jours) * days
          set out to ""
          repeat with m in (messages of inbox whose date received > cutoff)
            \(formatMessage)
          end repeat
          return out
        end tell
        end timeout
        """
        return analyser(try await executer(script))
    }

    /// Échanges avec une adresse : reçus d'elle et envoyés à elle.
    static func echanges(adresse: String, jours: Int = 120) async throws -> [MessageMail] {
        let a = adresse.replacingOccurrences(of: "\"", with: "")
        let script = """
        set US to character id 31
        set RS to character id 30
        with timeout of 120 seconds
        tell application "Mail"
          set cutoff to (current date) - \(jours) * days
          set out to ""
          set SENS to "r"
          repeat with m in (messages of inbox whose sender contains "\(a)" and date received > cutoff)
            \(formatMessage)
          end repeat
          set SENS to "e"
          repeat with m in (messages of sent mailbox whose date sent > cutoff)
            if (address of to recipients of m) contains "\(a)" then
              \(formatMessage)
            end if
          end repeat
          return out
        end tell
        end timeout
        """
        return analyser(try await executer(script)).sorted { $0.date > $1.date }
    }

    /// Le compte Gmail perso de Sacha dans Mail.app : c'est de lui que partent les mails de Pilote,
    /// jamais du domaine kryva.fr (réputation abîmée, décision du 16/10).
    static func compteGmail() async throws -> (compte: String, adresse: String) {
        let sortie = try await executer("""
        tell application "Mail"
          set out to ""
          repeat with a in every account
            set out to out & (name of a) & (character id 31) & ((email addresses of a) as string) & (character id 30)
          end repeat
          return out
        end tell
        """)
        let comptes = sortie.components(separatedBy: ligne).compactMap { bloc -> (String, String)? in
            let f = bloc.trimmingCharacters(in: .newlines).components(separatedBy: champ)
            guard f.count == 2, f[1].lowercased().hasSuffix("@gmail.com") else { return nil }
            return (f[0], f[1].trimmingCharacters(in: .whitespaces))
        }
        guard let c = comptes.first(where: { $0.0 == "Google" }) ?? comptes.first else { throw ErreurMail.pasDeGmail }
        return c
    }

    /// Ouvre un brouillon dans Mail, depuis le compte Gmail, prêt à relire. Rien ne part sans Sacha.
    /// L'expéditeur est TOUJOURS le Gmail perso : pas de repli sur le compte par défaut de Mail (qui peut être kryva.fr).
    /// Sans compte Gmail dans Mail, échec franc (`pasDeGmail`) : aucun brouillon n'est ouvert.
    static func brouillon(a adresse: String, objet: String = "", texte: String = "") async throws {
        if Demo.actif { throw Demo.Refus() }
        guard Reglages.courants.mail == true else { throw IntegrationCoupee(reglage: "mail") }
        let gmail = try await compteGmail()
        let expediteur = "\(Gmail.nomExpediteur) <\(gmail.adresse)>"
        let script = """
        tell application "Mail"
          set msg to make new outgoing message with properties {visible:true, subject:"\(echapper(objet))", content:"\(echapper(texte))"}
          set sender of msg to "\(echapper(expediteur))"
          tell msg to make new to recipient at end of to recipients with properties {address:"\(echapper(adresse))"}
          activate
        end tell
        """
        _ = try await executer(script)
    }

    /// Répond dans le fil : Mail retrouve le mail d'origine par son Message-ID et fait « Répondre » (objet « Re: … »,
    /// In-Reply-To et References posés par Mail). Expéditeur forcé sur le Gmail perso. Rien ne part sans Sacha.
    /// Le texte est posé APRÈS l'ouverture de la fenêtre : posé avant, Mail l'ignore et ne met que la citation (testé le 05/11).
    /// Mail d'origine absent de Mail : erreur 4401 (`ErreurMail.echec`), l'appelant ouvre alors un nouveau mail.
    static func repondre(a messageId: String, texte: String) async throws {
        let gmail = try await compteGmail()
        let id = messageId.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        let script = """
        with timeout of 90 seconds
        tell application "Mail"
          set idm to "\(echapper(id))"
          set ms to (messages of inbox whose message id is idm)
          if (count of ms) = 0 then
            repeat with c in every account
              repeat with b in every mailbox of c
                try
                  set ms to (messages of b whose message id is idm)
                end try
                if (count of ms) > 0 then exit repeat
              end repeat
              if (count of ms) > 0 then exit repeat
            end repeat
          end if
          if (count of ms) = 0 then error "Mail d'origine introuvable" number 4401
          set r to reply (item 1 of ms) with opening window
          set sender of r to "\(echapper("\(Gmail.nomExpediteur) <\(gmail.adresse)>"))"
          delay 1
          set content of r to "\(echapper(texte))"
          activate
        end tell
        end timeout
        """
        _ = try await executer(script)
    }

    static func ouvrir(_ m: MessageMail) {
        let id = m.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? m.id
        if let url = URL(string: "message://%3C\(id)%3E") { NSWorkspace.shared.open(url) }
    }
}
