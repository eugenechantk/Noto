//
//  MockChatData.swift
//  Noto
//
//  Preview data for AI Chat views using real NotoAIChat types.
//

import Foundation
import NotoAIChat

enum MockChatData {
    static let references: [BlockReference] = [
        BlockReference(blockId: UUID(), content: "but this is a bullet"),
        BlockReference(blockId: UUID(), content: "this is a even more closer bullet"),
        BlockReference(blockId: UUID(), content: "this is another bullet"),
        BlockReference(
            blockId: UUID(),
            content: "This is a very long text detailing everything about today, and even something in the future. But it might not be too good to have something this long."
        )
    ]

    static let suggestedEditProposal = EditProposal(
        operations: [
            .addBlock(AddBlockOp(parentId: UUID(), content: "today is a lovely day because it is very good"))
        ],
        summary: "Add a new thought"
    )

    static let messages: [ChatMessage] = [
        ChatMessage(
            role: .user,
            text: "what am i thinking today"
        ),
        ChatMessage(
            role: .ai,
            text: "You are thinking about a lot of things:\n1. what are you doing with your life\n2. What do you want to eat today\n3. How are you doing\n\nLet me add more text to your note",
            references: references,
            editProposal: suggestedEditProposal
        )
    ]
}
