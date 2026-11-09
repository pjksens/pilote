// La carte « Demain » d'Aujourd'hui (03/11) : le contrôle « Demain prêt ? » (Shared/DemainPret.swift), une ligne verte
// ou rouge par point, et pour chaque trou la session qui le comble (bouton « Prévenir », envoyé par le Facteur).
import SwiftUI

extension Etat {
    /// Le contrôle du jour ouvré suivant, avec ce que l'app a déjà lu (base, Rappels, décisions).
    func bilanDemain(_ agenda: Agenda, maintenant: Date = Date()) -> BilanDemain {
        let messages = (aEnvoyer + aValider + aRefaire).map {
            MessageDemain(espace: $0.contact.espace, jour: $0.jour, statut: $0.evenement.statut, nom: $0.contact.nom)
        }
        let taches: [TacheDemain]? = agenda.tachesLues ? agenda.taches.compactMap { t in
            guard !t.faite, let e = t.echeance, CalendriersPlanning.tache(t.liste) else { return nil }
            return TacheDemain(titre: t.titre, notes: t.notes, liste: t.liste, jour: Dates.jour.string(from: e))
        } : nil
        return DemainPret.controler(
            aujourdhui: Dates.jour.string(from: maintenant), videos: videos, contacts: contacts, messages: messages,
            taches: taches, accesRappels: agenda.accesRappels != .refuse && agenda.accesRappels != .coupe,
            decisionsOuvertes: agenda.rappels.filter { Decisions.estDecision($0.titre) }.count + questionsSessions.count,
            reponsesEnAttente: decisionsEnvoyees.filter(\.enAttente).count)
    }
}

struct CarteDemain: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    /// Les trous déjà signalés depuis cette carte (le message part ensuite avec le Facteur ou la veille).
    @State private var prevenus: Set<String> = []
    @State private var erreur: String?

    var body: some View {
        let b = etat.bilanDemain(agenda)
        let trous = b.trous.count
        Carte(titre: "Demain", detail: "\(DemainPret.libelleJour(b.jour)) · "
              + (trous == 0 ? "tout est prêt" : (trous == 1 ? "1 trou" : "\(trous) trous") + " sur \(b.points.count)")) {
            ForEach(Array(b.points.enumerated()), id: \.element.id) { i, p in
                LigneCarte(dernier: i == b.points.count - 1 && erreur == nil) { ligne(p, jour: b.jour) }
            }
            if let erreur { EtatErreur(texte: erreur).padding(.horizontal, 16).padding(.bottom, 10) }
            Text(b.dimanche ? "Contrôle du dimanche : demain et les sujets de la semaine. Notification à 19 h s'il manque quelque chose."
                 : "Contrôle de \(DemainPret.heureControle) h : notification s'il manque quelque chose (fenêtre Pilote ouverte).")
                .font(.petit).foregroundStyle(Color.texte3)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }

    private func ligne(_ p: PointDemain, jour: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: p.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(p.ok ? Color.vert : Color.rouge)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.titre).font(.ligne.weight(.semibold)).foregroundStyle(Color.texte)
                Text(p.detail).font(.secondaire).foregroundStyle(p.ok ? Color.texte2 : Color.rouge).lineLimit(2)
            }
            Spacer(minLength: 8)
            if !p.ok {
                if p.qui.isEmpty {
                    Text("à vous").font(.petit).foregroundStyle(Color.texte2).fixedSize()
                } else {
                    Text("à combler par \(Comble.court(p.qui))").font(.petit).foregroundStyle(Color.texte2).fixedSize()
                    if let session = session(p.qui) {
                        if prevenus.contains(p.id) {
                            Label("Prévenu", systemImage: "checkmark").font(.petit).foregroundStyle(Color.vert).fixedSize()
                        } else {
                            Button("Prévenir") { prevenir(p, jour: jour, session: session) }.controlSize(.small)
                                .help("Écrit à \(p.qui) : « \(texte(p, jour: jour)) ». Part avec le Facteur, sinon la veille.")
                        }
                    }
                }
            }
        }
        .help(p.regle)
    }

    private func session(_ nom: String) -> String? {
        etat.pyramide.tous.first { $0.membre.nom == nom && !$0.membre.sessionApp.isEmpty }?.membre.sessionApp
    }

    private func texte(_ p: PointDemain, jour: String) -> String {
        "Contrôle « Demain prêt ? » pour \(DemainPret.libelleJour(jour)) : \(p.titre), \(p.detail). À combler ce soir, puis mettre Pilote à jour."
    }

    private func prevenir(_ p: PointDemain, jour: String, session: String) {
        do {
            try etat.ecrire(a: p.qui, session: session, texte: texte(p, jour: jour), qui: "\(Moi.nom)")
            prevenus.insert(p.id)
            erreur = nil
        } catch { erreur = "Pas écrit : \(error.localizedDescription)" }
    }
}
