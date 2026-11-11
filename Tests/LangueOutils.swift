// Outils des tests de langue : détecter du français dans une sortie anglaise ou espagnole.
import XCTest

/// Les mots français (entiers, insensible à la casse) qu'un texte anglais ou espagnol contient : vide = rien de français.
/// `donnees` : des morceaux à ignorer d'abord (les données d'exemple françaises que la sortie recopie : titre, légende, nom…).
/// Les mots communs au français et à l'espagnol (la, de, en, un, que, se…) ne comptent que pour l'anglais.
func ContientDuFrancais(_ texte: String, langue: String = "en", donnees: [String] = []) -> [String] {
    var t = texte
    for d in donnees where !d.isEmpty { t = t.replacingOccurrences(of: d, with: " ") }
    let communsFrancais: Set<String> = [
        "du", "des", "une", "et", "ou", "où", "à", "pour", "avec", "dans", "est", "pas", "qui", "sur", "sans", "mais", "vous",
        "votre", "vos", "nous", "notre", "ne", "cette", "ces", "il", "elle", "ils", "elles", "aux", "au", "ses", "sa", "après",
        "avant", "depuis", "chez", "très", "aussi", "encore", "déjà", "rien", "tous", "toutes", "jours", "jour", "heure", "heures",
        "vues", "vidéo", "vidéos", "relevé", "relevés", "idée", "sujet", "sujets", "compte", "comptes",
    ]
    let enPlus: Set<String> = ["le", "la", "les", "de", "un", "que", "en", "par", "se", "son", "plus", "moins"]
    let interdits = langue == "en" ? communsFrancais.union(enPlus) : communsFrancais
    let lettresFrancaises = CharacterSet(charactersIn: "çèêôûœùëïà")
    var trouves: [String] = []
    for mot in t.lowercased().components(separatedBy: CharacterSet.letters.inverted) where !mot.isEmpty {
        if interdits.contains(mot) || mot.unicodeScalars.contains(where: { lettresFrancaises.contains($0) }) { trouves.append(mot) }
    }
    return trouves
}

/// Alias pour les tests de contacts et envois, qui nomment le paramètre `ignorer` (même sens que `donnees`).
func ContientDuFrancais(_ texte: String, langue: String = "en", ignorer: [String]) -> [String] {
    ContientDuFrancais(texte, langue: langue, donnees: ignorer)
}

// --- Détecteur à liste de mots (chantier écran unique et agents) ---


/// Cherche des mots français dans un texte. Mots entiers, sans tenir compte de la casse. La liste ne garde que des mots français
/// qui n'existent ni en anglais ni en espagnol (pas « de », « la », « en », « on », « plus », « non », « sur », « par »…), pour ne
/// pas accuser une traduction juste ; elle attrape donc l'essentiel d'une phrase oubliée, pas chaque mot isolé.
/// Les apostrophes coupent les mots : « aujourd'hui » donne « aujourd » et « hui », « n'est » donne « est ».
enum MotsFrancais {
    static let motsVides: Set<String> = [
        // petits mots
        "des", "du", "à", "pour", "avec", "dans", "est", "sont", "pas", "sans", "mais", "ou", "où", "qui", "quoi", "quand",
        "pourquoi", "toi", "moi", "ton", "tes", "ses", "vos", "votre", "vous", "nous", "cette", "ces", "aux", "chez", "être",
        "avoir", "très", "rien", "aucun", "aucune", "une", "elle", "ils", "oui", "donc", "puis", "aussi", "encore", "déjà",
        "toujours", "seulement", "avant", "après", "ici", "là", "ça", "deux", "trois",
        // temps
        "retard", "aujourd", "hui", "demain", "hier", "depuis", "jour", "jours", "semaine", "heure", "heures", "dernier",
        "dernière", "prochain", "prochaine",
        // le vocabulaire de l'écran unique
        "faire", "fait", "faits", "faite", "faites", "texte", "textes", "ligne", "lignes", "fiche", "fiches", "envoi", "envois",
        "réponse", "réponses", "reçue", "reçues", "reçu", "prêt", "prêts", "prête", "prévu", "prévue", "problème", "problèmes",
        "traité", "traitée", "traitées", "traités", "validé", "validée", "attente", "attendent", "reprend", "travaille",
        "réseaux", "ventes", "papiers", "domaine", "domaines", "parti", "partis", "envoyé", "envoyée", "relancer", "relance",
        "écrire", "écris", "ouvrir", "voir", "tout", "tous", "toutes",
    ]

    /// Les mots français trouvés dans `texte`, dans l'ordre, sans doublon. `hors` : des morceaux volontairement français (nom
    /// d'une personne, titre d'une carte d'exemple, texte écrit par une session) qu'on retire avant de chercher.
    static func mots(dans texte: String, hors exclusions: [String] = []) -> [String] {
        var t = texte
        for e in exclusions where !e.isEmpty { t = t.replacingOccurrences(of: e, with: " ", options: .caseInsensitive) }
        var trouves: [String] = []
        for mot in t.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init) where motsVides.contains(mot) {
            if !trouves.contains(mot) { trouves.append(mot) }
        }
        return trouves
    }

    static func contient(_ texte: String, hors exclusions: [String] = []) -> Bool {
        !mots(dans: texte, hors: exclusions).isEmpty
    }
}

/// Échoue pour chaque texte qui garde un mot français (voir `MotsFrancais`).
func XCTAssertSansFrancais(_ textes: [String], hors exclusions: [String] = [], _ contexte: @autoclosure () -> String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    for t in textes {
        let restes = MotsFrancais.mots(dans: t, hors: exclusions)
        XCTAssertTrue(restes.isEmpty, "\(contexte()) mots français \(restes) dans « \(t) »", file: file, line: line)
    }
}
