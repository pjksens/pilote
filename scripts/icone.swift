// Refait l'icône de l'app (App/Assets.xcassets/AppIcon.appiconset) depuis le maître en 1024 × 1024, avec sips.
//   swift scripts/icone.swift [maître.png] [dossier .appiconset]
// Le maître (scripts/icone/icone-1024.png) vient d'un rendu Blender, voir scripts/icone/ :
//   blender -b -P scripts/icone/modele.py -- scripts/icone/tmp/rendu.png   (Blender 5, Cycles)
//   python3 scripts/icone/composer.py                                      (Pillow et numpy : fond blanc, 1024)
import Foundation

let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let args = CommandLine.arguments.dropFirst()
let maitre = args.first.map { URL(fileURLWithPath: $0) } ?? racine.appendingPathComponent("scripts/icone/icone-1024.png")
let dossier = args.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? racine.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")

func sips(_ arguments: [String]) -> String {
    let p = Process(), sortie = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    p.arguments = arguments
    p.standardOutput = sortie
    p.standardError = sortie
    try! p.run()
    let texte = String(decoding: sortie.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { fatalError("sips \(arguments.joined(separator: " ")) : \(texte)") }
    return texte
}

// Le maître doit être un carré de 1024 pixels au moins : sips réduit bien, il agrandit mal.
let mesures = sips(["-g", "pixelWidth", "-g", "pixelHeight", maitre.path])
let nombres = mesures.split(whereSeparator: \.isNewline).compactMap { $0.split(separator: " ").last.flatMap { Int($0) } }
guard nombres.count == 2, nombres[0] == nombres[1], nombres[0] >= 1024 else {
    fatalError("\(maitre.path) : il faut un carré d'au moins 1024 pixels (lu : \(nombres))")
}

try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
var images: [[String: String]] = []
for taille in [16, 32, 128, 256, 512] {
    for e in [1, 2] {
        let nom = "icone-\(taille)@\(e)x.png", px = taille * e
        _ = sips(["-s", "format", "png", "-z", "\(px)", "\(px)", maitre.path, "--out", dossier.appendingPathComponent(nom).path])
        images.append(["idiom": "mac", "size": "\(taille)x\(taille)", "scale": "\(e)x", "filename": nom])
    }
}
let contenu: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contenu, options: [.prettyPrinted, .sortedKeys])
    .write(to: dossier.appendingPathComponent("Contents.json"))
print("Icône : \(images.count) images dans \(dossier.path)")
