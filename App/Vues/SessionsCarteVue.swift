// Vos sessions (03/11, Sacha : « je dois voir ce qu'ils font, où ils en sont sur la tâche posée… je dois tout voir
// depuis Pilote ») : chaque session de l'équipe, sa demande, l'étape de sa liste de tâches, ce qu'elle a écrit en
// dernier (sa réponse, sa question), et un champ pour lui écrire. Le message part tout de suite (Facteur ou veille).
import SwiftUI

struct CarteVosSessions: View {
    @Environment(Etat.self) private var etat

    /// PILOTE, les têtes de domaine (même hors ligne), puis les chantiers en ligne ; qui attend Sacha d'abord.
    private var noeuds: [NoeudPyramide] {
        let p = etat.pyramide
        let fixes = (p.pilote.map { [$0] } ?? []) + p.colonnes.compactMap(\.tete)
        let chantiers = p.colonnes.flatMap(\.chantiers).filter(\.enLigne) + p.horsCarte.filter(\.enLigne)
        func rang(_ n: NoeudPyramide) -> Int {
            switch n.activite?.etat { case "waiting"?: return 0; case "busy"?: return 1; case .some: return 2; case nil: return 3 }
        }
        return (fixes + chantiers).enumerated().sorted { (rang($0.element), $0.offset) < (rang($1.element), $1.offset) }.map(\.element)
    }

    var body: some View {
        let liste = noeuds
        let attendent = liste.filter { $0.activite?.etat == "waiting" }.count
        let travaillent = liste.filter { $0.activite?.etat == "busy" }.count
        Carte(titre: "Vos sessions", detail: "\(travaillent) au travail · \(attendent) vous attend\(attendent > 1 ? "ent" : "")") {
            if !etat.pyramideChargee {
                EtatChargement(texte: "Lecture des sessions…")
            } else if liste.isEmpty {
                EtatVide(texte: "Aucune session de l'équipe trouvée (EQUIPE.md).")
            } else {
                ForEach(Array(liste.enumerated()), id: \.element.id) { i, n in
                    LigneCarte(dernier: i == liste.count - 1) { LigneSessionEquipe(noeud: n) }
                }
            }
        }
    }
}

struct LigneSessionEquipe: View {
    @Environment(Etat.self) private var etat
    let noeud: NoeudPyramide

    @State private var ouvert = false
    @State private var ecrire = false
    @State private var brouillon = ""
    @State private var erreur: String?

