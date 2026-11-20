import Foundation

enum AppFormatters {
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func releaseDate(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return absoluteFormatter.string(from: date)
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    static func compactCount(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }
}

extension URL {
    static func safeHTTPS(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}
