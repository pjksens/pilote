// L'écran unique (docs/ECRAN-UNIQUE.md, 09/11) : le travail de Sacha rangé par domaine. On lit d'abord le vrai (base Pilote,
// publications, dépôt suivi en lecture seule, sessions, Rappels) ; les sessions ne déclarent par une carte que ce qui ne se
// lit nulle part (à corriger, pas pu faire, à faire). Le regroupement est pur : il se teste sans base ni réseau.
import Foundation

// MARK: - Le vocabulaire

enum Domaine: String, CaseIterable, Codable, Identifiable {
    // 09/11 : PILOTE a sa ligne (Sacha veut voir tout le travail d'agent, les rappels « pour PILOTE » compris).
    case app, reseaux, ventes, freelance, papiers, pilote
    var id: String { rawValue }

    var titre: String {
        switch self {
        case .app: return L("App KRYVA")
        case .reseaux: return L("Réseaux")
        case .ventes: return L("Ventes KRYVA")
        case .freelance: return "Freelance"
        case .papiers: return L("Papiers")
        case .pilote: return "Pilote"
        }
    }

    /// L'agent qui tient le domaine : son nom d'équipe (EQUIPE.md, celui du Facteur) et son nom court à l'écran.
    var equipe: String {
        switch self {
        case .app: return "KRYVA · App et interface"
        case .reseaux: return "KRYVA · Réseaux, image, événements"
        case .ventes: return "KRYVA · Ventes"
        case .freelance: return "FREELANCE"
        case .papiers: return "KRYVA · Papiers et admin"
        case .pilote: return "PILOTE"
        }
    }
    var agent: String {
        switch self {
        case .app: return "App"
        case .reseaux: return L("Réseaux")
        case .ventes: return L("Ventes")
        case .freelance: return "FREELANCE"
        case .papiers: return L("Papiers")
        case .pilote: return "PILOTE"
        }
    }
    /// Le nom court en français, quelle que soit la langue de l'écran : ce qu'on écrit aux agents (consignes, relances), qui
    /// travaillent en français.
    var agentFrancais: String {
        switch self {
        case .app: return "App"
        case .reseaux: return "Réseaux"
        case .ventes: return "Ventes"
        case .freelance: return "FREELANCE"
        case .papiers: return "Papiers"
        case .pilote: return "PILOTE"
        }
    }

    /// Le mot de la pastille rouge (à faire ou bloqué), propre au domaine.
    var motRouge: String {
        switch self {
        case .app: return L("à corriger")
        case .reseaux: return L("à préparer")
        case .ventes, .freelance: return L("en retard")
        case .papiers, .pilote: return L("à faire")
        }
    }

    static func depuis(_ texte: String) -> Domaine? {
        let t = texte.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespaces)
        if let d = Domaine(rawValue: t) { return d }
        switch t {
        case "app kryva", "kryva app": return .app
        case "ventes kryva": return .ventes
        default: return nil
        }
    }

    /// Le domaine d'une session : son titre d'abord (les sessions de domaine d'EQUIPE.md), puis son dossier.
    static func deSession(titre: String, dossier: String) -> Domaine? {
        let t = titre.lowercased()
        if t.contains("app et interface") { return .app }
        if t.contains("réseaux") || t.contains("reseaux") { return .reseaux }
        if t.contains("ventes") { return .ventes }
        if t.contains("freelance") { return .freelance }
        if t.contains("papiers") { return .papiers }
        if t.contains("pilote") { return .pilote }
        let d = dossier
        if d.contains("/Projects/freelance") || d.contains("/sachapraljak") { return .freelance }
        if d.contains("/reseaux-stats") || d.contains("/kryva-launch") || d.contains("/kryva-videos") { return .reseaux }
        if d.contains("/Documents/kryva") { return .papiers }
        if d.contains("/acquisition-plan") { return .ventes }
        if let depot = Reglages.courants.depot?.path, d == depot || d.hasPrefix(depot + "/") { return .app }
        if d.contains("/Projects/pilote") { return .pilote }
        return nil
    }
}

enum CaseDomaine: String, CaseIterable, Codable, Identifiable {
    case fait
    case enCours = "en_cours"
    case pasPuFaire = "pas_pu_faire"
    case prepare
    case aFaire = "a_faire"
    var id: String { rawValue }

    var titre: String {
        switch self {
        case .fait: return L("Fait")
        case .enCours: return L("En cours")
        case .pasPuFaire: return L("Pas pu faire")
        case .prepare: return L("Préparé")
        case .aFaire: return L("À faire")
        }
    }

    /// Cartes déclarées au plus, par domaine et par case : l'outil refuse au-delà (une carte se remplace).
    var plafond: Int {
        switch self {
        case .fait: return 8
        case .enCours: return 3
        case .pasPuFaire: return 5
        case .prepare: return 5
        case .aFaire: return 7
        }
    }

    static func depuis(_ texte: String) -> CaseDomaine? {
        let t = texte.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        switch t {
        case "fait": return .fait
        case "en_cours", "encours": return .enCours
        case "pas_pu_faire", "paspufaire", "bloque": return .pasPuFaire
        case "prepare": return .prepare
        case "a_faire", "afaire", "a_corriger", "a_preparer": return .aFaire
        default: return nil
        }
    }
}

/// Vert : fait ou en ligne. Ambre : prêt ou en attente. Rouge : à faire ou bloqué. Gris : rien de neuf.
enum TonStatut: String, Codable { case vert, ambre, rouge, gris }

struct PastilleStatut: Hashable, Codable {
    var texte: String
    var ton: TonStatut
    /// Le geste de Sacha qui débloque, s'il est dans « À toi » (id du geste) : la pastille y renvoie.
    var geste: String? = nil
}

/// Une ligne dépliée d'un domaine.
struct ElementDomaine: Identifiable, Hashable, Codable {
    var id: String
    var titre: String
    var detail: String = ""
    var quand: Date? = nil
    var lien: String = ""
    var contactId: String? = nil
    var carteId: String? = nil
    var ton: TonStatut = .gris
    /// Travail d'un agent : son nom d'équipe (bouton « Écrire à … », le texte part par le Facteur).
    var agent: String = ""
    /// Un geste de Sacha (09/11) : la ligne va dans « Pour toi » ; `geste` est l'id de sa ligne dans « À toi » quand elle y est.
    var pourToi = false
    var geste: String? = nil
    /// Des mots en plus pour reconnaître la même chose dite ailleurs (le nom de branche d'un commit).
    var cle = ""
    /// 09/11 (Organisation) : qui cette chose attend, hors de l'agent (« PILOTE », « l'académie ») ; vide sinon.
    var attend = ""
    /// Une personne (Ventes, Freelance) : le geste écrit de Sacha, sa date comprise (« Visio avec Arthur (mar. 10/11) »), sans
    /// « Pour toi : ». Un champ à part : la pastille le reprend sans relire le texte affiché, qui se traduit.
    var gesteTexte: String? = nil
}

/// Ce qui fera partir une chose prête (section « Prêt, … ») : une valeur, pas un texte relu, car le titre se traduit.
enum SuitePret: Hashable, Codable {
    case aucune, attendPush, fusionner, partALHeure, envoyerLeJour
    case preciser(String)      // l'agent qui doit préciser la suite
    case fairePartir(String)   // l'agent qui fait partir la chose
    case attend(String)        // qui elle attend

    /// « attend ton push » ; au pluriel (« 3 prêts, attendent ton push ») seuls les verbes s'accordent.
    func texte(pluriel: Bool = false) -> String {
        switch self {
        case .aucune: return ""
        case .attendPush: return pluriel ? L("attendent ton push") : L("attend ton push")
        case .fusionner: return L("à fusionner par \(Domaine.app.agent)")
        case .partALHeure: return pluriel ? L("partent à l'heure prévue") : L("part à l'heure prévue")
        case .envoyerLeJour: return L("à envoyer le jour prévu")
        case .preciser(let agent): return L("suite à préciser par \(agent)")
        case .fairePartir(let agent): return L("à faire partir par \(agent)")
        case .attend(let qui): return pluriel ? L("attendent \(qui)") : L("attend \(qui)")
        }
    }

    /// Le titre de la section : « Prêt, attend ton push ».
    var titre: String { self == .aucune ? L("Prêt") : L("Prêt") + ", " + texte() }

    /// La pastille du bilan : « 1 prêt, attend ton push », « 3 prêts, attendent ton push ».
    func pastille(n: Int) -> String {
        let nombre = n == 1 ? L("1 prêt") : L("\(n) prêts")
        return self == .aucune ? nombre : nombre + ", " + texte(pluriel: n > 1)
    }
}

/// Une section du domaine déplié (09/11) : les mêmes mots et les mêmes nombres que la ligne fermée.
struct SectionDomaine: Identifiable, Hashable, Codable {
    var titre: String
    var elements: [ElementDomaine]
    var ton: TonStatut = .gris
    /// Renseigné pour une section « Prêt… » (le bilan la reconnaît par là, pas par son titre).
    var pret: SuitePret? = nil
    var id: String { titre }
}

struct EtatDomaine: Identifiable, Hashable, Codable {
    var domaine: Domaine
    var id: Domaine { domaine }
    var cases: [CaseDomaine: [ElementDomaine]] = [:]
    /// Seulement ce qui demande attention (en retard, réponse reçue, pas en ligne, en échec) ; rien à signaler = aucune.
    var pastilles: [PastilleStatut] = []
    /// Ce qui avance sans Sacha, en une phrase (« 15 messages prêts, dès le mar. 10/11 ») ; vide sinon.
    var resume = ""
    /// Rien à faire, rien d'en cours, rien de bloqué ni de préparé, et rien de fait depuis 24 h : la ligne reste grise.
    var rienDeNeuf = true
    /// Une source illisible (dépôt suivi, Rappels) : dit, jamais confondu avec « rien ».
    var erreur: String? = nil
    /// Qui tient le domaine et ce qu'il fait en ce moment (« App au travail : … », « Ventes en pause depuis 2 h »).
    var qui = ""
    var quiTon: TonStatut = .gris
    /// Le texte pré-rempli du bouton « Relancer X » (09/11, Organisation) : seulement quand du travail attend (réponse reçue,
    /// problème) et que l'agent ne travaille pas ; nil sinon.
    var relance: String? = nil
    /// Le texte du bouton « Relancer PILOTE » : une carte du domaine attend PILOTE ; nil sinon.
    var relancePilote: String? = nil
    /// Le travail des agents en une ligne, section par section (« 1 problème · 13 à faire par App, dont 2 d'ici 18 h · 3 prêts
    /// · 5 faits aujourd'hui ») : chaque nombre est celui de la section du même nom, une fois déplié.
    var bilan: [PastilleStatut] = []
    var bilanTexte: String { bilan.map(\.texte).joined(separator: " · ") }
    /// Le domaine déplié : Problème, Pour toi, En cours, À faire par X, Prêt, Fait aujourd'hui, Fait ces 7 derniers jours.
    var sections: [SectionDomaine] = []

    func elements(_ c: CaseDomaine) -> [ElementDomaine] { cases[c] ?? [] }
    var total: Int { cases.values.reduce(0) { $0 + $1.count } }
}

// MARK: - Les sources (structures simples, remplies par l'app ou par les tests)

/// Une carte déclarée par une session (outil carte_domaine, commande pilote carte-domaine).
struct CarteDomaine: Identifiable, Hashable, Codable {
    var id: String
    var domaine: Domaine
    var etat: CaseDomaine
    var texte: String
    var pourquoi: String = ""
    var lien: String = ""
    var auteur: String = ""
    var creeLe: String = ""
    var majLe: String = ""
    /// 09/11 (Organisation) : qui la carte attend : « Sacha », « PILOTE », l'agent lui-même ou un tiers (« l'académie ») ;
    /// vide = personne d'autre que l'agent.
    var attend: String = ""
    /// Quand elle attend Sacha : le rappel à son nom qui porte son geste (identifiant ou titre exact).
    var rappel: String = ""
}

/// Un commit du dépôt suivi : dans origin/main (ref locale) = en ligne ; ailleurs = corrigé, pas en ligne.
struct CommitKryva: Hashable, Codable {
    var hash: String
    var sujet: String
    var le: Date?
    var enLigne: Bool
    var branche: String = "main"
}

