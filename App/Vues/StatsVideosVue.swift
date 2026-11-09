// Stats vidéos : pour chaque vidéo postée, ce qu'elle a donné à 48 h et à 7 jours, où les gens restent, ce qu'elle a fait venir,
// et le verdict de Réseaux (a marché ou non, pourquoi, leçon). Chiffres lus dans reseaux-stats/stats.sqlite, rien de recopié.
import SwiftUI

struct StatsVideosVue: View {
    @Environment(Etat.self) private var etat
    @State private var famille = "tous"        // tous | kryva | perso
    @State private var archivees = false

    private var posts: [PostVideo] {
        etat.suivi.posts.filter { (archivees || $0.visible) && (famille == "tous" || $0.famille == famille) }
    }

    private var choisi: PostVideo? { etat.suivi.posts.first { $0.id == etat.suiviSelection } }

    var body: some View {
        @Bindable var etat = etat
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $famille) {
                        Text("Toutes").tag("tous"); Text("KRYVA").tag("kryva"); Text("Perso").tag("perso")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    HStack {
                        Toggle("Archivées", isOn: $archivees).toggleStyle(.checkbox).font(.petit)
                        Spacer()
                        Text(resumeListe).font(.petit).foregroundStyle(Color.texte2)
                    }
                }
                .padding(14)
                Rectangle().fill(Color.separateur).frame(height: 0.5)
                if let e = etat.suivi.erreur {
                    EtatErreur(texte: e, reessayer: { etat.chargerSuivi(force: true) })
                    Spacer()
                } else if posts.isEmpty {
                    EtatVide(texte: "Aucune vidéo avec ce filtre.")
                    Spacer()
                } else {
                    List(selection: $etat.suiviSelection) {
                        ForEach(posts) { p in LignePost(post: p).tag(p.id) }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(width: 400)
            Rectangle().fill(Color.separateur).frame(width: 0.5)
            Group {
                if let p = choisi {
                    FichePostVue(post: p)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choisissez une vidéo").font(.titreSection).foregroundStyle(Color.texte)
                        Text("Chaque vidéo montre ses relevés à 48 h et 7 jours, où les gens restent, ce qu'elle a fait venir et le verdict de Réseaux.")
                            .font(.secondaire).foregroundStyle(Color.texte2)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .task {
            // stats.sqlite est tenu par Réseaux, hors de l'app : on regarde s'il a changé toutes les 20 secondes.
            while !Task.isCancelled {
                etat.chargerSuivi()
                if etat.suiviSelection == nil || choisi == nil { etat.suiviSelection = posts.first?.id }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private var resumeListe: String {
        let jugees = posts.filter { $0.verdict != nil }.count
        let aReleve = posts.filter { SuiviVideo.etat($0, .h48, maintenant: Date()) == .aReleve || SuiviVideo.etat($0, .j7, maintenant: Date()) == .aReleve }.count
        return "\(posts.count) vidéos · \(jugees) jugées" + (aReleve > 0 ? " · \(aReleve) à relever" : "")
    }
}

// MARK: Formats

private enum Fmt {
    static func nombre(_ n: Int?) -> String {
        guard let n else { return "—" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    static func decimal(_ d: Double) -> String { String(format: "%.1f", d).replacingOccurrences(of: ".", with: ",") }
    static func pct(_ d: Double?) -> String {
        guard let d else { return "—" }
        return (d == d.rounded() ? String(Int(d)) : decimal(d)) + " %"
    }
    static func secondes(_ d: Double?) -> String { d.map { decimal($0) + " s" } ?? "—" }
    static func jour(_ iso: String) -> String {
        let p = iso.prefix(10).split(separator: "-")
        guard p.count == 3 else { return iso }
        let heure = iso.count >= 16 ? " à " + iso.dropFirst(11).prefix(5) : ""
        return "\(p[2])/\(p[1])/\(p[0])" + heure
    }
    static func court(_ iso: String) -> String {
        let p = iso.prefix(10).split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : iso
    }
}

private func couleurVerdict(_ v: String) -> Color {
    switch v {
    case "marche": return .vert
    case "moyen": return .ambre
    case "rate": return .rouge
    default: return .texte2
    }
}

// MARK: Liste

private struct LignePost: View {
    let post: PostVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(post.titre.isEmpty ? post.ref : post.titre).font(.ligneForte).foregroundStyle(Color.texte).lineLimit(1)
                Spacer(minLength: 6)
                badge
            }
            HStack(spacing: 6) {
                Text("\(post.reseau) · \(post.compte) · \(Fmt.court(post.publieLe))").font(.petit).foregroundStyle(Color.texte2)
                Spacer(minLength: 6)
                Text(vues).font(.petit).foregroundStyle(Color.texte2)
            }
        }
        .padding(.vertical, 3)
        .opacity(post.visible ? 1 : 0.55)
    }

    private var vues: String {
        guard let v = post.dernier?.vues else { return post.releves.isEmpty ? "pas de relevé" : "vues ?" }
        return Fmt.nombre(v) + " vues"
    }

    @ViewBuilder private var badge: some View {
        let maintenant = Date()
        let e48 = SuiviVideo.etat(post, .h48, maintenant: maintenant), e7 = SuiviVideo.etat(post, .j7, maintenant: maintenant)
        if e48 == .aReleve || e7 == .aReleve {
            Pastille(texte: "À relever", couleur: .ambre)
        } else if e48 == .aJuger || e7 == .aJuger {
            Pastille(texte: "À juger", couleur: .texte2)
        } else if let v = post.verdict {
            Pastille(texte: VerdictVocabulaire.libelle(v.verdict) + " · " + v.palier, couleur: couleurVerdict(v.verdict))
        } else if post.releves.isEmpty {
            Pastille(texte: "Sans relevé", couleur: .texte3)
        } else if e48 == .manque || e7 == .manque {
            Pastille(texte: "Relevé manqué", couleur: .texte3)
        } else {
            Pastille(texte: "En attente", couleur: .texte3)
        }
    }
}

// MARK: Verdict d'un relevé

private struct VerdictPalier: View {
    let post: PostVideo
    let palier: PalierReleve

    private var titre: String { palier == .j7 ? "À 7 jours : l'analyse de fond" : "À 48 h : le premier avis" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre).font(.ligneForte).foregroundStyle(Color.texte)
            if let v = post.verdict(palier) {
                Pastille(texte: VerdictVocabulaire.libelle(v.verdict), couleur: couleurVerdict(v.verdict))
                if !v.pourquoi.isEmpty { Bloc(titre: "Pourquoi", texte: v.pourquoi) }
                if !v.lecon.isEmpty { Bloc(titre: "Leçon", texte: v.lecon) }
                if !v.analyse.isEmpty { Bloc(titre: "Analyse", texte: v.analyse) }
                Text(pied(v)).font(.petit).foregroundStyle(Color.texte3)
            } else {
                let e = SuiviVideo.etat(post, palier, maintenant: Date())
                Text(message(e)).font(.secondaire).foregroundStyle(e == .aReleve ? Color.ambre : Color.texte2)
            }
        }
    }

    private func message(_ e: EtatPalier) -> String {
        let du = Fmt.jour(SuiviVideo.ajouterHeures(post.publieLe, palier.cible)), limite = Fmt.jour(SuiviVideo.ajouterHeures(post.publieLe, palier.limite))
        switch e {
        case .aAttendre: return "Pas encore l'heure : relevé prévu le \(du)."
        case .aReleve: return "Relevé à faire maintenant (utile jusqu'au \(limite)). Réseaux écrit ensuite le verdict."
        case .aJuger: return "Relevé fait, verdict à écrire par Réseaux."
        case .manque: return "Relevé manqué : la fenêtre s'est fermée le \(limite)."
        case .fait: return ""
        }
    }

    private func pied(_ v: VerdictVideo) -> String {
        var p: [String] = []
        if !v.baseReleveLe.isEmpty { p.append("d'après le relevé du " + Fmt.jour(v.baseReleveLe)) }
        if !v.par.isEmpty { p.append("par " + v.par) }
        if !v.ecritLe.isEmpty { p.append("écrit le " + Fmt.jour(v.ecritLe)) }
        return p.joined(separator: " · ")
    }
}

// MARK: Fiche d'une vidéo

private struct FichePostVue: View {
    let post: PostVideo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                entete
                verdict
                resultats
                retention
                conversions
                tousLesReleves
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.titre.isEmpty ? post.ref : post.titre).font(.titrePage).tracking(-0.6).foregroundStyle(Color.texte)
            Text("\(post.reseau) · \(post.compte) \(post.pseudo.isEmpty ? "" : "(\(post.pseudo))") · publiée le \(Fmt.jour(post.publieLe))")
                .font(.ligne).foregroundStyle(Color.texte2)
            let infos = self.infos
            if !infos.isEmpty { Text(infos.joined(separator: " · ")).font(.secondaire).foregroundStyle(Color.texte2) }
        }
    }

