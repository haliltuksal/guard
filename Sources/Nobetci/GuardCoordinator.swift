import Foundation
import NobetciCore

/// GuardEngine'i saran actor: olayları sırayla işler ve etki listesi döndürür.
/// Kamera, sensörler ve girdi filtresi farklı iş parçacıklarından olay gönderir;
/// actor bunların motora tek tek, yarışsız ulaşmasını sağlar.
actor GuardCoordinator {
    private var engine: GuardEngine

    init(engine: GuardEngine) { self.engine = engine }

    func handle(_ event: GuardEvent) -> [GuardEffect] { engine.handle(event) }

    var state: GuardState { engine.state }
}