/// Une personne suivie, résumée en une ligne : dernier échange, mails partis et à partir, prochaine étape.
struct ResumeContact: Hashable, Codable {
    var id: String
    var nom: String
    var entreprise: String = ""
    var espace: String
    var etape: String = ""
    var prochaineAction: String = ""
    var prochaineDate: String = ""
    var dernierLe: String = ""
    var dernierSens: String = ""
    var dernierCanal: String = ""
    /// Messages sortants envoyés depuis 7 jours.
    var partis = 0
    /// Messages préparés, à valider ou à refaire.
    var aPartir = 0
    /// Envois en échec depuis 7 jours.
    var echecs = 0
    /// Réponses reçues depuis 7 jours.
    var recus = 0
    /// Messages prêts (« prepare » : texte validé, Sacha les envoie le jour dit).
    var prets = 0
    /// Textes qui attendent la validation de Sacha.
    var aValider = 0
    /// Le jour où part le premier message prêt (AAAA-MM-JJ, règle Libelles.jourDuMessage) ; vide = dès aujourd'hui.
    var envoiLe = ""
    /// Ce premier message attend une condition pas encore cochée.
    var envoiSousCondition = false
    /// 10/11 : l'agent a marqué « aucune réponse due » et rien n'est arrivé depuis : la réponse reçue n'est plus à traiter.
    var aucuneReponseDue = false
}

/// Un rappel de la liste Papiers.
struct TacheDomaine: Hashable, Codable {
    var id: String
    var titre: String
    var echeance: Date?
    var faite: Bool
    var faiteLe: Date?
    /// 09/11 (Organisation) : le domaine de l'agent à qui ce rappel de Sacha sert (« Pour : App » dans ses notes ; pour un ❓,
    /// sa liste aussi) ; nil = aucun agent dit.
    var domaine: Domaine? = nil
    /// Une décision ❓ (sa ligne dans À toi est « decision:<id> »).
    var decision = false
}

/// Une session vivante, vue par l'écran : quel domaine, depuis quand, son étape k/n.
struct SessionDomaine: Hashable, Codable {
    var id: String
    var titre: String
    var dossier: String = ""
    var etat: String               // busy | waiting | idle
    var depuis: Date?
    var etape: String = ""
    var k = 0
    var n = 0
    var question: String = ""

    init(id: String, titre: String, dossier: String = "", etat: String, depuis: Date? = nil, etape: String = "",
         k: Int = 0, n: Int = 0, question: String = "") {
        self.id = id; self.titre = titre; self.dossier = dossier; self.etat = etat; self.depuis = depuis
        self.etape = etape; self.k = k; self.n = n; self.question = question
    }

    init(_ a: ActiviteSession) {
        let n = a.plan.count
        let enCours = a.plan.firstIndex { $0.statut == "in_progress" }
        let faites = a.plan.filter { $0.statut == "completed" }.count
        let k = enCours.map { $0 + 1 } ?? min(faites, n)
        let etape = a.etape.isEmpty ? (enCours.map { a.plan[$0].contenu } ?? "") : a.etape
        self.init(id: a.sessionApp.isEmpty ? a.id : a.sessionApp, titre: a.titre, dossier: a.dossier, etat: a.etat,
                  depuis: a.depuis, etape: etape, k: k, n: n, question: a.question)
    }
}

struct SourcesDomaines {
    var maintenant = Date()
    var cartes: [CarteDomaine] = []
    /// nil : le dépôt suivi n'a pas pu être lu.
    var commits: [CommitKryva]? = []
    var publications: [Publication] = []
    var contacts: [ResumeContact] = []
    /// nil : les Rappels ne sont pas accessibles.
    var taches: [TacheDomaine]? = []
    var sessions: [SessionDomaine] = []
    /// La liste Rappels « Agents » (faits depuis 7 jours et à faire).
    var travaux: [TravailAgent] = []
    /// Le rappel de Sacha qui porte son « push » KRYVA (le premier à faire), s'il existe.
    var push: TacheDomaine? = nil
    /// 09/11 : les rappels des listes de Sacha (à faire, et faits depuis 7 jours), pour les cartes qui l'attendent ;
    /// nil : les Rappels ne sont pas accessibles.
    var rappelsSacha: [TacheDomaine]? = []
}

// MARK: - Le regroupement

enum Domaines {
    static let jour: TimeInterval = 86_400

    static func regrouper(_ s: SourcesDomaines) -> [EtatDomaine] {
        Domaine.allCases.map { d in
            var e = EtatDomaine(domaine: d)
            var cases: [CaseDomaine: [ElementDomaine]] = [:]
            switch d {
            case .app: app(s, &cases, &e)
            case .reseaux: reseaux(s, &cases)
            case .ventes: personnes(s, espace: "kryva", &cases)
            case .freelance: personnes(s, espace: "freelance", &cases)
            case .papiers: papiers(s, &cases, &e)
            case .pilote: break
            }
            for c in s.cartes where c.domaine == d && visible(c, maintenant: s.maintenant) {
                let (k, el) = element(c, s)
                cases[k, default: []].append(el)
            }
            // 09/11 (Organisation) : un ❓ ou un rappel de Sacha qui sert l'agent du domaine (« Pour : App ») compte dans
            // « Pour toi » de ce domaine, sauf s'il y est déjà (liste Papiers, ou rappel lié à une carte).
            let lies = Set(s.cartes.filter { $0.domaine == d }.compactMap { rappelLie($0.rappel, s.rappelsSacha ?? [])?.id })
            for r in s.rappelsSacha ?? [] where r.domaine == d && !r.faite && !lies.contains(r.id) {
                let deja = cases.values.contains { $0.contains { $0.id == "rappel:\(r.id)" || $0.geste == "rappel:\(r.id)"
                    || ($0.id == "push" && r.id == s.push?.id) } }
                guard !deja else { continue }
                cases[.aFaire, default: []].append(element(r, d, maintenant: s.maintenant))
            }
            // 09/11 : le travail d'agent (liste « Agents ») : fait, prévu à telle heure, ou en retard (= problème).
            for t in s.travaux where t.domaine == d {
                if let (k, el) = element(t, d, maintenant: s.maintenant) { cases[k, default: []].append(el) }
            }
            // 09/11 : une chose = une ligne (la même correction dite par un commit, une carte et un rappel « Agents »).
            dedoublonner(&cases)
            // L'écran de Sacha dit « tu » partout, sujets de commit compris (« validée par Sacha » → « validée par toi »).
            for k in cases.keys {
                cases[k] = cases[k]?.map {
                    var x = $0
                    x.titre = Libelles.tutoyer(x.titre); x.detail = Libelles.tutoyer(x.detail)
                    x.gesteTexte = x.gesteTexte.map(Libelles.tutoyer)
                    return x
                }
            }
            if var aFaire = cases[.aFaire] {
                aFaire.sort { ($0.quand ?? .distantFuture) < ($1.quand ?? .distantFuture) }
                cases[.aFaire] = aFaire
            }
            if var faits = cases[.fait] {
                // Ce qui demande attention d'abord (une réponse reçue est ambre), puis le plus récent.
                faits.sort { a, b in
                    (a.ton == .ambre) != (b.ton == .ambre) ? a.ton == .ambre : (a.quand ?? .distantPast) > (b.quand ?? .distantPast)
                }
                cases[.fait] = faits
            }
            e.cases = cases.filter { !$0.value.isEmpty }
            e.sections = sections(d, e, maintenant: s.maintenant)
            e.pastilles = pastilles(d, e, s)
            e.resume = resume(d, e, s)
            (e.qui, e.quiTon) = qui(d, s, e)
            e.relance = relance(d, s, e)
            e.relancePilote = relancePilote(d, e, maintenant: s.maintenant)
            e.bilan = bilan(d, e, maintenant: s.maintenant)
            let recent = e.elements(.fait).contains { ($0.quand ?? .distantPast) > s.maintenant.addingTimeInterval(-jour) }
            e.rienDeNeuf = e.erreur == nil && !recent
                && [CaseDomaine.enCours, .pasPuFaire, .prepare, .aFaire].allSatisfy { e.elements($0).isEmpty }
            return e
        }
    }

    /// Une carte « fait » sort de l'écran après 7 jours.
    static func visible(_ c: CarteDomaine, maintenant: Date) -> Bool {
        guard c.etat == .fait else { return true }
        guard let le = Dates.iso.date(from: c.majLe) else { return true }
        return le > maintenant.addingTimeInterval(-7 * jour)
    }

    /// Une carte dit qui (le nom court de l'agent) et quand : fait quand, en cours depuis quand ; « à faire » n'a pas d'heure
    /// prévue, la carte le dit (09/11 : rouge = en retard ou problème seulement). Son texte parle à Sacha en « tu ».
    private static func element(_ c: CarteDomaine, maintenant: Date) -> ElementDomaine {
        // « session », « agent » : un auteur générique ; c'est l'agent du domaine.
        let generique = ["", "session", "agent", "claude"].contains(c.auteur.lowercased().trimmingCharacters(in: .whitespaces))
        let qui = TravailAgents.domaine(c.auteur)?.agent ?? (generique ? c.domaine.agent : c.auteur)
        let le = Dates.iso.date(from: c.majLe)
        let quand = le.map { Libelles.quand($0, maintenant: maintenant) }
        let pourquoi = Libelles.tutoyer(c.pourquoi)
        let ton: TonStatut
        let detail: String
        switch c.etat {
        case .fait:
            ton = .vert; detail = quand.map { L("Fait par \(qui) \($0)") } ?? L("Fait par \(qui)")
        case .enCours:
            ton = .ambre
            detail = le.map { L("\(qui) y travaille depuis \(Libelles.depuis($0, maintenant: maintenant))") } ?? L("\(qui) y travaille")
        case .prepare:
            ton = .ambre; detail = quand.map { L("Préparé par \(qui) \($0)") } ?? L("Préparé par \(qui)")
        case .aFaire:
            ton = .ambre
            detail = le.map { L("\(qui) · sans heure prévue, noté le \(Libelles.jourHeure($0))") } ?? L("\(qui) · sans heure prévue")
        case .pasPuFaire:
            ton = .rouge; detail = (pourquoi.isEmpty ? "" : pourquoi + " · ") + qui + (quand.map { ", \($0)" } ?? "")
        }
        return ElementDomaine(id: "carte:\(c.id)", titre: Libelles.tutoyer(c.texte), detail: detail, quand: c.etat == .aFaire ? nil : le,
                              lien: c.lien, carteId: c.id, ton: ton, agent: c.domaine.equipe)
    }

    /// 09/11 (Organisation) : une carte qui attend quelqu'un le dit, et va où ce quelqu'un la cherche.
    /// - Sacha : sa ligne passe dans « Pour toi », dite par le rappel à son nom (la même ligne que dans « À toi ») ; rappel
    ///   fait = l'agent reprend ; rappel introuvable = problème de la carte, à corriger par l'agent.
    /// - PILOTE ou un tiers (« l'académie ») : « attend X depuis HH:MM » ; jamais un problème de l'agent.
    private static func element(_ c: CarteDomaine, _ s: SourcesDomaines) -> (CaseDomaine, ElementDomaine) {
        var el = element(c, maintenant: s.maintenant)
        let attend = attendu(c.attend)
        guard c.etat != .fait, !attend.isEmpty else { return (c.etat, el) }
        let qui = TravailAgents.domaine(c.auteur)?.agent ?? c.domaine.agent
        let le = Dates.iso.date(from: c.majLe)
        let depuis = le.map { Libelles.depuisLe($0, maintenant: s.maintenant) }
        let pourquoi = c.pourquoi.isEmpty ? "" : Libelles.tutoyer(c.pourquoi)
        let attente: CaseDomaine = c.etat == .pasPuFaire ? .enCours : c.etat
        if attend == "\(Moi.nom)" {
            guard let rappels = s.rappelsSacha else {
                el.pourToi = true
                el.detail = depuis.map { L("\(qui) attend ton geste depuis \($0) · Rappels pas accessibles") }
                    ?? L("\(qui) attend ton geste · Rappels pas accessibles")
                return (attente, el)
            }
            guard let r = rappelLie(c.rappel, rappels) else {
                el.ton = .rouge
                el.detail = L("Attend toi, mais aucun rappel à ton nom (« \(court(c.rappel, 30)) ») : à poser par \(qui)")
                return (.pasPuFaire, el)
            }
            if r.faite {
                el.detail += " · " + L("ton geste est fait (« \(court(r.titre, 40)) »), \(qui) reprend")
                return (c.etat, el)
            }
            let retard = r.echeance.map { $0 < s.maintenant } ?? false
            el.cle = el.titre
            el.titre = titre(r)
            let pour = court(Libelles.tutoyer(c.texte), 60)
            el.detail = L("\(qui) l'attend pour « \(pour) »") + " · " + texteEcheance(r.echeance, retard: retard)
            el.quand = r.echeance
            el.ton = retard ? .rouge : .ambre
            el.pourToi = true
            el.geste = geste(r, maintenant: s.maintenant)
            return (attente, el)
        }
        // L'agent lui-même : la carte est à lui, rien de plus à dire (un « prêt » le dit dans sa section).
        if attend == c.domaine.agent { el.attend = attend; return (c.etat, el) }
        el.attend = attend
        el.ton = .ambre
        var detail = depuis.map { L("\(qui) · attend \(attend) depuis \($0)") } ?? L("\(qui) · attend \(attend)")
        if !pourquoi.isEmpty { detail = L("\(detail) : \(pourquoi)") }
        el.detail = detail
        return (attente, el)
    }

