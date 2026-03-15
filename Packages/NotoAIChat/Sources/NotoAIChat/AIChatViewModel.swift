//
//  AIChatViewModel.swift
//  NotoAIChat
//
//  State machine for AI chat: idle -> loading -> complete/error.
//  Orchestrates persistence (AIChatBlockStore) and API calls (AIChatService).
//

import Foundation
import SwiftData
import os.log
import NotoModels
import NotoClaudeAPI
import NotoDirtyTracker

private let logger = Logger(subsystem: "com.noto", category: "AIChatViewModel")

/// State of the chat view.
public enum AIChatState: Sendable, Equatable {
    case idle
    case loading
    case streaming
    case complete
    case error(String)
}

/// A display-ready chat message derived from persisted Block data.
public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: ChatMessageRole
    public let text: String
    public let references: [BlockReference]
    public let editProposal: EditProposal?
    public let editStatus: EditStatus?

    public enum ChatMessageRole: Sendable {
        case user
        case ai
        case suggestedEdit
    }

    public init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        text: String,
        references: [BlockReference] = [],
        editProposal: EditProposal? = nil,
        editStatus: EditStatus? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.references = references
        self.editProposal = editProposal
        self.editStatus = editStatus
    }
}

/// ViewModel for the AI Chat sheet. Manages conversation state, persistence,
/// and API orchestration.
@MainActor
public final class AIChatViewModel: ObservableObject {
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var state: AIChatState = .idle

    private let chatService: AIChatService
    private let modelContext: ModelContext
    private let dirtyTracker: DirtyTracker
    private let noteContext: NoteContext?
    private let initialQuery: String?

    private var conversationBlock: Block?
    private var apiHistory: [Message] = []
    private var didAppear = false
    private var lastUserMessage: String?

    /// Full init with pre-built AIChatService (used in tests).
    public init(
        chatService: AIChatService,
        modelContext: ModelContext,
        dirtyTracker: DirtyTracker,
        noteContext: NoteContext? = nil,
        initialQuery: String? = nil
    ) {
        self.chatService = chatService
        self.modelContext = modelContext
        self.dirtyTracker = dirtyTracker
        self.noteContext = noteContext
        self.initialQuery = initialQuery
    }

    /// Convenience init that creates AIChatService from a SearchService.
    /// Reads API key from the environment.
    public convenience init(
        modelContext: ModelContext,
        dirtyTracker: DirtyTracker,
        searchService: any SearchServiceProtocol,
        noteContext: NoteContext? = nil,
        initialQuery: String? = nil
    ) {
        let apiKey = APIKeyStore.load()
            ?? ProcessInfo.processInfo.environment["CLAUDE_API_KEY"]
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? ""
        let chatService = AIChatService(
            apiKey: apiKey,
            searchService: searchService,
            modelContext: modelContext
        )
        self.init(
            chatService: chatService,
            modelContext: modelContext,
            dirtyTracker: dirtyTracker,
            noteContext: noteContext,
            initialQuery: initialQuery
        )
    }

