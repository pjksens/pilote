// Le Radar : posts des comptes suivis classés par ratio (vues ÷ médiane des autres posts du compte), Top 3 des pistes,
// boîte à idées. Les chiffres viennent de Shared/Radar.swift (testé) ; cet écran ne calcule rien.
import SwiftUI

private enum Onglet: String, CaseIterable, Identifiable {
    case classement = "Classement", idees = "Boîte à idées"
    var id: String { rawValue }
}

private func nombre(_ n: Int?) -> String {
    guard let n else { return "inconnu" }
    return n.formatted(.number.locale(Locale(identifier: "fr_FR")))
}

func decimal(_ x: Double, _ chiffres: Int = 1) -> String {
    x.formatted(.number.precision(.fractionLength(chiffres)).locale(Locale(identifier: "fr_FR")))
}

func libelleEspaceRadar(_ e: String) -> String { e == "kryva" ? "KRYVA" : "Perso" }

private func libelleAge(_ heures: Double) -> String { "\(Int(heures.rounded())) h" }

private func ilYa(_ iso: String?) -> String? {
    guard let iso, let d = Dates.iso.date(from: iso) else { return nil }
    let h = Date().timeIntervalSince(d) / 3600
    return h < 1 ? "il y a moins d'une heure" : (h < 48 ? "il y a \(Int(h)) h" : "il y a \(Int(h / 24)) jours")
}

struct RadarVue: View {
    @Environment(Etat.self) private var etat
    @Environment(\.dismiss) private var fermer
    @State private var espace = "kryva"
    @State private var fenetre = 72.0
    @State private var onglet = Onglet.classement
    @State private var classement: RadarClassement?
    @State private var idees: [RadarIdee] = []
    @State private var erreur: String?
    @State private var ecartesOuverts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                EnTete(titre: "Radar", detail: detail)
                Button("Fermer") { fermer() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 16) {
                Picker("Espace", selection: $espace) {
                    ForEach(RadarVocabulaire.espaces, id: \.self) { Text(libelleEspaceRadar($0)).tag($0) }
                }.pickerStyle(.segmented).frame(width: 190).labelsHidden()
                Picker("Onglet", selection: $onglet) {
                    ForEach(Onglet.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 260).labelsHidden()
                if onglet == .classement {
                    Picker("Fenêtre", selection: $fenetre) {
                        Text("24 h").tag(24.0); Text("48 h").tag(48.0); Text("72 h").tag(72.0)
                    }.pickerStyle(.segmented).frame(width: 190).labelsHidden()
                }
                Spacer()
            }
            if let erreur { EtatErreur(texte: erreur) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if onglet == .classement { vueClassement } else { vueIdees }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 640)
        .background(Color.fond)
        .task(id: "\(espace)-\(fenetre)-\(etat.revision)") { recharger() }
    }

    private var detail: String {
        var p = ["Ratio = vues ÷ médiane des autres posts du compte"]
        if let c = classement, let d = ilYa(c.dernierReleve) { p.append("dernier relevé \(d)") }
        return p.joined(separator: " · ")
    }

    private func recharger() {
        guard let stock = etat.stock else { return }
        do {
            classement = try stock.radarClassement(espace: espace, fenetre: RadarCalcul.fenetreParDefaut.lowerBound...fenetre)
            idees = try stock.radarIdees(espace: espace)
            erreur = nil
        } catch { erreur = "Lecture du Radar impossible : \(error)" }
    }

    // MARK: Classement

