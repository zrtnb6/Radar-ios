import Foundation

enum DownloadError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse(Int)
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "附件地址无效，只允许 GitHub HTTPS 直链。"
        case .invalidResponse(let code):
            return "下载失败，服务器返回 \(code)。"
        case .fileSystem(let message):
            return "保存文件失败：\(message)"
        }
    }
}

/// 纯逻辑层：下载地址校验、文件名清理、目标路径生成。不访问网络，便于单元测试。
enum DownloadPolicy {
    private static let allowedHosts: Set<String> = ["github.com", "www.github.com"]

    /// 只接受 GitHub Release 附件的 HTTPS 直链，拒绝其它协议、域名、内嵌账号与任意跳转目标。
    static func validatedURL(_ raw: String) throws -> URL {
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              allowedHosts.contains(host),
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            throw DownloadError.invalidURL
        }
        return url
    }

    /// 去掉路径分隔符与控制字符，防止附件名造成路径穿越或写入隐藏文件。
    static func sanitizedFileName(_ raw: String) -> String {
        let last = (raw as NSString).lastPathComponent
        let invalid = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        var cleaned = last
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned.hasPrefix(".") {
            cleaned = "Radar-Download"
        }
        return cleaned
    }

    /// 同名文件不覆盖：追加 " 2"、" 3"…，极端情况下退回 UUID 文件名。
    static func destinationURL(for fileName: String, in directory: URL) -> URL {
        let name = sanitizedFileName(fileName)
        let base = directory.appendingPathComponent(name)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: base.path) else { return base }

        let nsName = name as NSString
        let ext = nsName.pathExtension
        let stem = nsName.deletingPathExtension
        for index in 2...999 {
            let candidateName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }
}