    private var a: ActiviteSession? { noeud.activite }
    private var idApp: String { a?.sessionApp.isEmpty == false ? a!.sessionApp : noeud.membre.sessionApp }
    private var mesMessages: [Facteur.Message] {
        etat.messagesSessions.filter { $0.session == idApp || (!noeud.membre.nom.isEmpty && $0.pour == noeud.membre.nom) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            entete
            if let a {
                if !a.demande.isEmpty {
                    Text("Demande : \(a.demande)").font(.secondaire).foregroundStyle(Color.texte2).lineLimit(ouvert ? 8 : 2)
                }
                avancement(a)
                let dit = a.recap.isEmpty ? a.dernierTexte : a.recap
                if !dit.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.etat == "waiting" ? "Ce qu'elle vous dit" : "Où elle en est").font(.petit.weight(.semibold))
                            .foregroundStyle(a.etat == "waiting" ? Color.ambre : Color.texte2)
                        Text(LectureMarkdown.enLigne(ouvert && !a.dernierTexte.isEmpty ? a.dernierTexte : dit))
                            .font(.secondaire).foregroundStyle(Color.texte).lineLimit(ouvert ? nil : 3)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if ouvert { detail(a) }
            } else {
                Text("Hors ligne : la session n'est pas ouverte dans l'app Claude.").font(.secondaire).foregroundStyle(Color.texte3)
            }
            if !mesMessages.isEmpty { messages }
            if ecrire { champ }
        }
    }

    private var entete: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(couleur).frame(width: 8, height: 8)
            Text(noeud.membre.nom).font(.ligneForte).foregroundStyle(Color.texte).lineLimit(1)
            Text(a?.libelleEtat ?? "Hors ligne").font(.petit.weight(.medium)).foregroundStyle(a?.etat == "waiting" ? Color.ambre : Color.texte2)
            if let d = a?.depuis {
                Text(d.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR"))))
                    .font(.petit).foregroundStyle(Color.texte3)
            }
            Spacer(minLength: 8)
            if a != nil {
                Button(ouvert ? "Moins" : "Tout voir") { withAnimation(.snappy) { ouvert.toggle() } }
                    .buttonStyle(.link).font(.petit)
            }
            if !idApp.isEmpty {
                Button { ecrire.toggle() } label: { Label("Écrire", systemImage: "square.and.pencil") }.controlSize(.small)
                Button("Ouvrir") { Claude.ouvrir(id: idApp) }.controlSize(.small)
                    .help("Ouvrir la session dans l'app Claude")
            }
        }
    }

    private var couleur: Color {
        switch a?.etat { case "busy"?: return .vert; case "waiting"?: return .ambre; default: return .texte3 }
    }

    /// Étape k/n de sa liste de tâches, ou sa dernière action.
    @ViewBuilder
    private func avancement(_ a: ActiviteSession) -> some View {
        let faites = a.plan.filter(\.faite).count
        if !a.plan.isEmpty, faites < a.plan.count {
            let k = a.plan.firstIndex(where: \.enCours).map { $0 + 1 } ?? faites
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: Double(faites), total: Double(a.plan.count)).tint(Color.action)
                Text("Étape \(k)/\(a.plan.count) : \(a.etape.isEmpty ? "—" : a.etape)")
                    .font(.petit).foregroundStyle(Color.texte2).lineLimit(1)
            }
            .frame(maxWidth: 520, alignment: .leading)
        } else if a.etat == "busy", !a.action.isEmpty {
            Text("Fait : \(a.action)").font(.petit).foregroundStyle(Color.texte2).lineLimit(1)
        }
    }

    @ViewBuilder
    private func detail(_ a: ActiviteSession) -> some View {
        if !a.plan.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(a.plan.enumerated()), id: \.offset) { i, e in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: e.faite ? "checkmark.circle.fill" : (e.enCours ? "circle.dotted.circle" : "circle"))
                            .foregroundStyle(e.faite ? Color.vert : (e.enCours ? Color.action : Color.texte3))
                        Text("\(i + 1). \(e.contenu)").font(.petit).foregroundStyle(e.faite ? Color.texte3 : Color.texte)
                    }
                }
            }
            .padding(.top, 2)
        }
        if !a.recap.isEmpty, !a.dernierTexte.isEmpty, a.recap != a.dernierTexte {
            Text("Résumé : \(a.recap)").font(.petit).foregroundStyle(Color.texte2).fixedSize(horizontal: false, vertical: true)
        }
        if !a.fichiers.isEmpty {
            HStack(spacing: 6) {
                Text("Fichiers :").font(.petit).foregroundStyle(Color.texte3)
                ForEach(a.fichiers.suffix(4), id: \.self) { f in
                    Button((f as NSString).lastPathComponent) { etat.montrer(f) }.buttonStyle(.link).font(.petit)
                }
            }
        }
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(mesMessages.prefix(ouvert ? 6 : 1)) { m in
                let l = Facteur.libelle(m.remise, pour: noeud.membre.nom, veille: etat.prochaineVeille)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: l.fait ? "checkmark.circle.fill" : "paperplane").foregroundStyle(l.fait ? Color.vert : Color.ambre)
                    Text("Vous, \(m.heure.formatted(date: .omitted, time: .shortened)) : \(m.texte)")
                        .font(.petit).foregroundStyle(Color.texte2).lineLimit(ouvert ? 4 : 1)
                    Spacer(minLength: 6)
                    Text(l.texte).font(.petit).foregroundStyle(l.fait ? Color.vert : Color.ambre)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380, alignment: .trailing).layoutPriority(1)
                        .help(l.texte)
                }
            }
        }
    }

    private var champ: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Votre message à \(noeud.membre.nom)", text: $brouillon, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...6)
                Button { envoyer() } label: { Label("Envoyer", systemImage: "paperplane.fill") }
                    .buttonStyle(.borderedProminent).tint(.action)
                    .disabled(brouillon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Annuler") { ecrire = false; brouillon = "" }
            }
            if let erreur { Text(erreur).font(.petit).foregroundStyle(Color.rouge) }
            EtatFacteur()
        }
        .padding(.top, 4)
    }

    private func envoyer() {
        do {
            try etat.ecrire(a: noeud.membre.nom, session: idApp, texte: brouillon, qui: "\(Moi.nom)")
            brouillon = ""; ecrire = false; erreur = nil
        } catch { erreur = "Pas écrit : \(error.localizedDescription)" }
    }
}