    /// Un ❓ ou un rappel de Sacha qui sert l'agent du domaine : sa ligne « Pour toi », avec le geste de sa ligne dans À toi.
    private static func element(_ r: TacheDomaine, _ d: Domaine, maintenant: Date) -> ElementDomaine {
        let retard = r.echeance.map { $0 < maintenant } ?? false
        let detail = (r.decision ? L("\(d.agent) attend ta décision") : L("\(d.agent) attend ce geste")) + " · "
            + texteEcheance(r.echeance, retard: retard)
        return ElementDomaine(id: "rappel:\(r.id)", titre: titre(r), detail: detail, quand: r.echeance, ton: retard ? .rouge : .ambre,
                              pourToi: true, geste: geste(r, maintenant: maintenant))
    }

    private static func titre(_ r: TacheDomaine) -> String {
        r.decision ? L("Décider : \(Decisions.question(r.titre))") : Libelles.tutoyer(r.titre)
    }

    /// « échéance 10/11 », « en retard, échéance 10/11 », « sans échéance ».
    private static func texteEcheance(_ d: Date?, retard: Bool) -> String {
        guard let d else { return L("sans échéance") }
        return retard ? L("en retard, échéance \(Libelles.jourCourt(d))") : L("échéance \(Libelles.jourCourt(d))")
    }

    /// Le geste vers À toi : un ❓ y est dès qu'il est posé ; un rappel, s'il est dû aujourd'hui ou en retard.
    private static func geste(_ r: TacheDomaine, maintenant: Date) -> String? {
        if r.decision { return "decision:\(r.id)" }
        return r.echeance.map { $0 < finDuJour(maintenant) } ?? false ? "rappel:\(r.id)" : nil
    }

    /// Le domaine de l'agent qu'un rappel de Sacha sert : « Pour : App » dans ses notes ; pour un ❓, sa liste aussi (règle des
    /// réponses, Decisions.pour). Jamais l'étiquette d'une liste mélangée (KRYVA) ; PILOTE n'est pas un domaine d'agent ici.
    static func domaineDuRappel(titre: String, liste: String, notes: String) -> Domaine? {
        let pour: String?
        if Decisions.estDecision(titre) { pour = Decisions.pour(liste: liste, notes: notes) }
        else { pour = notes.split(whereSeparator: \.isNewline).lazy.compactMap { Decisions.destinataireEcrit(String($0)) }.first }
        guard let d = pour.flatMap(TravailAgents.domaine), d != .pilote else { return nil }
        return d
    }

    /// Qui une carte attend, écrit d'une seule façon : « toi », « Sacha » → « Sacha » ; « pilote » → « PILOTE » ; un agent
    /// par son nom court (« App ») ; « personne », « rien » → vide ; le reste tel quel (« l'académie »).
    static func attendu(_ texte: String) -> String {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        let bas = t.lowercased()
        if ["", "personne", "rien", "aucun", "-"].contains(bas) { return "" }
        if ["toi", "tu", "moi", "vous", "sacha", Moi.nom.lowercased()].contains(bas) { return "\(Moi.nom)" }
        if let d = TravailAgents.domaine(t) { return d.agent }
        return t
    }

    /// Le rappel lié à une carte : par identifiant (ou ses 8 premiers caractères au moins), sinon par titre exact ; un rappel
    /// à faire passe avant un rappel fait du même titre.
    static func rappelLie(_ ref: String, _ rappels: [TacheDomaine]) -> TacheDomaine? {
        let r = Libelles.refRappel(ref)
        guard !r.isEmpty else { return nil }
        if let t = rappels.first(where: { $0.id == r }) { return t }
        if r.count >= 8, let t = rappels.first(where: { $0.id.hasPrefix(r) }) { return t }
        let memes = rappels.filter { $0.titre.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(r) == .orderedSame }
        return memes.first { !$0.faite } ?? memes.first
    }

    /// Un rappel de la liste « Agents » : qui le fait et quand, toujours dits.
    private static func element(_ t: TravailAgent, _ d: Domaine, maintenant: Date) -> (CaseDomaine, ElementDomaine)? {
        let id = "agent:\(t.id)"
        let titre = Libelles.tutoyer(t.titre)
        if t.faite {
            guard let le = t.faiteLe, le > maintenant.addingTimeInterval(-7 * jour) else { return nil }
            return (.fait, ElementDomaine(id: id, titre: titre, detail: L("Fait par \(d.agent) \(Libelles.quand(le, maintenant: maintenant))"),
                                          quand: le, ton: .vert, agent: d.equipe))
        }
        guard let p = t.prevu else {
            return (.aFaire, ElementDomaine(id: id, titre: titre, detail: L("\(d.agent) · sans heure prévue"), ton: .gris, agent: d.equipe))
        }
        if p < maintenant {
            return (.pasPuFaire, ElementDomaine(id: id, titre: titre,
                                                detail: L("\(d.agent) · prévu \(Libelles.quand(p, maintenant: maintenant)), pas encore fait"),
                                                quand: p, ton: .rouge, agent: d.equipe))
        }
        return (.aFaire, ElementDomaine(id: id, titre: titre, detail: L("\(d.agent) · prévu \(Libelles.quand(p, maintenant: maintenant))"),
                                        quand: p, ton: .ambre, agent: d.equipe))
    }

    // MARK: Une chose = une ligne

    /// 09/11 (Organisation : « Une chose = une ligne ») : la même chose dite par un commit, une carte et un rappel « Agents »
    /// ne fait plus qu'une ligne. On garde la plus sûre : en ligne, puis prête dans le dépôt (lue, pas déclarée), puis bloquée,
    /// faite, en cours, prête, à faire. Deux lignes de la même source dans deux cases différentes restent toutes les deux
    /// (une tâche qui revient chaque lundi : faite hier, à refaire lundi prochain), sauf deux cartes pas encore faites
    /// (09/11, Organisation : la Pub « en cours » et la Pub « prête » de App, une seule chose).
    static func dedoublonner(_ cases: inout [CaseDomaine: [ElementDomaine]]) {
        struct Ligne { let k: CaseDomaine; let el: ElementDomaine; let mots: Set<String>; let source: String }
        var lignes: [Ligne] = []
        for k in CaseDomaine.allCases {
            for el in cases[k] ?? [] {
                let source = String(el.id.prefix { $0 != ":" })
                guard ["carte", "agent", "git"].contains(source) else { continue }
                lignes.append(Ligne(k: k, el: el, mots: mots(el.titre + " " + el.cle), source: source))
            }
        }
        guard lignes.count > 1 else { return }
        var parent = Array(lignes.indices)
        func racine(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        // Les paires les plus proches d'abord ; deux commits différents ne sont jamais la même chose, même par une chaîne
        // (09/11 : « Envoi bloqué » et « TVA par ligne » réunis par une carte, un des deux commits disparaissait).
        var paires: [(a: Int, b: Int, p: Double)] = []
        for a in lignes.indices {
            for b in lignes.indices where b > a {
                if lignes[a].source == lignes[b].source && lignes[a].k != lignes[b].k
                    && (lignes[a].source != "carte" || lignes[a].k == .fait || lignes[b].k == .fait) { continue }
                if lignes[a].source == "git" && lignes[b].source == "git" { continue }
                if memeChose(lignes[a].mots, lignes[b].mots) { paires.append((a, b, proximite(lignes[a].mots, lignes[b].mots))) }
            }
        }
        var aUnCommit = lignes.map { $0.source == "git" }
        for (a, b, _) in paires.sorted(by: { $0.p != $1.p ? $0.p > $1.p : ($0.a, $0.b) < ($1.a, $1.b) }) {
            let (ra, rb) = (racine(a), racine(b))
            guard ra != rb, !(aUnCommit[ra] && aUnCommit[rb]) else { continue }
            parent[rb] = ra
            aUnCommit[ra] = aUnCommit[ra] || aUnCommit[rb]
        }
        var groupes: [Int: [Int]] = [:]
        for x in lignes.indices { groupes[racine(x), default: []].append(x) }
        var retirer: [CaseDomaine: Set<String>] = [:]
        for g in groupes.values where g.count > 1 {
            let garde = g.min { rang(lignes[$0].k, lignes[$0].el.id) < rang(lignes[$1].k, lignes[$1].el.id) }!
            for x in g where x != garde { retirer[lignes[x].k, default: []].insert(lignes[x].el.id) }
        }
        for (k, ids) in retirer { cases[k]?.removeAll { ids.contains($0.id) } }
    }

    private static func rang(_ k: CaseDomaine, _ id: String) -> Int {
        if id.hasPrefix("git:") { return k == .fait ? 0 : 1 }
        switch k {
        case .pasPuFaire: return 2
        case .fait: return 3
        case .enCours: return 4
        case .prepare: return 5
        case .aFaire: return 6
        }
    }

    /// Les mots qui disent de quoi parle une ligne : sans accents, sans les petits mots ni ceux qui disent seulement l'état.
    static func mots(_ t: String) -> Set<String> {
        let plie = t.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        var r = Set<String>()
        for m in plie.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            var w = String(m)
            if w.count > 4 && w.hasSuffix("s") { w.removeLast() }
            guard w.count >= 3, !motsVides.contains(w) else { continue }
            r.insert(w)
        }
        return r
    }

    /// Même chose : 3 mots en commun au moins, et la moitié des mots de la plus courte.
    static func memeChose(_ a: Set<String>, _ b: Set<String>) -> Bool {
        let commun = a.intersection(b).count
        return commun >= 3 && Double(commun) >= 0.5 * Double(min(a.count, b.count))
    }

    static func proximite(_ a: Set<String>, _ b: Set<String>) -> Double {
        Double(a.intersection(b).count) / Double(max(1, min(a.count, b.count)))
    }

    private static let motsVides: Set<String> = [
        "les", "des", "une", "aux", "pas", "plus", "que", "qui", "quand", "pour", "par", "sur", "sans", "avec", "dans", "cet",
        "cette", "ces", "son", "ses", "leur", "mon", "mes", "ton", "tes", "nos", "vos", "notre", "votre", "elle", "ils", "nous",
        "vous", "toi", "lui", "est", "sont", "ete", "etre", "fait", "faire", "dit", "aussi", "comme", "tout", "tou", "toute",
        "tre", "bien", "non", "oui", "apre", "apres", "avant", "encore", "deja", "puis", "entre", "dont", "peut", "doit",
        "app", "kryva", "sacha", "idee", "code", "codee", "teste", "testee", "vue", "voir", "part", "partir", "push",
        "version", "suivante", "suivant", "hors", "reste", "ecran", "feat", "fix", "branche", "main", "the", "and",
        "attend", "attendent", "attente", "pousse", "poussee", "pret", "prete",
    ]

    // MARK: Les sections, le bilan, qui

    // Les titres des sections : le code les retrouve avec ces mêmes fonctions, jamais avec un texte écrit en dur.
    static var pourToi: String { L("Pour toi") }
    static var titreProbleme: String { L("Problème") }
    static var titreEnCours: String { L("En cours") }
    static var titreFaitAujourdhui: String { L("Fait aujourd'hui") }
    static var titreFait7Jours: String { L("Fait ces 7 derniers jours") }
    static func aFairePar(_ d: Domaine) -> String { L("À faire par \(d.agent)") }

    /// Le domaine déplié (09/11) : chaque section porte le mot du bilan de la ligne fermée, avec le même nombre.
    static func sections(_ d: Domaine, _ e: EtatDomaine, maintenant: Date) -> [SectionDomaine] {
        let cal = Calendar.current
        let pourToi = [CaseDomaine.aFaire, .enCours, .prepare].flatMap { e.elements($0) }.filter(\.pourToi)
            .sorted { ($0.quand ?? .distantFuture) < ($1.quand ?? .distantFuture) }
        // « Prêt » dit ce qui le fera partir : « Prêt, à fusionner par App », « Prêt, attend ton push »…
        var prets: [SectionDomaine] = []
        for el in e.elements(.prepare) where !el.pourToi {
            let suite = suitePret(el, d)
            if let i = prets.firstIndex(where: { $0.pret == suite }) { prets[i].elements.append(el) }
            else { prets.append(SectionDomaine(titre: suite.titre, elements: [el], ton: .ambre, pret: suite)) }
        }
        let faits = e.elements(.fait)
        // Une réponse reçue n'est pas un travail fait : elle attend l'agent.
        let reponses = faits.filter { $0.contactId != nil && $0.ton == .ambre }
        let vraiment = faits.filter { el in !reponses.contains { $0.id == el.id } }
        let duJour = vraiment.filter { $0.quand.map { cal.isDate($0, inSameDayAs: maintenant) } ?? false }
        let avant = vraiment.filter { el in !duJour.contains { $0.id == el.id } }
        return ([
            SectionDomaine(titre: titreProbleme, elements: e.elements(.pasPuFaire), ton: .rouge),
            SectionDomaine(titre: Self.pourToi, elements: pourToi, ton: pourToi.contains { $0.ton == .rouge } ? .rouge : .ambre),
            SectionDomaine(titre: titreEnCours, elements: e.elements(.enCours).filter { !$0.pourToi }, ton: .vert),
            SectionDomaine(titre: reponsesPar(d), elements: reponses, ton: .ambre),
            SectionDomaine(titre: aFairePar(d), elements: e.elements(.aFaire).filter { !$0.pourToi }, ton: .ambre),
        ] + prets + [
            SectionDomaine(titre: titreFaitAujourdhui, elements: duJour, ton: .vert),
            SectionDomaine(titre: titreFait7Jours, elements: avant, ton: .vert),
        ]).filter { !$0.elements.isEmpty }
    }

