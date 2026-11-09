// Les vidéos (03/11, Sacha) : la semaine en un coup d'œil, lundi à vendredi, une ligne KRYVA et une ligne perso.
// Chaque case dit un mot et une couleur : vert = prête ou publiée, ambre = à faire aujourd'hui, rouge = en retard.
import SwiftUI

enum JourAffiche {
    private static func format(_ motif: String, _ jour: String, majuscule: Bool = true) -> String {
        guard let d = Dates.jour.date(from: jour) else { return jour }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = motif
        let s = f.string(from: d)
        return majuscule ? s.prefix(1).uppercased() + s.dropFirst() : s
    }
    /// « Lun. 3 »
    static func entete(_ jour: String) -> String { format("EEE d", jour) }
    /// « Lundi 3 novembre »
    static func long(_ jour: String, majuscule: Bool = true) -> String { format("EEEE d MMMM", jour, majuscule: majuscule) }
}

struct SemaineVue: View {
    @Environment(Etat.self) private var etat
    @State private var reference = Dates.aujourdhui()

    private var jours: [String] { VideoCalcul.semaine(de: reference) }
    private var aujourdhui: String { Dates.aujourdhui() }
    private var cetteSemaine: Bool { jours == VideoCalcul.semaine(de: aujourdhui) }

    private var bilan: String {
        let vids = etat.videos.filter { jours.contains($0.jour) }
        let publiees = vids.filter { $0.statut == "publiee" }.count
        let pretes = vids.filter { $0.statut == "prete" }.count
        let sujets = vids.filter { $0.statut != "a_choisir" && $0.statut != "annulee" }.count
        return "\(publiees) publiées · \(pretes) prêtes · \(sujets) sujets validés sur 10"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnTete(titre: "Vidéos", detail: "2 par jour du lundi au vendredi, tournées et montées la veille")
                navigation
                grille
                legende
                reserve
            }
            .padding(28)
        }
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            Button { reference = VideoCalcul.decalerSemaine(reference, -1) } label: { Image(systemName: "chevron.left") }
            Text("Semaine du \(jours.first.map { JourAffiche.long($0, majuscule: false) } ?? "")").font(.titreSection).foregroundStyle(Color.texte)
            Button { reference = VideoCalcul.decalerSemaine(reference, 1) } label: { Image(systemName: "chevron.right") }
            if !cetteSemaine {
                Button("Cette semaine") { reference = aujourdhui }.buttonStyle(.link)
            }
            Spacer()
            Text(bilan).font(.secondaire).foregroundStyle(Color.texte2)
            Button { etat.ecran = .stats } label: { Label("Stats des vidéos postées", systemImage: "chart.bar") }.buttonStyle(.link)
        }
    }

    private var grille: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Color.clear.frame(width: 64, height: 1)
                ForEach(jours, id: \.self) { j in
                    Text(JourAffiche.entete(j))
                        .font(.secondaire.weight(j == aujourdhui ? .bold : .semibold))
                        .foregroundStyle(j == aujourdhui ? Color.action : Color.texte2)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(VideoVocabulaire.comptes, id: \.0) { compte in
                GridRow {
                    Text(compte.1).font(.ligneForte).foregroundStyle(Color.texte).frame(width: 64, alignment: .leading)
                    ForEach(jours, id: \.self) { j in TuileVideo(jour: j, compte: compte.0, compacte: true) }
                }
            }
        }
    }

    private var legende: some View {
        HStack(spacing: 16) {
            ForEach([(TonVideo.vert, "Prête ou publiée"), (.ambre, "À faire aujourd'hui"), (.rouge, "En retard ou sans sujet"), (.neutre, "Plus tard")], id: \.1) { t in
                HStack(spacing: 6) {
                    Circle().fill(Couleurs.ton(t.0)).frame(width: 9, height: 9)
                    Text(t.1).font(.petit).foregroundStyle(Color.texte2)
                }
            }
            Spacer()
            Text("Cliquer une case pour la détailler").font(.petit).foregroundStyle(Color.texte3)
        }
    }

    private var reserve: some View {
        let sujets = etat.videos.filter { $0.jour.isEmpty && $0.statut != "annulee" }
        return Carte(titre: "Sujets de réserve", detail: "si un sujet tombe") {
            if sujets.isEmpty {
                EtatVide(texte: "Aucun sujet de réserve. Il en faut un par compte, choisi le dimanche.")
            } else {
                ForEach(Array(sujets.enumerated()), id: \.element.id) { i, v in
                    LigneCarte(dernier: i == sujets.count - 1) {
                        HStack(spacing: 10) {
                            Pastille(texte: VideoVocabulaire.compte(v.compte), couleur: .texte2)
                            Text(v.sujet).font(.ligne).foregroundStyle(Color.texte)
                            Spacer()
                            if !v.fiche.isEmpty { Button("Fiche") { etat.montrer(v.fiche) }.controlSize(.small) }
                        }
                    }
                }
            }
        }
    }
}

