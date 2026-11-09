// Jetons de la charte KRYVA (docs/refonte-ui/CHARTE.md § 2), clair par défaut, sombre au choix.
import SwiftUI
import AppKit

extension Color {
    static let fond = Color.dynamique(0xF5F5F7, 0x0F0F11)
    static let surface = Color.dynamique(0xFFFFFF, 0x1C1C1E)
    static let eleve = Color.dynamique(0xFFFFFF, 0x2C2C2E)
    static let texte = Color.dynamique(0x1D1D1F, 0xF5F5F7)
    static let texte2 = Color.dynamique(0x6E6E73, 0xA1A1A6)
    static let texte3 = Color.dynamique(0x8A8A8E, 0x7C7C82)
    /// La seule couleur pour agir.
    /// Le bleu de l'icône (feutrine #3675FF, ombre #3869EC), un peu plus sombre : texte blanc à 5,1:1, 4,7:1 sur le fond clair.
    static let action = Color(hex: 0x3063EB)
    /// Le bleu pour un texte ou une icône (lien, bouton teinté) : éclairci en sombre pour rester lisible (6,1:1 sur la surface, charte, accent-text).
    static let actionTexte = Color.dynamique(0x3063EB, 0x6E99F7)
    static let vert = Color.dynamique(0x1F7A37, 0x30D158)
    static let ambre = Color.dynamique(0xA34A00, 0xFFB340)
    static let rouge = Color.dynamique(0xC8102E, 0xFF6961)
    static let separateur = Color.dynamique(0xD1D1D6, 0x38383A)

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static func dynamique(_ clair: UInt32, _ sombre: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { apparence in
            let hex = apparence.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? sombre : clair
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Échelle typographique de la charte : 28 · 22 · 19 · 17 · 15 · 13 · 12, rien sous 11.
extension Font {
    static let titrePage = Font.system(size: 28, weight: .bold)
    static let titreSection = Font.system(size: 17, weight: .semibold)
    static let ligne = Font.system(size: 15)
    static let ligneForte = Font.system(size: 15, weight: .semibold)
    static let secondaire = Font.system(size: 13)
    static let petit = Font.system(size: 12)
}

enum Couleurs {
    static func etape(_ e: String) -> Color {
        switch e {
        case "gagne": return .vert
        case "repondu", "rdv": return .ambre
        case "perdu": return .texte3
        default: return .texte2
        }
    }

    static func ton(_ t: TonVideo) -> Color {
        switch t {
        case .vert: return .vert
        case .ambre: return .ambre
        case .rouge: return .rouge
        case .neutre: return .texte2
        }
    }

    /// Depuis combien de jours on n'a rien fait avec un contact : vert jusqu'à 3, ambre jusqu'à 10, rouge au-delà.
    static func depuis(_ jours: Int?) -> Color {
        guard let jours else { return .texte3 }
        return jours <= 3 ? .vert : (jours <= 10 ? .ambre : .rouge)
    }
}

/// Une carte de la charte : surface, rayon 12, séparateurs fins.
struct Carte<Contenu: View>: View {
    let titre: String
    var detail: String? = nil
    @ViewBuilder var contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(titre).font(.titreSection).foregroundStyle(Color.texte)
                if let detail { Text(detail).font(.secondaire).foregroundStyle(Color.texte2) }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            contenu
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Une ligne de carte, avec séparateur de 0,5 pt.
struct LigneCarte<Contenu: View>: View {
    var dernier = false
    @ViewBuilder var contenu: Contenu
    var body: some View {
        VStack(spacing: 0) {
            contenu.padding(.horizontal, 16).padding(.vertical, 10)
            if !dernier { Rectangle().fill(Color.separateur).frame(height: 0.5).padding(.leading, 16) }
        }
    }
}

/// États dessinés : vide, chargement, erreur (jamais une roue seule sur fond blanc).
struct EtatVide: View {
    let texte: String
    var body: some View {
        Text(texte).font(.secondaire).foregroundStyle(Color.texte2)
            .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EtatChargement: View {
    let texte: String
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(texte).font(.secondaire).foregroundStyle(Color.texte2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EtatErreur: View {
    let texte: String
    var reessayer: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Color.rouge)
            Text(texte).font(.secondaire).foregroundStyle(Color.texte)
            Spacer()
            if let reessayer { Button("Réessayer", action: reessayer).buttonStyle(.link) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// Le bouton principal de l'écran : bleu, avec son mot (charte, règles 2, 4 et 5).
struct BoutonPrincipal: View {
    let titre: String
    let symbole: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(titre, systemImage: symbole).labelStyle(.titleAndIcon) }
            .buttonStyle(.borderedProminent)
            .tint(.action)
    }
}

/// Pastille d'étape (rayon 999, couleur de statut).
struct Pastille: View {
    let texte: String
    let couleur: Color
    var body: some View {
        Text(texte).font(.petit.weight(.medium)).foregroundStyle(couleur)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(couleur.opacity(0.12), in: Capsule())
    }
}
