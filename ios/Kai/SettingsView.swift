import SwiftUI

/// 第一次打开（或者换了模型、对应的令牌还没填）：粘贴魔搭令牌 / 智谱 Key。填一次就行，存在 iPad 的钥匙串里。
struct KeySetupView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var key = ""

    private var provider: Provider { store.selectedModel.provider }

    var body: some View {
        VStack(spacing: 20) {
            AvatarView(size: 64)
            Text("先填一下\(provider.keyName)")
                .font(.title3.weight(.semibold))
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField(provider == .modelscope ? "粘贴令牌（ms- 开头）" : "粘贴 Key", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                store.saveKey(key, for: provider)
                key = ""
            } label: {
                Text("保存")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if provider == .modelscope && store.hasKey(for: .zhipu) {
                Button("先不填，接着用原来的 glm-4.6") {
                    store.selectModel(.glm46)
                }
                .font(.subheadline)
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
    }

    private var hint: String {
        switch provider {
        case .modelscope:
            return "现在默认用魔搭上免费的 GLM-5.2。令牌在魔搭网站（modelscope.cn）登录后，点右上角头像 → 访问令牌，复制那串 ms- 开头的。只存在这台 iPad 上，不会上传到 GitHub。"
        case .zhipu:
            return "只存在这台 iPad 上，不会上传到 GitHub。以后重装也不用再填。"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var newModelScopeKey = ""
    @State private var newZhipuKey = ""
    @State private var pingEnabled = PingScheduler.shared.isEnabled
    @State private var confirmReset = false
    @State private var exportURL: URL?

    private var modelBinding: Binding<ModelOption> {
        Binding(get: { store.selectedModel }, set: { store.selectModel($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("用哪个模型", selection: modelBinding) {
                        ForEach(ModelOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if !store.hasKey {
                        Text("还没填\(store.selectedModel.provider.keyName)，在下面填上才能用这个模型。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let used = store.lastReplyModel, used != store.selectedModel {
                        Text("上一条是 \(used.shortName) 回的（\(store.selectedModel.shortName) 当时不行，自动换了备用）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("模型")
                } footer: {
                    Text("点一下就换，下一条消息生效，聊天记录不变。用魔搭的两个时，主模型太忙或次数用完（429），会自动等几秒再试一次，还不行就换另一个魔搭模型回这一条。glm-4.6 要用智谱 Key，会花智谱额度。")
                }

                keySection(provider: .modelscope, text: $newModelScopeKey,
                           footer: "魔搭网站（modelscope.cn）→ 右上角头像 → 访问令牌。GLM-5.2 和 DeepSeek 共用这一个。免费，但每天有次数上限。")
                keySection(provider: .zhipu, text: $newZhipuKey,
                           footer: "只有选 glm-4.6 时才用。每条回复都会用掉一点智谱额度。")

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
                    LabeledContent("现在的模型", value: store.selectedModel.shortName)
                    LabeledContent("温度", value: String(ModelConfig.temperature))
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

    private func keySection(provider: Provider, text: Binding<String>, footer: String) -> some View {
        Section {
            LabeledContent("现在用的", value: store.maskedKey(for: provider))
            SecureField("换一个（粘贴）", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("保存") {
                store.saveKey(text.wrappedValue, for: provider)
                text.wrappedValue = ""
            }
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text(provider.keyName)
        } footer: {
            Text(footer + " 只存在这台 iPad 的钥匙串里。")
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