    static func reponsesPar(_ d: Domaine) -> String { L("Réponse reçue, à traiter par \(d.agent)") }

    /// Ce qui fera partir une chose prête, et qui le fait. Une carte le dit par « attend » (09/11, Organisation : « 1 prêt »
    /// seul ne dit pas qui agit) ; une ancienne carte qui ne le dit pas le montre.
    static func suitePret(_ el: ElementDomaine, _ d: Domaine) -> SuitePret {
        if el.id.hasPrefix("git:") { return el.cle.isEmpty ? .attendPush : .fusionner }
        if el.id.hasPrefix("pub:") { return .partALHeure }
        if el.id.hasPrefix("contact:") { return .envoyerLeJour }
        if el.id.hasPrefix("carte:") {
            if el.attend.isEmpty { return .preciser(d.agent) }
            if el.attend == d.agent { return .fairePartir(d.agent) }
            return .attend(el.attend)
        }
        return .aucune
    }

    /// Les cartes qui attendent quelqu'un d'autre que l'agent, par qui, dans l'ordre : (qui, combien, depuis le plus ancien).
    static func attendus(_ els: [ElementDomaine], _ d: Domaine) -> [(qui: String, n: Int, depuis: Date?)] {
        var r: [(qui: String, n: Int, depuis: Date?)] = []
        for el in els where !el.attend.isEmpty && el.attend != d.agent {
            let le = el.carteId.flatMap { _ in el.quand }
            if let i = r.firstIndex(where: { $0.qui == el.attend }) {
                r[i].n += 1
                if let le { r[i].depuis = min(r[i].depuis ?? le, le) }
            } else {
                r.append((el.attend, 1, le))
            }
        }
        return r
    }

    static func section(_ e: EtatDomaine, _ titre: String) -> [ElementDomaine] {
        e.sections.first { $0.titre == titre }?.elements ?? []
    }

    /// Le travail des agents, section par section, avec les mêmes mots (« 13 à faire par App » = la section « À faire par App »).
    static func bilan(_ d: Domaine, _ e: EtatDomaine, maintenant: Date) -> [PastilleStatut] {
        var l: [PastilleStatut] = []
        let problemes = section(e, titreProbleme).count
        if problemes > 0 { l.append(PastilleStatut(texte: problemes == 1 ? L("1 problème") : L("\(problemes) problèmes"), ton: .rouge)) }
        // 09/11 (Organisation) : un « en cours » qui attend quelqu'un est compté en le nommant (« 1 en cours attend PILOTE
        // depuis 17:34 », « 3 en cours, dont 1 attend l'académie depuis 17:04 »).
        let enCoursEl = section(e, titreEnCours)
        if !enCoursEl.isEmpty {
            let n = enCoursEl.count
            let att = attendus(enCoursEl, d)
            // « attend PILOTE depuis 17:34 » : le verbe s'accorde avec le nombre de cartes qui attendent.
            func dit(_ a: (qui: String, n: Int, depuis: Date?)) -> String {
                let qui = a.qui
                if let h = a.depuis.map({ Libelles.depuisLe($0, maintenant: maintenant) }) {
                    return a.n > 1 ? L("attendent \(qui) depuis \(h)") : L("attend \(qui) depuis \(h)")
                }
                return a.n > 1 ? L("attendent \(qui)") : L("attend \(qui)")
            }
            let texte: String
            if att.count == 1 && att[0].n == n { let clause = dit(att[0]); texte = L("\(n) en cours \(clause)") }
            else if att.isEmpty { texte = L("\(n) en cours") }
            else {
                let liste = att.map { String($0.n) + " " + dit($0) }.joined(separator: ", ")
                texte = L("\(n) en cours, dont \(liste)")
            }
            l.append(PastilleStatut(texte: texte, ton: att.isEmpty ? .vert : .ambre))
        }
        let reponses = section(e, reponsesPar(d)).count
        if reponses > 0 {
            let agent = d.agent
            l.append(PastilleStatut(texte: reponses == 1 ? L("1 réponse reçue, à traiter par \(agent)")
                                                         : L("\(reponses) réponses reçues, à traiter par \(agent)"), ton: .ambre))
        }
        let aFaire = section(e, aFairePar(d))
        if !aFaire.isEmpty {
            let cal = Calendar.current
            let duJour = aFaire.compactMap(\.quand).filter { $0 >= maintenant && cal.isDate($0, inSameDayAs: maintenant) }
            let agent = d.agent, n = aFaire.count
            let texte = duJour.max().map { fin -> String in
                let h = Libelles.heureCourte(fin), k = duJour.count
                return L("\(n) à faire par \(agent), dont \(k) d'ici \(h)")
            } ?? L("\(n) à faire par \(agent)")
            l.append(PastilleStatut(texte: texte, ton: .ambre))
        }
        // Une section « Prêt… » se reconnaît à son champ `pret`, pas à son titre.
        for sec in e.sections {
            guard let suite = sec.pret else { continue }
            l.append(PastilleStatut(texte: suite.pastille(n: sec.elements.count), ton: .ambre))
        }
        let faits = section(e, titreFaitAujourdhui).count
        if faits > 0 { l.append(PastilleStatut(texte: faits == 1 ? L("1 fait aujourd'hui") : L("\(faits) faits aujourd'hui"), ton: .vert)) }
        return l
    }

    /// Qui tient le domaine et ce qu'il fait (même source que l'outil agents) : sa session d'équipe d'abord, sinon une
    /// session dont le titre dit le domaine. En pause avec du travail en attente : pourquoi, ou quand ça reprend.
    static func qui(_ d: Domaine, _ s: SourcesDomaines, _ e: EtatDomaine? = nil) -> (String, TonStatut) {
        let tenant = Self.tenant(d, s)
        let autres = s.sessions.filter { $0.etat == "busy" && $0.id != tenant?.id
            && Domaine.deSession(titre: $0.titre, dossier: $0.dossier) == d }.count
        let enPlus = autres == 0 ? "" : " · " + (autres == 1 ? L("1 autre session au travail") : L("\(autres) autres sessions au travail"))
        let attente = e.map { enAttente(d, s, $0) } ?? ""
        // Du travail attend pendant que personne ne s'en occupe : le point passe à l'ambre.
        let calme: TonStatut = e.flatMap { Self.attente(d, $0, maintenant: s.maintenant) } != nil ? .ambre : .gris
        let agent = d.agent
        guard let t = tenant else { return (L("\(agent) n'est pas lancé") + attente + enPlus, autres > 0 ? .vert : calme) }
        switch t.etat {
        case "busy":
            var texte = L("\(agent) au travail")
            if !t.etape.isEmpty {
                let etape = court(t.etape, 70)
                texte = t.n > 0 ? L("\(agent) au travail : \(etape) (étape \(t.k)/\(t.n))") : L("\(agent) au travail : \(etape)")
            }
            return (texte + enPlus, .vert)
        case "waiting":
            return ((t.question.isEmpty ? L("\(agent) attend un message de toi") : L("\(agent) attend ta réponse, dans À toi")) + enPlus, .ambre)
        default:
            let pause = t.depuis.map { L("\(agent) en pause depuis \(Libelles.depuis($0, maintenant: s.maintenant))") } ?? L("\(agent) en pause")
            return (pause + attente + enPlus, autres > 0 ? .vert : calme)
        }
    }

    /// La session qui tient le domaine : sa session d'équipe d'abord, sinon une au travail, sinon la première.
    static func tenant(_ d: Domaine, _ s: SourcesDomaines) -> SessionDomaine? {
        let duDomaine = s.sessions.filter { Domaine.deSession(titre: $0.titre, dossier: "") == d }
        return duDomaine.first { $0.titre == d.equipe } ?? duDomaine.first { $0.etat == "busy" } ?? duDomaine.first
    }

    /// Le travail qui attend l'agent, avec les mots du bilan : réponses reçues, puis problèmes (un travail d'agent en retard
    /// est un problème). `depuis` = le plus ancien des deux, s'il est daté.
    struct Attente: Hashable {
        var reponses: Int
        var problemes: Int
        var n: Int
        var depuis: Date?
        var titres: [String]

        /// « 1 réponse reçue et 1 problème ». `francais` : le texte envoyé à l'agent, qui travaille en français quelle que
        /// soit la langue de l'écran.
        func quoi(francais: Bool = false) -> String {
            let r: String, p: String
            if francais {
                r = reponses == 1 ? "1 réponse reçue" : "\(reponses) réponses reçues"
                p = problemes == 1 ? "1 problème" : "\(problemes) problèmes"
                return reponses > 0 && problemes > 0 ? "\(r) et \(p)" : (reponses > 0 ? r : p)
            }
            r = reponses == 1 ? L("1 réponse reçue") : L("\(reponses) réponses reçues")
            p = problemes == 1 ? L("1 problème") : L("\(problemes) problèmes")
            return reponses > 0 && problemes > 0 ? L("\(r) et \(p)") : (reponses > 0 ? r : p)
        }
    }

    static func attente(_ d: Domaine, _ e: EtatDomaine, maintenant: Date) -> Attente? {
        let reponses = section(e, reponsesPar(d))
        let problemes = e.elements(.pasPuFaire)
        guard !reponses.isEmpty || !problemes.isEmpty else { return nil }
        let tous = reponses + problemes
        return Attente(reponses: reponses.count, problemes: problemes.count, n: tous.count,
                       depuis: tous.compactMap(\.quand).filter { $0 <= maintenant }.min(), titres: tous.map(\.titre))
    }

    /// « 1 réponse reçue et 1 problème attendent depuis 14:12 ». `francais` : pour le texte envoyé à l'agent.
    static func phrase(_ a: Attente, maintenant: Date, francais: Bool = false) -> String {
        if francais {
            return "\(a.quoi(francais: true)) \(a.n > 1 ? "attendent" : "attend")"
                + (a.depuis.map { " depuis \(Libelles.depuisLe($0, maintenant: maintenant, francais: true))" } ?? "")
        }
        let quoi = a.quoi()
        if let h = a.depuis.map({ Libelles.depuisLe($0, maintenant: maintenant) }) {
            return a.n > 1 ? L("\(quoi) attendent depuis \(h)") : L("\(quoi) attend depuis \(h)")
        }
        return a.n > 1 ? L("\(quoi) attendent") : L("\(quoi) attend")
    }

    /// Le texte du bouton « Relancer X », envoyé par « Écrire à » quand Sacha clique Envoyer. Rien si l'agent travaille ou
    /// attend une réponse de Sacha (elle est dans À toi). La veille ne réveille jamais l'agent pour ces entrées : les réponses
    /// reçues vont à PILOTE, et les listes de 7 h 05, 11 h 13, 16 h 13 et 18 h 13 ne portent que les fiches dues.
    static func relance(_ d: Domaine, _ s: SourcesDomaines, _ e: EtatDomaine) -> String? {
        guard let a = attente(d, e, maintenant: s.maintenant) else { return nil }
        if let t = tenant(d, s), t.etat == "busy" || t.etat == "waiting" { return nil }
        // Ce texte part à l'agent (Écrire à, par le Facteur) : français, la langue de ses sessions, quelle que soit celle de l'écran.
        let noms = a.titres.prefix(3).map { "« \(court($0, 40)) »" }.joined(separator: ", ")
        let plus = a.titres.count > 3 ? " et \(a.titres.count - 3) de plus" : ""
        return "\(phrase(a, maintenant: s.maintenant, francais: true)) : \(noms)\(plus). À traiter maintenant, puis dis-moi en une ligne où tu en es."
    }

