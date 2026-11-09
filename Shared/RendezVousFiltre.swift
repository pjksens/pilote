// Rendez-vous encore à afficher dans Aujourd'hui : ceux qui ne sont pas finis, et les événements « journée ».
import Foundation

enum RendezVousFiltre {
    static func encoreAffiche(fin: Date, journee: Bool, a maintenant: Date) -> Bool {
        journee || fin > maintenant
    }
}
