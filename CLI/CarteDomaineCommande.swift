// `pilote carte-domaine` et l'outil MCP carte_domaine : une session pose, déplace ou retire une carte de l'écran unique,
// seulement pour ce qui ne se lit nulle part (à corriger, pas pu faire, à faire). Règles dans Shared/Domaines.swift.
import Foundation

enum CarteDomaineCommande {
    static let aide = """
      pilote carte-domaine [liste]          les cartes à l'écran, par domaine et par case
      pilote carte-domaine poser --domaine app|reseaux|ventes|freelance|papiers --case a_faire|en_cours|pas_pu_faire|prepare|fait
                                            --texte "…" [--pourquoi "…"] [--lien CHEMIN] [--id ID pour remplacer]
                                            [--attend toi|PILOTE|<agent>|"l'académie"] [--rappel ID|"titre exact"]
                                            120 caractères au plus ; « pourquoi » obligatoire pour pas_pu_faire ; plafond par case ;
                                            « attend » obligatoire pour une carte qui entre en prepare ; « attend toi » avec --rappel
      pilote carte-domaine deplacer <id> --case fait [--pourquoi "…"] [--attend …] [--rappel …]
      pilote carte-domaine retirer <id>     chaque mouvement s'écrit au journal ; une carte « fait » sort après 7 jours
    """

    /// La session qui écrit (retrouvée par le processus parent, comme note-journal) : auteur et champs du journal.
    static func identite(_ auteur: String?) -> (String, [String: Any]) {
        var champs: [String: Any] = [:]
        var nom = auteur ?? ""
        if let qui = Sessions.identite(pid: getppid()) {
            champs["session"] = qui.session
            champs["session_app"] = qui.sessionApp
            champs["titre_session"] = qui.titre
            champs["dossier"] = qui.dossier
            if nom.isEmpty { nom = qui.titre }
        }
        return (nom.isEmpty ? "session" : nom, champs)
    }

    static func executer(_ stock: Stockage, action: String, id: String?, domaine: String?, etat: String?, texte: String?,
                         pourquoi: String?, lien: String?, attend: String? = nil, rappel: String? = nil, auteur: String?) throws -> Encodable {
        let (qui, journal) = identite(auteur)
        switch action {
        case "", "liste", "lister":
            return try stock.cartesDomaine()
        case "poser":
            guard let d = domaine.flatMap(Domaine.depuis) else {
                throw RefusCarte(description: "Domaine attendu : app, reseaux, ventes, freelance ou papiers.")
            }
            guard let c = etat.flatMap(CaseDomaine.depuis) else {
                throw RefusCarte(description: "Case attendue : a_faire, en_cours, pas_pu_faire, prepare ou fait.")
            }
            if let id, let avant = try stock.carteDomaine(id) {
                return try stock.poserCarte(id: avant.id, domaine: d, etat: c, texte: texte ?? avant.texte,
                                            pourquoi: pourquoi ?? avant.pourquoi, lien: lien ?? avant.lien,
                                            attend: attend, rappel: rappel, auteur: qui, journal: journal)
            }
            return try stock.poserCarte(id: id, domaine: d, etat: c, texte: texte ?? "", pourquoi: pourquoi ?? "", lien: lien ?? "",
                                        attend: attend, rappel: rappel, auteur: qui, journal: journal)
        case "deplacer":
            guard let id else { throw RefusCarte(description: "Id de la carte attendu.") }
            guard let c = etat.flatMap(CaseDomaine.depuis) else { throw RefusCarte(description: "Case attendue.") }
            return try stock.deplacerCarte(id: id, vers: c, pourquoi: pourquoi, attend: attend, rappel: rappel, auteur: qui, journal: journal)
        case "retirer":
            guard let id else { throw RefusCarte(description: "Id de la carte attendu.") }
            return try stock.retirerCarte(id: id, auteur: qui, journal: journal)
        default:
            throw RefusCarte(description: "Action inconnue : \(action) (liste, poser, deplacer, retirer).")
        }
    }