/// Une vidéo d'un jour et d'un compte : le mot et la couleur de son état, le sujet, et le bouton de l'étape suivante.
struct TuileVideo: View {
    @Environment(Etat.self) private var etat
    let jour: String
    let compte: String
    var compacte = false
    @State private var detail = false

    var body: some View {
        let v = etat.video(jour: jour, compte: compte)
        let a = VideoCalcul.affichage(v, jour: jour, aujourdhui: Dates.aujourdhui())
        let couleur = Couleurs.ton(a.ton)
        let sujet = v?.sujet ?? ""
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !compacte {
                    Text(VideoVocabulaire.compte(compte).uppercased()).font(.petit.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Color.texte2)
                }
                Pastille(texte: a.texte, couleur: couleur)
                Spacer(minLength: 0)
                if let h = v?.heure, !h.isEmpty, !compacte { Text(h).font(.petit.monospacedDigit()).foregroundStyle(Color.texte3) }
            }
            Text(sujet.isEmpty ? "Pas de sujet" : sujet)
                .font(compacte ? .secondaire.weight(.medium) : .ligneForte)
                .foregroundStyle(sujet.isEmpty ? Color.texte3 : Color.texte)
                .lineLimit(compacte ? 3 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if !compacte, let v { boutons(v) }
        }
        .padding(compacte ? 10 : 12)
        .frame(maxWidth: .infinity, minHeight: compacte ? 96 : 128, alignment: .topLeading)
        .background(couleur.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(couleur.opacity(0.35), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { detail = true }
        .popover(isPresented: $detail, arrowEdge: .bottom) { DetailVideo(jour: jour, compte: compte) }
        .help("Cliquer pour détailler")
    }

    @ViewBuilder
    private func boutons(_ v: Video) -> some View {
        HStack(spacing: 6) {
            switch v.statut {
            case "valide": Button("Tournée") { etat.changerVideo(jour: jour, compte: compte, statut: "tournee") }
            case "tournee": Button("Prête") { etat.changerVideo(jour: jour, compte: compte, statut: "prete") }
            case "prete": Button("Publiée") { etat.changerVideo(jour: jour, compte: compte, statut: "publiee") }
            default: EmptyView()
            }
            if !v.prompteur.isEmpty { Button("Prompteur") { etat.ouvrirChemin(v.prompteur) } }
            if !v.fiche.isEmpty { Button("Fiche") { etat.montrer(v.fiche) } }
        }
        .controlSize(.small)
    }
}

/// Le détail d'une case : le sujet (modifiable), l'état, le jour du tournage, le prompteur et la fiche.
struct DetailVideo: View {
    @Environment(Etat.self) private var etat
    let jour: String
    let compte: String
    @State private var sujet = ""

    var body: some View {
        let v = etat.video(jour: jour, compte: compte)
        VStack(alignment: .leading, spacing: 12) {
            Text("\(VideoVocabulaire.compte(compte)) · \(JourAffiche.long(jour))").font(.titreSection).foregroundStyle(Color.texte)
            TextField("Sujet", text: $sujet, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...4)
                .onSubmit { enregistrerSujet(v) }
            Picker("État", selection: Binding(get: { v?.statut ?? "a_choisir" },
                                              set: { etat.changerVideo(jour: jour, compte: compte, statut: $0) })) {
                ForEach(VideoVocabulaire.statuts, id: \.0) { Text($0.1).tag($0.0) }
            }
            Text("Tournage et montage : \(JourAffiche.long(VideoCalcul.veilleOuvree(jour), majuscule: false))\(v.map { $0.heure.isEmpty ? "" : " · publication à \($0.heure)" } ?? "")")
                .font(.secondaire).foregroundStyle(Color.texte2)
            if let v, !v.notes.isEmpty {
                Text(v.notes).font(.secondaire).foregroundStyle(Color.texte2).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if let p = v?.prompteur, !p.isEmpty { Button("Ouvrir le prompteur") { etat.ouvrirChemin(p) } }
                if let f = v?.fiche, !f.isEmpty { Button("Lire la fiche") { etat.montrer(f) } }
                Spacer()
                if sujet != (v?.sujet ?? "") { Button("Enregistrer le sujet") { enregistrerSujet(v) }.buttonStyle(.borderedProminent).tint(.action) }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { sujet = v?.sujet ?? "" }
    }

    private func enregistrerSujet(_ v: Video?) {
        let propre = sujet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard propre != (v?.sujet ?? "") else { return }
        etat.enregistrer(video: ["jour": jour, "compte": compte, "sujet": propre])
    }
}
