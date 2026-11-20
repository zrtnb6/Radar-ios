import Foundation
import SwiftData

@Model
final class Asset {
    @Attribute(.unique) var id: Int64
    var releaseID: Int64
    var name: String
    var size: Int64
    var contentType: String
    var downloadURL: String
    var createdAt: Date?
    var updatedAt: Date?
    var downloadCount: Int?
    /// 附件类型原始值（ipa / dmg / archive / other）。iOS 客户端以 IPA 为主要识别对象。
    var kindRaw: String

    init(
        id: Int64,
        releaseID: Int64,
        name: String,
        size: Int64,
        contentType: String,
        downloadURL: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        downloadCount: Int? = nil,
        kind: AssetKind
    ) {
        self.id = id
        self.releaseID = releaseID
        self.name = name
        self.size = size
        self.contentType = contentType
        self.downloadURL = downloadURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.downloadCount = downloadCount
        self.kindRaw = kind.rawValue
    }

    var kind: AssetKind {
        get { AssetKind(rawValue: kindRaw) ?? AssetKind.detect(fileName: name) }
        set { kindRaw = newValue.rawValue }
    }

    /// iOS 上可直接安装（侧载）的附件：.ipa。
    var isIPA: Bool { kind == .ipa }

    /// 旧版本 macOS 端的判别方式，保留给「仅显示 IPA」过滤以外的只读判断。
    var isDMG: Bool { kind == .dmg }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var fileExtension: String {
        (name as NSString).pathExtension.uppercased()
    }
}
