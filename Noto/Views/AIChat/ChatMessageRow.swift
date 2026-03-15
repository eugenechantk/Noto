//
//  ChatMessageRow.swift
//  Noto
//
//  Renders a single chat message — user bubble (right-aligned) or AI response (left-aligned).
//

import SwiftUI
import os.log
import NotoAIChat

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "ChatMessageRow")

struct ChatMessageRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: ChatMessage
    var onAcceptEdit: (() -> Void)?
    var onDismissEdit: (() -> Void)?

    /// User bubble background — white in light mode, elevated dark in dark mode.
    private var userBubbleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.22, green: 0.22, blue: 0.24)
            : .white
    }

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .ai:
            aiResponse
        case .suggestedEdit:
            if let proposal = message.editProposal {
                SuggestedEditCard(
                    proposal: proposal,
                    status: message.editStatus ?? .pending,
                    onAccept: onAcceptEdit,
                    onDismiss: onDismissEdit
                )
            }
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        HStack {
            Spacer()
            Text(message.text)
                .font(.system(size: 20))
                .tracking(-0.45)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(userBubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("You said: \(message.text)")
        }
    }

    // MARK: - AI Response

    private var aiResponse: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !message.references.isEmpty {
                ReferencesSection(references: message.references)
            }

            MarkdownTextView(text: message.text)

            if let proposal = message.editProposal {
                SuggestedEditCard(
                    proposal: proposal,
                    status: .pending,
                    onAccept: onAcceptEdit,
                    onDismiss: onDismissEdit
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI response")
    }
}
