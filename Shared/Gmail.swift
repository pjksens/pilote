// Envoi par le serveur d'envoi de Gmail (SMTP), avec un mot de passe d'application que Sacha crée et colle lui-même.
// Le mot de passe reste dans le trousseau du Mac. Texte brut, sans signature ajoutée, sans brouillon, réponses dans le fil.
// Jamais depuis le domaine kryva.fr (réputation abîmée, décision du 16/10) : refusé ici même, pour l'app comme pour l'outil.
// 05/11 (étape 1 de PILOTE, envoi sur « envoie ») : sorti de l'app vers Shared/ pour que `pilote envoie` envoie avec
// EXACTEMENT le même code que le bouton « Envoyer depuis Gmail » (composition du mail, curl, en-têtes de fil).
import Foundation
import Security

enum Gmail {
    private static let service = "io.github.pjksens.pilote.gmail"
    /// Nom affiché de l'expéditeur : PILOTE_NOM, sinon le nom complet du compte macOS.
    static let nomExpediteur = ProcessInfo.processInfo.environment["PILOTE_NOM"] ?? NSFullUserName()
    private static let cleAdresse = "gmail.adresse"
    /// L'adresse est rangée dans les réglages de l'APP (io.github.pjksens.pilote) : l'outil `pilote` les lit au même endroit.
    private static let domaineApp = Identite.app

    enum ErreurGmail: LocalizedError {
        case nonConnecte, refuse, depuisKryva(String), autorisationTrousseau, echec(String)
        var errorDescription: String? {
            switch self {
            case .nonConnecte: return L("Gmail n'est pas encore connecté à Pilote.")
            case .refuse: return L("Gmail a refusé le mot de passe d'application. Créez-en un nouveau et reconnectez Gmail.")
            case .depuisKryva(let a): return L("Envoi refusé : l'expéditeur \(a) est dans un domaine interdit (reglages.json, domaines_interdits).")
            case .autorisationTrousseau:
                return L("Le trousseau du Mac demande une autorisation pour l'outil pilote : sur le Mac, lancer une fois « \(Identite.depot.path)/pilote gmail-acces » et cliquer « Toujours autoriser ». Rien n'est parti.")
            case .echec(let m): return L("Gmail n'a pas accepté l'envoi (\(m)).")
            }
        }
    }

    private static var reglages: UserDefaults {
        Bundle.main.bundleIdentifier == domaineApp ? .standard : (UserDefaults(suiteName: domaineApp) ?? .standard)
    }

    static var adresse: String? { reglages.string(forKey: cleAdresse) }
    static var connecte: Bool { adresse.map { motDePasse($0) != nil } ?? false }

    // MARK: Trousseau

    static func motDePasse(_ adresse: String) -> String? {
        if case .present(let m) = lireMotDePasse(adresse, interactif: true) { return m }
        return nil
    }

    enum LectureMotDePasse: Equatable { case present(String), absent, autorisationRequise, erreur(Int32) }

    /// `interactif: false` (outil lancé depuis l'iPhone) : jamais de fenêtre du trousseau sur le Mac. Si macOS en demande une
    /// (l'élément a été créé par l'app, l'outil n'est pas encore autorisé), la lecture échoue tout de suite (`autorisationRequise`).
    static func lireMotDePasse(_ adresse: String, interactif: Bool) -> LectureMotDePasse {
        var requete: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                      kSecAttrAccount as String: adresse, kSecReturnData as String: true]
        if !interactif {
            requete[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            // Trousseau « login » (fichier) : c'est ce réglage qui coupe la fenêtre « pilote veut utiliser… » (API ancienne, sans remplaçant).
            SecKeychainSetUserInteractionAllowed(false)
        }
        defer { if !interactif { SecKeychainSetUserInteractionAllowed(true) } }
        var resultat: AnyObject?
        let statut = SecItemCopyMatching(requete as CFDictionary, &resultat)
        switch statut {
        case errSecSuccess:
            guard let data = resultat as? Data, let m = String(data: data, encoding: .utf8) else { return .erreur(statut) }
            return .present(m)
        case errSecItemNotFound: return .absent
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .autorisationRequise
        default: return .erreur(statut)
        }
    }

    /// Le mot de passe est-il rangé ? Lecture des attributs seulement (jamais le secret) : aucune fenêtre du trousseau.
    static func motDePassePresent(_ adresse: String) -> Bool {
        let requete: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                      kSecAttrAccount as String: adresse, kSecReturnAttributes as String: true,
                                      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        var resultat: AnyObject?
        return SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess
    }

