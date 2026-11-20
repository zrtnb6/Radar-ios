import SwiftUI
import UIKit

struct GitHubTokenSection: View {
    @EnvironmentObject private var appState: AppState

    @State private var tokenInput = ""
    @State private var hasSavedToken = KeychainService.hasToken()
    @State private var quota: GitHubRateLimitStatus?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasSavedToken {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(AppColors.ipa)
                    Text("已保存令牌，请求会带上 Bearer 认证")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            SecureField(hasSavedToken ? "输入新令牌以替换" : "粘贴 Fine-grained PAT", text: $tokenInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .padding(10)
                .background(AppColors.groupedBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    saveToken()
                } label: {
                    Text(hasSavedToken && tokenInput.isEmpty ? "保存" : "保存令牌")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBusy || tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    validate()
                } label: {
                    Text(isBusy ? "验证中…" : "验证令牌 / 查看配额")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)

                if hasSavedToken {
                    Button(role: .destructive) {
                        clearToken()
                    } label: {
                        Text("清除")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)
                }
            }

            if let quota {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quota.isAuthenticated
                         ? "已认证 · 剩余 \(quota.remaining.formatted()) / \(quota.limit.formatted()) 次"
                         : "未认证 · 剩余 \(quota.remaining.formatted()) / \(quota.limit.formatted()) 次")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(quota.isAuthenticated ? AppColors.ipa : AppColors.warning)
                    Text("配额将在 \(AppFormatters.relativeDate(quota.reset)) 重置")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? AppColors.error : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let url = URL(string: "https://github.com/settings/personal-access-tokens") {
                Link(destination: url) {
                    Label("在 GitHub 生成 Fine-grained PAT", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.medium))
                }
            }

            Text("令牌只写入系统 Keychain（设备解锁后可读），不进入数据库、日志或 iCloud；公开仓库不填令牌也能用，但匿名请求每小时仅 60 次。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func saveToken() {
        isBusy = true
        statusMessage = nil
        let token = tokenInput
        Task {
            do {
                try KeychainService.saveToken(token)
                await MainActor.run {
                    tokenInput = ""
                    hasSavedToken = KeychainService.hasToken()
                    statusMessage = "令牌已保存，正在校验配额…"
                    statusIsError = false
                    appState.showToast("GitHub 令牌已保存")
                }
                validate()
            } catch {
                await MainActor.run {
                    isBusy = false
                    statusIsError = true
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func validate() {
        isBusy = true
        statusMessage = nil
        Task {
            do {
                let status = try await GitHubClient().fetchRateLimit()
                await MainActor.run {
                    quota = status
                    hasSavedToken = KeychainService.hasToken()
                    isBusy = false
                    statusIsError = !status.isAuthenticated
                    statusMessage = status.isAuthenticated
                        ? "令牌有效，核心 API 限额已提升至 \(status.limit.formatted()) 次/小时。"
                        : "当前仍是匿名配额（60 次/小时）。如果刚保存令牌，请确认它有读取公开仓库的权限。"
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    statusIsError = true
                    statusMessage = error.userFacingMessage
                }
            }
        }
    }

    private func clearToken() {
        do {
            try KeychainService.deleteToken()
            tokenInput = ""
            hasSavedToken = false
            quota = nil
            statusIsError = false
            statusMessage = "已清除令牌，恢复匿名请求。"
            appState.showToast("已清除令牌")
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}
