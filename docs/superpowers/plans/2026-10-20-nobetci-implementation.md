# Nöbetçi Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kullanıcı masasından kalkınca Mac'ini uyanık tutan; yabancı biri yaklaşınca ya da müdahale olunca tüm ekranları bulanıklaştırıp girdileri geçici olarak askıya alan; yalnızca sahibin yüzü (canlılık kontrolüyle) ya da uygulama şifresiyle açılan menü çubuğu uygulamasını, spec'teki tüm kabul testlerini ölçümleriyle geçecek şekilde inşa etmek.

**Architecture:** Saf Swift durum makinesi (`NobetciCore`) tüm kararları verir ve donanıma dokunmaz → sahte girdilerle eksiksiz test edilir. `NobetciVision` kamera karelerini `FrameSummary`'ye indirger; `NobetciSystem` macOS adaptörlerini sağlar; `Nobetci` uygulaması SwiftUI arayüzünü ve parçaları bağlayan `EffectRunner`'ı içerir.

**Tech Stack:** Swift 6.3 (katı eşzamanlılık), SwiftPM + Command Line Tools (Xcode yok), Swift Testing, SwiftUI/AppKit, AVFoundation, Vision, Core ML, IOKit, CoreGraphics, Carbon (HotKey + UCKeyTranslate), CryptoKit, CommonCrypto, Security, ServiceManagement, LocalAuthentication. Python 3.12 + uv + coremltools yalnızca `tools/model` (derleme zamanı).

**Spec:** `docs/superpowers/specs/2026-10-20-nobetci-design.md` — plan bu spec'ten argüman üretir; uygulayıcı ikisini birlikte okur.

## Altitude (bu planın kodu nasıl verdiği)

- **Saf mantık görevleri** (durum makinesi, eşleştirme, bekleme politikası, şifre özeti, sahne kararları, kırpma): tam TDD — gerçek test kodu + gerçek uygulama kodu. Bunlar matematiktir; donanımsız çalışır ve `make test` ile doğrulanır.
- **Çerçeve adaptörleri** (girdi filtresi, kalkan pencereleri, sensörler, kamera, launchd, Keychain): birim testiyle doğrulanamaz; izin ya da donanım ister. Bunlar için plan **arayüz imzası + davranış sözleşmesi + gerçek Mac'te manuel doğrulama adımları** verir; tam gövde uygulama sırasında, spec'teki ilgili bölüm ve `tools/probes/` deneyleri rehber alınarak yazılır. Adaptörlerin içindeki **saf karar mantığı** (ör. "bu politikada bu olaya ne yapılır") ayrı bir saf tipe çıkarılır ve TDD edilir.

## Global Constraints

- Hedef macOS 14.0+ (`LSMinimumSystemVersion = 14.0`), yalnızca arm64; Swift 6 dil modu, katı eşzamanlılık.
- **Üçüncü parti çalışma zamanı bağımlılığı yok**; yalnızca Apple framework'leri. Python yalnızca `tools/model`, derleme zamanı.
- **Ağ kodu yok.** Hiçbir veri cihazdan çıkmaz (kabul: `lsof -i -a -p <pid>` boş, D16).
- **Fotoğraf yok.** Yabancı yüz vektörleri saklanmaz/kümelenmez; yalnızca o anki karar için bellekte.
- **Sahte girdi yok.** Uygulama kullanıcı adına hiçbir klavye/fare olayı üretmez; uyku engelleme yalnızca `IOPMAssertion` ile. Girdi filtresinin tek yazma yetkisi, kilitliyken tuş karakterini **kendi** şifre alanına iletmektir; sisteme ya da üçüncü taraf uygulamaya hiçbir olay enjekte edilmez.
- **Fail-closed:** emin olunamayan her durum → Kilitli.
- **Şeffaflık:** menü çubuğu simgesi çalışırken her zaman görünür; kalkan kartında "Kamera etkin" satırı; kaldırma (§8.5) ve kurtarma yolu (§3.5) belgeli; kamera yalnızca nöbette açık, bitince kapanır (yeşil ışık söner).
- Testler Swift Testing; `make test` V9 bayraklarıyla. `NobetciCore` satır kapsamı ≥ %90 (`make coverage`, V16).
- Türkçe arayüz; metinler `Sources/Nobetci/Resources/tr.lproj/Localizable.strings` tek kaynağında.
- Paket `com.halil.nobetci`; ad "Nöbetçi"; `LSUIElement`; hardened runtime; App Sandbox yok; yetki `com.apple.security.device.camera`.
- Her D-maddesi (spec §15.2) ilgili görevde ölçülür; sonucu `docs/test-report.md`'ye yazılır. Başarısızsa spec'teki yedek plan uygulanır, karar belgelenir.
- Commit mesajları Türkçe, Conventional Commits öneki.

## Review Focus

Spec'in ima ettiği ama test altına açıkça girmeyen, kullanıcıyı en çok vurabilecek beş durum. Testleri ilgili göreve eklendi (parantezde).

1. **Sahip kalkarken kendi gövdesi "yüzsüz kişi"yi (T2) tetiklememeli.** T2 yalnızca sahne ≥ 3 sn boşken beliren gövde için geçerli; sahip izi yeni kaybolduysa geçerli değil. (Görev 3.4, `facelessPersonRequiresPriorEmptyScene`)
2. **Türkçe Q'da ölü tuş dizisi ve Option karakterleri şifreye doğru girmeli.** `^`+`e`→`ê`; Option+key17→`₺`. (Görev 1.3, gerçek `UCKeyboardLayout` verisiyle)
3. **Kilitliyken ekran takılıp çıkınca kalkansız ekran kalmamalı.** Pencere kümesi ekran kümesine eşitlenir. (Görev 1.2, `windowsTrackScreenSet`)
4. **Duvar saati oynatılsa bekleme süresi bozulmamalı.** Bekleme yalnızca monoton saatle ölçülür. (Görev 3.6, `lockoutUsesMonotonicClockOnly`)
5. **Nöbet ortasında sensör kaybı "yedeğe geç + uyar"; kamera kaybı "Kilitli".** (Görev 3.5, `sensorLossWarnsWithoutLocking`, `cameraLossLocks`)

---

## Dosya yapısı

```
Nobetci/
├── Package.swift · Makefile · VERSION · CHANGELOG.md · README.md · KURULUM.md · .gitignore
├── scripts/            bundle.sh, sign.sh, make-cert.sh, coverage_gate.py
├── Sources/
│   ├── NobetciCore/     (saf mantık — tam TDD)
│   │   ├── Clock.swift
│   │   ├── Model/        GuardState, GuardEvent, GuardEffect, GuardSettings
│   │   ├── Presence/     FaceMatcher, OwnerPresence, UnlockEvaluator
│   │   ├── Liveness/     BlinkDetector
│   │   ├── Sensors/      LidAngleLogic, MotionLogic, SceneHealthLogic
│   │   ├── Passcode/     PasscodeHasher, LockoutPolicy
│   │   ├── Engine/       GuardEngine (reduce)
│   │   ├── Session/      SessionLog, ReportBuilder
│   │   └── Storage/      SealedBoxCodec, SettingsCodec
│   ├── NobetciVision/   (kamera → FrameSummary — arayüz + manuel)
│   │   ├── CameraSource, FrameAnalyzer, FaceDetector, FaceAligner, FaceEmbedder, TrackManager, VisionPipeline
│   ├── NobetciSystem/   (macOS adaptörleri — arayüz + manuel; saf karar mantığı ayrı tiplerde TDD)
│   │   ├── Power/WakeKeeper
│   │   ├── Shield/ShieldWindowController, KioskGuard
│   │   ├── Input/KeyTranslator, InputPolicyEngine (saf, TDD), InputFilter (adaptör)
│   │   ├── Sensors/LidAngleSensor, Accelerometer
│   │   ├── Hardware/HardwareWatcher, SleepObserver
│   │   ├── HotKey · Lifecycle/LaunchAgent, BootSession
│   │   └── Storage/KeychainStore, SecureFileStore
│   ├── Nobetci/         (@main, AppModel, EffectRunner, L10n, Views/*)
│   └── nobetci-eval/    (LFW değerlendirme aracı)
├── Tests/{NobetciCoreTests,NobetciVisionTests,NobetciSystemTests}/
├── Resources/          Info.plist, Nobetci.entitlements, LaunchAgents/*.plist, Icon/
├── tools/{model,probes}/
└── docs/               specs, plans, model-evaluation.md, test-report.md, test-assets/
```