    private var infos: [String] {
        var infos: [String] = []
        if !post.format.isEmpty { infos.append("Format : " + post.format) }
        if let d = post.dureeS { infos.append("Durée : " + Fmt.secondes(d)) }
        if post.promoEur > 0 { infos.append("Promo : \(Fmt.decimal(post.promoEur)) €") }
        if let s = post.sujetPlanning { infos.append("Sujet du planning : " + s) }
        if !post.visible { infos.append("Archivée ou masquée") }
        return infos
    }

    // Les verdicts d'abord : « a-t-elle marché, pourquoi, qu'est-ce qu'on retient ». Un par relevé : l'analyse de fond est celle du 7 jours.
    private var verdict: some View {
        CarteStats(titre: "Verdict") {
            VStack(alignment: .leading, spacing: 18) {
                VerdictPalier(post: post, palier: .j7)
                VerdictPalier(post: post, palier: .h48)
                if let v = post.verdictPrecoce {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lecture précoce (avant 24 h, ne compte pas pour le 48 h)").font(.ligneForte).foregroundStyle(Color.texte)
                        Pastille(texte: VerdictVocabulaire.libelle(v.verdict), couleur: couleurVerdict(v.verdict))
                        if !v.pourquoi.isEmpty { Bloc(titre: "Pourquoi", texte: v.pourquoi) }
                        if !v.baseReleveLe.isEmpty { Text("D'après le relevé du " + Fmt.jour(v.baseReleveLe)).font(.petit).foregroundStyle(Color.texte3) }
                    }
                }
            }
        }
    }

    private func tempsMoyen(_ t: Double?) -> String {
        guard let t else { return "—" }
        guard let d = post.dureeS, d > 0 else { return Fmt.secondes(t) }
        return Fmt.secondes(t) + " sur " + Fmt.secondes(d) + " (" + Fmt.pct(t / d * 100) + ")"
    }

    private var resultats: some View {
        CarteStats(titre: "Résultats") {
            HStack(alignment: .top, spacing: 14) {
                Palier(titre: "À 48 h", releve: post.releve(.h48), vide: "Pas relevé à 48 h")
                Palier(titre: "À 7 jours", releve: post.releve(.j7), vide: "Pas relevé à 7 jours")
            }
        }
    }

    // La rétention vient du dernier relevé qui la donne ; le moment où les gens décrochent n'existe que si Réseaux l'a noté (courbe du Studio).
    private var retention: some View {
        CarteStats(titre: "Où les gens restent") {
            VStack(alignment: .leading, spacing: 8) {
                if let r = post.releveRetention {
                    Ligne("Restés après 3 s", Fmt.pct(r.r3sPct))
                    Ligne("Temps moyen regardé", tempsMoyen(r.tempsMoyenS))
                    Ligne("Vue en entier", Fmt.pct(r.vueEntierPct))
                    if r.pourToiPct != nil || r.recherchePct != nil {
                        Ligne("Vient de « Pour toi » / de la recherche", "\(Fmt.pct(r.pourToiPct)) / \(Fmt.pct(r.recherchePct))")
                    }
                    Text("Relevé du \(Fmt.jour(r.releveLe)) (\(r.delaiTexte) après la publication, \(r.source)).").font(.petit).foregroundStyle(Color.texte3)
                } else {
                    Text("Pas de rétention relevée pour cette vidéo (ni 3 s, ni temps moyen, ni vue entière).").font(.secondaire).foregroundStyle(Color.texte2)
                }
                if let v = post.verdicts.first(where: { $0.decrochageS != nil }), let s = v.decrochageS {
                    Ligne("Les gens décrochent vers", Fmt.secondes(s))
                    if !v.decrochageNote.isEmpty { Text(v.decrochageNote).font(.secondaire).foregroundStyle(Color.texte2) }
                } else {
                    Text("Moment du décrochage : pas relevé (la courbe du Studio n'est pas dans les chiffres).").font(.petit).foregroundStyle(Color.texte3)
                }
            }
        }
    }

    private var conversions: some View {
        CarteStats(titre: "Ce que ça a fait venir") {
            VStack(alignment: .leading, spacing: 8) {
                if post.conversions.isEmpty {
                    Text("Pas encore de relevé de conversions pour la période de cette vidéo.").font(.secondaire).foregroundStyle(Color.texte2)
                } else {
                    ForEach(post.conversions, id: \.source) { c in
                        Ligne(c.source == ConversionLigne.total ? "Toutes visites du lien suivi" : "Clics, source « \(c.source) »",
                              [c.clics.map { Fmt.nombre($0) + " visites" }, c.inscriptions.map { Fmt.nombre($0) + " inscrits" }]
                                .compactMap { $0 }.joined(separator: " · ").nonVide("—"))
                        Text("période \(c.periode)").font(.petit).foregroundStyle(Color.texte3)
                    }
                }
                Text("Par réseau et par période, pas par vidéo : le lien est le même pour toutes les vidéos du réseau. Pour compter une vidéo seule, il faudrait un lien à elle.")
                    .font(.petit).foregroundStyle(Color.texte3)
            }
        }
    }

    private var tousLesReleves: some View {
        CarteStats(titre: "Tous les relevés (\(post.releves.count))") {
            if post.releves.isEmpty {
                Text("Aucun relevé.").font(.secondaire).foregroundStyle(Color.texte2)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        titreColonne("Après").gridColumnAlignment(.leading); titreColonne("Vues"); titreColonne("J'aime"); titreColonne("Comm."); titreColonne("Partages"); titreColonne("Enreg.")
                        titreColonne("Temps moy."); titreColonne("3 s"); titreColonne("Entière"); titreColonne("Abonnés")
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(post.releves.enumerated()), id: \.offset) { _, r in
                        GridRow {
                            Text("\(r.delaiTexte) · \(Fmt.court(r.releveLe))").foregroundStyle(Color.texte).gridColumnAlignment(.leading)
                            Text(Fmt.nombre(r.vues)); Text(Fmt.nombre(r.likes)); Text(Fmt.nombre(r.commentaires)); Text(Fmt.nombre(r.partages))
                            Text(Fmt.nombre(r.enregistrements)); Text(Fmt.secondes(r.tempsMoyenS)); Text(Fmt.pct(r.r3sPct))
                            Text(Fmt.pct(r.vueEntierPct)); Text(Fmt.nombre(r.abonnesGagnes))
                        }
                        .font(.petit).foregroundStyle(Color.texte2)
                    }
                }
            }
        }
    }

    private func titreColonne(_ t: String) -> some View { Text(t).font(.petit.weight(.semibold)).foregroundStyle(Color.texte3) }
}

