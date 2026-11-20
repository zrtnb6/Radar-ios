import Foundation

struct ParsedRepositoryURL: Equatable, Sendable {
    let owner: String
    let repository: String

    var fullName: String { "\(owner)/\(repository)" }
    var canonicalURL: String { "https://github.com/\(owner)/\(repository)" }
}

enum GitHubURLParser {
    private static let componentPattern = /^[A-Za-z0-9_.-]+$/

    static func parse(_ input: String) throws -> ParsedRepositoryURL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "https",
              let host = components.host?.lowercased(), host == "github.com" || host == "www.github.com",
              components.user == nil, components.password == nil else {
            throw GitHubError.invalidURL
        }

        var pathComponents = components.path.split(separator: "/").map(String.init)
        guard pathComponents.count >= 2 else {
            throw GitHubError.invalidURL
        }

        let owner = pathComponents.removeFirst()
        var repository = pathComponents.removeFirst()
        if repository.lowercased().hasSuffix(".git") {
            repository = String(repository.dropLast(4))
        }

        let remainder = pathComponents
        let validRemainder = remainder.isEmpty ||
            remainder == ["releases"] ||
            (remainder.count >= 2 && remainder[0] == "releases" && remainder[1] == "tag")

        guard validRemainder,
              !owner.isEmpty, !repository.isEmpty,
              owner.wholeMatch(of: componentPattern) != nil,
              repository.wholeMatch(of: componentPattern) != nil,
              owner != ".", owner != "..", repository != ".", repository != ".." else {
            throw GitHubError.invalidURL
        }

        return ParsedRepositoryURL(owner: owner, repository: repository)
    }
}