    /// Vérifie le mot de passe auprès de Gmail (connexion seule, aucun mail), puis le range dans le trousseau.
    static func connecter(adresse: String, motDePasse brut: String) async throws {
        let mdp = brut.replacingOccurrences(of: " ", with: "")
        try await Task.detached { try verifier(adresse: adresse, motDePasse: mdp) }.value
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: adresse]
        SecItemDelete(base as CFDictionary)
        var ajout = base
        ajout[kSecValueData as String] = Data(mdp.utf8)
        guard SecItemAdd(ajout as CFDictionary, nil) == errSecSuccess else { throw ErreurGmail.echec("trousseau") }
        reglages.set(adresse, forKey: cleAdresse)
    }

    /// Connexion seule au serveur Gmail : le mot de passe est-il accepté ? Aucun mail, rien n'est rangé ni changé.
    static func verifier(adresse: String, motDePasse: String) throws {
        try curl(["--url", "smtps://smtp.gmail.com:465"], adresse: adresse, motDePasse: motDePasse)
    }

    static func deconnecter() {
        if let a = adresse {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                           kSecAttrAccount as String: a] as CFDictionary)
        }
        reglages.removeObject(forKey: cleAdresse)
    }

    // MARK: Composition (pure : testée, et montrée telle quelle par `pilote envoie --essai`)

    static func nouveauMessageId() -> String { "\(UUID().uuidString.lowercased())@pilote.mac" }

    static func dateEnTete(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: d)
    }

    /// In-Reply-To et References : le mail part dans le fil de `reponseA` (Message-ID, avec ou sans « < > »).
    static func entetesDeFil(_ reponseA: String) -> [String] {
        guard !reponseA.isEmpty else { return [] }
        let id = reponseA.hasPrefix("<") ? reponseA : "<\(reponseA)>"
        return ["In-Reply-To: \(id)", "References: \(id)"]
    }

    /// Les en-têtes en clair (objet et nom non encodés) : ce que l'essai montre.
    static func entetesLisibles(de: String, a: String, objet: String, reponseA: String) -> [String] {
        ["From: \(nomExpediteur) <\(de)>", "To: <\(a)>", "Subject: \(objet)"] + entetesDeFil(reponseA)
    }

    /// Le mail complet tel qu'il part chez Gmail : en-têtes, puis le texte brut en base64 (UTF-8, fins de ligne CRLF).
    static func composer(de adresse: String, a destinataire: String, objet: String, texte: String, reponseA: String,
                         messageId: String, date: Date = Date()) -> String {
        func entete(_ s: String) -> String { "=?UTF-8?B?\(Data(s.utf8).base64EncodedString())?=" }
        var lignes = [
            "From: \(entete(nomExpediteur)) <\(adresse)>",
            "To: <\(destinataire)>",
            "Subject: \(entete(objet))",
            "Date: \(dateEnTete(date))",
            "Message-ID: <\(messageId)>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
        ]
        lignes += entetesDeFil(reponseA)
        let corps = Data(texte.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n").utf8)
            .base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return lignes.joined(separator: "\r\n") + "\r\n\r\n" + corps + "\r\n"
    }

    // MARK: Envoi

    /// Envoie un mail en texte brut (app : bouton « Envoyer depuis Gmail »). Renvoie son Message-ID.
    static func envoyer(a destinataire: String, objet: String, texte: String, reponseA: String = "") async throws -> String {
        if Demo.actif { throw Demo.Refus() }
        guard let adresse, let mdp = motDePasse(adresse) else { throw ErreurGmail.nonConnecte }
        return try await Task.detached {
            try envoyerMaintenant(de: adresse, motDePasse: mdp, a: destinataire, objet: objet, texte: texte, reponseA: reponseA)
        }.value
    }

    /// Le même envoi, synchrone (outil `pilote envoie`), mot de passe lu sans fenêtre du trousseau.
    static func envoyerSansFenetre(a destinataire: String, objet: String, texte: String, reponseA: String) throws -> String {
        guard let adresse else { throw ErreurGmail.nonConnecte }
        switch lireMotDePasse(adresse, interactif: false) {
        case .present(let mdp):
            return try envoyerMaintenant(de: adresse, motDePasse: mdp, a: destinataire, objet: objet, texte: texte, reponseA: reponseA)
        case .absent: throw ErreurGmail.nonConnecte
        case .autorisationRequise: throw ErreurGmail.autorisationTrousseau
        case .erreur(let s): throw ErreurGmail.echec("trousseau, code \(s)")
        }
    }

    /// Le cœur commun : compose, écrit le mail dans un fichier temporaire (0600), le passe à curl, l'efface. Renvoie le Message-ID.
    static func envoyerMaintenant(de adresse: String, motDePasse mdp: String, a destinataire: String, objet: String,
                                  texte: String, reponseA: String) throws -> String {
        if Demo.actif { throw Demo.Refus() }
        if EnvoisKryva.estInterdit(adresse) { throw ErreurGmail.depuisKryva(adresse) }
        let messageId = nouveauMessageId()
        let mail = composer(de: adresse, a: destinataire, objet: objet, texte: texte, reponseA: reponseA, messageId: messageId)
        let fichier = Base.dossier.appendingPathComponent("envoi-\(UUID().uuidString).eml")
        try Data(mail.utf8).write(to: fichier, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fichier.path)
        defer { try? FileManager.default.removeItem(at: fichier) }
        try curl(["--url", "smtps://smtp.gmail.com:465", "--mail-from", adresse, "--mail-rcpt", destinataire,
                  "--upload-file", fichier.path], adresse: adresse, motDePasse: mdp)
        return messageId
    }

    /// curl parle au serveur Gmail. Les identifiants passent par l'entrée standard, jamais sur la ligne de commande.
    private static func curl(_ arguments: [String], adresse: String, motDePasse: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["--silent", "--show-error", "--ssl-reqd", "--connect-timeout", "15", "--max-time", "60", "-K", "-"] + arguments
        let entree = Pipe(), erreur = Pipe()
        p.standardInput = entree
        p.standardOutput = Pipe()
        p.standardError = erreur
        try p.run()
        let echappe = motDePasse.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        entree.fileHandleForWriting.write(Data("user = \"\(adresse):\(echappe)\"\n".utf8))
        try? entree.fileHandleForWriting.close()
        let message = String(data: erreur.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        switch p.terminationStatus {
        case 0: return
        case 67: throw ErreurGmail.refuse
        default: throw ErreurGmail.echec(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "code \(p.terminationStatus)" : message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