// MARK: Petits blocs

private struct CarteStats<Contenu: View>: View {
    let titre: String
    @ViewBuilder var contenu: () -> Contenu
    init(titre: String, @ViewBuilder _ contenu: @escaping () -> Contenu) { self.titre = titre; self.contenu = contenu }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titre).font(.titreSection).foregroundStyle(Color.texte)
            contenu()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.separateur, lineWidth: 0.5))
    }
}

private struct Bloc: View {
    let titre: String
    let texte: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(.petit.weight(.semibold)).foregroundStyle(Color.texte3)
            Text(texte).font(.ligne).foregroundStyle(Color.texte).textSelection(.enabled)
        }
    }
}

private struct Ligne: View {
    let libelle: String
    let valeur: String
    init(_ libelle: String, _ valeur: String) { self.libelle = libelle; self.valeur = valeur }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(libelle).font(.secondaire).foregroundStyle(Color.texte2)
            Spacer(minLength: 12)
            Text(valeur).font(.ligneForte).foregroundStyle(Color.texte)
        }
    }
}

private struct Palier: View {
    let titre: String
    let releve: ReleveVideo?
    let vide: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre).font(.petit.weight(.semibold)).foregroundStyle(Color.texte3)
            if let r = releve {
                Text(Fmt.nombre(r.vues) + " vues").font(.titreSection).foregroundStyle(Color.texte)
                Text("\(Fmt.nombre(r.likes)) j'aime · \(Fmt.nombre(r.commentaires)) comm. · \(Fmt.nombre(r.partages)) partages · \(Fmt.nombre(r.enregistrements)) enreg.")
                    .font(.secondaire).foregroundStyle(Color.texte2)
                Text("\(Fmt.nombre(r.abonnesGagnes)) abonnés gagnés").font(.secondaire).foregroundStyle(Color.texte2)
                Text("relevé \(r.delaiTexte) après, \(Fmt.court(r.releveLe))").font(.petit).foregroundStyle(Color.texte3)
            } else {
                Text(vide).font(.secondaire).foregroundStyle(Color.texte2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fond, in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension String {
    func nonVide(_ autre: String) -> String { isEmpty ? autre : self }
}
