import Foundation

/// Mevcut açılış oturumunun kimliği (`kern.bootsessionuuid`). Nöbetçi, kayıtlı
/// durumun bu oturuma mı ait olduğunu buradan anlar: aynı oturumda çökme/öldürme
/// sonrası Kilitli açılır, Mac yeniden başladıysa (oturum değişti) Kapalı açılır.
public enum BootSession {
    public static func current() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}