    /// Called when the view appears. Fires the initial query if one was provided.
    public func onAppear() {
        guard !didAppear else { return }
        didAppear = true
        if let query = initialQuery, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            Task { await sendMessage(query) }
        }
    }

    /// Send a user message through the chat pipeline.
    public func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if case .loading = state { return }

        state = .loading
        lastUserMessage = trimmed

        // Ensure conversation exists
        if conversationBlock == nil {
            conversationBlock = AIChatBlockStore.createConversation(
                noteContext: nil,
                context: modelContext,
                dirtyTracker: dirtyTracker
            )
            try? modelContext.save()
        }

        guard let conversation = conversationBlock else {
            state = .error("Failed to create conversation")
            return
        }

        // Persist user message
        AIChatBlockStore.addUserMessage(
            content: trimmed,
            to: conversation,
            context: modelContext,
            dirtyTracker: dirtyTracker
        )

        // Set conversation title to the first user message
        if conversation.content == "Conversation" {
            conversation.content = trimmed
            conversation.updatedAt = Date()
            dirtyTracker.markDirty(conversation.id)
        }

        try? modelContext.save()

        // Add to display
        let userMsg = ChatMessage(role: .user, text: trimmed)
        messages.append(userMsg)

        // Build API history from prior turns
        apiHistory.append(Message(role: "user", content: .text(trimmed)))

        do {
            let result = try await chatService.chat(
                userMessage: trimmed,
                history: Array(apiHistory.dropLast()),
                noteContext: noteContext
            )

            // Persist AI response
            let aiBlock = AIChatBlockStore.addAIResponse(
                text: result.text,
                references: result.references,
                toolCalls: result.toolCallHistory,
                to: conversation,
                context: modelContext,
                dirtyTracker: dirtyTracker
            )
            try? modelContext.save()

            // Add AI message to display
            let aiMsg = ChatMessage(
                id: aiBlock.id,
                role: .ai,
                text: result.text,
                references: result.references,
                editProposal: result.editProposal
            )
            messages.append(aiMsg)

            // Update API history with assistant response
            apiHistory.append(Message(role: "assistant", content: .text(result.text)))

            // If there's an edit proposal, persist it too
            if let proposal = result.editProposal {
                let editBlock = AIChatBlockStore.addSuggestedEdit(
                    proposal: proposal,
                    parentResponseId: aiBlock.id,
                    to: conversation,
                    context: modelContext,
                    dirtyTracker: dirtyTracker
                )
                try? modelContext.save()

                let editMsg = ChatMessage(
                    id: editBlock.id,
                    role: .suggestedEdit,
                    text: proposal.summary,
                    editProposal: proposal,
                    editStatus: .pending
                )
                messages.append(editMsg)
            }

            state = .complete
            logger.debug("Chat turn complete: \(result.references.count) refs, hasEdit=\(result.editProposal != nil)")

        } catch {
            state = .error(Self.friendlyErrorMessage(error))
            logger.error("Chat error: \(error)")
            apiHistory.removeLast()
        }
    }

    /// Load messages from an existing conversation block.
    public func loadConversation(_ conversation: Block) {
        conversationBlock = conversation
        messages = AIChatBlockStore.fetchMessages(for: conversation).compactMap { block in
            blockToChatMessage(block)
        }

        // Rebuild API history from persisted messages
        apiHistory = messages.compactMap { msg in
            switch msg.role {
            case .user:
                return Message(role: "user", content: .text(msg.text))
            case .ai:
                return Message(role: "assistant", content: .text(msg.text))
            case .suggestedEdit:
                return nil
            }
        }
    }

    /// Accept a suggested edit: apply the proposal and update status.
    public func acceptEdit(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              let proposal = messages[index].editProposal else {
            logger.error("acceptEdit: message \(messageId) not found or has no proposal")
            return
        }

        // Find the persisted edit block
        guard let conversation = conversationBlock else { return }
        let editBlocks = AIChatBlockStore.fetchMessages(for: conversation)
        guard let editBlock = editBlocks.first(where: { $0.id == messageId }) else {
            logger.error("acceptEdit: no persisted block for \(messageId)")
            return
        }

        do {
            let proposalCreatedAt = editBlock.createdAt
            _ = try AIEditApplier.apply(
                proposal: proposal,
                proposalCreatedAt: proposalCreatedAt,
                context: modelContext,
                dirtyTracker: dirtyTracker
            )

            AIChatBlockStore.updateEditStatus(editBlock, status: .accepted, context: modelContext, dirtyTracker: dirtyTracker)
            try? modelContext.save()

            messages[index] = ChatMessage(
                id: messageId,
                role: .suggestedEdit,
                text: messages[index].text,
                editProposal: proposal,
                editStatus: .accepted
            )
            logger.debug("Edit accepted for message \(messageId)")
        } catch {
            logger.error("acceptEdit failed: \(error)")
            // Surface error — mark as dismissed with error context
            AIChatBlockStore.updateEditStatus(editBlock, status: .dismissed, context: modelContext, dirtyTracker: dirtyTracker)
            try? modelContext.save()
            messages[index] = ChatMessage(
                id: messageId,
                role: .suggestedEdit,
                text: "Edit could not be applied: the note may have changed since this suggestion was made.",
                editProposal: proposal,
                editStatus: .dismissed
            )
        }
    }

    /// Dismiss a suggested edit without applying.
    public func dismissEdit(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            logger.error("dismissEdit: message \(messageId) not found")
            return
        }

        guard let conversation = conversationBlock else { return }
        let editBlocks = AIChatBlockStore.fetchMessages(for: conversation)
        guard let editBlock = editBlocks.first(where: { $0.id == messageId }) else {
            logger.error("dismissEdit: no persisted block for \(messageId)")
            return
        }

        AIChatBlockStore.updateEditStatus(editBlock, status: .dismissed, context: modelContext, dirtyTracker: dirtyTracker)
        try? modelContext.save()

        messages[index] = ChatMessage(
            id: messageId,
            role: .suggestedEdit,
            text: messages[index].text,
            editProposal: messages[index].editProposal,
            editStatus: .dismissed
        )
        logger.debug("Edit dismissed for message \(messageId)")
    }

    /// Delete the entire conversation and all its child blocks.
    public func deleteConversation() {
        guard let conversation = conversationBlock else { return }
        // Delete all children first
        for child in conversation.sortedChildren {
            dirtyTracker.markDeleted(child.id)
            modelContext.delete(child)
        }
        dirtyTracker.markDeleted(conversation.id)
        modelContext.delete(conversation)
        try? modelContext.save()
        conversationBlock = nil
        messages = []
        apiHistory = []
        state = .idle
        logger.debug("Deleted conversation")
    }

    /// Retry the last failed message.
    public func retryLastMessage() {
        guard let last = lastUserMessage else { return }
        // Remove the failed user message from display if it was the last one
        if let lastMsg = messages.last, lastMsg.role == .user {
            messages.removeLast()
        }
        state = .idle
        Task { await sendMessage(last) }
    }

    /// Whether a retry is possible (there's a failed message to retry).
    public var canRetry: Bool {
        if case .error = state { return lastUserMessage != nil }
        return false
    }

    /// Map errors to user-friendly messages.
    static func friendlyErrorMessage(_ error: Error) -> String {
        if let apiError = error as? ClaudeAPIError {
            switch apiError {
            case .httpError(let statusCode, let body):
                // Try to parse the API error message from the response body
                if let body = body, let data = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = json["error"] as? [String: Any],
                   let message = errorObj["message"] as? String {
                    return message
                }
                switch statusCode {
                case 429:
                    return "Too many requests. Please wait a moment and try again."
                case 401:
                    return "API key is invalid or missing. Check your settings."
                case 500...599:
                    return "The AI service is temporarily unavailable. Please try again."
                default:
                    return "Something went wrong (HTTP \(statusCode)). Please try again."
                }
            case .decodingError:
                return "Received an unexpected response. Please try again."
            case .invalidResponse:
                return "Could not connect to the AI service. Check your internet connection."
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return "No internet connection. Please check your network and try again."
        }
        return "Something went wrong. Please try again."
    }

    private func blockToChatMessage(_ block: Block) -> ChatMessage? {
        if let ext = block.decodeExtension(UserMessageExtension.self), ext.role == .userMessage {
            return ChatMessage(role: .user, text: block.content)
        }
        if let ext = block.decodeExtension(AIResponseExtension.self), ext.role == .aiResponse {
            return ChatMessage(
                id: block.id,
                role: .ai,
                text: block.content,
                references: ext.references
            )
        }
        if let ext = block.decodeExtension(SuggestedEditExtension.self), ext.role == .suggestedEdit {
            return ChatMessage(
                id: block.id,
                role: .suggestedEdit,
                text: block.content,
                editProposal: ext.proposal,
                editStatus: ext.status
            )
        }
        return nil
    }
}
