import SwiftUI

/// 和网页版一样：顶部只有「@/」头像和标题，中间是气泡，底下是输入框和发送键。
struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var input = ""
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    private var canSend: Bool {
        !store.isLoading && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            inputBar
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: Binding(get: { !store.hasKey && !showSettings }, set: { _ in })) {
            KeySetupView()
                .environmentObject(store)
        }
        .task {
            await PingScheduler.shared.requestPermissionIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(size: 36)
            Text("@/")
                .font(.headline)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if store.isLoading {
                        TypingBubble()
                            .id("typing")
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.isLoading) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: inputFocused) { _, focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("发消息", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.blue.opacity(canSend ? 1 : 0.4)))
            }
            .disabled(!canSend)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func send() {
        guard canSend else { return }
        let text = input
        input = ""
        inputFocused = true
        Task { await store.send(text) }
    }
}

struct AvatarView: View {
    var size: CGFloat

    var body: some View {
        Text("@/")
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(white: 0.1)))
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.sender == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 80) }
            Text(message.content)
                .font(.system(size: 16))
                .italic(message.isError)
                .textSelection(.enabled)
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !isUser { Spacer(minLength: 80) }
        }
    }

    private var foreground: Color {
        if message.isError { return .secondary }
        return isUser ? .white : .primary
    }

    private var background: Color {
        isUser ? .blue : Color(.secondarySystemBackground)
    }
}

struct TypingBubble: View {
    var body: some View {
        HStack {
            Text("...")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer()
        }
    }
}
