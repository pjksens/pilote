# Langues de l'app (10/11/2026)

Pilote suit la langue du Mac : **français** (langue source, clés du catalogue), **anglais** (repli pour toute autre langue),
**espagnol**. L'outil en ligne de commande (`pilote`, serveur MCP) n'a pas de catalogue : il reste en français.
Changer de langue demande de relancer l'app.

## Les pièces

- `Shared/Loc.swift` : `Loc.langue` (`fr`/`en`/`es`), `Loc.locale`, `Loc.date(date, "EEEEdMMMM")`, et `L("…")`.
- `App/Localizable.xcstrings` : le catalogue. **Clé = la phrase française telle que le code l'écrit** ; un nombre y devient
  `%lld`, un texte ou une date `%@`. Ne se modifie pas à la main : `scripts/loc.py` (voir son en-tête).
- Le compilateur relève les textes du code (`SWIFT_EMIT_LOC_STRINGS`, fichiers `.stringsdata`) ; `scripts/loc.py extraire`
  les ajoute au catalogue ; `scripts/loc.py fusionner traductions.json` verse les traductions ; `verifier` contrôle.
- `Tests/LangueTests.swift` : le catalogue est complet (en + es sur chaque clé, mêmes `%@` / `%lld`), aucun mot français
  dans une traduction, et les phrases calculées sortent sans français dans chaque langue.

## Écrire un texte

| Cas | Écriture |
|---|---|
| Un littéral passé à une vue SwiftUI : `Text("…")`, `Button("…")`, `Label("…", systemImage:)`, `.help("…")`, `Section("…")`, `Toggle`, `TextField`, `.navigationTitle`, `confirmationDialog("…")`, `Picker("…")`, `Menu("…")`, `CommandMenu("…")` | **Rien à changer** : SwiftUI le localise tout seul. Une interpolation (`"\(n) contacts"`) devient `%lld contacts` dans le catalogue. |
| Un `String` calculé qui finit à l'écran (propriété, `switch`, retour de fonction, tableau de libellés, alerte, notification, titre de fenêtre, `NSAlert`, `NSMenuItem`) | `L("…")` : `case .app: return L("App KRYVA")`, `L("Fait le \(jour)")`. Puis `Text(texte)` (un `String` n'est jamais traduit une 2e fois). |
| Un nombre qui change l'accord (`"\(n) contact\(n > 1 ? "s" : "")"`) | **Une seule clé avec le nombre** : `L("\(n) contacts")` ; le catalogue porte les pluriels (`one` / `other`) dans les 3 langues. Jamais de `s` collé à la main. |
| Une date, un mois, un jour de semaine | `Loc.date(d, "EEEEdMMMM")` (gabarit de composants), `Loc.locale` à la place de `Locale(identifier: "fr_FR")`. Pas de `dateFormat` français fixe (`"d MMMM"`, `"EEE d/MM 'à' HH:mm"`). L'heure reste `HH:mm` (24 h) partout ; une date numérique `dd/MM` reste telle quelle. |
| Un nombre formaté | `.formatted(.number.locale(Loc.locale))`. |

Un tableau ou un `static let` de libellés (`Libelles.etapes`) devient `static var … { … }` calculé : la langue se lit à
l'appel, pas une fois pour toutes (les tests changent de langue).

## Ce qu'on ne traduit PAS

Une donnée n'est pas un texte de l'app : noms, entreprises, notes, titres de rappels, textes de cartes déclarées par les
sessions, légendes, tout ce qui vient de la base, de Rappels, du Calendrier, de Mail ou des sessions. Et :