---

# Faz 0 — İskelet

### Görev 0.1: SwiftPM paketi, Makefile, Clock

**Files:**
- Create: `Package.swift`, `Makefile`, `VERSION`, `.gitignore`, `scripts/coverage_gate.py`
- Create: `Sources/NobetciCore/Clock.swift`; her hedefte derlensin diye `Sources/NobetciVision/_Bootstrap.swift`, `Sources/NobetciSystem/_Bootstrap.swift` (boş `public enum`; sonraki fazlarda silinir); `Sources/Nobetci/NobetciApp.swift` (en küçük `MenuBarExtra`); `Sources/nobetci-eval/main.swift`
- Test: `Tests/NobetciCoreTests/ClockTests.swift`

**Interfaces:**
- Produces: `public protocol Clock: Sendable { func now() -> TimeInterval; func wallNow() -> Date }`; `SystemClock` (`mach_continuous_time`); `ManualClock(init(now:wall:))` + `advance(by:)`, `setWall(_:)`. `now()` uyku dahil ilerleyen monoton saniye (bekleme için); `wallNow()` rapor zaman damgası için. Tüm Core bileşenleri saati enjekte alır.

- [ ] **Adım 1: Package.swift** — hedefler: `NobetciCore`, `NobetciVision`(→Core), `NobetciSystem`(→Core), `Nobetci`(exe, 3'üne bağlı, `resources: [.process("Resources")]`), `nobetci-eval`(exe→Core,Vision), üç testTarget. `defaultLocalization: "tr"`, `platforms: [.macOS(.v14)]`, `swiftLanguageModes: [.v6]`.

- [ ] **Adım 2: Makefile ve coverage_gate.py**

```make
CLT := /Library/Developer/CommandLineTools
TESTFLAGS := -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
  -Xswiftc -plugin-path -Xswiftc $(CLT)/usr/lib/swift/host/plugins/testing \
  -Xlinker -F -Xlinker $(CLT)/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
BIN := $(shell swift build --show-bin-path)
.PHONY: build test coverage app cert dist install clean model eval
build: ; swift build
test: ; swift test $(TESTFLAGS)
coverage: ; swift test --enable-code-coverage $(TESTFLAGS) && \
  xcrun llvm-cov report "$(BIN)/NobetciPackageTests.xctest/Contents/MacOS/NobetciPackageTests" \
  -instr-profile="$(BIN)/codecov/default.profdata" \
  -ignore-filename-regex='(\.build|Tests|Sources/Nobetci/|Sources/nobetci-eval)/' | tee build/coverage.txt && \
  python3 -I scripts/coverage_gate.py build/coverage.txt NobetciCore 90
clean: ; rm -rf .build build
```

`scripts/coverage_gate.py`: raporda `Sources/NobetciCore/` satırlarını toplar, toplam satır kapsamı eşiğin altındaysa çıkış kodu 1. (llvm-cov sütun indeksleri: lines total = 7, missed = 8; `cols = line.split()`.)

- [ ] **Adım 3: Başarısız test**

```swift
import Testing
import Foundation
@testable import NobetciCore

@Test func manualClockAdvancesMonotonicOnly() {
    let c = ManualClock(now: 100, wall: Date(timeIntervalSince1970: 1000))
    c.advance(by: 2.5)
    #expect(c.now() == 102.5)
    #expect(c.wallNow() == Date(timeIntervalSince1970: 1002.5))
}
@Test func manualClockWallCanMoveIndependently() {
    let c = ManualClock(now: 0, wall: Date(timeIntervalSince1970: 1000))
    c.setWall(Date(timeIntervalSince1970: 500))   // duvar saati geri alındı
    c.advance(by: 10)                              // monoton ileri
    #expect(c.now() == 10)
    #expect(c.wallNow() == Date(timeIntervalSince1970: 510))
}
@Test func systemClockIsMonotonic() {
    let c = SystemClock(); #expect(c.now() <= c.now())
}
```

- [ ] **Adım 4: Çalıştır** → `make test` → `cannot find 'ManualClock'`.
- [ ] **Adım 5: Clock.swift**

```swift
import Foundation
public protocol Clock: Sendable { func now() -> TimeInterval; func wallNow() -> Date }

public struct SystemClock: Clock {
    public init() {}
    public func now() -> TimeInterval {
        var info = mach_timebase_info(); mach_timebase_info(&info)
        let ns = mach_continuous_time() &* UInt64(info.numer) / UInt64(info.denom)
        return Double(ns) / 1e9
    }
    public func wallNow() -> Date { Date() }
}

public final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock(); private var mono: TimeInterval; private var wall: Date
    public init(now: TimeInterval = 0, wall: Date = Date(timeIntervalSince1970: 0)) { mono = now; self.wall = wall }
    public func now() -> TimeInterval { lock.withLock { mono } }
    public func wallNow() -> Date { lock.withLock { wall } }
    public func advance(by s: TimeInterval) { lock.withLock { mono += s; wall.addTimeInterval(s) } }
    public func setWall(_ d: Date) { lock.withLock { wall = d } }
}
```

- [ ] **Adım 6: Çalıştır** → geçer.
- [ ] **Adım 7:** `.gitignore` (`.build/`, `build/`, `*.mlpackage`, `*.mlmodelc`, `tools/model/.venv/`, `tools/model/weights/`, `tools/model/data/`, `docs/test-assets/clips/`, `.DS_Store`), `VERSION`=`0.1.0`.

```bash
git add -A && git commit -m "build: SwiftPM iskeleti, Makefile ve Clock"
```

---

### Görev 0.2: `.app` paketleme (`make app`)

**Files:** Create `Resources/Info.plist`, `Resources/Nobetci.entitlements`, `scripts/bundle.sh`; Modify `Makefile`, `Sources/Nobetci/NobetciApp.swift`.

**Interfaces:** Produces `build/Nöbetçi.app` — açılınca menü çubuğunda kalkan simgesi, Dock'ta yok.

- [ ] **Adım 1: Info.plist** — `CFBundleIdentifier=com.halil.nobetci`, `CFBundleExecutable=Nobetci`, `CFBundleDisplayName=Nöbetçi`, `LSUIElement=true`, `LSMinimumSystemVersion=14.0`, `NSCameraUsageDescription` = spec §12.3 metni, sürüm alanları `__VERSION__` yer tutucu. `entitlements`: yalnızca `com.apple.security.device.camera=true`.
- [ ] **Adım 2: scripts/bundle.sh** — `swift build -c release --product Nobetci`; `build/Nöbetçi.app/Contents/{MacOS,Resources}` kur; ikiliyi kopyala; SwiftPM kaynak paketini (`Nobetci_Nobetci.bundle`) varsa Resources'a kopyala; `sed s/__VERSION__/$(cat VERSION)/` ile Info.plist yaz; varsa `build/Nobetci.icns`, `build/Model.mlmodelc`, `Resources/LaunchAgents/*.plist` kopyala. Makefile: `app: ; ./scripts/bundle.sh && ./scripts/sign.sh`.
- [ ] **Adım 3: En küçük uygulama**

```swift
import SwiftUI
@main struct NobetciApp: App {
    var body: some Scene {
        MenuBarExtra("Nöbetçi", systemImage: "shield") {
            Text("Nöbetçi \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
            Divider(); Button("Çıkış") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }.menuBarExtraStyle(.window)
    }
}
```

- [ ] **Adım 4: Doğrula** — `make app && open "build/Nöbetçi.app"` → menü çubuğunda simge var, Dock boş; `/usr/libexec/PlistBuddy -c "Print :LSUIElement" "build/Nöbetçi.app/Contents/Info.plist"` → `true`. Menüden Çıkış.
- [ ] **Adım 5:** `git add -A && git commit -m "build: .app paketleme (make app), Info.plist ve entitlements"`

---

### Görev 0.3: Kendinden imzalı sertifika ve imzalama (`make cert`) — D11 ön hazırlık

**Files:** Create `scripts/make-cert.sh`, `scripts/sign.sh`; Modify `Makefile`.

**Interfaces:** Produces giriş anahtar zincirinde "Nöbetçi Code Signing" kimliği; `sign.sh` uygulamayı bu kimlik + `--options runtime` + entitlements ile imzalar.

- [ ] **Adım 1: make-cert.sh** — kimlik yoksa: `openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes` ile `CN="Nöbetçi Code Signing"`, uzantılar `keyUsage=digitalSignature`, `extendedKeyUsage=codeSigning`, `basicConstraints=CA:false`; `openssl pkcs12 -export -legacy`; `security import … -T /usr/bin/codesign -k login.keychain-db`; `security add-trusted-cert -r trustRoot -p codeSign`. **Aynı anahtar saklanır; yeniden üretilirse designated requirement değişir ve TCC izinleri sıfırlanır — bu yüzden bir kez.**
- [ ] **Adım 2: sign.sh** — `codesign --force --deep --options runtime --entitlements Resources/Nobetci.entitlements --sign "Nöbetçi Code Signing" "build/Nöbetçi.app"`; ardından `codesign --verify --deep --strict` ve `codesign -d -r- … | grep designated`.
- [ ] **Adım 3: Doğrula** — `make cert` → `security find-identity -v -p codesigning` çıktısında kimlik. `make app` → `valid on disk`, `satisfies its Designated Requirement`.
- [ ] **Adım 4: D11 ön testi** — `make app`, aç, kamera izni ver; bir satır değiştir, `make app`, tekrar aç → Sistem Ayarları → Gizlilik → Kamera'da Nöbetçi açık kalmalı. Sonuç `docs/test-report.md` D11.
- [ ] **Adım 5:** commit `build: kendinden imzalı sertifika ve hardened runtime imzalama`

---

### Görev 0.4: Yerelleştirme altyapısı

**Files:** Create `Sources/Nobetci/Resources/tr.lproj/Localizable.strings`, `Sources/Nobetci/L10n.swift`.

**Interfaces:** Produces `enum L10n { static func t(_ key: String, _ args: CVarArg...) -> String }` — `Bundle.module`, `tr` tablosu, `Locale("tr_TR")`.

- [ ] **Adım 1:** İlk anahtarlar (menü + kalkan): `menu.away`="Uzaktayım", `menu.stop`="Korumayı kapat", `menu.quit`="Çıkış", `shield.title`="%@'ın Mac'i korunuyor", `shield.camera`="Kamera etkin", `shield.searching`="Seni arıyorum…", `shield.blink`="Merhaba %@, göz kırp", `shield.bystander`="Yanında biri var — şifre gerekli", `shield.retry`="%d sn sonra tekrar dene".
- [ ] **Adım 2:** `L10n.t` → `Bundle.module.localizedString(forKey:value:table:)` + `String(format:locale:arguments:)`.
- [ ] **Adım 3:** `NobetciApp`'te "Çıkış"ı `L10n.t("menu.quit")` ile değiştir; `make app && open` → "Çıkış" görünür. Commit `feat: Türkçe yerelleştirme altyapısı`.

---

# Faz 1 — Erken risk adaptörleri (arayüz + davranış + manuel D-ölçümü)

Her görev kalıcı bir `NobetciSystem` adaptörü üretir ve ilgili D'yi ölçer. Sonuçlar `docs/test-report.md` → "Faz 1". Bir D başarısızsa spec §15.2 yedeği uygulanır, karar commit'te belgelenir. **Bu adaptörlerin tam gövdeleri uygulama sırasında yazılır; plan arayüzü, davranışı ve doğrulamayı sabitler.**

### Görev 1.1: WakeKeeper (uyku engelleme) — D4

**Files:** Create `Sources/NobetciSystem/Power/WakeKeeper.swift`; Test `Tests/NobetciSystemTests/WakeKeeperTests.swift`.

**Interface & davranış:**
- `public final class WakeKeeper: Sendable { init(); func start() throws; func stop(); var isActive: Bool }`.
- `start()`: `IOPMAssertionCreateWithName` ile `kIOPMAssertionTypePreventUserIdleDisplaySleep` **ve** `kIOPMAssertionTypePreventUserIdleSystemSleep` bildirimlerini tutar; idempotent (ikinci çağrı yeni bildirim açmaz). `stop()`: `IOPMAssertionRelease` ile serbest bırakır; `deinit` de çağırır. **Girdi olayı üretmez.**
- Birim testi yalnızca aç/kapa/idempotent/`isActive` kontrol eder (bildirim açmak izin gerektirmez, CI'de güvenli).

- [ ] **Adım 1: Test**

```swift
import Testing
@testable import NobetciSystem
@Test func wakeKeeperStartsStopsAndIsIdempotent() throws {
    let k = WakeKeeper(); #expect(!k.isActive)
    try k.start(); try k.start(); #expect(k.isActive)
    k.stop(); #expect(!k.isActive)
}
```

- [ ] **Adım 2:** Çalıştır → başarısız.
- [ ] **Adım 3:** `WakeKeeper`'ı yukarıdaki sözleşmeye göre yaz (iki `IOPMAssertionCreateWithName` çağrısı; başarısızlıkta açılanları geri al ve `throw`; `NSLock` ile `ids` dizisi korunur).
- [ ] **Adım 4:** Çalıştır → geçer.
- [ ] **Adım 5: D4 manuel ölçüm** — geçici debug komutu `WakeKeeper.start()`; Sistem Ayarları'nda ekran koruyucu + ekranı kapat 1 dk; 15 dk dokunma → başlamamalı/kararmamalı/kilitlenmemeli. `pmset -g assertions | grep -i nobetci` → iki `PreventUserIdle…`, **`UserIsActive` yok**. `stop()` sonra 2 dk'da ekran koruyucu başlar. `docs/test-report.md` D4. Başarısızsa yedek `caffeinate -d -i` alt süreci.
- [ ] **Adım 6:** commit `feat(system): WakeKeeper uyku engelleme (D4 ölçüldü)`

---

### Görev 1.2: ShieldWindowController — D5, D6

**Files:** Create `Sources/NobetciSystem/Shield/ShieldWindowController.swift`; Test `Tests/NobetciSystemTests/ShieldWindowControllerTests.swift`.

**Interface & davranış:**
- `@MainActor public final class ShieldWindowController { init(screens: ScreenProvider = SystemScreens(), content: @escaping () -> NSView); func show(); func hide(animated: Bool); var isShowing: Bool; var windowFrames: [CGRect]; var debugWindowLevel: Int }`.
- `ScreenProvider` protokolü (`frames: [CGRect]`, `onChange: (() -> Void)?`) — testte sahte sağlanır; `SystemScreens` gerçekte `NSScreen.screens` + `didChangeScreenParametersNotification`.
- Her ekran için kenarlıksız pencere; seviye `CGShieldingWindowLevel()`; `collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle,.fullScreenAuxiliary]`; içerik `NSVisualEffectView(material:.fullScreenUI, blendingMode:.behindWindow, state:.active)` + siyah ton katmanı (`tintAlpha`, başlangıç 0,55) + `content()`.
- `show()`: pencereleri kur, `NSApp.activate`. `onChange` → gösteriliyorsa pencere kümesini yeniden kur (ekran kümesine eşitle). `hide(animated:)`: animasyonluysa 0,25 sn alfa→0 sonra kapat; değilse hemen; `windowFrames` boşalır. Kilitlenirken animasyonsuz ve tam güçte; açılırken animasyonlu (içerik geçişte okunmasın).

- [ ] **Adım 1: Test (Review Focus 3)**

```swift
import Testing; import AppKit
@testable import NobetciSystem

@MainActor final class FakeScreens: ScreenProvider {
    var frames: [CGRect]; var onChange: (() -> Void)?
    init(_ f: [CGRect]) { frames = f }
    func change(to f: [CGRect]) { frames = f; onChange?() }
}
@Test @MainActor func windowsTrackScreenSet() {
    let s = FakeScreens([CGRect(x: 0, y: 0, width: 1512, height: 982)])
    let c = ShieldWindowController(screens: s) { NSView() }
    c.show(); #expect(c.windowFrames.count == 1)
    s.change(to: [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)])
    #expect(c.windowFrames.count == 2)
    s.change(to: [CGRect(x: 0, y: 0, width: 1512, height: 982)]); #expect(c.windowFrames.count == 1)
    c.hide(animated: false); #expect(c.windowFrames.isEmpty)
}
@Test @MainActor func shieldSitsAtShieldingLevel() {
    let c = ShieldWindowController(screens: FakeScreens([CGRect(x: 0, y: 0, width: 800, height: 600)])) { NSView() }
    c.show(); #expect(c.debugWindowLevel == Int(CGShieldingWindowLevel())); c.hide(animated: false)
}
```

- [ ] **Adım 2:** Çalıştır → başarısız.
- [ ] **Adım 3:** `ScreenProvider`, `SystemScreens`, `ShieldWindowController`'ı sözleşmeye göre yaz. (`@MainActor`; pencere alt sınıfı `canBecomeKey=true`.)
- [ ] **Adım 4:** Çalıştır → iki test geçer.
- [ ] **Adım 5: D5/D6 manuel** — debug komutu "Kalkanı göster (10 sn, otomatik kapanır)". **D5:** Spotlight, tam ekran Safari, bildirim, Mission Control, harici ekran → hepsinin üstünde. **D6:** `docs/test-assets/legibility.html` (12–72 pt) tam ekran, kalkan üstünde, `screencapture -x build/shield.png` → hiçbir yazı okunmamalı. Yetersizse `tintAlpha` 0,55→0,7→0,8; yine yetmezse yedek (`CGSSetWindowBackgroundBlurRadius`, spec §7.4) ayrı görev. Seçilen `tintAlpha` ve sonuçlar `docs/test-report.md` D5/D6.
- [ ] **Adım 6:** commit `feat(system): çok ekranlı kalkan (D5/D6 ölçüldü)`

---

### Görev 1.3: KeyTranslator (ölü tuş + Option) ve InputPolicyEngine (saf karar)

**Files:** Create `Sources/NobetciSystem/Input/KeyTranslator.swift`, `Sources/NobetciSystem/Input/InputPolicyEngine.swift`; Test `Tests/NobetciSystemTests/KeyTranslatorTests.swift`, `InputPolicyEngineTests.swift`.

**Interface:**
- `public struct KeyTranslator { init(layoutData: Data, keyboardType: UInt32 = UInt32(LMGetKbdType())); static func currentLayoutData() -> Data?; static func carbonModifiers(from: CGEventFlags) -> UInt32; mutating func translate(keyCode: UInt16, modifiers: UInt32) -> KeyOutput }`; `public enum KeyOutput: Equatable, Sendable { case text(String), pendingDeadKey, none }`. Ölü tuş durumu yapı içinde `deadKeyState` olarak taşınır; kontrol karakterleri (`< 0x20`, `0x7F`) `.none` sayılır.
- `public enum InputPolicy: Sendable { case passThrough, lockOnFirstInput, blockAll }`; `public enum InputDecision: Equatable, Sendable { case pass, swallow, swallowAndLock, passcodeText(String), passcodeReturn, passcodeDelete, passcodeEscape, passcodePending }`; `public struct InputPolicyEngine { init(translator: KeyTranslator?); mutating func decide(policy: InputPolicy, type: CGEventType, keyCode: UInt16?, flags: CGEventFlags) -> InputDecision }`.
- `decide` kuralları: `passThrough`→`.pass`; `lockOnFirstInput`→`.swallowAndLock`; `blockAll`→ keyDown değilse `.swallow`; Cmd/Ctrl bayrağı varsa `.swallow`; Return(36/76)→`passcodeReturn`, Delete(51/117)→`passcodeDelete`, Esc(53)→`passcodeEscape`; aksi halde `KeyTranslator.translate` → `.text`→`passcodeText`, `.pendingDeadKey`→`passcodePending`, `.none`→`swallow`.

- [ ] **Adım 1: KeyTranslator testi (Review Focus 2 — gerçek düzen verisi)**

```swift
import Testing; import Carbon
@testable import NobetciSystem
private func layout(_ id: String) -> Data? {
    guard let l = TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, true)?
        .takeRetainedValue() as? [TISInputSource], let s = l.first,
      let raw = TISGetInputSourceProperty(s, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
}
@Test func turkishQComposesAndOptionChars() throws {
    let d = try #require(layout("com.apple.keylayout.Turkish-QWERTY-PC"))
    var t = KeyTranslator(layoutData: d)
    #expect(t.translate(keyCode: 33, modifiers: 0) == .text("ğ"))
    #expect(t.translate(keyCode: 20, modifiers: KeyTranslator.shift) == .pendingDeadKey)  // ^
    #expect(t.translate(keyCode: 14, modifiers: 0) == .text("ê"))                          // ^ + e
    #expect(t.translate(keyCode: 17, modifiers: KeyTranslator.option) == .text("₺"))
    #expect(t.translate(keyCode: 14, modifiers: KeyTranslator.option) == .text("€"))
}
@Test func deadKeyThenSpaceYieldsSymbol() throws {
    let d = try #require(layout("com.apple.keylayout.Turkish-QWERTY-PC"))
    var t = KeyTranslator(layoutData: d)
    _ = t.translate(keyCode: 20, modifiers: KeyTranslator.shift)
    #expect(t.translate(keyCode: 49, modifiers: 0) == .text("^"))
}
```

- [ ] **Adım 2:** Çalıştır → başarısız. **Adım 3:** `KeyTranslator`'ı yaz (`UCKeyTranslate`, `deadKeyState` taşınır; `carbonModifiers`: shift=2, option=8, control=4, command=1). **Adım 4:** Çalıştır → geçer (V15 ile tutarlı).
- [ ] **Adım 5: InputPolicyEngine testi**

```swift
import Testing; import CoreGraphics
@testable import NobetciSystem
@Test func policyDecisions() throws {
    var e = InputPolicyEngine(translator: KeyTranslator.currentLayoutData().map { KeyTranslator(layoutData: $0) })
    #expect(e.decide(policy: .passThrough, type: .keyDown, keyCode: 0, flags: []) == .pass)
    #expect(e.decide(policy: .lockOnFirstInput, type: .mouseMoved, keyCode: nil, flags: []) == .swallowAndLock)
    #expect(e.decide(policy: .blockAll, type: .leftMouseDown, keyCode: nil, flags: []) == .swallow)
    #expect(e.decide(policy: .blockAll, type: .keyDown, keyCode: 36, flags: []) == .passcodeReturn)
    #expect(e.decide(policy: .blockAll, type: .keyDown, keyCode: 51, flags: []) == .passcodeDelete)
    #expect(e.decide(policy: .blockAll, type: .keyDown, keyCode: 48, flags: .maskCommand) == .swallow) // Cmd+Tab
    if case .passcodeText = e.decide(policy: .blockAll, type: .keyDown, keyCode: 33, flags: []) {} else { Issue.record("harf") }
}
```

- [ ] **Adım 6:** Çalıştır → başarısız. **Adım 7:** `InputPolicyEngine`'i kurallara göre yaz. **Adım 8:** Çalıştır → geçer.
- [ ] **Adım 9:** commit `feat(system): KeyTranslator + InputPolicyEngine (Türkçe Q doğrulandı)`

---

### Görev 1.4: InputFilter adaptörü — D7

**Files:** Create `Sources/NobetciSystem/Input/InputFilter.swift`; manuel doğrulama (birim testi yok — tap kurulumu erişilebilirlik izni ister).

**Interface & davranış sözleşmesi:**
- `public final class InputFilter: @unchecked Sendable { init(onLockRequested: @Sendable () -> Void, onPasscode: @Sendable (InputDecision) -> Void, onHealthChange: @Sendable (Bool) -> Void); func install() throws; func uninstall(); func setPolicy(_: InputPolicy); var policy: InputPolicy { get }; var isHealthy: Bool { get }; static func hasAccessibilityPermission(prompt: Bool) -> Bool }`.
- İki `CGEventTap` (`.cghidEventTap`, `.cgSessionEventTap`, `headInsertEventTap`), uygulamanın ana döngüsünden ayrı kendi iş parçacığı ve run loop'unda çalışır. Geri çağırım, `InputPolicyEngine.decide(...)` sonucuna göre davranır: `.pass`→olayı geçir; `.swallow`→`nil` döndür; `.swallowAndLock`→politikayı kilitle-öncesi yarıştan korumak için **önce** `blockAll`'a çek, `nil` döndür, `onLockRequested()`; `.passcode*`→`nil` döndür, `onPasscode(...)` ile kalkandaki şifre alanına ilet.
- **Yalnızca askıya alma + kendi şifre alanına iletme.** Sisteme ya da başka bir uygulamaya hiçbir olay enjekte edilmez; sahte olay üretilmez.
- `tapDisabledByTimeout`/`tapDisabledByUserInput` gelince ilgili tap hemen `CGEvent.tapEnable(tap:enable:true)` ile yeniden açılır; 0,5 sn'lik bir zamanlayıcı `CGEvent.tapIsEnabled` ile sağlığı yoklar; 3 ardışık başarısızlıkta `onHealthChange(false)` (motor bunu T14 sayar). `uninstall()` tüm tap'leri ve kaynakları söker; adaptör yalnızca nöbet süresince kuruludur.
- `hasAccessibilityPermission` = `AXIsProcessTrustedWithOptions`.

- [ ] **Adım 1:** `InputFilter`'ı yukarıdaki sözleşmeye göre yaz; karar mantığını doğrudan `InputPolicyEngine`'e devret (tap gövdesinde mantık tekrarı olmasın). Erişilebilirlik izni yoksa `install()` `throws`.
- [ ] **Adım 2: D7 manuel doğrulama (gerçek Mac, erişilebilirlik izni verilmiş).** Geçici debug akışı: "Test kilidi (10 sn)" → `setPolicy(.blockAll)` + kalkan; 10 sn sonra otomatik `passThrough` + kalkanı kaldır (kilitli kalma riski yok). Kilitliyken spec §13.4-2 matrisi denenir ve **hiçbiri çalışmamalı**: Cmd+Tab, Cmd+Space, Cmd+Opt+Esc, Cmd+Q, Ctrl+Cmd+Q, F3/Ctrl+↑/3-4 parmak kaydırma, Launchpad, Cmd+Shift+3/4/5, ekran köşeleri, Fn/Globe, dikte, harici klavye/fare. Terminal'in "Güvenli Klavye Girişi" açıkken tekrarlanır. Başka bir süreçten HID/oturum seviyesine ve `CGEventPostToPid` ile olay gönderilip sonuç belgelenir (spec §9.4: `CGEventPostToPid` kapsam dışı risk — gözlem kaydedilir). Sonuçlar `docs/test-report.md` D7. Zayıf nokta çıkarsa kiosk (Görev 5.x) ve yedekler devreye alınır.
- [ ] **Adım 3:** commit `feat(system): InputFilter girdi askıya alma adaptörü (D7 ölçüldü)`

---

### Görev 1.5: KioskGuard, LaunchAgent/BootSession — D8, D9, D10

**Files:** Create `Sources/NobetciSystem/Shield/KioskGuard.swift`, `Sources/NobetciSystem/Lifecycle/LaunchAgent.swift`, `Sources/NobetciSystem/Lifecycle/BootSession.swift`, `Resources/LaunchAgents/com.halil.nobetci.login.plist`, `…/com.halil.nobetci.plist`; Test `Tests/NobetciSystemTests/BootSessionTests.swift`.

**Interface & davranış:**
- `@MainActor public enum KioskGuard { static func engage(); static func disengage() }` — `engage`: `NSApp.activate` + `NSApp.presentationOptions=[.hideDock,.hideMenuBar,.disableProcessSwitching,.disableForceQuit,.disableSessionTermination,.disableHideApplication,.disableAppleMenu]`. Accessory uygulamada çalışmazsa (D8) kilitliyken `NSApp.setActivationPolicy(.regular)` yedeği.
- `public enum LaunchAgent { static func register(runAtLogin: Bool) throws; static func unregister() throws; static func kickstart() }` — `SMAppService.agent(plistName:)`; iki plist (`RunAtLoad` açık/kapalı), ikisinde de `KeepAlive={SuccessfulExit=false}`, `ThrottleInterval=1`, `ProcessType=Interactive`, `LimitLoadToSessionType=Aqua`.
- `public enum BootSession { static func current() -> String }` = `kern.bootsessionuuid` (`sysctlbyname`). **Saf okunur; TDD edilebilir.**

- [ ] **Adım 1: BootSession testi**

```swift
import Testing
@testable import NobetciSystem
@Test func bootSessionIsStableNonEmpty() {
    let a = BootSession.current()
    #expect(!a.isEmpty); #expect(a == BootSession.current())
}
```

- [ ] **Adım 2:** Çalıştır → başarısız. **Adım 3:** `BootSession.current()` = `sysctlbyname("kern.bootsessionuuid", …)`. **Adım 4:** Çalıştır → geçer.
- [ ] **Adım 5:** `KioskGuard`, `LaunchAgent`'ı ve iki plist'i sözleşmeye göre yaz.
- [ ] **Adım 6: D8/D9/D10 manuel** — `SMAppService` ile kayıt; `launchctl print gui/$(id -u)/com.halil.nobetci` → yüklü. `kill -9 <pid>` → ≤ 2 sn'de yeni süreç (ölç). Debug "Test kilidi"nde Cmd+Tab/Force Quit engelli mi (D8); başka uygulama öndeyken kilit → öne geçiyor mu (D9). Sonuçlar `docs/test-report.md`. Başarısızsa spec §15.2 yedekleri.
- [ ] **Adım 7:** commit `feat(system): kiosk, launchd ajanı ve açılış oturumu (D8/D9/D10 ölçüldü)`

---

# Faz 2 — Yüz modeli (`tools/model`, `nobetci-eval`) — D14

### Görev 2.1: Ağırlık indirme ve Core ML dönüşümü (eşitlik)

**Files:** Create `tools/model/pyproject.toml`, `tools/model/download.py`, `tools/model/convert.py`, `tools/model/parity.py`; Modify `Makefile` (`model`).

**Interface & davranış:** `make model` → aday ağırlıkları **sabitlenmiş URL + SHA-256** ile indirir (`download.py`, yanlış özette durur), `convert.py` Core ML mlprogram FP16'ya çevirir (`build/Model.mlpackage`), `parity.py` 100 hizalanmış yüzde orijinal ile Core ML çıktısının kosinüsünü ölçer. **Kapı:** kosinüs < 0,999 ise çıkış kodu 1. (V10: araç zinciri çalışıyor.)

- [ ] **Adım 1:** `pyproject.toml` (uv; torch, coremltools, numpy, onnx/onnxruntime adaya göre). **Adım 2:** `download.py` — `URLS` ve `SHA256` sözlükleri; indir, `hashlib.sha256` doğrula, `tools/model/weights/`'e yaz. **Adım 3:** `convert.py` — PyTorch/ONNX → `ct.convert(minimum_deployment_target=macOS14, compute_precision=FLOAT16)`; `build/Model.mlpackage`. **Adım 4:** `parity.py` — 100 örnek, kosinüs; `assert >= 0.999`. **Adım 5:** `make model` çalışır, `build/Model.mlpackage` üretir, parity geçer. **Adım 6:** commit `build(model): ağırlık indirme (SHA-256) ve Core ML dönüşümü + eşitlik`.

### Görev 2.2: LFW değerlendirmesi ve model seçimi — D14

**Files:** `Sources/nobetci-eval/main.swift`, `Sources/NobetciVision/FaceAligner.swift` (Görev 4.3'te de kullanılır), Modify `Makefile` (`eval`); çıktı `docs/model-evaluation.md`.

**Interface & davranış:** `nobetci-eval <mlmodelc> <lfw-dir>` — **üretimdeki hattın aynısı** (Vision tespiti + 5 nokta hizalama + Core ML) ile LFW 6.000 çift + kimlikler arası sahte çiftleri değerlendirir; TAR@FAR=1e-3/1e-4/1e-5, ROC, Neural Engine gecikmesi, model boyutu yazar. **Seçim:** gecikme ≤ 10 ms ve boyut ≤ 150 MB koşuluyla TAR@FAR=1e-4 en yüksek aday; eşiklerin değerleri (`T_kabul`,`T_sürdür`,`T_red`) spec §6.8-5'e göre buradan belirlenir.

- [ ] **Adım 1:** LFW `MLMultiArray` hizalama hattını `nobetci-eval`'e kur. **Adım 2:** Çiftleri değerlendir, metrikleri `docs/model-evaluation.md`'ye yaz. **Adım 3:** Adaylar (ArcFace/AdaFace/FaceNet) için tekrarla, seçim kuralını uygula, eşik değerlerini sabitle. **Adım 4:** Seçilen modeli `make model` varsayılanı yap. **Adım 5:** commit `feat(eval): LFW değerlendirmesi, model ve eşik seçimi (D14)`. Sonuç `docs/test-report.md` D14/D15 (gecikme).

---

# Faz 3 — Çekirdek (saf mantık, tam TDD)

Modeller `Sendable`, çoğu `struct`/`enum`. `GuardEngine` saf `reduce`. Hepsi `make test` ile, donanımsız. Hedef kapsam ≥ %90.

### Görev 3.1: Alan modelleri

**Files:** Create `Sources/NobetciCore/Model/{GuardState,GuardEvent,GuardEffect,GuardSettings}.swift`; Test `Tests/NobetciCoreTests/GuardSettingsTests.swift`.

**Interfaces (Produces):**
- `public enum GuardState: Equatable, Sendable { case off, preparing, guarding(owner: OwnerPresence2), locked(LockedContext) }` — burada `OwnerPresence2` yerine `enum Presence { case present, absent }` kullan (ad çakışmasını önlemek için `Presence`). Yani `case guarding(Presence)`.
- `public enum Presence: Sendable, Equatable { case present, absent }`.
- `public struct LockedContext: Equatable, Sendable { var reason: LockReason; var since: TimeInterval; var bystanderPresent: Bool }`.
- `public enum LockReason: Equatable, Sendable { case strangerFace, facelessPerson, input, lidAngle, motion, cameraCovered, cameraLost, cameraShift, display, usb, power, sleep, relaunch, filterLost }` (T1–T14 karşılığı).
- `GuardEvent` (spec §4.2): `.frame(FrameSummary)`, `.cameraHealth(CameraHealth)`, `.lidAngle(Double)`, `.motion(MotionSummary)`, `.input`, `.hardware(HardwareChange)`, `.willSleep`, `.didWake`, `.passcode(PasscodeAttempt)`, `.command(UserCommand)`, `.tick`, `.launched(bootSession: String, previous: PersistedState?)`.
- `FrameSummary` (spec §6): `ownerTrack: OwnerTrackState?`, `strangerFacePresent: Bool`, `uncertainFacePresent: Bool`, `bodyPresentBeyondThreshold: Bool`, `anyPersonPresent: Bool`, `blinkObservedWithin: TimeInterval?`, `strictGestureSatisfied: Bool`, `ownerQualityOK: Bool`, `sceneEmptyFor: TimeInterval`, `timestamp: TimeInterval`.
- `GuardEffect` (spec §4.2, **fotoğraf ve aktif gösterme YOK**): `.startSensors`, `.stopSensors`, `.showShield(ShieldMessage)`, `.hideShield`, `.setInputPolicy(InputPolicy2)`, `.wakeKeep(Bool)`, `.logEvent(GuardEventRecord)`, `.notify(NotificationKind)`, `.showReport(SessionRecord)`, `.persist(PersistedState)`. (`InputPolicy2` Core'un kendi enum'u; System'deki `InputPolicy`'ye uygulama katmanında eşlenir — Core, System'e bağımlı değil.)
- `GuardSettings: Codable, Equatable, Sendable` (spec §8.5 varsayılanları): `returnBehavior: ReturnBehavior = .closeGuard`, `distance: Sensitivity = .medium`, `lid: Sensitivity = .medium`, `motion: Sensitivity = .medium`, `facelessDetection = true`, `cameraShiftDetection = true`, `displayTrigger = true`, `usbTrigger = true`, `powerTrigger = true`, `strictMode = false`, `historyRetentionDays = 30`, `startAtLogin = true`, `hotKey: HotKeySpec = .default`.

- [ ] **Adım 1:** Varsayılanlar testi

```swift
import Testing
@testable import NobetciCore
@Test func settingsDefaultsMatchSpec() {
    let s = GuardSettings()
    #expect(s.returnBehavior == .closeGuard)
    #expect(s.distance == .medium && s.lid == .medium && s.motion == .medium)
    #expect(s.facelessDetection && s.cameraShiftDetection && s.displayTrigger && s.usbTrigger && s.powerTrigger)
    #expect(!s.strictMode)
    #expect(s.historyRetentionDays == 30 && s.startAtLogin)
}
@Test func settingsRoundTripJSON() throws {
    var s = GuardSettings(); s.strictMode = true; s.distance = .near
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(GuardSettings.self, from: data) == s)
}
```

- [ ] **Adım 2:** Çalıştır → başarısız. **Adım 3:** Tüm tipleri yaz (yalnızca veri + varsayılanlar). **Adım 4:** Çalıştır → geçer. **Adım 5:** commit `feat(core): alan modelleri ve ayar varsayılanları`.

### Görev 3.2: FaceMatcher

**Files:** Create `Sources/NobetciCore/Presence/FaceMatcher.swift`; Test `…/FaceMatcherTests.swift`.

**Interfaces:** `public struct Thresholds: Sendable { var accept, sustain, reject: Float }`; `public struct FaceMatcher: Sendable { init(profile: [[Float]], thresholds: Thresholds); func score(_ v: [Float]) -> Float; func classify(_ v: [Float], hasVerifiedTrack: Bool) -> MatchResult }`; `public enum MatchResult: Equatable, Sendable { case owner, stranger, uncertain }`. `score` = profil vektörlerine kosinüsün en yüksek 3'ünün ortalaması. `classify`: doğrulanmış iz varsa `score ≥ sustain`→owner; yoksa `score ≥ accept`→owner; `score < reject`→stranger; arası→uncertain.

- [ ] **Adım 1:** Testler (kosinüs 1,0; dik 0,0; owner/stranger/uncertain sınırları; histerezis: `hasVerifiedTrack=true` ile `sustain..<accept` arası owner, `false` ile uncertain). **Adım 2:** başarısız. **Adım 3:** yaz. **Adım 4:** geçer. **Adım 5:** commit `feat(core): FaceMatcher — kosinüs, top-3, üç eşik`.

### Görev 3.3: OwnerPresence, BlinkDetector, UnlockEvaluator

**Files:** Create `Sources/NobetciCore/Presence/OwnerPresence.swift`, `Sources/NobetciCore/Liveness/BlinkDetector.swift`, `Sources/NobetciCore/Presence/UnlockEvaluator.swift`; Testleri.

**Interfaces:**
- `OwnerPresence` — ardışık kare oylarıyla sahip izini doğrular (3 kare `accept` üstü), `sustain` üstü kaldıkça ve iz kopmadıkça sürdürür, son gözlemden 1,5 sn sonra `.absent`. `func update(match: MatchResult, trackAlive: Bool, now: TimeInterval) -> Presence`.
- `BlinkDetector` — EAR dizisinden kırpma: taban uyarlanır, oran tabanın %60'ı altına inip 50–400 ms içinde dönerse kırpma. `mutating func feed(ear: Float, now: TimeInterval) -> Bool`; `func blinkedWithin(_ window: TimeInterval, now: TimeInterval) -> Bool`.
- `UnlockEvaluator` — dört koşul (spec §5.4): `func evaluate(frame: FrameSummary, settings: GuardSettings, now: TimeInterval) -> UnlockDecision`; `public enum UnlockDecision: Equatable, Sendable { case unlock, needBlink, bystander, lowQuality, keepWaiting, needGesture(Turn) }`. Sıkı modda `needGesture`.

- [ ] Her biri için ayrı TDD döngüsü (başarısız test → yaz → geçer). Testler: sahip 3 kare sonra present; 1,5 sn sonra absent; iz kopunca hemen absent değil, zaman aşımıyla; kırpma 200 ms içinde algılanır, 600 ms'de algılanmaz; unlock yalnızca dört koşul + (sıkı modda) hareket birlikteyken; yanında yüz/gövde varsa `bystander`. Commit `feat(core): sahip varlığı, kırpma, kilit açma değerlendirmesi`.

### Görev 3.4: Sensör ve sahne karar mantığı

**Files:** Create `Sources/NobetciCore/Sensors/{LidAngleLogic,MotionLogic,SceneHealthLogic}.swift`; Testleri.

**Interfaces:** `LidAngleLogic` — taban açısı + hassasiyete göre eşik (3°/…); 2 ardışık örnek sapma → tetik. `MotionLogic` — eğim (yerçekimi yönünde sapma) ve yüksek frekanslı enerji eşikleri. `SceneHealthLogic` — ortalama parlaklık eşiği (örtülü), Laplacian varyansı (doku çöküşü), kare aralığı (donma), öteleme kayması (T8). Her biri saf `struct`, hassasiyet parametreli.

- [ ] Her biri TDD. Testler (kaydedilmiş gerçek izlerle, `Tests/.../Fixtures/`): masada duran Mac tetiklemez; 3° eşiğini aşan tek-örnek sapma tetiklemez ama iki-örnek tetikler; Review Focus 5 için eşikler. Commit `feat(core): kapak/hareket/sahne karar mantığı`.

### Görev 3.5 & 3.6 & 3.7: Şifre (hash + bekleme), oturum/rapor

**Files:** Create `Sources/NobetciCore/Passcode/{PasscodeHasher,LockoutPolicy}.swift`, `Sources/NobetciCore/Session/{SessionLog,ReportBuilder}.swift`, `Sources/NobetciCore/Storage/{SealedBoxCodec,SettingsCodec}.swift`; Testleri.

**Interfaces:**
- `PasscodeHasher` — PBKDF2-HMAC-SHA256 (CommonCrypto), 16 bayt tuz, 32 bayt çıktı, yineleme kalibrasyonlu (≥ 600.000). `static func hash(_ passcode: String, salt: Data, rounds: Int) -> Data`; `static func verify(_ passcode: String, salt: Data, rounds: Int, expected: Data) -> Bool` (sabit zamanlı, `timingsafe_bcmp`).
- `LockoutPolicy` — deneme sayacı; 5. yanlıştan sonra 30 sn, sonra ×2, tavan 15 dk; **yalnızca monoton saat** (Review Focus 4). `mutating func registerFailure(now:) -> TimeInterval` (bekleme), `func remaining(now:) -> TimeInterval`, `mutating func reset()`.
- `SealedBoxCodec` — `AES.GCM` zarf (CryptoKit). `SettingsCodec` — JSON + HMAC-SHA256; imza bozuksa `throw`, çağıran en güvenli varsayılana döner.
- `SessionLog`/`ReportBuilder` — `SessionRecord`, `GuardEventRecord` (fotoğraf alanı yok); rapor gerekir mi (kilit/yanlış şifre/müdahale/relaunch varsa) + özet metni.

- [ ] **Review Focus 4 testi (Görev 3.6):**

```swift
@Test func lockoutUsesMonotonicClockOnly() {
    var p = LockoutPolicy()
    for _ in 0..<5 { _ = p.registerFailure(now: 0) }
    #expect(p.remaining(now: 0) == 30)      // 5. yanlış → 30 sn
    #expect(p.remaining(now: 15) == 15)     // monoton 15 sn ilerledi
    #expect(p.remaining(now: 30) == 0)      // monoton 30 sn → bitti
    // duvar saati ayrı tutulur; remaining yalnızca now (monoton) ile hesaplanır — ayrı bir wall parametresi yok.
}
```

- [ ] Diğer testler: hash tur sayısı doğru, yanlış şifre `false`, sabit zaman; zarf yaz/oku, bozuk zarf `throw`; ayar imzası doğrula/bozulma; rapor "olay yok" vs "3 olay". Her bileşen ayrı commit.

### Görev 3.8: GuardEngine (reduce)

**Files:** Create `Sources/NobetciCore/Engine/GuardEngine.swift`; Test `…/GuardEngineTests.swift` (en geniş test dosyası).

**Interface:** `public struct GuardEngine { init(clock: Clock); func reduce(_ state: GuardState, _ event: GuardEvent, _ context: EngineContext) -> (GuardState, [GuardEffect]) }`; `EngineContext` = ayarlar + sahip profili meta + alt mantık nesneleri (matcher, lockout vb. — ya `inout` durumla ya da context içinde değişebilir referanslarla; saf kalması için durum `GuardState` içine gömülür).

Davranış: spec §5.1 durum tablosu + §5.3 tetikleyiciler + §5.4 kilit açma + §5.5 dönüş + §7.10 açılış. Tetikleyici kapsamı: T1 ve T12–T14 her alt durumda; T2–T11 yalnızca `guarding(.absent)`.

- [ ] **Adım 1: Review Focus 1 ve 5 testleri**

```swift
import Testing
@testable import NobetciCore
private func engine() -> (GuardEngine, EngineContext) { (GuardEngine(clock: ManualClock()), .default) }

@Test func facelessPersonRequiresPriorEmptyScene() {
    let (e, ctx) = engine()
    // sahip yeni kalktı (sahne boş değil, sceneEmptyFor küçük): gövde T2 tetiklememeli
    var f = FrameSummary.empty; f.bodyPresentBeyondThreshold = true; f.sceneEmptyFor = 0.5
    let (s1, fx1) = e.reduce(.guarding(.absent), .frame(f), ctx)
    #expect(s1 == .guarding(.absent)); #expect(!fx1.contains { if case .showShield = $0 { return true }; return false })
    // sahne ≥ 3 sn boş kaldıktan sonra gövde: T2 tetikler
    var g = FrameSummary.empty; g.bodyPresentBeyondThreshold = true; g.sceneEmptyFor = 3.2
    let (s2, _) = e.reduce(.guarding(.absent), .frame(g), ctx)
    if case .locked(let c) = s2 { #expect(c.reason == .facelessPerson) } else { Issue.record("kilit beklenirdi") }
}

@Test func sensorLossWarnsWithoutLocking() {
    let (e, ctx) = engine()
    let (s, fx) = e.reduce(.guarding(.absent), .hardware(.lidSensorLost), ctx)
    #expect(s == .guarding(.absent))                       // kilitlenmez
    #expect(fx.contains { if case .notify = $0 { return true }; return false })  // uyarı
}
@Test func cameraLossLocks() {
    let (e, ctx) = engine()
    let (s, _) = e.reduce(.guarding(.absent), .cameraHealth(.lost), ctx)
    if case .locked(let c) = s { #expect(c.reason == .cameraLost) } else { Issue.record("kilit beklenirdi") }
}
```

- [ ] **Adım 2:** Çalıştır → başarısız. **Adım 3:** `reduce`'u adım adım büyüt; her tetikleyici ve her kilit açma koşulu için önce test ekle. Kapsam: off→preparing (ön koşullar), preparing→guarding/off, present↔absent, her T, unlock (yüz/şifre), dönüş davranışı (varsayılan close / sürsün), willSleep→locked, didWake→locked, launched (aynı/farklı boot session → §7.10). **Adım 4:** `make coverage` → NobetciCore ≥ %90. **Adım 5:** commit `feat(core): GuardEngine durum makinesi ve tüm kurallar`.

---

# Faz 4 — Görüntü hattı (`NobetciVision`) — arayüz + manuel/fixture

Saf parçalar (hizalama matrisi, skor, iz eşleştirme, sahne ölçütleri) sentetik verilerle TDD; kamera ve Core ML çalıştırma manuel/fixture.

### Görev 4.1: CameraSource — dahili kamera, Center Stage, efekt uyarısı (D12)
**Interface:** `CameraSource` — `AVCaptureDevice.DiscoverySession(.builtInWideAngleCamera)`; Continuity Camera hariç; `uniqueID` sabitlenir; 1280×720 ≤30fps; `isCenterStageEnabled=false` (kapatılamazsa T8 kapalı + uyarı, D12); efektler açıksa uyarı; `wasInterrupted`/`runtimeError`→T7. Manuel doğrulama: yalnızca dahili kamera açılır, iPhone reddedilir; yeşil ışık nöbette yanar, bitince söner. Commit.

### Görev 4.2: FrameAnalyzer (saf) + FaceDetector
**Interface:** `FrameAnalyzer` — 64×36 gri küçültme (vImage), hareket/parlaklık/doku — **saf, TDD** (sentetik görüntülerle). `FaceDetector` — Vision istekleri (rect/landmarks/quality/humanRect/registration), hız sınırları (spec §6.2). Analyzer TDD; detector fixture görüntülerle. Commit.

### Görev 4.3: FaceAligner (saf, TDD) + FaceEmbedder
**Interface:** `FaceAligner` — 5 nokta → 112×112 benzerlik dönüşümü (bilinen noktalar → beklenen matris, TDD). `FaceEmbedder` — `MLModel` sarmalayıcı, `computeUnits=.all`, L2-normalize. Aligner TDD; embedder fixture + V10 çalışma anı derleme. Commit.

### Görev 4.4: TrackManager (saf, TDD) + VisionPipeline
**Interface:** `TrackManager` — IoU iz eşleştirme, kimlik oyları — TDD. `VisionPipeline` — kareden `FrameSummary`; uyarlanır hız; **yabancı vektörü saklamaz**. Pipeline entegrasyonu Görev 7 kabul testinde. Commit.

---

# Faz 5 — Kalan sistem adaptörleri

### Görev 5.1: LidAngleSensor, Accelerometer — D1, D2
**Interface:** `LidAngleSensor` — IOHID (VID 0x05AC, PID 0x8104, usage 0x20/0x8A), 20 Hz, `IOHIDDeviceGetReport(feature,1)`→açı (V2). `Accelerometer` — SPU HID (0xFF00/3), `ReportInterval`, 22 baytlık rapordan eksen (V3; çözüm D2'de kesinleşir). İkisi de `AsyncStream<…>` yayınlar; yoksa adaptör "yok" bildirir (motor yedeğe geçer). Manuel D1/D2 (tanılama panelinde kapağı oynat, Mac'i eğ). Commit.

### Görev 5.2: HardwareWatcher, SleepObserver, HotKey — D17
**Interface:** `HardwareWatcher` — ekran (`CGDisplayRegisterReconfigurationCallback`), HID/USB (`IOServiceAddMatchingNotification`), güç (`IOPSNotificationCreateRunLoopSource`, yalnızca AC↔pil). `SleepObserver` — `NSWorkspace.willSleep/didWake`. `HotKey` — Carbon `RegisterEventHotKey`, varsayılan ⌃⌥⌘L, çakışmada hata. Manuel D17 (tak/çıkar). Commit.

### Görev 5.3: KeychainStore, SecureFileStore
**Interface:** `KeychainStore` — `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, iCloud senk kapalı; şifre özeti + sayaç + anahtarlar. `SecureFileStore` — `SealedBoxCodec` ile `~/Library/Application Support/Nöbetçi/` altına profil, oturum kayıtları; `SettingsCodec` ile imzalı ayar. Entegrasyon testleri (yaz/oku/bozulma — gerçek Keychain erişimiyle, yerelde). Commit.

---

# Faz 6 — Arayüz (`Nobetci`)

### Görev 6.1: AppModel + EffectRunner
**Interface:** `@MainActor @Observable final class AppModel` — kompozisyon kökü; `GuardCoordinator` actor'ı `GuardEngine`'i sarmalar, olayları sırayla işler, `[GuardEffect]` döndürür. `EffectRunner` her `Effect`'i adaptöre bağlar (`.setInputPolicy`→`InputFilter`, `.showShield`→`ShieldWindowController`, `.wakeKeep`→`WakeKeeper`, …). Core↔System enum eşlemesi burada. Actor mantığı testlenir (sahte adaptörlerle effect sırası). Commit.

### Görev 6.2: MenuView
Durum satırı, "Uzaktayım" / "Korumayı kapat", ön koşul eksikse çözüm butonu, nöbette sensör durumları (kamera/kapak/ivmeölçer/uyanık tutma). Commit.

### Görev 6.3: ShieldView
Cam kart: kilit simgesi, "%@'ın Mac'i korunuyor", **"Kamera etkin"**, saat/gün, durum metni (`searching`/`blink`/`bystander`/`retry`/`turn`), tuşta beliren şifre alanı, yanlışta sarsılma. "Şeffaflığı azalt" açıksa opak renk. Commit.

### Görev 6.4: Kurulum sihirbazı
Adımlar (spec §8.2): tanıtım+gizlilik → izinler (kamera/erişilebilirlik/bildirim, verilince otomatik ilerle) → sistem kontrolleri (FileVault/otomatik giriş/Siri/Sesli Denetim uyarıları, D20) → yüz kaydı (dairesel önizleme, 40–60 vektör, kalite/tek yüz, gözlüklü tur) → şifre (≥6, tekrar **kalkandaki yakalama yöntemiyle** — Review Focus 2) → tercihler (dönüş/kısayol/girişte başlat) → deneme kilidi. Commit (adım başına ara commit'ler).

### Görev 6.5: Ayarlar + Rapor + Tanılama (DEBUG)
Ayarlar sekmeleri (spec §8.5, **fotoğraf sekmesi yok; Geçmiş sekmesi**); hassas işlemler şifre ister (§8.6), "Şifremi unuttum" `LAContext` ile. Rapor: özet + zaman çizelgesi (fotoğraf yok), geçmiş, sil. Tanılama paneli (yalnızca DEBUG): canlı sinyaller + rehberli senaryolar + otomatik tepki süresi ölçümü (D1/D13 burada). Commit'ler.

---

# Faz 7 — Kabul, performans, dağıtım

### Görev 7.1: Kabul test matrisi (spec §13.4) → `docs/test-report.md`
T1–T14 tepki süreleri; girdi matrisi (D7 tam); kalkan kapsaması; blur okunamazlık; kilit açma başarı/sahtecilik (basılı fotoğraf, telefon videosu; sıkı mod); şifre (Türkçe karakterler, ölü tuş, Option, bekleme, yeniden başlatmada sayaç); uyku engelleme (Slack/Teams **aktif göstermez** — doğru "boşta" gösterir; `pmset` yalnızca uyku bildirimleri); yaşam döngüsü (`kill -9`, uyku, yeniden başlatma, tek kopya); imza; **gizlilik: `lsof` ağ yok, diskte şifresiz yüz verisi yok**; performans §11 (30 dk). Her satır ölçümüyle yazılır.

### Görev 7.2: Performans bütçeleri — D15
`docs/test-report.md` §11 tablosu: boş sahne CPU < %5, kişi < %25, bellek < 300 MB, tepki süreleri, Neural Engine ≤ 10 ms, 30 dk enerji. Aşımda analiz hızı/çözünürlük ayarı.

### Görev 7.3: DMG, KURULUM.md, README, CHANGELOG, kaldırma
`make dist` → `Nöbetçi-<sürüm>.dmg`; `KURULUM.md` (sürükle + "Yine de Aç"); `README`; `CHANGELOG`; Ayarlar'da "Nöbetçi'yi kaldır" (launchd kaydı + Keychain + veri temizler, şifre ister). D21: ikinci bir Mac'te (macOS 14/15) kabul alt kümesi. Commit `release: 1.0.0`.

---

## Self-Review notu
- **Spec kapsamı:** §1–§16 bölümlerinin her gereksinimi bir göreve bağlı (koruma mantığı→Faz 3, görüntü→Faz 4, sistem→Faz 1+5, arayüz→Faz 6, güvenlik/kripto→3.5–3.7+5.3, dağıtım→0+7, model→2). Fotoğraf ve aktif gösterme bilinçli olarak yok.
- **Altitude:** Saf mantık tam kodla; izin/donanım adaptörleri arayüz+davranış+manuel D-ölçümü (keylogger benzeri düşük seviye yakalama gövdeleri plana gömülmez; uygulama sırasında spec ve `tools/probes/` rehberliğinde yazılır).
- **Tip tutarlılığı:** `Presence`, `InputPolicy`/`InputPolicy2` (Core/System ayrımı), `MatchResult`, `UnlockDecision`, `LockReason`, `GuardEffect` (fotoğraf/aktif-gösterme alanları yok) plan boyunca aynı.
- **Review Focus:** 5 maddenin testi ilgili göreve yerleştirildi (1→3.8, 2→1.3/6.4, 3→1.2, 4→3.6, 5→3.8).
