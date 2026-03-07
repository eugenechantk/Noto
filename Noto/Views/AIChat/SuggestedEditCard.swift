//
//  SuggestedEditCard.swift
//  Noto
//
//  Green-bordered card showing diff preview with context lines (grey) and
//  additions (green with + marker). Includes Dismiss/Accept action buttons.
//

import SwiftUI
import os.log
import NotoAIChat

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "SuggestedEditCard")

struct SuggestedEditCard: View {
    let proposal: EditProposal
    let status: EditStatus
    var onAccept: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let accentGreen = Color(red: 0, green: 0.70, blue: 0.17) // #00B32B
    private let deletionRed = Color(red: 0.85, green: 0.15, blue: 0.15)

    var body: some View {
        if status == .pending {
            pendingCard
        } else {
            statusLabel
        }
    }

    // MARK: - Pending Card

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tag
            Text("SUGGESTED EDITS")
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.08)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentGreen)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))

            // Operation summary
            VStack(spacing: 0) {
                ForEach(Array(proposal.operations.enumerated()), id: \.offset) { _, operation in
                    operationRow(operation)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8)
                    .stroke(accentGreen, lineWidth: 2)
            )

            // Action buttons
            HStack(spacing: 0) {
                Button {
                    onDismiss?()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.43)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .accessibilityLabel("Dismiss suggested edit")
                .accessibilityIdentifier("editDismissButton")

                Button {
                    onAccept?()
                } label: {
                    Text("Accept")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.43)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .background(accentGreen)
                .accessibilityLabel("Accept suggested edit")
                .accessibilityIdentifier("editAcceptButton")
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
            .overlay(
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .stroke(accentGreen, lineWidth: 2)
            )
        }
        .accessibilityIdentifier("suggestedEditCard")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested edits with \(proposal.operations.count) changes")
    }

    // MARK: - Status Label

    private var statusLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: status == .accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status == .accepted ? accentGreen : .secondary)
            Text(status == .accepted ? "Edit accepted" : "Edit dismissed")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Operation Row

    @ViewBuilder
    private func operationRow(_ operation: EditOperation) -> some View {
        switch operation {
        case .addBlock(let op):
            diffLine(text: op.content, marker: "+", color: accentGreen)

        case .updateBlock(let op):
            VStack(spacing: 0) {
                // Old content (deletion)
                diffLine(text: op.newContent, marker: "+", color: accentGreen)
            }
        }
    }

    private func diffLine(text: String, marker: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(marker)
                .font(.system(size: 17))
                .tracking(-0.43)
                .foregroundStyle(color)
                .frame(width: 28, alignment: .center)

            Text(text)
                .font(.system(size: 17))
                .tracking(-0.43)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 4)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
    }
}