    /// Ligne de commande : pilote carte-domaine <action> [id] --domaine … --case … --texte … --pourquoi … --lien …
    static func lancer(_ stock: Stockage, _ args: [String]) {
        let action = args.count > 1 && !args[1].hasPrefix("--") ? args[1] : "liste"
        let id = args.count > 2 && !args[2].hasPrefix("--") ? args[2] : option("--id", args)
        do {
            sortir(try executer(stock, action: action, id: id, domaine: option("--domaine", args), etat: option("--case", args),
                                texte: option("--texte", args), pourquoi: option("--pourquoi", args), lien: option("--lien", args),
                                attend: option("--attend", args), rappel: option("--rappel", args), auteur: option("--par", args)))
        } catch {
            echouer("\(error)")
        }
    }

    static let outilMCP: [String: Any] = [
        "name": "carte_domaine",
        "description": "Écran unique de Pilote : pose, déplace ou retire une carte d'un domaine (app, reseaux, ventes, freelance, papiers), "
            + "SEULEMENT pour ce qui ne se lit nulle part (à corriger, pas pu faire, à faire). Messages, publications, commits et "
            + "sessions se lisent déjà seuls. Texte de 120 caractères au plus, sans tiret long ; « pourquoi » obligatoire pour "
            + "pas_pu_faire (et ce qu'il faut) ; plafond par case (fait 8, en_cours 3, pas_pu_faire 5, prepare 5, a_faire 7) : au-delà, "
            + "remplacer une carte (même id) ou en retirer une. Chaque mouvement va au journal ; une carte « fait » sort après 7 jours. "
            + "« attend » dit qui agit ensuite, hors de toi : « toi » (\(Moi.tiers), avec « rappel » = le rappel à son nom, qui fait sa ligne "
            + "dans À toi), « PILOTE », un tiers (« l'académie ») ; ton propre nom pour un « prepare » que tu fais partir toi-même. "
            + "Obligatoire pour une carte qui entre en prepare. Une carte qui attend un tiers n'est pas un problème : en_cours + attend.",
        "inputSchema": ["type": "object", "properties": [
            "action": ["type": "string", "enum": ["liste", "poser", "deplacer", "retirer"]],
            "id": ["type": "string", "description": "La carte à remplacer, déplacer ou retirer (les 8 premiers caractères suffisent)."],
            "domaine": ["type": "string", "enum": Domaine.allCases.map(\.rawValue)],
            "case": ["type": "string", "enum": CaseDomaine.allCases.map(\.rawValue)],
            "texte": ["type": "string", "description": "Verbe + chose, 120 caractères au plus."],
            "pourquoi": ["type": "string", "description": "Pour pas_pu_faire : pourquoi, et ce qu'il faut."],
            "lien": ["type": "string", "description": "Chemin complet d'un fichier (facultatif)."],
            "attend": ["type": "string", "description": "Qui agit ensuite : toi (\(Moi.tiers)), PILOTE, ton nom, ou un tiers (« l'académie ») ; « personne » pour effacer."],
            "rappel": ["type": "string", "description": "Avec attend toi : le rappel de \(Moi.tiers) qui porte son geste (identifiant ou titre exact)."]],
            "required": ["action"]],
    ]

    static func appelerMCP(_ stock: Stockage, _ a: [String: Any]) throws -> Encodable {
        do {
            return try executer(stock, action: a["action"] as? String ?? "liste", id: a["id"] as? String, domaine: a["domaine"] as? String,
                                etat: a["case"] as? String, texte: a["texte"] as? String, pourquoi: a["pourquoi"] as? String,
                                lien: a["lien"] as? String, attend: a["attend"] as? String, rappel: a["rappel"] as? String,
                                auteur: a["par"] as? String)
        } catch let e as RefusCarte { throw ErreurBase(description: e.description) }
    }
}
