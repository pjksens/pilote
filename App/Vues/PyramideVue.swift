// Pyramide : l'équipe de sessions Claude sur trois étages, en lignes compactes, en haut de l'écran Agents.
// La hiérarchie vient d'EQUIPE.md, l'état des sessions vivantes de Sessions.vivantes() (voir Shared/Equipe.swift).
// La vue ne fait que montrer : elle n'archive, ne ferme et ne déplace rien. Elle n'a ni minuteur ni lecture à elle :
// l'écran Agents lui passe la pyramide que l'Etat relit en arrière-plan (boucle des agents, voir Etat.suivreAgents).
// Une session au travail montre sa demande en cours sur une 2e ligne discrète ; le reste (étape, dernier fait,
// résumé, projet) est dans l'infobulle de la ligne.
import SwiftUI

struct PyramideCompacte: View {
    let pyramide: Pyramide
    let charge: Bool

    /// Une ligne : une session, ou un intitulé de groupe (sans session parente, hors carte).
    private struct Rang: Identifiable {
        let id: String
        let noeud: NoeudPyramide?
        let titre: String
        let niveau: Int
    }

    private var rangs: [Rang] {
        var l: [Rang] = []
        if let p = pyramide.pilote { l.append(Rang(id: p.id, noeud: p, titre: "", niveau: 0)) }
        for c in pyramide.colonnes {
            if let t = c.tete { l.append(Rang(id: t.id, noeud: t, titre: "", niveau: 1)) }
            else { l.append(Rang(id: "titre-" + c.id, noeud: nil, titre: c.titre, niveau: 1)) }
            for n in c.chantiers { l.append(Rang(id: n.id, noeud: n, titre: "", niveau: 2)) }
        }
        if !pyramide.horsCarte.isEmpty {
            l.append(Rang(id: "titre-hors-carte", noeud: nil, titre: "Hors carte (absentes d'EQUIPE.md)", niveau: 1))
            for n in pyramide.horsCarte { l.append(Rang(id: "hc-" + n.id, noeud: n, titre: "", niveau: 2)) }
        }
        return l
    }

    private var resume: String? {
        guard charge, pyramide.pilote != nil else { return nil }
        let nb = pyramide.tous.filter(\.enLigne).count
        return "\(nb) en ligne sur \(pyramide.tous.count)"
    }

    var body: some View {
        Carte(titre: "Pyramide", detail: resume) {
            if !charge {
                EtatChargement(texte: "Lecture de l'équipe…").padding(.horizontal, 16).padding(.bottom, 12)
            } else if pyramide.pilote == nil {
                EtatVide(texte: pyramide.fichierTrouve
                         ? "EQUIPE.md ne contient pas de ligne PILOTE."
                         : "EQUIPE.md est introuvable : \(Equipe.fichier.path)")
            } else {
                VStack(spacing: 0) {
                    ForEach(rangs) { r in
                        if let n = r.noeud { LignePyramide(noeud: n, niveau: r.niveau) }
                        else { Intitule(texte: r.titre, niveau: r.niveau) }
                    }
                    Text("≈ : estimation. Les pastilles signalent seulement : Pilote n'archive rien.")
                        .font(.petit).foregroundStyle(Color.texte3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 8)
                }
                .padding(.bottom, 12)
            }
        }
    }
}

