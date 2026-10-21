import Testing
import Foundation
@testable import NobetciCore

// Fotoğraf künyelerinin kalıcı dizini: galeri bunu okur, saklama süresi bunu budar.
// `prune` hem künyeyi hem silinecek dosyaları döndürür; dosyayı silen uygulama katmanıdır.

private func ref(_ id: String, _ at: Date, _ reason: SnapshotReason = .personSeen) -> SnapshotRef {
    SnapshotRef(id: id, at: at, reason: reason)
}

@Test func indexListsNewestFirst() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    var idx = SnapshotIndex()
    idx.add(ref("a", t0))
    idx.add(ref("b", t0.addingTimeInterval(60)))
    idx.add(ref("c", t0.addingTimeInterval(30)))
    #expect(idx.newestFirst.map(\.id) == ["b", "c", "a"])
}

@Test func pruneDropsEntriesOlderThanRetention() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    var idx = SnapshotIndex()
    idx.add(ref("eski", now.addingTimeInterval(-86_400 - 1)))   // 1 günü geçti
    idx.add(ref("sinir", now.addingTimeInterval(-86_400 + 1)))  // tam sınırın içinde
    idx.add(ref("yeni", now.addingTimeInterval(-60)))
    let dropped = idx.prune(olderThan: 1, now: now)
    #expect(dropped.map(\.id) == ["eski"])
    #expect(idx.newestFirst.map(\.id) == ["yeni", "sinir"])
}

@Test func pruneWithNonPositiveDaysKeepsEverything() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    var idx = SnapshotIndex()
    idx.add(ref("cok-eski", now.addingTimeInterval(-10 * 86_400)))
    let dropped = idx.prune(olderThan: 0, now: now)
    #expect(dropped.isEmpty)
    #expect(idx.newestFirst.count == 1)
}

@Test func indexIsCappedAndDropsOldestBeyondLimit() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    var idx = SnapshotIndex()
    var dropped: [SnapshotRef] = []
    for i in 0...SnapshotIndex.maxEntries {
        dropped += idx.add(ref("f\(i)", t0.addingTimeInterval(Double(i))))
    }
    #expect(idx.newestFirst.count == SnapshotIndex.maxEntries)
    #expect(dropped.map(\.id) == ["f0"])          // en eskisi taşınca düşer
    #expect(!idx.newestFirst.contains { $0.id == "f0" })
}

@Test func removeDeletesOneEntry() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    var idx = SnapshotIndex()
    idx.add(ref("a", t0))
    idx.add(ref("b", t0.addingTimeInterval(1)))
    let removed = idx.remove(id: "a"); #expect(removed)          // mutating: önce değişkene al
    let missing = idx.remove(id: "yok"); #expect(!missing)
    #expect(idx.newestFirst.map(\.id) == ["b"])
}

@Test func indexRoundTripsThroughJSON() throws {
    var idx = SnapshotIndex()
    idx.add(ref("a", Date(timeIntervalSince1970: 5), .locked(.strangerFace)))
    let data = try JSONEncoder().encode(idx)
    #expect(try JSONDecoder().decode(SnapshotIndex.self, from: data) == idx)
}
