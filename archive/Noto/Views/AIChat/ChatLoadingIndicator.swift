//
//  ChatLoadingIndicator.swift
//  Noto
//
//  Typing/loading animation displayed while waiting for AI response.
//

import SwiftUI

struct ChatLoadingIndicator: View {
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .offset(y: animateDot(index: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        }
        .accessibilityIdentifier("chatLoadingIndicator")
        .accessibilityLabel("AI is thinking")
    }

    private func animateDot(index: Int) -> CGFloat {
        let delay = Double(index) * 0.15
        let progress = max(0, min(1, animationPhase - delay))
        return -6 * sin(.pi * progress)
    }
}