private struct Intitule: View {
    let texte: String
    let niveau: Int
    var body: some View {
        Text(texte).font(.petit.weight(.medium)).foregroundStyle(Color.texte3)
            .padding(.leading, 16 + CGFloat(niveau) * 20).padding(.top, 6).padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Une session sur une ligne : pastille d'état, nom, signalements, sous-agents estimés, contexte, état.
private struct LignePyramide: View {
    @Environment(Etat.self) private var etat
    let noeud: NoeudPyramide
    let niveau: Int

    /// 2e ligne : ce que la session fait en ce moment (sa demande, sinon son étape, sinon son dernier fait).
    private var enCours: String? {
        guard let a = noeud.activite, a.etat == "busy" else { return nil }
        for t in [a.demande, a.etape, a.action] where !t.isEmpty { return Equipe.court(t, 200) }
        return nil
    }

    private var couleurEtat: Color {
        guard let a = noeud.activite else { return .texte3 }
        return a.etat == "busy" ? .vert : (a.etat == "waiting" ? .ambre : .texte3)
    }

    private var couleurContexte: Color {
        guard let a = noeud.activite else { return .texte3 }
        if a.contexte > 300_000 && a.etat == "busy" { return .rouge }
        return a.contexte >= Equipe.seuilRelais ? .ambre : .texte3
    }

    private var infobulle: String {
        var l: [String] = []
        if !noeud.membre.domaine.isEmpty { l.append(noeud.membre.domaine) }
        if let a = noeud.activite {
            if let p = etat.projet(pour: a.dossier) { l.append("Projet : \(p.nom)") }
            if a.etat == "busy" {
                if !a.demande.isEmpty { l.append("Demande : " + Equipe.court(a.demande, 400)) }
                if !a.etape.isEmpty { l.append("Étape : " + Equipe.court(a.etape, 200)) }
                if !a.action.isEmpty {
                    l.append("Fait : " + Equipe.court(a.action, 200) + (a.actionLe.map { " (\(Equipe.heure($0)))" } ?? ""))
                }
                if let d = a.depuis { l.append("Au travail depuis \(Equipe.heure(d))") }
            } else if !a.recap.isEmpty {
                l.append(Equipe.court(a.recap, 400))
            }
        }
        if let d = noeud.dernier { l.append(d.texte + (d.quand.map { " (\(Equipe.heure($0)))" } ?? "")) }
        if noeud.contexteK != nil { l.append("Le contexte est relu à chaque action. À partir de 130 k, une session de pilotage écrit sa passation et se remet à zéro.") }
        if noeud.sousAgents > 0 { l.append("Sous-agents : estimation (fils modifiés depuis moins de \(Int(Equipe.fenetreSousAgents)) s et non marqués finis). Ce n'est pas une preuve.") }
        if noeud.badges.contains("À valider puis archiver") { l.append("Au repos depuis plus de 24 h : à valider, puis à archiver à la main.") }
        if !noeud.membre.sessionApp.isEmpty { l.append("Clic : ouvre la session dans l'app Claude.") }
        return l.joined(separator: "\n")
    }

    var body: some View {
        let ligne = VStack(alignment: .leading, spacing: 1) { entete; sousLigne }
        .padding(.leading, 16 + CGFloat(niveau) * 20).padding(.trailing, 16).padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(noeud.enLigne ? 1 : 0.55)
        .help(infobulle)

        if noeud.membre.sessionApp.isEmpty {
            ligne
        } else {
            Button { Claude.ouvrir(id: noeud.membre.sessionApp) } label: { ligne }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var sousLigne: some View {
        if let t = enCours {
            Text(t).font(.petit).foregroundStyle(Color.texte2)
                .lineLimit(1).truncationMode(.tail)
                .padding(.leading, 15)
        }
    }

    private var entete: some View {
        HStack(spacing: 8) {
            Group {
                if noeud.enLigne { Circle().fill(couleurEtat) } else { Circle().strokeBorder(Color.texte3, lineWidth: 1) }
            }
            .frame(width: 7, height: 7)
            Text(noeud.membre.nom)
                .font(niveau == 0 ? .ligneForte : (niveau == 1 ? .ligne.weight(.medium) : .secondaire))
                .foregroundStyle(niveau == 2 ? Color.texte2 : Color.texte).lineLimit(1)
            ForEach(noeud.badges, id: \.self) { b in Pastille(texte: b, couleur: .ambre) }
            Spacer(minLength: 8)
            if noeud.sousAgents > 0 {
                Text("≈ \(noeud.sousAgents) sous-agent\(noeud.sousAgents > 1 ? "s" : "")").font(.petit).foregroundStyle(Color.texte2)
            }
            Text(noeud.contexteK.map { "\($0) k" } ?? "").font(.petit.monospacedDigit()).foregroundStyle(couleurContexte)
                .frame(width: 44, alignment: .trailing)
            Text(noeud.libelleEtat).font(.petit)
                .foregroundStyle(noeud.activite?.etat == "waiting" ? Color.ambre : Color.texte2)
                .frame(width: 76, alignment: .trailing)
        }
    }
}
