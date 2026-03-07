//
//  ChatComposerBar.swift
//  Noto
//
//  Text field + send button, pinned to bottom above keyboard.
//  Uses Liquid Glass styling to match the app's bottom toolbar pattern.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "ChatComposerBar")

struct ChatComposerBar: View {
    @Binding var text: String
    var isDisabled: Bool = false
    let onSend: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var toolbarForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var placeholderColor: Color {
        toolbarForegroundColor.opacity(0.35)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Text field with glass effect
            HStack(spacing: 4) {
                TextField("Ask anything", text: $text)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(toolbarForegroundColor)
                    .tint(toolbarForegroundColor)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .disabled(isDisabled)
                    .onSubmit {
                        guard !isDisabled, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSend()
                    }
                    .accessibilityIdentifier("chatTextField")
                    .accessibilityLabel("Message input")

                Spacer()
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
            .glassEffect(.regular, in: .capsule)

            // Send button
            Button {
                guard !isDisabled, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(placeholderColor)
                    .frame(width: 36, height: 36)
            }
            .frame(height: 48)
            .padding(.horizontal, 6)
            .disabled(isDisabled)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityIdentifier("chatSendButton")
            .accessibilityLabel("Send message")
        }
        .opacity(isDisabled ? 0.5 : 1.0)
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
        .padding(.top, 4)
    }
}
