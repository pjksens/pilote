// Quels messages de l'Envelope Index de Mail comptent comme « arrivés dans la boîte de réception » (04/11, bug du mail de Julien).
//
// Constat vérifié : pour un compte Gmail, Mail range parfois le message dans « [Gmail]/Tous les messages » (colonne
// messages.mailbox) et ne garde la boîte de réception que comme ÉTIQUETTE (table labels : message_id, mailbox_id).
// Le capteur ne regardait que messages.mailbox = …/INBOX : ces mails-là (ex. la réponse de julien.morel@client-exemple.fr,
// 04/11 à 17:21, mail:198500) n'arrivaient jamais dans entrants.jsonl.

import Foundation

enum MailBoiteReception {
    /// Condition SQL (alias : m = messages, mb = la boîte de m.mailbox). `avecEtiquettes` : la table labels existe dans l'index.
    static func condition(avecEtiquettes: Bool) -> String {
        // 05/11 (T13) : les dossiers Indésirables (iCloud/OVH « INBOX/Junk », Gmail « [Gmail]/Spam ») sont lus aussi ; le tri ne garde
        // une de leurs lignes que pour un contact connu ou une plateforme suivie (estIndesirable, TriMail.garderIndesirable).
        let directe = "(lower(mb.url) LIKE '%/inbox' OR lower(mb.url) LIKE '%/junk' OR lower(mb.url) LIKE '%/spam')"
        guard avecEtiquettes else { return directe }
        return "(\(directe) OR EXISTS (SELECT 1 FROM labels l JOIN mailboxes lb ON lb.ROWID = l.mailbox_id "
            + "WHERE l.message_id = m.ROWID AND lower(lb.url) LIKE '%/inbox'))"
    }

    /// URL de boîte Mail d'un dossier Indésirables / Spam (« …/INBOX/Junk », « …/%5BGmail%5D/Spam »).
    static func estIndesirable(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.hasSuffix("/junk") || u.hasSuffix("/spam")
    }

    /// Rattrapage : à chaque passe, le capteur relit aussi les mails des dernières heures déjà derrière son curseur, au cas où
    /// l'étiquette de boîte de réception arrive après la ligne du message. Fenêtre en secondes.
    static let fenetreRattrapage: TimeInterval = 6 * 3600

    /// Un message neuf (derrière rien) se traite toujours. Un message déjà derrière le curseur (relu par le rattrapage) ne se
    /// reprend que s'il est de travail ou inconnu et n'a pas déjà été émis : jamais de doublon, jamais de recomptage perso/ignoré.
    static func aTraiter(rowid: Int, curseur: Int, classe: String, dejaEmis: Bool) -> Bool {
        if rowid > curseur { return true }
        return !dejaEmis && (classe == "travail" || classe == "inconnu")
    }
}