- les valeurs stockées ou comparées (`"prepare"`, `"a_contacter"`, `"kryva"`, rawValue, clés JSON, noms de colonnes, URL,
  motifs d'expression régulière, scripts AppleScript, commandes) ;
- **les noms d'équipe et titres de sessions** (`Domaine.equipe`, « KRYVA · Ventes », « PILOTE », « FACTEUR », « FREELANCE ») : ce
  sont des identifiants que le code compare au titre réel d'une session ;
- **ce qui part vers un autre programme ou une personne** : consigne envoyée à une session Claude, corps d'un mail ou d'un SMS,
  texte écrit dans la base par une action (note du fil, journal), message du Facteur. Les équipes d'agents travaillent en
  français. Si une action de l'app écrit un texte en base, ne le change pas : liste-le dans ton rapport (`ecrit_en_base`).
- `Libelles.tutoyer` : réécrit un texte FRANÇAIS de carte en « tu » ; en anglais et en espagnol la donnée reste telle quelle
  (garde la fonction, ajoute `guard Loc.estFrancais else { return t }` en tête).

**Piège : une phrase pour les agents qui contient un libellé de l'app.** Une consigne ou une note écrite en base reste en
français ; si elle intègre `Libelles.*`, `VideoVocabulaire.*` ou un `L(…)`, ces mots sortiraient traduits dans une app en
anglais. Enveloppe la construction du texte dans `Loc.enFrancais { … }` (la langue repasse à « fr » le temps de la
fermeture ; ne traverse pas un `Task.detached`).

**Piège : un texte qu'on relit.** Si le code compare ou découpe l'affichage (`hasPrefix("Pour toi : ")`, `contains("à faire")`,
`==` avec un libellé), la traduction le casse sans bruit. Remplace par un champ structuré (booléen, énumération), ou compare
avec la même fonction `L(…)` des deux côtés. Chaque cas trouvé va dans ton rapport.

## Traduire

Anglais et espagnol **naturels**, comme les écrirait un produit natif, pas de calque du français. Le français d'origine
est tantôt « vous », tantôt « tu » : anglais « you », espagnol « tú » (jamais « usted »). Les phrases n'ont pas besoin de
suivre la ponctuation française : pas d'espace avant `: ; ? !`, guillemets `“ ”` en anglais et `« »` en espagnol, `¿…?` `¡…!`
en espagnol. Majuscules : anglais, **Title Case** pour un bouton ou un menu court (« Open in Mail »), sentence case pour
tout le reste (phrases, infobulles, étiquettes) ; espagnol : sentence case partout. Même longueur ou plus court qu'en
français quand c'est possible (boutons, onglets, pastilles : l'espace est compté). Garder tels quels : `Pilote`, `PILOTE`,
`KRYVA`, `Facteur` (nom d'agent), `Radar`, `Notion`, `Gmail`, `Mail`, `Messages`, `LinkedIn`, `TikTok`, `Instagram`,
`YouTube`, `PlugKit`, `Claude`, noms de personnes.

Glossaire (même mot partout) :

| Français | English | Español |
|---|---|---|
| Aujourd'hui · Demain | Today · Tomorrow | Hoy · Mañana |
| Planning · Tâches · Contacts · Projets · Agents | Schedule · Tasks · Contacts · Projects · Agents | Planificación · Tareas · Contactos · Proyectos · Agentes |
| Ma journée | My day | Mi día |
| À toi / Pour toi | For you | Para ti |
| Rappels (l'app) · un rappel | Reminders · a reminder | Recordatorios · un recordatorio |
| Calendrier | Calendar | Calendario |
| relance, relancer | follow-up, to follow up | seguimiento, dar seguimiento |
| fil (d'un contact) | timeline | historial |
| fiche (d'un contact) | record | ficha |
| contact · prospect | contact · prospect | contacto · prospecto |
| étapes : À contacter · Contacté · A répondu · RDV · Gagné · Perdu | To contact · Contacted · Replied · Meeting · Won · Lost | Por contactar · Contactado · Respondió · Cita · Ganado · Perdido |
| Ne plus contacter | Do not contact | No volver a contactar |
| message préparé · à valider · à envoyer · envoyé | prepared message · to approve · to send · sent | mensaje preparado · por validar · por enviar · enviado |
| brouillon | draft | borrador |
| domaines : App KRYVA · Réseaux · Ventes KRYVA · Freelance · Papiers · Pilote | KRYVA App · Social · KRYVA Sales · Freelance · Paperwork · Pilote | App KRYVA · Redes · Ventas KRYVA · Freelance · Papeleo · Pilote |
| session (Claude) · agent · consigne | session · agent · instruction | sesión · agente · instrucción |
| carte (écran unique) · pastille · bilan | card · badge · summary | tarjeta · insignia · resumen |
| publication (réseaux) · légende · couverture · prompteur | post · caption · cover · teleprompter | publicación · descripción · portada · teleprompter |
| relevé (de chiffres) · verdict | reading · verdict | medición · veredicto |
| file d'envoi | send queue | cola de envío |
| décision (un ❓) | decision | decisión |
| en retard · à faire · fait / terminé | overdue · to do · done | atrasado · pendiente · hecho |

## Plan de travail (ce que fait un agent sur ses fichiers)

1. Lister les littéraux à décider : `python3 -I scripts/loc_candidats.py <fichier.swift>…` (lignes de texte que le compilateur
   n'a pas relevées : à convertir en `L("…")`, ou à laisser parce que ce sont des données).
2. Convertir (règles ci-dessus), compiler : `xcodegen generate --quiet`, puis
   `xcodebuild -project Pilote.xcodeproj -scheme Pilote -configuration Debug -derivedDataPath build/derived-loc build 2>&1 | grep -E "error:|BUILD"`.
3. `python3 -I scripts/loc.py extraire` (met à jour le catalogue de ton dossier de travail), puis
   `python3 -I scripts/loc.py manque en --source <tes fichiers>` : chaque clé listée demande une traduction.
4. Écrire `loc/fragments/<ton-nom>.json` : `{ "clé française": {"en": "…", "es": "…"} }`. Les clés doivent être **identiques**
   à celles de `manque` (mêmes `%@` / `%lld`, dans le même ordre ; `%1$@` pour inverser l'ordre si la langue l'exige).
   Un pluriel : `{"fr": {"one": "%lld contact", "other": "%lld contacts"}, "en": {"one": "%lld contact", "other": "%lld contacts"}, "es": {...}}`
   (la clé du catalogue est la forme `other` française). Versement à l'essai : `python3 -I scripts/loc.py fusionner loc/fragments/<nom>.json`
   puis `python3 -I scripts/loc.py manque en --source …` doit être vide ; `python3 -I scripts/loc.py verifier` aussi.
5. `./scripts/tester.sh` : tous les tests restent verts (leurs attentes sont en français, langue par défaut des tests).
6. Rapport `loc/rapports/<ton-nom>.md` : ce qui reste volontairement en français (et pourquoi), les textes écrits en base
   (`ecrit_en_base`), les couplages affichage ↔ code trouvés et corrigés, les doutes de traduction.
