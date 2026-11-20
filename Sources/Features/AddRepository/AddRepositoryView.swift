import SwiftUI

struct AddRepositoryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var syncService: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var isFieldFocused: Bool

    private let examples = ["https://github.com/zrtnb6/Radar-ios", "https://github.com/zrtnb6/Radar"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://github.com/owner/repository", text: $urlText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($isFieldFocused)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                        .lineLimit(1...3)

                    HStack {
                        Button {
                            if let paste = UIPasteboard.general.string {
                                urlText = paste
                                errorMessage = nil
                            }
                        } label: {
                            Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                                .font(.footnote)
                        }
                        Spacer()
                        if !urlText.isEmpty {
                            Button("清空") { urlText = "" }
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text("仓库链接")
                } footer: {
                    Text("支持仓库首页、/releases 与 /releases/tag/xxx 链接；输入后会自动解析 owner 与仓库名。")
                }

                Section("示例") {
                    ForEach(examples, id: \.self) { example in
                        Button {
                            urlText = example
                            errorMessage = nil
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                    .font(.footnote)
                                Text(example.replacingOccurrences(of: "https://github.com/", with: ""))
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage {
                    Section {
                        InlineNotice(level: .error, message: errorMessage)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView().controlSize(.small)
                                Text("正在检查仓库…")
                            } else {
                                Text("添加并立即检查")
                            }
                            Spacer()
                        }
                        .font(.body.weight(.semibold))
                    }
                    .disabled(isSubmitting || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("添加时会把已有版本标记为已读，只对之后发布的新版本推送通知。")
                }
            }
            .navigationTitle("添加项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if let paste = UIPasteboard.general.string,
                   let parsed = try? GitHubURLParser.parse(paste),
                   urlText.isEmpty {
                    urlText = parsed.canonicalURL
                }
            }
        }
        .presentationDetents([.large])
    }

    private func submit() {
        guard !isSubmitting else { return }
        let input = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isFieldFocused = false
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let outcome = try await appState.addRepository(input)
                await MainActor.run {
                    isSubmitting = false
                    switch outcome {
                    case .added(let repository):
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        appState.showToast("已添加 \(repository.fullName)")
                    case .duplicate(let repository):
                        appState.showToast("\(repository.fullName) 已在列表中")
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.userFacingMessage
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
