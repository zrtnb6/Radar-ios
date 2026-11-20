import SwiftUI

enum AppColors {
    /// 品牌蓝：与 Radar macOS 端的图标底色一致。
    static let accent = Color(red: 0.075, green: 0.345, blue: 0.665)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let subtle = Color(uiColor: .quaternaryLabel)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let separator = Color(uiColor: .separator)
    static let newRelease = Color(uiColor: .systemBlue)
    /// IPA 是 iOS 端的主角，用绿色区分；DMG 在 iOS 上不可安装，用中性色。
    static let ipa = Color(uiColor: .systemGreen)
    static let dmg = Color(uiColor: .secondaryLabel)
    static let warning = Color(uiColor: .systemOrange)
    static let error = Color(uiColor: .systemRed)
}

enum AppRadius {
    static let small: CGFloat = 6
    static let card: CGFloat = 14
}
