import SwiftUI

/// 第一次打开：粘贴智谱 API Key。填一次就行，存在 iPad 的钥匙串里。
struct KeySetupView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var key = ""

    var body: some View {
        VStack(spacing: 20) {
            AvatarView(size: 64)
            Text("先填一下智谱 API Key")
                .font(.title3.weight(.semibold))
            Text("只存在这台 iPad 上，不会上传到 GitHub。以后重装也不用再填。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField("粘贴 Key", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                store.saveKey(key)
            } label: {
                Text("保存")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(32)
        .frame(maxWidth: 480)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var newKey = ""
    @State private var pingEnabled = PingScheduler.shared.isEnabled
    @State private var confirmReset = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("现在用的", value: store.maskedKey)
                    SecureField("换一个 Key（粘贴）", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存新 Key") {
                        store.saveKey(newKey)
                        newKey = ""
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("智谱 API Key")
                } footer: {
                    Text("只存在这台 iPad 的钥匙串里。每条回复都会用掉一点智谱额度。")
                }

                Section {
                    Toggle("让他偶尔主动找你", isOn: $pingEnabled)
                        .onChange(of: pingEnabled) { _, value in
                            PingScheduler.shared.isEnabled = value
                            if value {
                                Task { await PingScheduler.shared.requestPermissionIfNeeded() }
                            }
                        }
                } footer: {
                    Text("你离开 app 后，他会在 1 到 3 天后的晚上 7 点到 10 点（布拉格是下午）发你一个「?」。你不回他不会连着发。")
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("导出聊天记录", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("从开场重新开始", role: .destructive) {
                        confirmReset = true
                    }
                } header: {
                    Text("聊天记录")
                } footer: {
                    Text("聊天记录存在这台 iPad 上，关掉重开还在。导出会生成一个文字文件，可以存到「文件」或发给别人。")
                }

                Section {
                    LabeledContent("模型", value: ZhipuConfig.model)
                    LabeledContent("温度", value: String(ZhipuConfig.temperature))
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("清掉开场之后的所有聊天？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("清掉，从开场重新开始", role: .destructive) {
                    store.resetToOpening()
                    dismiss()
                }
                Button("算了", role: .cancel) {}
            } message: {
                Text("清掉以后找不回来。想留着的话先导出。")
            }
            .onAppear(perform: prepareExport)
        }
    }

    private func prepareExport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("和 @ 的聊天记录.md")
        do {
            try store.exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}
