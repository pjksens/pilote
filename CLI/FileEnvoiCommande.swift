// pilote file-envoi : la file d'envoi des mails validés (voir Shared/FileEnvoi.swift).
// --passe est lancé toutes les 30 s par l'agent launchd io.github.pjksens.pilote.file-envoi ; la mise en file se fait au clic
// de Sacha dans l'app (« Envoyer les mails validés ») : l'outil ne met en file lui-même que sur une copie de la base (essais).
import Foundation

enum FileEnvoiCommande {
    struct CandidatAffiche: Encodable {
        let id: String, contact: String, a: String, objet: String, jour: String, coche: Bool, refus: [String]
    }

    static func lancer(_ stock: Stockage, _ args: [String]) throws {
        let env = ProcessInfo.processInfo.environment
        let copie = FileEnvoi.surCopie(env)
        let outils = try OutilsEnvoi.selonEnvironnement(env)
        let faux = env["PILOTE_ENVOI_FAUX"] != nil
        // Réglages d'essai : refusés sur la vraie base.
        var intervalle = FileEnvoi.intervalle
        if let s = env["PILOTE_FILE_INTERVALLE"] {
            guard copie, let v = TimeInterval(s), v >= 1 else { echouer("PILOTE_FILE_INTERVALLE : seulement sur une copie de la base (PILOTE_BASE), en secondes.") }
            intervalle = v
        }
        let destinataireEssai = env["PILOTE_ESSAI_DESTINATAIRE"]?.trimmingCharacters(in: .whitespaces).lowercased()
        if destinataireEssai != nil && !copie { echouer("PILOTE_ESSAI_DESTINATAIRE : seulement sur une copie de la base (PILOTE_BASE).") }
        // Sur une copie avec un vrai envoi Gmail, une seule adresse est permise (jamais un vrai contact depuis une copie).
        if copie && !faux && (destinataireEssai ?? "").isEmpty && (args.contains("--passe") || args.contains("--mettre")) {
            echouer("Copie de la base avec envoi réel : PILOTE_ESSAI_DESTINATAIRE=<adresse> obligatoire (seule adresse permise).")
        }
        let garde: ((String) -> String?)? = destinataireEssai.flatMap { d in
            d.isEmpty ? nil : { a in a.lowercased() == d ? nil : "essai : seule l'adresse \(d) est permise (pas \(a))" }
        }

        if args.contains("--acces") {
            // Ce que l'agent verra : le mot de passe Gmail lu sans fenêtre (aucune connexion à Gmail, aucun mail).
            if faux { sortir(["ok": "true", "detail": "essai (PILOTE_ENVOI_FAUX) : pas de trousseau"]); return }
            guard let adresse = Gmail.adresse, !adresse.isEmpty else { echouer("Gmail n'est pas connecté à Pilote : « Connecter Gmail » dans l'app.") }
            switch Gmail.lireMotDePasse(adresse, interactif: false) {
            case .present: sortir(["ok": "true", "adresse": adresse])
            case .absent: echouer("Aucun mot de passe d'application rangé pour \(adresse) : « Connecter Gmail » dans l'app.")
            case .autorisationRequise:
                echouer("L'envoi automatique n'a pas le droit de lire le mot de passe Gmail : dans le Terminal, lancer \(Identite.depot.path)/pilote gmail-acces puis cliquer « Toujours autoriser ».")
            case .erreur(let code): echouer("Trousseau illisible (code \(code)).")
            }
            return
        }
        if args.contains("--passe") {
            // Une passe à la fois (launchd ne relance pas une passe en cours, mais l'outil peut aussi être lancé à la main).
            let chemin = FileEnvoi.dossierDeLaBase.appendingPathComponent("file-envoi.verrou").path
            let fd = open(chemin, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else { echouer("Verrou illisible : \(chemin)") }
            defer { close(fd) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { sortir(["suite": "une autre passe tourne"]); return }
            // Rien en file : on sort sans toucher au trousseau ni à Gmail (cas de presque toutes les passes).
            if try FileEnvoi.actifs(stock).isEmpty && !args.contains("--toujours") { return }
            let bilan = try FileEnvoi.passe(stock, outils: outils, intervalle: intervalle, garde: garde,
                                            alerter: { FileEnvoi.publier($0, essai: copie) })
            sortir(bilan)
            return
        }
        if args.contains("--arreter") {
            let n = try FileEnvoi.arreter(stock, raison: "file arrêtée à la main (pilote file-envoi --arreter)")
            sortir(["annules": "\(n)"])
            return
        }
        if args.contains("--candidats") {
            sortir(try FileEnvoi.candidats(stock, outils: outils).map {
                CandidatAffiche(id: $0.id, contact: EnvoiPilote.nomContact($0.contact), a: $0.contact.email, objet: $0.evenement.objet,
                                jour: $0.jour, coche: $0.cocheParDefaut, refus: $0.refus)
            })
            return
        }
        if let i = args.firstIndex(of: "--mettre") {
            guard copie else {
                echouer("Mise en file par l'outil refusée sur la vraie base : \(Moi.tiers) clique « Envoyer les mails validés » dans l'app.")
            }
            let ids = args[(i + 1)...].prefix { !$0.hasPrefix("--") }.map { $0 }
            guard !ids.isEmpty else { echouer("Usage : pilote file-envoi --mettre <id> [<id>…]  (copie de la base seulement)") }
            var fils: [String: String] = [:]
            for id in ids {
                if let e = try stock.evenement(id), FileEnvoi.filACherche(e), let c = try stock.contact(e.contactId),
                   let f = try? outils.dernierRecu(c.email.trimmingCharacters(in: .whitespaces), e.objet), !f.isEmpty { fils[id] = f }
            }
            sortir(try FileEnvoi.mettreEnFile(stock, ids: ids, fils: fils, outils: outils, intervalle: intervalle))
            return
        }
        sortir(try FileEnvoi.duJour(stock))
    }
}