    @ViewBuilder private var vueClassement: some View {
        if let c = classement {
            ForEach(c.avertissements, id: \.self) { a in
                Label(a, systemImage: "exclamationmark.triangle").font(.secondaire).foregroundStyle(Color.ambre)
            }
            Carte(titre: "Pistes du moment", detail: "ratio au-dessus de 1, 3 au plus") {
                if c.top.isEmpty {
                    EtatVide(texte: c.classement.isEmpty
                        ? "Rien à classer pour l'instant : il faut des posts de 6 à \(Int(fenetre)) h avec au moins 5 autres posts du compte sur 30 jours."
                        : "Aucun post ne dépasse l'habitude de son compte. Le Top n'est pas rempli pour faire joli.")
                }
                ForEach(Array(c.top.enumerated()), id: \.element.id) { i, l in
                    LigneCarte(dernier: i == c.top.count - 1) { LigneRadar(ligne: l, enregistrer: { garder(l) }) }
                }
            }
            let autres = c.classement.filter { $0.rang == nil }
            if !autres.isEmpty {
                Carte(titre: "Classement", detail: "\(c.classement.count) posts avec un ratio") {
                    ForEach(Array(autres.enumerated()), id: \.element.id) { i, l in
                        LigneCarte(dernier: i == autres.count - 1) { LigneRadar(ligne: l, enregistrer: { garder(l) }) }
                    }
                }
            }
            if !c.ecartes.isEmpty {
                DisclosureGroup(isExpanded: $ecartesOuverts) {
                    VStack(spacing: 0) {
                        ForEach(Array(c.ecartes.enumerated()), id: \.element.id) { i, l in
                            LigneCarte(dernier: i == c.ecartes.count - 1) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("@\(l.createur) · \(l.plateforme == "tiktok" ? "TikTok" : "Instagram")").font(.secondaire).foregroundStyle(Color.texte)
                                    Text(l.legende.isEmpty ? l.postId : l.legende).font(.secondaire).foregroundStyle(Color.texte3).lineLimit(1)
                                    Spacer()
                                    Text(l.raison ?? "").font(.petit).foregroundStyle(Color.texte2)
                                }
                            }
                        }
                    }
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } label: {
                    Text("Écartés · \(c.ecartes.count)").font(.titreSection).foregroundStyle(Color.texte)
                }
            }
        } else {
            EtatChargement(texte: "Lecture du Radar")
        }
    }

    private func garder(_ l: RadarLigne) {
        guard let stock = etat.stock else { return }
        do { _ = try stock.radarEnregistreIdee(postId: l.postId, espace: espace, simulation: classement?.simulation ?? false); etat.charger() }
        catch { erreur = "\(error)" }
    }

    // MARK: Boîte à idées

    @ViewBuilder private var vueIdees: some View {
        if idees.isEmpty {
            Carte(titre: "Boîte à idées") {
                EtatVide(texte: "Aucune idée gardée pour \(libelleEspaceRadar(espace)). Dans le classement, « Garder l'idée » fige le post (lien, chiffres, ratio) et ouvre votre brouillon ici.")
            }
        }
        ForEach(idees) { i in
            FicheIdee(idee: i, erreur: $erreur)
        }
    }
}

/// Un post classé : rang, compte, légende, ratio, chiffres, et le geste « Garder l'idée ».
private struct LigneRadar: View {
    let ligne: RadarLigne
    let enregistrer: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let r = ligne.rang { Pastille(texte: "n° \(r)", couleur: .action).frame(width: 52, alignment: .leading) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("@\(ligne.createur)").font(.ligneForte).foregroundStyle(Color.texte)
                    Text(ligne.plateforme == "tiktok" ? "TikTok" : "Instagram").font(.petit).foregroundStyle(Color.texte3)
                }
                Text(ligne.legende.isEmpty ? ligne.postId : ligne.legende).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(2)
                Text(chiffres).font(.petit).foregroundStyle(Color.texte3)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ligne.ratio.map { "×\(decimal($0))" } ?? "—").font(.titreSection).foregroundStyle(ligne.piste ? Color.vert : Color.texte2)
                Text("médiane \(nombre(ligne.mediane.map { Int($0.rounded()) }))").font(.petit).foregroundStyle(Color.texte3)
            }
            .frame(minWidth: 110, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 6) {
                if ligne.ideeId != nil {
                    Pastille(texte: "Dans la boîte", couleur: .vert)
                } else {
                    Button("Garder l'idée", action: enregistrer).buttonStyle(.borderedProminent).tint(.action).controlSize(.small)
                }
                if let u = URL(string: ligne.url), !ligne.url.isEmpty {
                    Link("Voir le post", destination: u).font(.petit)
                }
            }
            .frame(minWidth: 112, alignment: .trailing)
        }
    }

    private var chiffres: String {
        var p = ["\(nombre(ligne.vues)) vues", "publié il y a \(libelleAge(ligne.ageHeures)) au relevé"]
        if let v = ligne.vuesParHeure { p.append("\(nombre(Int(v.rounded()))) vues/h") }
        if let l = ligne.likesPour1000Vues { p.append("\(decimal(l, 0)) j'aime / 1 000 vues") }
        p.append("\(ligne.references) posts de référence")
        if ligne.source != "manuelle" { p.append("source : \(ligne.source)") }
        return p.joined(separator: " · ")
    }
}

/// Une idée : la source figée (ne bouge plus) au-dessus, notre version (brouillon vivant) en dessous.
private struct FicheIdee: View {
    let idee: RadarIdee
    @Binding var erreur: String?
    @Environment(Etat.self) private var etat
    @State private var brouillon = ""
    @State private var statut = "a_ecrire"
    @State private var revisionLue = -1

    private static let statuts: [(String, String)] = [("a_ecrire", "À écrire"), ("en_cours", "En cours"), ("pret", "Prêt à tourner")]
    private var modifie: Bool { brouillon != idee.brouillon || statut != idee.statut }