    /// Le texte du bouton « Relancer PILOTE » (09/11, Organisation) : des cartes du domaine attendent PILOTE. Toujours
    /// proposé, même PILOTE au travail : le Facteur lui remet le message à la fin de son tour.
    static func relancePilote(_ d: Domaine, _ e: EtatDomaine, maintenant: Date) -> String? {
        guard d != .pilote else { return nil }
        let els = [CaseDomaine.enCours, .prepare, .aFaire].flatMap { e.elements($0) }.filter { $0.attend == Domaine.pilote.agent }
        guard !els.isEmpty else { return nil }
        // Texte pour PILOTE : français, comme la relance de l'agent (nom d'agent français aussi).
        let depuis = els.compactMap(\.quand).filter { $0 <= maintenant }.min()
            .map { " depuis \(Libelles.depuisLe($0, maintenant: maintenant, francais: true))" } ?? ""
        let noms = els.prefix(3).map { "« \(court($0.titre, 50)) »" }.joined(separator: ", ")
        let plus = els.count > 3 ? " et \(els.count - 3) de plus" : ""
        return "\(d.agentFrancais) t'attend\(depuis) : \(noms)\(plus). Réponds-lui maintenant, puis dis-moi en une ligne où ça en est."
    }

    /// 09/11 (Organisation) : du travail qui attend (réponse reçue, problème, travail d'agent en retard) se dit d'abord,
    /// « 1 réponse reçue attend depuis 14:12 » ; « reprend le … » seulement quand plus rien n'attend ; sinon le travail sans
    /// heure ; rien s'il n'y a rien.
    static func enAttente(_ d: Domaine, _ s: SourcesDomaines, _ e: EtatDomaine) -> String {
        if let a = attente(d, e, maintenant: s.maintenant) { return " · " + phrase(a, maintenant: s.maintenant) }
        let aFaire = section(e, aFairePar(d))
        if let p = aFaire.filter({ ($0.quand ?? .distantPast) > s.maintenant }).min(by: { $0.quand! < $1.quand! }), let q = p.quand {
            let quand = Libelles.quand(q, maintenant: s.maintenant), titre = court(p.titre, 50)
            return " · " + L("reprend \(quand) : « \(titre) »")
        }
        if !aFaire.isEmpty {
            return " · " + (aFaire.count == 1 ? L("1 à faire sans heure prévue, écris-lui") : L("\(aFaire.count) à faire sans heure prévue, écris-lui"))
        }
        return ""
    }

    // MARK: App KRYVA : en ligne · prêt (à fusionner, ou attend ton push) · à corriger

    private static func app(_ s: SourcesDomaines, _ cases: inout [CaseDomaine: [ElementDomaine]], _ e: inout EtatDomaine) {
        guard let commits = s.commits else {
            e.erreur = GitKryva.depot == nil ? L("Aucun dépôt suivi : à régler dans reglages.json (depot_suivi).") : L("Le dépôt suivi n'a pas pu être lu.")
            return
        }
        let limite = s.maintenant.addingTimeInterval(-7 * jour)
        let equipe = Domaine.app.equipe
        var dansMain = 0
        for c in commits {
            guard let titre = titreCommit(c.sujet) else { continue }
            if c.enLigne {
                guard (c.le ?? .distantPast) > limite else { continue }
                cases[.fait, default: []].append(ElementDomaine(id: "git:\(c.hash)", titre: titre,
                                                                detail: L("En ligne") + (c.le.map { " · \(Libelles.jourCourt($0))" } ?? ""),
                                                                quand: c.le, ton: .vert))
            } else if c.branche != "main" {
                // 09/11 : sur une branche, rien ne part avec le push tant qu'App ne l'a pas fusionnée (une branche peut
                // attendre la version suivante). Le nom de branche aide à reconnaître la même chose dite par une carte.
                cases[.prepare, default: []].append(ElementDomaine(id: "git:\(c.hash)", titre: titre,
                                                                   detail: L("Prêt sur la branche \(c.branche), à fusionner par \(Domaine.app.agent)"),
                                                                   quand: c.le, ton: .ambre, agent: equipe, cle: c.branche))
            } else {
                dansMain += 1
                let part = s.push?.echeance.map { L("part avec ton push \(Libelles.quand($0, maintenant: s.maintenant))") }
                    ?? L("attend ton push, pas encore prévu")
                cases[.prepare, default: []].append(ElementDomaine(id: "git:\(c.hash)", titre: titre, detail: L("Prêt dans main, \(part)"),
                                                                   quand: c.le, ton: .ambre, agent: equipe))
            }
        }
        // Le push KRYVA est le geste de Sacha (il le tape lui-même dans la session App) : sa ligne « Pour toi », avec l'heure.
        if dansMain > 0 {
            let quand = s.push?.echeance
            let retard = quand.map { $0 < s.maintenant } ?? false
            let detail = quand.map { q -> String in
                let le = Libelles.quand(q, maintenant: s.maintenant)
                return retard ? L("En retard · prévu \(le)") : L("Prévu \(le)")
            } ?? L("Pas encore prévu")
            let geste = quand.flatMap { $0 < finDuJour(s.maintenant) ? s.push.map { "rappel:\($0.id)" } : nil }
            cases[.aFaire, default: []].append(ElementDomaine(id: "push", titre: dansMain == 1 ? L("Taper « push » dans App (1 changement)") : L("Taper « push » dans App (\(dansMain) changements)"),
                                                              detail: detail, quand: quand, ton: retard ? .rouge : .ambre,
                                                              pourToi: true, geste: geste))
        }
    }

