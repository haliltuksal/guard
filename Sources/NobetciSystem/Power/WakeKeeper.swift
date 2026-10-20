import Foundation
import IOKit.pwr_mgt

/// Nöbet boyunca Mac'in uyumasını, ekranın kararmasını ve boşta kalmaya bağlı
/// otomatik kilidin devreye girmesini engeller — yalnızca güç bildirimleriyle.
/// SAHTE GİRDİ ÜRETMEZ: boşta kalma sayaçlarına dokunmaz, yani Slack/Teams gibi
/// araçlar kullanıcıyı doğru şekilde "boşta" gösterir (spec §1.5, §7.6).
public final class WakeKeeper: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [IOPMAssertionID] = []

    public init() {}

    public var isActive: Bool { lock.withLock { !ids.isEmpty } }

    public func start() throws {
        try lock.withLock {
            guard ids.isEmpty else { return }   // idempotent
            let types = [
                kIOPMAssertionTypePreventUserIdleDisplaySleep,
                kIOPMAssertionTypePreventUserIdleSystemSleep,
            ]
            for type in types {
                var id = IOPMAssertionID(0)
                let result = IOPMAssertionCreateWithName(
                    type as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "Nöbetçi nöbette: ekran açık kalmalı" as CFString,
                    &id)
                guard result == kIOReturnSuccess else {
                    ids.forEach { IOPMAssertionRelease($0) }
                    ids = []
                    throw WakeKeeperError.assertionFailed(result)
                }
                ids.append(id)
            }
        }
    }

    public func stop() {
        lock.withLock {
            ids.forEach { IOPMAssertionRelease($0) }
            ids = []
        }
    }

    deinit { stop() }
}

public enum WakeKeeperError: Error, Sendable {
    case assertionFailed(IOReturn)
}
