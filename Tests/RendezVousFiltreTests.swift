// Tests du filtre de l'agenda : un rendez-vous fini disparaît, un événement « journée » reste.
import XCTest

final class RendezVousFiltreTests: XCTestCase {
    let fin = Dates.iso.date(from: "2026-10-28T12:45:00Z")!

    func testFiniDisparait() {
        XCTAssertFalse(RendezVousFiltre.encoreAffiche(fin: fin, journee: false, a: fin.addingTimeInterval(1)))
        XCTAssertFalse(RendezVousFiltre.encoreAffiche(fin: fin, journee: false, a: fin))
    }

    func testEnCoursEtAVenirRestent() {
        XCTAssertTrue(RendezVousFiltre.encoreAffiche(fin: fin, journee: false, a: fin.addingTimeInterval(-1)))
        XCTAssertTrue(RendezVousFiltre.encoreAffiche(fin: fin, journee: false, a: fin.addingTimeInterval(-3600 * 5)))
    }

    func testJourneeResteMemeApresLaFin() {
        XCTAssertTrue(RendezVousFiltre.encoreAffiche(fin: fin, journee: true, a: fin.addingTimeInterval(3600 * 9)))
    }
}