    static func finDuJour(_ maintenant: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: maintenant))!
    }

    /// Le sujet d'un commit tel que Sacha le lit : sans le préfixe technique (« fix(planning): », « feat: »), la première
    /// lettre en capitale. nil pour l'entretien du dépôt (chore, docs, test, ci, build, style), qui ne change rien pour l'artisan.
    static func titreCommit(_ sujet: String) -> String? {
        let entretien: Set<String> = ["chore", "docs", "doc", "test", "tests", "ci", "build", "style"]
        guard let r = sujet.range(of: #"^([a-zA-Z]+)(\([^)]*\))?!?:\s*"#, options: .regularExpression) else { return sujet }
        let type = String(sujet[r]).prefix { $0.isLetter }.lowercased()
        if entretien.contains(type) { return nil }
        let reste = sujet[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if reste.isEmpty { return sujet }
        // « iPhone », « macOS » : un mot qui porte déjà une majuscule garde sa forme.
        let premierMot = reste.prefix { !$0.isWhitespace && $0 != "," }
        if premierMot.dropFirst().contains(where: \.isUppercase) { return reste }
        return reste.prefix(1).uppercased() + reste.dropFirst()
    }

    // MARK: Réseaux : publié · prêt · à préparer

    /// « Nom, entreprise », sans redire le nom : « Jean Moreau » + « Moreau » → « Jean Moreau » ;
    /// « Lucas Petit » + « Lucas Petit, projet » → « Lucas Petit, projet ».
    static func nomEtEntreprise(_ nom: String, _ entreprise: String) -> String {
        let e = entreprise.trimmingCharacters(in: .whitespaces)
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if e.isEmpty || nom.range(of: e, options: opts) != nil { return nom }
        if let r = e.range(of: nom, options: opts.union(.anchored)) {
            let reste = e[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " ,·—-"))
            return reste.isEmpty ? nom : "\(nom), \(reste)"
        }
        return "\(nom), \(e)"
    }

    static func nomCompte(_ compte: String) -> String {
        let p = compte.split(separator: "-", maxSplits: 1).map(String.init)
        let reseau: String
        switch p.first ?? "" {
        case "yt": reseau = "YouTube"
        case "ig": reseau = "Instagram"
        case "tt": reseau = "TikTok"
        default: reseau = p.first ?? compte
        }
        let qui = p.count > 1 ? (p[1] == "kryva" ? "KRYVA" : p[1]) : ""
        return qui.isEmpty ? reseau : "\(reseau) \(qui)"
    }

    private static func reseaux(_ s: SourcesDomaines, _ cases: inout [CaseDomaine: [ElementDomaine]]) {
        let limite = s.maintenant.addingTimeInterval(-7 * jour)
        for p in s.publications {
            let titre = ATOI.titre(p, videos: [])   // jamais « Vidéo sans titre » (09/11)
            let quand = p.prevu
            let ou = nomCompte(p.compte) + (quand.map { " · \(Libelles.jourHeure($0))" } ?? "")
            switch p.etat {
            case "publie":
                guard (quand ?? s.maintenant) > limite else { continue }
                cases[.fait, default: []].append(ElementDomaine(id: "pub:\(p.id)", titre: titre, detail: L("Publié · \(ou)"),
                                                                quand: quand, lien: p.lien, ton: .vert))
            case "planifie", "envoi", "envoye":
                // Dans la boîte TikTok : c'est Sacha qui publie (sa ligne de « À toi »).
                let boite = estDansBoiteTikTok(p)
                cases[.prepare, default: []].append(ElementDomaine(id: "pub:\(p.id)", titre: titre,
                                                                   detail: programme(p, maintenant: s.maintenant), quand: quand,
                                                                   ton: .ambre, pourToi: boite, geste: boite ? "tiktok:\(p.id)" : nil))
            case "a_valider":
                cases[.prepare, default: []].append(ElementDomaine(id: "pub:\(p.id)", titre: titre,
                                                                   detail: L("Attend ta validation · \(ou)"), quand: quand, ton: .ambre,
                                                                   pourToi: true, geste: "publication:\(p.id)"))
            case "echec", "reconnexion":
                let pourquoi = p.raison.isEmpty ? (p.etat == "reconnexion" ? L("Compte à reconnecter") : L("Envoi en échec")) : p.raison
                cases[.pasPuFaire, default: []].append(ElementDomaine(id: "pub:\(p.id)", titre: titre,
                                                                      detail: "\(pourquoi) · \(ou)", quand: quand, ton: .rouge))
            default:
                continue
            }
        }
        if var prets = cases[.prepare] {
            prets.sort { ($0.quand ?? .distantFuture) < ($1.quand ?? .distantFuture) }
            cases[.prepare] = prets
        }
    }

    /// TikTok ne prend pas la légende par l'API : le brouillon arrive dans la boîte TikTok et c'est Sacha qui publie.
    static func estDansBoiteTikTok(_ p: Publication) -> Bool {
        p.compte.hasPrefix("tt") && p.etat == "envoye" && p.phase == "boite"
    }

    /// Ce qui va se passer pour une vidéo programmée, dit pour Sacha. YouTube et Instagram partent seuls à l'heure ;
    /// TikTok attend son geste dans l'app.
    static func programme(_ p: Publication, maintenant: Date) -> String {
        let compte = nomCompte(p.compte)
        let quand = p.prevu.map { Libelles.quand($0, maintenant: maintenant) } ?? L("dès que possible")
        if estDansBoiteTikTok(p) { return L("Dans ta boîte TikTok, à publier par toi · prévue \(quand)") }
        if p.compte.hasPrefix("tt") { return L("Arrive dans ta boîte TikTok \(quand), à publier par toi") }
        return L("Part toute seule \(quand) · \(compte)")
    }

    // MARK: Ventes et Freelance : une ligne par personne

    /// La case d'une personne : bloqué d'abord, puis préparé, puis un geste de Sacha, puis fait (une seule case par
    /// personne). Une action d'agent (vérifier, relire, attendre, relancer) ne met personne « à faire » : ce n'est pas à Sacha.
    static func caseDe(_ c: ResumeContact, aujourdhui: String) -> CaseDomaine? {
        if c.echecs > 0 { return .pasPuFaire }
        if c.aPartir > 0 { return .prepare }
        if gesteSacha(c) != nil { return .aFaire }
        if c.partis > 0 || c.recus > 0 { return .fait }
        return nil
    }

    /// Rang d'une décision ❓ dans « À toi » (plus petit = plus haut) : en retard 15, du jour ou pour demain 50 (avec les
    /// autres gestes du jour), plus tard 80 (après les rendez-vous du jour, 60, et les vidéos à tourner, 70).
    static func urgenceDecision(echeance: Date?, enRetard: Bool, maintenant: Date = Date(), calendrier: Calendar = .current) -> Int {
        if enRetard { return 15 }
        guard let e = echeance,
              let apresDemain = calendrier.date(byAdding: .day, value: 2, to: calendrier.startOfDay(for: maintenant)) else { return 50 }
        return e < apresDemain ? 50 : 80
    }

    /// Le geste de Sacha écrit dans la prochaine action (« Sacha : visio avec Arthur mardi 10/11… »), en une phrase courte,
    /// sans « Sacha : », sans identifiant ; nil si la prochaine action est le travail d'un agent, ou si la personne est perdue.
    static func gesteSacha(_ c: ResumeContact) -> String? {
        guard c.etape != "perdu", Libelles.pourSacha(c.prochaineAction) else { return nil }
        var t = Libelles.sansDateEnTete(c.prochaineAction)
        if let r = t.range(of: #"^sacha\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) { t.removeSubrange(r) }
        // La première phrase : on coupe à « . » suivi d'une capitale (« mer. 11/11 » reste entier) ou à « ; ».
        if let r = t.range(of: #"(\.\s+(?=[A-ZÀ-Ý])|\s*;\s)"#, options: .regularExpression) { t = String(t[..<r.lowerBound]) }
        t = sansIdentifiants(t)
        t = court(t, 95)
        return t.isEmpty ? nil : t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Retire les identifiants d'agent (« texte rangé c02fa0fa », « rid A2D7EEDF ») : 8 caractères hexadécimaux avec un chiffre.
    static func sansIdentifiants(_ t: String) -> String {
        t.replacingOccurrences(of: #"\s*\(?\b(rid\s+)?(?=[0-9a-fA-F]*\d)[0-9a-fA-F]{8}\b\)?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Coupe à la dernière virgule avant `max` caractères, sinon net avec « … ».
    static func court(_ t: String, _ max: Int) -> String {
        guard t.count > max else { return t }
        let debut = String(t.prefix(max))
        if let r = debut.range(of: ", ", options: .backwards), debut.distance(from: debut.startIndex, to: r.lowerBound) > max / 2 {
            return String(debut[..<r.lowerBound])
        }
        return debut.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Ce qui se passe pour Sacha avec cette personne, en une phrase, plus son geste s'il en a un.
    static func ligne(_ c: ResumeContact, aujourdhui: String) -> String {
        var phrase = ""
        if c.echecs > 0 {
            phrase = c.echecs == 1 ? L("Un envoi n'est pas parti") : L("\(c.echecs) envois ne sont pas partis")
        } else if c.aValider > 0 {
            phrase = c.aValider == 1 ? L("Texte à valider") : L("\(c.aValider) textes à valider")
        } else if c.prets > 0 {
            let jour = jourEnvoi(c.envoiLe, aujourdhui)
            phrase = c.prets == 1 ? L("Message prêt, à envoyer \(jour)") : L("\(c.prets) messages prêts, à envoyer \(jour)")
            if c.envoiSousCondition { phrase += ", " + L("sous condition") }
        } else if c.aPartir > 0 {
            phrase = L("Texte en cours de réécriture")
        } else if let le = Dates.iso.date(from: c.dernierLe) ?? Dates.jour.date(from: String(c.dernierLe.prefix(10))) {
            let canal = c.dernierCanal.isEmpty ? "" : " (\(Libelles.canal(c.dernierCanal)))"
            let jour = Libelles.jourCourt(le)
            if c.dernierSens == "entrant" {
                phrase = L("A répondu le \(jour)\(canal)")
                if c.aucuneReponseDue { phrase += ", " + L("aucune réponse due") }
            } else {
                phrase = L("Message parti le \(jour)\(canal)")
                if c.etape != "gagne" && c.etape != "perdu" { phrase += ", " + L("attend sa réponse") }
            }
        }
        if let g = gestePersonne(c, aujourdhui: aujourdhui) {
            phrase += (phrase.isEmpty ? "" : " · ") + L("Pour toi : \(g)")
        }
        return phrase
    }

    /// Le geste de Sacha pour cette personne, sa date comprise : « Visio avec Arthur (mar. 10/11) » ; nil sans geste. Le
    /// texte du geste est celui de l'agent (donnée, en français) ; la date n'est ajoutée que si le texte ne la dit pas.
    static func gestePersonne(_ c: ResumeContact, aujourdhui: String) -> String? {
        guard let g = gesteSacha(c) else { return nil }
        var quand = ""
        if let d = Dates.jour.date(from: c.prochaineDate), !g.contains(Libelles.jourCourt(d)) {
            let jour = Libelles.jourCourt(d)
            quand = c.prochaineDate < aujourdhui ? " (" + L("prévu le \(jour)") + ")" : " (\(jour))"
        }
        return g + quand
    }

    /// « aujourd'hui » ou « le mar. 10/11 ».
    static func jourEnvoi(_ jour: String, _ aujourdhui: String) -> String {
        guard !jour.isEmpty, jour > aujourdhui, let d = Dates.jour.date(from: jour) else { return L("aujourd'hui") }
        return L("le \(Libelles.jourSemaine(d))")
    }

    private static func personnes(_ s: SourcesDomaines, espace: String, _ cases: inout [CaseDomaine: [ElementDomaine]]) {
        let aujourdhui = Dates.jour.string(from: s.maintenant)
        for c in s.contacts where c.espace == espace {
            guard var k = caseDe(c, aujourdhui: aujourdhui) else { continue }
            // Un texte en réécriture n'est ni prêt ni à Sacha : l'agent y travaille.
            if k == .prepare && c.aValider == 0 && c.prets == 0 { k = .enCours }
            let nom = c.nom.isEmpty ? (c.entreprise.isEmpty ? L("Sans nom") : c.entreprise) : nomEtEntreprise(c.nom, c.entreprise)
            let ton: TonStatut
            switch k {
            case .pasPuFaire: ton = .rouge
            case .prepare, .enCours: ton = .ambre
            case .aFaire: ton = c.prochaineDate.isEmpty || c.prochaineDate > aujourdhui ? .gris : (c.prochaineDate < aujourdhui ? .rouge : .ambre)
            default: ton = c.dernierSens == "entrant" && !c.aucuneReponseDue ? .ambre : .vert
            }
            let quand = Dates.iso.date(from: c.dernierLe) ?? Dates.jour.date(from: String(c.dernierLe.prefix(10)))
            // Pour Sacha (09/11) : son geste écrit (« Sacha : … »), un texte à valider, ou des messages prêts à envoyer
            // aujourd'hui sans condition (il clique Envoyer). Le geste renvoie à sa ligne de « À toi » quand elle y est.
            let dus = c.prets > 0 && !c.envoiSousCondition && (c.envoiLe.isEmpty || c.envoiLe <= aujourdhui)
            let pourToi = k == .aFaire || (k == .prepare && (c.aValider > 0 || dus))
            let geste = k == .aFaire && !c.prochaineDate.isEmpty && c.prochaineDate <= aujourdhui ? "prospect:\(c.id)" : nil
            cases[k, default: []].append(ElementDomaine(id: "contact:\(c.id)", titre: nom,
                                                        detail: ligne(c, aujourdhui: aujourdhui),   // « Pour toi : … » y est déjà
                                                        quand: k == .aFaire ? Dates.jour.date(from: c.prochaineDate) : quand,
                                                        contactId: c.id, ton: ton, pourToi: pourToi, geste: geste,
                                                        gesteTexte: gestePersonne(c, aujourdhui: aujourdhui)))
        }
        if var prets = cases[.prepare] {
            let envoi = Dictionary(s.contacts.map { ("contact:\($0.id)", $0.envoiLe) }, uniquingKeysWith: { a, _ in a })
            prets.sort { (envoi[$0.id] ?? "") < (envoi[$1.id] ?? "") }
            cases[.prepare] = prets
        }
        if var dus = cases[.aFaire] {
            dus.sort { ($0.quand ?? .distantPast) < ($1.quand ?? .distantPast) }
            cases[.aFaire] = dus
        }
    }

    // MARK: Papiers : fait · à faire · échéance

    private static func papiers(_ s: SourcesDomaines, _ cases: inout [CaseDomaine: [ElementDomaine]], _ e: inout EtatDomaine) {
        guard let taches = s.taches else {
            e.erreur = L("Les Rappels ne sont pas accessibles.")
            return
        }
        let limite = s.maintenant.addingTimeInterval(-7 * jour)
        for t in taches {
            if t.faite {
                guard (t.faiteLe ?? .distantPast) > limite else { continue }
                cases[.fait, default: []].append(ElementDomaine(id: "rappel:\(t.id)", titre: t.titre,
                                                                detail: t.faiteLe.map { L("Fait le \(Libelles.jourCourt($0))") } ?? L("Fait"),
                                                                quand: t.faiteLe, ton: .vert))
            } else {
                let retard = t.echeance.map { $0 < s.maintenant } ?? false
                let detail = L("Pour toi") + " · " + texteEcheance(t.echeance, retard: retard)
                // Un ❓ de la liste Papiers : sa ligne dans À toi est « decision:<id> ».
                var r = t; r.decision = Decisions.estDecision(t.titre)
                cases[.aFaire, default: []].append(ElementDomaine(id: "rappel:\(t.id)", titre: titre(r), detail: detail,
                                                                  quand: t.echeance, ton: retard ? .rouge : .ambre, pourToi: true,
                                                                  geste: geste(r, maintenant: s.maintenant)))
            }
        }
        if var aFaire = cases[.aFaire] {
            aFaire.sort { ($0.quand ?? .distantFuture) < ($1.quand ?? .distantFuture) }
            cases[.aFaire] = aFaire
        }
    }

    // MARK: La pastille : ce qui attend Sacha, et seulement ça

    /// 09/11 (Organisation : « chaque ligne dit le geste de Sacha, sinon rien à faire pour toi ») : une pastille, celle de
    /// Sacha. Le travail des agents est dit par le bilan, avec les mêmes nombres que les sections dépliées.
    private static func pastilles(_ d: Domaine, _ e: EtatDomaine, _ s: SourcesDomaines) -> [PastilleStatut] {
        let pourToi = section(e, Self.pourToi)
        guard !pourToi.isEmpty else { return [PastilleStatut(texte: L("Rien à faire pour toi"), ton: .gris)] }
        let retard = pourToi.filter { $0.ton == .rouge }
        let ton: TonStatut = retard.isEmpty ? .ambre : .rouge
        let geste = (retard + pourToi).first { $0.geste != nil }?.geste
        if pourToi.count == 1 {
            let geste1 = court(gesteCourt(pourToi[0]), 70)
            return [PastilleStatut(texte: L("Pour toi : \(geste1)"), ton: ton, geste: geste)]
        }
        let n = pourToi.count
        let t: String
        if !retard.isEmpty {
            t = retard.count == n ? L("\(n) pour toi, en retard") : L("\(n) pour toi, dont \(retard.count) en retard")
        } else if let q = pourToi.compactMap(\.quand).min() {
            let quand = Libelles.quand(q, maintenant: s.maintenant)
            t = L("\(n) pour toi, la 1re \(quand)")
        } else {
            t = L("\(n) pour toi")
        }
        return [PastilleStatut(texte: t, ton: ton, geste: geste)]
    }

    /// Le geste d'une ligne « Pour toi » en quelques mots : pour une personne, son geste écrit (« Visio avec Arthur… »).
    static func gesteCourt(_ el: ElementDomaine) -> String {
        if el.geste?.hasPrefix("tiktok:") == true { let t = court(el.titre, 50); return L("Publier sur TikTok « \(t) »") }
        if el.geste?.hasPrefix("publication:") == true { let t = court(el.titre, 50); return L("Valider « \(t) »") }
        // Le geste écrit d'une personne est un champ à part (`gesteTexte`) : on ne relit plus « Pour toi : » dans le texte affiché.
        if el.contactId != nil, let g = el.gesteTexte { return g }
        if el.contactId != nil { return "\(el.titre), \(el.detail.prefix(1).lowercased() + el.detail.dropFirst())" }
        return el.titre
    }

    /// 09/11 : plus de résumé à part (« 15 messages prêts » contre une section de 12 personnes) ; tout est dans le bilan.
    private static func resume(_ d: Domaine, _ e: EtatDomaine, _ s: SourcesDomaines) -> String { "" }
}

// MARK: - Libellés courts

extension Libelles {
    /// 09/11 (Organisation : « tout en tu / ton sur l'écran de Sacha ») : un texte de carte ou de rappel qui parle de Sacha à la
    /// 3e personne, dit à Sacha. Les tournures courantes seulement ; le reste passe tel quel.
    static func tutoyer(_ t: String) -> String {
        // Les tournures sont françaises : en anglais et en espagnol la donnée (écrite en français par les agents) reste telle quelle.
        guard Loc.estFrancais else { return t }
        guard let prenom = Moi.prenom, t.contains(prenom) else { return t }
        let moi = NSRegularExpression.escapedPattern(for: prenom)
        var r = t
        // « Sacha : » en tête (une ligne de geste).
        r = remplacer(r, #"^\#(moi)\s*:\s*"#) { _ in "Toi : " }
        // « le feu vert de Sacha » → « ton feu vert » ; « la validation de Sacha » → « ta validation ».
        r = remplacer(r, #"\b([Ll]es|[Ll]e|[Ll]a|[Ll]')\s?([\p{L}-]+(?: [\p{L}-]+)?) de \#(moi)\b"#) { g in
            let art = g[1].lowercased(), nom = g[2]
            let voyelle = nom.first.map { "aeiouyéèêàâîôûh".contains($0.lowercased()) } ?? false
            let pos = art == "les" ? "tes" : (art == "la" && !voyelle ? "ta" : "ton")
            return (g[1].first!.isUppercase ? pos.prefix(1).uppercased() + pos.dropFirst() : pos) + " " + nom
        }
        // « les montrer à Sacha » → « te les montrer » ; « envoyer à Sacha » → « t'envoyer ».
        r = remplacer(r, #"\bles (\p{Ll}+(?:er|ir)) à \#(moi)\b"#) { g in "te les \(g[1])" }
        r = remplacer(r, #"\b(\p{Ll}+(?:er|ir)) à \#(moi)\b"#) { g in
            "aeiouyéèêh".contains(g[1].first!) ? "t'\(g[1])" : "te \(g[1])"
        }
        // « Sacha a / est / fait… » → « tu as / es / fais… » ; « Sacha valide » → « tu valides ».
        let verbes = ["a": "as", "est": "es", "fait": "fais", "doit": "dois", "peut": "peux", "veut": "veux", "dit": "dis",
                      "va": "vas", "sait": "sais", "voit": "vois", "prend": "prends", "met": "mets", "reçoit": "reçois"]
        r = remplacer(r, #"\b\#(moi) n'(a|est)\b"#) { g in "tu n'\(verbes[g[1]]!)" }
        r = remplacer(r, #"\b\#(moi) ne (\p{Ll}+)\b"#) { g in "tu ne " + (verbes[g[1]] ?? (g[1].hasSuffix("e") ? g[1] + "s" : g[1])) }
        r = remplacer(r, #"\b\#(moi) (\p{Ll}+)\b"#) { g in
            if let v = verbes[g[1]] { return "tu \(v)" }
            if g[1].hasSuffix("ait") && g[1].count > 3 { return "tu \(g[1].dropLast())s" }   // « avait » → « avais »
            if g[1].hasSuffix("e") && g[1].count > 2 { return "tu \(g[1])s" }
            return g[0]
        }
        // « par Sacha », « d'après Sacha », « pour Sacha », « à Sacha »… → « … toi ».
        r = remplacer(r, #"\b(par|d['’]après|pour|avec|à|chez|de|selon) \#(moi)\b"#) { g in "\(g[1]) toi" }
        // Une capitale en début de phrase.
        r = remplacer(r, #"(^|[.!?]\s+)(tu|te|ton|ta|tes|t')\b"#) { g in g[1] + g[2].prefix(1).uppercased() + g[2].dropFirst() }
        return r
    }

    /// Remplace chaque occurrence du motif par ce que renvoie `par` (groupes : 0 = tout, 1… = groupes, "" si absent).
    static func remplacer(_ t: String, _ motif: String, par: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: motif) else { return t }
        let ns = t as NSString
        var res = "", fin = 0
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            res += ns.substring(with: NSRange(location: fin, length: m.range.location - fin))
            let g = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            res += par(g)
            fin = m.range.location + m.range.length
        }
        return res + ns.substring(from: fin)
    }

    static let jourCourtFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "dd/MM"; return f
    }()
    /// Le jour de la semaine en français (« mar. 10/11 ») : pour le français et pour les textes qu'on écrit aux agents.
    static let jourSemaineFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE dd/MM"; return f
    }()
    static let heureFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }()
    /// « 10/11 » : un jour numérique, pareil dans toutes les langues.
    static func jourCourt(_ d: Date) -> String { jourCourtFormat.string(from: d) }
    /// « 10/11 à 14:05 ».
    static func jourHeure(_ d: Date) -> String { L("\(jourCourt(d)) à \(heureFormat.string(from: d))") }
    /// « mar. 10/11 » (« Tue 10/11 », « mar 10/11 ») ; `francais` : toujours le français, pour les textes écrits aux agents.
    static func jourSemaine(_ d: Date, francais: Bool = false) -> String {
        francais || Loc.estFrancais ? jourSemaineFormat.string(from: d) : Loc.date(d, "EEE") + " " + jourCourt(d)
    }
    /// « aujourd'hui à 18:00 », « demain à 11:30 », « le jeu. 12/11 à 17:00 ».
    static func quand(_ d: Date, maintenant: Date = Date()) -> String {
        let cal = Calendar.current
        // Une date sans heure (minuit) ne dit pas « à 00:00 » (09/11 : « la 1re le lun. 23/11 à 00:00 »).
        let c = cal.dateComponents([.hour, .minute], from: d)
        let sansHeure = c.hour == 0 && c.minute == 0
        let h = heureFormat.string(from: d)
        if cal.isDate(d, inSameDayAs: maintenant) { return sansHeure ? L("aujourd'hui") : L("aujourd'hui à \(h)") }
        if let demain = cal.date(byAdding: .day, value: 1, to: maintenant), cal.isDate(d, inSameDayAs: demain) {
            return sansHeure ? L("demain") : L("demain à \(h)")
        }
        let jour = jourSemaine(d)
        return sansHeure ? L("le \(jour)") : L("le \(jour) à \(h)")
    }

    /// « 18 h », « 13 h 35 » ; hors du français, l'heure en 24 h (« 18:00 »).
    static func heureCourte(_ d: Date) -> String {
        guard Loc.estFrancais else { return heureFormat.string(from: d) }
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return m == 0 ? "\(h) h" : String(format: "%d h %02d", h, m)
    }

    /// Depuis quand une chose attend : « 14:12 » (aujourd'hui), « hier 18:40 », « le jeu. 05/11 » ; sans heure (minuit) :
    /// « aujourd'hui », « hier ».
    /// `francais` : le français quelle que soit la langue de l'écran, pour les textes écrits aux agents.
    static func depuisLe(_ d: Date, maintenant: Date = Date(), francais: Bool = false) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: d)
        let sansHeure = c.hour == 0 && c.minute == 0
        let h = heureFormat.string(from: d)
        let aujourdhui = cal.isDate(d, inSameDayAs: maintenant)
        let hier = cal.date(byAdding: .day, value: -1, to: maintenant).map { cal.isDate(d, inSameDayAs: $0) } ?? false
        if francais {
            if aujourdhui { return sansHeure ? "aujourd'hui" : h }
            if hier { return sansHeure ? "hier" : "hier \(h)" }
            return "le \(jourSemaine(d, francais: true))"
        }
        if aujourdhui { return sansHeure ? L("aujourd'hui") : h }
        if hier { return sansHeure ? L("hier") : L("hier \(h)") }
        let jour = jourSemaine(d)
        return L("le \(jour)")
    }

    /// « 14 min », « 2 h », « 3 j » (une durée).
    static func depuis(_ d: Date, maintenant: Date = Date()) -> String {
        let s = max(0, maintenant.timeIntervalSince(d))
        if s < 3600 { return L("\(max(1, Int(s / 60))) min") }
        if s < 86_400 { return L("\(Int(s / 3600)) h") }
        return L("\(Int(s / 86_400)) j")
    }
}

// MARK: - Le dépôt suivi (reglages.json, depot_suivi), en lecture seule

enum GitKryva {
    /// nil : aucun dépôt réglé.
    static var depot: URL? { Reglages.courants.depot }
    private static let sep = "\u{1f}"

    /// Ce qui est dans origin/main (ref locale, sans fetch) depuis `jours` jours = en ligne ; les commits des branches locales
    /// actives depuis 14 jours qui n'y sont pas = corrigé, pas en ligne. nil si le dépôt ne se lit pas. Rien n'est écrit.
    static func lire(depot: URL? = depot, jours: Int = 7, maintenant: Date = Date()) -> [CommitKryva]? {
        if Demo.actif { return DemoDonnees.commits(maintenant: maintenant) }
        guard let depot else { return nil }
        let format = "--format=%H\(sep)%s\(sep)%cI"
        guard let enLigne = git(depot, ["log", "origin/main", "--no-merges", "--since=\(jours).days", "--max-count=80", format]) else { return nil }
        var res = commits(enLigne, enLigne: true, branche: "main")
        var vus = Set(res.map(\.hash))
        var sujets = Set(res.map(\.sujet))
        let refs = git(depot, ["for-each-ref", "--format=%(refname:short)\(sep)%(committerdate:unix)", "refs/heads"]) ?? ""
        for ligne in refs.split(separator: "\n") {
            let p = ligne.components(separatedBy: sep)
            guard p.count == 2, let t = Double(p[1]), maintenant.timeIntervalSince1970 - t < 14 * 86_400,
                  !p[0].hasPrefix("sauvegarde/"), !p[0].hasPrefix("_") else { continue }
            // --cherry-pick : un commit déjà repris dans origin/main sous une autre empreinte (même correctif) ne compte pas
            // (09/11 : 990f6ad de fix/arrondi-tva = b2683c4 en ligne depuis le 29/10, compté « pas en ligne » à tort).
            guard let sortie = git(depot, ["log", "--right-only", "--cherry-pick", "--no-merges", "--max-count=30", format,
                                           "origin/main...\(p[0])"]) else { continue }
            // Un commit rebasé change d'empreinte : on écarte aussi les sujets déjà vus.
            for c in commits(sortie, enLigne: false, branche: p[0]) where !vus.contains(c.hash) && !sujets.contains(c.sujet) {
                vus.insert(c.hash)
                sujets.insert(c.sujet)
                res.append(c)
            }
        }
        return res
    }

    static func commits(_ sortie: String, enLigne: Bool, branche: String) -> [CommitKryva] {
        sortie.split(separator: "\n").compactMap { l in
            let p = l.components(separatedBy: sep)
            guard p.count == 3 else { return nil }
            return CommitKryva(hash: p[0], sujet: p[1], le: ISO8601DateFormatter().date(from: p[2]), enLigne: enLigne, branche: branche)
        }
    }

    private static func git(_ depot: URL, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", depot.path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"   // aucune écriture, même pas l'index
        p.environment = env
        let sortie = Pipe()
        p.standardOutput = sortie
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

// MARK: - Les cartes déclarées (table cartes_domaine)

struct RefusCarte: Error, CustomStringConvertible { let description: String }

extension Stockage {
    static let longueurCarte = 120

    /// Les cartes encore à l'écran (une carte « fait » sort après 7 jours).
    func cartesDomaine(maintenant: Date = Date()) throws -> [CarteDomaine] {
        try base.lignes("SELECT * FROM cartes_domaine ORDER BY maj_le DESC").compactMap(Self.carte)
            .filter { Domaines.visible($0, maintenant: maintenant) }
    }

    func carteDomaine(_ id: String) throws -> CarteDomaine? {
        try base.lignes("SELECT * FROM cartes_domaine WHERE id = ? OR id LIKE ?", [id, "\(id)%"]).compactMap(Self.carte).first
    }

    static func carte(_ l: [String: Any]) -> CarteDomaine? {
        guard let d = Domaine(rawValue: l["domaine"] as? String ?? ""), let e = CaseDomaine(rawValue: l["etat"] as? String ?? "") else { return nil }
        return CarteDomaine(id: l["id"] as? String ?? "", domaine: d, etat: e, texte: l["texte"] as? String ?? "",
                            pourquoi: l["pourquoi"] as? String ?? "", lien: l["lien"] as? String ?? "",
                            auteur: l["auteur"] as? String ?? "", creeLe: l["cree_le"] as? String ?? "", majLe: l["maj_le"] as? String ?? "",
                            attend: l["attend"] as? String ?? "", rappel: l["rappel"] as? String ?? "")
    }

    /// Les règles de l'outil : texte court (une carte se remplace, elle ne s'allonge pas), « pourquoi » obligatoire pour
    /// « pas pu faire », pas de tiret long.
    static func verifierCarte(texte: String, pourquoi: String, etat: CaseDomaine) throws {
        if texte.isEmpty { throw RefusCarte(description: "Texte vide.") }
        if texte.count > longueurCarte {
            throw RefusCarte(description: "Texte trop long : \(texte.count) caractères, \(longueurCarte) au plus. Une carte se remplace, elle ne s'allonge pas.")
        }
        if etat == .pasPuFaire && pourquoi.isEmpty {
            throw RefusCarte(description: "« Pas pu faire » demande un pourquoi (et ce qu'il faut).")
        }
        if pourquoi.count > longueurCarte {
            throw RefusCarte(description: "Pourquoi trop long : \(pourquoi.count) caractères, \(longueurCarte) au plus.")
        }
        if texte.contains("—") || pourquoi.contains("—") {
            throw RefusCarte(description: "Pas de tiret long (charte) : une virgule ou deux phrases.")
        }
    }

    /// 09/11 (Organisation) : « attend » dit qui agit ensuite. Sacha : avec le rappel à son nom (c'est lui qui fait la ligne
    /// dans « À toi ») ; une nouvelle carte « prête » le dit toujours (« 1 prêt » seul ne dit pas qui agit).
    static func verifierAttente(attend: String, rappel: String, etat: CaseDomaine, entreEnPrepare: Bool, domaine: Domaine) throws {
        if attend.count > 40 { throw RefusCarte(description: "« attend » trop long : \(attend.count) caractères, 40 au plus (« PILOTE », « l'académie »).") }
        if attend.contains("—") { throw RefusCarte(description: "Pas de tiret long (charte).") }
        if attend == "\(Moi.nom)" && rappel.isEmpty {
            throw RefusCarte(description: "« attend toi » demande le rappel à son nom (rappel : identifiant ou titre exact) : "
                             + "c'est lui qui fait la ligne dans « À toi ». Pas de rappel = poser le rappel d'abord.")
        }
        if !rappel.isEmpty && attend != "\(Moi.nom)" {
            throw RefusCarte(description: "« rappel » seulement quand la carte attend \(Moi.nom) (attend : toi).")
        }
        if etat == .prepare && entreEnPrepare && attend.isEmpty {
            throw RefusCarte(description: "« Prêt » dit qui agit ensuite : attend toi (avec le rappel), PILOTE, \(domaine.agent) "
                             + "(c'est toi qui le fais partir) ou un tiers (« l'académie »).")
        }
    }

    private func plafondAtteint(domaine: Domaine, etat: CaseDomaine, sauf: String?, maintenant: Date) throws {
        let deja = try cartesDomaine(maintenant: maintenant).filter { $0.domaine == domaine && $0.etat == etat && $0.id != sauf }
        guard deja.count >= etat.plafond else { return }
        let liste = deja.map { "\($0.id.prefix(8)) « \($0.texte) »" }.joined(separator: " ; ")
        throw RefusCarte(description: "Case « \(etat.titre) » de \(domaine.titre) pleine (\(etat.plafond) cartes au plus). "
                         + "Remplacez une carte (même id) ou retirez-en une : \(liste)")
    }

    /// Pose une carte, ou remplace celle qui a cet id (texte, case, pourquoi, lien). Chaque mouvement s'écrit au journal.
    @discardableResult
    /// `attend` et `rappel` : nil garde ceux de la carte remplacée ; une carte faite n'attend plus personne.
    func poserCarte(id: String? = nil, domaine: Domaine, etat: CaseDomaine, texte: String, pourquoi: String = "", lien: String = "",
                    attend: String? = nil, rappel: String? = nil,
                    auteur: String, journal: [String: Any] = [:], maintenant: Date = Date()) throws -> CarteDomaine {
        let texte = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        let pourquoi = pourquoi.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.verifierCarte(texte: texte, pourquoi: pourquoi, etat: etat)
        let avant = try id.flatMap { try carteDomaine($0) }
        if let id, avant == nil { throw RefusCarte(description: "Carte introuvable : \(id)") }
        var rappelLu = Libelles.refRappel(rappel ?? avant?.rappel ?? "")
        var attendLu = Domaines.attendu(attend ?? avant?.attend ?? "")
        if attend == nil && rappel != nil && !rappelLu.isEmpty { attendLu = "\(Moi.nom)" }   // un rappel donné seul : la carte attend Sacha
        if etat == .fait { (attendLu, rappelLu) = ("", "") }                             // faite : elle n'attend plus personne
        else if attendLu != "\(Moi.nom)" && rappel == nil { rappelLu = "" }                   // n'attend plus Sacha : l'ancien rappel tombe
        try Self.verifierAttente(attend: attendLu, rappel: rappelLu, etat: etat, entreEnPrepare: avant?.etat != .prepare, domaine: domaine)
        try plafondAtteint(domaine: domaine, etat: etat, sauf: avant?.id, maintenant: maintenant)
        let le = Dates.iso.string(from: maintenant)
        let carte = CarteDomaine(id: avant?.id ?? UUID().uuidString.lowercased(), domaine: domaine, etat: etat, texte: texte,
                                 pourquoi: etat == .pasPuFaire ? pourquoi : "", lien: lien, auteur: auteur,
                                 creeLe: avant?.creeLe ?? le, majLe: le, attend: attendLu, rappel: rappelLu)
        try base.executer("""
            INSERT INTO cartes_domaine (id, domaine, etat, texte, pourquoi, lien, auteur, cree_le, maj_le, attend, rappel)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET domaine = excluded.domaine, etat = excluded.etat, texte = excluded.texte,
              pourquoi = excluded.pourquoi, lien = excluded.lien, auteur = excluded.auteur, maj_le = excluded.maj_le,
              attend = excluded.attend, rappel = excluded.rappel
            """, [carte.id, domaine.rawValue, etat.rawValue, texte, carte.pourquoi, lien, auteur, carte.creeLe, le, attendLu, rappelLu])
        let mouvement: String
        if let avant {
            mouvement = avant.etat != etat ? "Carte déplacée (\(avant.etat.titre) → \(etat.titre))" : "Carte remplacée"
        } else {
            mouvement = "Carte posée"
        }
        try noterCarte(mouvement, carte, journal: journal, maintenant: le)
        return carte
    }

    @discardableResult
    func deplacerCarte(id: String, vers etat: CaseDomaine, pourquoi: String? = nil, attend: String? = nil, rappel: String? = nil,
                       auteur: String, journal: [String: Any] = [:], maintenant: Date = Date()) throws -> CarteDomaine {
        guard let c = try carteDomaine(id) else { throw RefusCarte(description: "Carte introuvable : \(id)") }
        return try poserCarte(id: c.id, domaine: c.domaine, etat: etat, texte: c.texte, pourquoi: pourquoi ?? c.pourquoi, lien: c.lien,
                              attend: attend, rappel: rappel, auteur: auteur, journal: journal, maintenant: maintenant)
    }

    @discardableResult
    func retirerCarte(id: String, auteur: String, journal: [String: Any] = [:], maintenant: Date = Date()) throws -> CarteDomaine {
        guard let c = try carteDomaine(id) else { throw RefusCarte(description: "Carte introuvable : \(id)") }
        try base.executer("DELETE FROM cartes_domaine WHERE id = ?", [c.id])
        var retiree = c
        retiree.auteur = auteur
        try noterCarte("Carte retirée", retiree, journal: journal, maintenant: Dates.iso.string(from: maintenant))
        return c
    }

    private func noterCarte(_ mouvement: String, _ c: CarteDomaine, journal: [String: Any], maintenant: String) throws {
        var champs = journal
        champs["type"] = "carte"
        champs["le"] = maintenant
        var texte = "\(mouvement) · \(c.domaine.titre) › \(c.etat.titre) : \(c.texte)"
        if !c.pourquoi.isEmpty { texte += " (pourquoi : \(c.pourquoi))" }
        if !c.attend.isEmpty { texte += " · attend \(c.attend)" + (c.rappel.isEmpty ? "" : " (rappel \(c.rappel))") }
        if !c.auteur.isEmpty { texte += " · par \(c.auteur)" }
        champs["texte"] = texte
        if !c.lien.isEmpty { champs["fichiers"] = [c.lien] }
        _ = try ajouterJournal(champs)
    }

    // MARK: Ventes et Freelance : chaque personne suivie résumée en une requête

    func resumesContacts(maintenant: Date = Date()) throws -> [ResumeContact] {
        let depuis = Dates.jour.string(from: maintenant.addingTimeInterval(-7 * 86_400))
        let lignes = try base.lignes("""
            SELECT c.id, c.nom, c.entreprise, c.espace, c.etape, c.prochaine_action, c.prochaine_date,
              (SELECT e.le || char(31) || e.sens || char(31) || e.canal FROM evenements e
                 WHERE e.contact_id = c.id AND e.supprime_le = '' AND e.sens IN ('sortant', 'entrant') AND e.statut IN ('envoye', 'fait')
                 ORDER BY e.le DESC LIMIT 1) AS dernier,
              (SELECT count(*) FROM evenements e WHERE e.contact_id = c.id AND e.supprime_le = '' AND e.sens = 'sortant'
                 AND e.statut = 'envoye' AND substr(e.le, 1, 10) >= ?) AS partis,
              (SELECT count(*) FROM evenements e WHERE e.contact_id = c.id AND e.supprime_le = ''
                 AND e.statut IN ('prepare', 'a_valider', 'a_refaire')) AS a_partir,
              (SELECT count(*) FROM evenements e WHERE e.contact_id = c.id AND e.supprime_le = '' AND e.statut = 'echec'
                 AND substr(e.le, 1, 10) >= ?
                 -- 09/11 (Organisation) : un échec est réglé dès qu'après lui un envoi part, un envoi est annulé ou la
                 -- personne répond (Yanis, SMS raté le 02/11, annulé le 04/11, comptait encore « problème »).
                 AND NOT EXISTS (SELECT 1 FROM evenements f WHERE f.contact_id = c.id AND f.supprime_le = ''
                   AND julianday(f.le) > julianday(e.le)
                   AND ((f.sens = 'sortant' AND f.statut IN ('envoye', 'annule')) OR f.sens = 'entrant'))) AS echecs,
              (SELECT count(*) FROM evenements e WHERE e.contact_id = c.id AND e.supprime_le = '' AND e.sens = 'entrant'
                 AND substr(e.le, 1, 10) >= ?) AS recus,
              (SELECT count(*) FROM evenements e WHERE e.contact_id = c.id AND e.supprime_le = '' AND e.statut = 'prepare') AS prets,
              (SELECT count(*) FROM evenements e WHERE e.contact_id = c.id AND e.supprime_le = '' AND e.statut = 'a_valider') AS a_valider,
              -- 10/11 : « aucune réponse due » tient tant que le nombre de réponses reçues n'a pas bougé.
              (c.aucune_reponse_due_recus >= 0 AND c.aucune_reponse_due_recus = (SELECT count(*) FROM evenements e
                 WHERE e.contact_id = c.id AND e.supprime_le = '' AND e.sens = 'entrant')) AS rien_du
            FROM contacts c
            WHERE c.espace IN ('kryva', 'freelance') AND c.ne_plus_contacter = 0 AND c.supprime_le = ''
            """, [depuis, depuis, depuis])
        // Le jour de chaque message prêt, par la même règle que l'app et `pilote a-envoyer` (Libelles.jourDuMessage).
        let aujourdhui = Dates.jour.string(from: maintenant)
        var envois: [String: (jour: String, condition: Bool)] = [:]
        for m in try base.lignes("""
            SELECT e.contact_id, e.texte, e.le, e.condition, e.condition_ok_le, e.reponse_a, c.prochaine_date
            FROM evenements e JOIN contacts c ON c.id = e.contact_id
            WHERE e.statut = 'prepare' AND e.supprime_le = ''
            """) {
            let id = m["contact_id"] as? String ?? ""
            let condition = (m["condition"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let enAttente = !condition.isEmpty && (m["condition_ok_le"] as? String ?? "").isEmpty
            let jour = Libelles.jourDuMessage(texte: m["texte"] as? String ?? "", le: m["le"] as? String ?? "",
                                              dateFiche: m["prochaine_date"] as? String ?? "", aujourdhui: aujourdhui,
                                              condition: enAttente ? condition : "", reponseA: m["reponse_a"] as? String ?? "")
            if let avant = envois[id], avant.jour <= jour { continue }
            envois[id] = (jour, enAttente)
        }
        return lignes.map { l in
            let dernier = (l["dernier"] as? String ?? "").components(separatedBy: "\u{1f}")
            let id = l["id"] as? String ?? ""
            var r = ResumeContact(id: id, nom: l["nom"] as? String ?? "", entreprise: l["entreprise"] as? String ?? "",
                                  espace: l["espace"] as? String ?? "", etape: l["etape"] as? String ?? "",
                                  prochaineAction: l["prochaine_action"] as? String ?? "", prochaineDate: l["prochaine_date"] as? String ?? "",
                                  dernierLe: dernier.count == 3 ? dernier[0] : "", dernierSens: dernier.count == 3 ? dernier[1] : "",
                                  dernierCanal: dernier.count == 3 ? dernier[2] : "",
                                  partis: Self.entier(l["partis"]), aPartir: Self.entier(l["a_partir"]),
                                  echecs: Self.entier(l["echecs"]), recus: Self.entier(l["recus"]))
            r.prets = Self.entier(l["prets"])
            r.aValider = Self.entier(l["a_valider"])
            r.aucuneReponseDue = Self.entier(l["rien_du"]) == 1
            if let e = envois[id] { r.envoiLe = e.jour; r.envoiSousCondition = e.condition }
            return r
        }
    }

    static func entier(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let i = v as? Int64 { return Int(i) }
        if let d = v as? Double { return Int(d) }
        return 0
    }
}
