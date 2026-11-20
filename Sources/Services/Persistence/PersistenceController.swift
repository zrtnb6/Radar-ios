import Foundation
import SwiftData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    let storageError: String?

    init(inMemory: Bool = false) {
        let schema = Schema([Repository.self, Release.self, Asset.self, NotificationEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            storageError = nil
        } catch {
            do {
                let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [fallback])
                storageError = "本地数据库打开失败，当前使用临时内存存储。错误：\(error.localizedDescription)"
            } catch {
                fatalError("SwiftData 无法初始化：\(error.localizedDescription)")
            }
        }
    }
}
