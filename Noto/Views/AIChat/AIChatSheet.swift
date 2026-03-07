//
//  AIChatSheet.swift
//  Noto
//
//  Main AI Chat sheet view: grabber, title bar, scrollable message list, composer bar.
//  Wired to AIChatViewModel for live API integration and persistence.
//

import SwiftUI
import os.log
import NotoAIChat

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "AIChatSheet")

struct AIChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: AIChatViewModel

    @State private var composerText: String = ""

    private var isLoading: Bool {
        viewModel.state == .loading || viewModel.state == .streaming
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .trailing, spacing: 24) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageRow(
                                message: message,
                                onAcceptEdit: { viewModel.acceptEdit(messageId: message.id) },
                                onDismissEdit: { viewModel.dismissEdit(messageId: message.id) }
                            )
                                .id(message.id)
                        }

                        if isLoading {
                            ChatLoadingIndicator()
                                .id("loading")
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.state) {
                    if isLoading {
                        withAnimation {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Error banner
            if case .error(let msg) = viewModel.state {
                errorBanner(msg)
            }

            // Composer bar
            ChatComposerBar(text: $composerText, isDisabled: isLoading, onSend: sendMessage)
        }
        .background(Color(.secondarySystemGroupedBackground).ignoresSafeArea())
        .accessibilityIdentifier("aiChatSheet")
        .onAppear {
            viewModel.onAppear()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            // Close button
            GlassToolbarButton(systemImage: "chevron.left") {
                dismiss()
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("chatCloseButton")

            Spacer()

            // Trailing spacer for centering
            Color.clear
                .frame(width: 44, height: 44)
        }
        .overlay {
            Text("AI Chat")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(labelPrimary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            if viewModel.canRetry {
                Button {
                    viewModel.retryLastMessage()
                } label: {
                    Text("Retry")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Retry last message")
                .accessibilityIdentifier("chatRetryButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Colors

    private var labelPrimary: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.9)
            : Color(red: 0.1, green: 0.1, blue: 0.1)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = composerText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        logger.debug("Send tapped: \(text)")
        composerText = ""

        Task {
            await viewModel.sendMessage(text)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