    var body: some View {
        Carte(titre: "@\(idee.sourceFigee.createur)", detail: idee.concept.isEmpty ? nil : idee.concept) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Source figée le \(idee.creeLe.prefix(10))").font(.petit.weight(.semibold)).foregroundStyle(Color.texte3)
                    if !idee.sourceFigee.legende.isEmpty { Text(idee.sourceFigee.legende).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(3) }
                    Text("\(nombre(idee.sourceFigee.vues)) vues · ratio \(idee.sourceFigee.ratio.map { "×" + decimal($0) } ?? "inconnu") · \(idee.sourceFigee.references) posts de référence")
                        .font(.petit).foregroundStyle(Color.texte3)
                    if let u = URL(string: idee.sourceFigee.url), !idee.sourceFigee.url.isEmpty { Link("Voir le post", destination: u).font(.petit) }
                }
                Text("Notre version").font(.petit.weight(.semibold)).foregroundStyle(Color.texte3)
                TextEditor(text: $brouillon)
                    .font(.secondaire).frame(minHeight: 90).scrollContentBackground(.hidden)
                    .padding(6).background(Color.fond, in: RoundedRectangle(cornerRadius: 8))
                if revisionLue != idee.revision {
                    HStack {
                        Label("Cette idée a changé ailleurs pendant votre saisie.", systemImage: "exclamationmark.triangle")
                            .font(.secondaire).foregroundStyle(Color.ambre)
                        Spacer()
                        Button("Relire la version enregistrée") { charger() }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                HStack {
                    Picker("Statut", selection: $statut) {
                        ForEach(Self.statuts, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.segmented).frame(width: 300).labelsHidden()
                    Spacer()
                    Button("Enregistrer ma version") { enregistrer() }
                        .buttonStyle(.borderedProminent).tint(.action).disabled(!modifie)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .onAppear { charger() }
        // Une autre session a écrit : sans modification en cours on se met à jour ; sinon on garde la saisie et on propose de relire.
        .onChange(of: idee.revision) { _, _ in if !modifie { charger() } }
    }

    private func charger() {
        brouillon = idee.brouillon
        statut = idee.statut
        revisionLue = idee.revision
    }

    private func enregistrer() {
        guard let stock = etat.stock else { return }
        do {
            _ = try stock.radarEcritIdee(id: idee.id, brouillon: brouillon, statut: statut, revision: revisionLue)
            erreur = nil
            etat.charger()
        } catch {
            // Conflit : une autre session a écrit entre-temps. On ne remplace rien, on le dit.
            erreur = "\(error)"
        }
    }
}

/// La carte d'Aujourd'hui : le Top 3 de chaque espace, et le chemin vers l'écran complet.
struct CarteRadar: View {
    @Environment(Etat.self) private var etat

    private var aDesDonnees: Bool { etat.radar.contains { $0.nbPosts > 0 } }

    /// Premier relevé de la session Réseaux : jeudi 29/10/2026 à 10 h (heure de Paris).
    private static let premierReleve = Date(timeIntervalSince1970: 1_793_264_400)

    var body: some View {
        if aDesDonnees { carte } else { carteCourte }
    }

    /// Sans relevé, la carte reste là (sinon le Radar passe pour absent) : une ligne, et un clic qui ouvre l'écran complet.
    private var carteCourte: some View {
        Carte(titre: "Radar") {
            Button { etat.radarOuvert = true } label: {
                HStack {
                    Text(Date() < Self.premierReleve ? "Premier relevé jeudi 29/10 vers 10 h" : "En attente du premier relevé")
                        .font(.ligne).foregroundStyle(Color.texte2)
                    Spacer()
                    Image(systemName: "chevron.right").font(.petit).foregroundStyle(Color.texte3)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre le Radar")
        }
    }

    private var carte: some View {
        Carte(titre: "Radar", detail: "pistes du moment : posts au-dessus de l'habitude de leur compte") {
            ForEach(etat.radar, id: \.espace) { c in
                if c.nbPosts > 0 {
                    Text("\(libelleEspaceRadar(c.espace)) · \(c.top.count)").font(.secondaire.weight(.semibold)).foregroundStyle(Color.texte2)
                        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                    if c.top.isEmpty { EtatVide(texte: c.avertissements.first ?? "Aucun post au-dessus de l'habitude de son compte.") }
                    ForEach(Array(c.top.enumerated()), id: \.element.id) { i, l in
                        LigneCarte(dernier: i == c.top.count - 1) {
                            HStack {
                                Pastille(texte: "n° \(l.rang ?? i + 1)", couleur: .action).frame(width: 52, alignment: .leading)
                                Text("@\(l.createur)").font(.ligneForte).foregroundStyle(Color.texte)
                                Text(l.legende).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(1)
                                Spacer()
                                Text("×\(decimal(l.ratio ?? 0))").font(.ligneForte).foregroundStyle(Color.vert)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Ouvrir le Radar") { etat.radarOuvert = true }.buttonStyle(.bordered)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}
