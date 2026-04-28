import SwiftUI

// MARK: - RaiseUp 브랜드 컬러

extension Color {
    /// 다크 배경 — 가죽/석재 다크브라운
    static let ruBackground = Color(hex: "1A0F06")
    /// 대리석 라이트 배경
    static let ruMarble     = Color(hex: "E8D9C0")
    /// 카드 배경 (대리석보다 살짝 어둠)
    static let ruCard       = Color(hex: "D4C5A9")
    /// 다크 테마 카드 배경
    static let ruDarkCard   = Color(hex: "2E1B0E")
    /// 골드 포인트
    static let ruGold       = Color(hex: "C9A84C")
    /// 다크 텍스트 (라이트 배경 위)
    static let ruDark       = Color(hex: "2C1810")
    /// 서브 텍스트
    static let ruSubtext    = Color(hex: "7A6550")

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch s.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
