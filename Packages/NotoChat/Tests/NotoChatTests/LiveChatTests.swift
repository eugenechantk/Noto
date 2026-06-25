import Foundation
import Testing
@testable import NotoChat

// End-to-end smoke test: real OpenRouter model + real vault. Gated on both env vars so it no-ops
// in CI / on other machines. The API key is NEVER hardcoded — supplied via OPENROUTER_API_KEY.
//
// Run:
//   OPENROUTER_API_KEY="sk-or-..." \
//   NOTO_VAULT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Noto" \
//   swift test --filter LiveChat
@Suite struct LiveChatTests {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    @Test func liveAgenticChatAgainstRealVault() async throws {
        guard let key = env["OPENROUTER_API_KEY"], !key.isEmpty else {
            print("[LiveChatTests] OPENROUTER_API_KEY not set — skipping.")
            return
        }
        guard let vaultPath = env["NOTO_VAULT"],
              FileManager.default.fileExists(atPath: vaultPath) else {
            print("[LiveChatTests] NOTO_VAULT not set/found — skipping.")
            return
        }

        let client = OpenRouterClient(configuration: .init(
            apiKey: key,
            referer: "https://noto.app",
            title: "Noto"
        ))
        let tools = VaultTools(root: URL(fileURLWithPath: vaultPath))
        let agent = ChatAgent(client: client, tools: tools) // default google/gemini-3.1-flash-lite

        let question = "Search my vault and tell me, in 3 short bullets, what I've written about pricing. Cite the specific notes you used."
        print("[LiveChatTests] model=\(agent.model)")
        print("[LiveChatTests] Q: \(question)\n")

        var streamed = ""
        var finalResult: AgentResult?
        for try await event in agent.sendStreaming(question) {
            switch event {
            case .toolCallStarted(let name, let args):
                print("  → tool: \(name)(\(args))")
            case .toolCallFinished(let name, let summary, _):
                print("  ✓ \(name): \(summary)")
            case .editProposal(let p):
                print("  ✎ proposed \(p.blocks.count) edit(s) to \(p.path)")
            case .textDelta(let delta):
                streamed += delta
            case .finished(let result):
                finalResult = result
            }
        }

        let result = try #require(finalResult)
        print("\n[LiveChatTests] ANSWER:\n\(result.answer)")
        print("\n[LiveChatTests] SOURCES: \(result.sources)")
        print("[LiveChatTests] rounds=\(result.rounds), hitRoundLimit=\(result.hitRoundLimit)")

        #expect(!streamed.isEmpty)            // streaming produced text
        #expect(!result.answer.isEmpty)
        #expect(!result.hitRoundLimit)
    }

    @Test func liveDiariesInTheLastFiveDays() async throws {
        guard let key = env["OPENROUTER_API_KEY"], !key.isEmpty,
              let vaultPath = env["NOTO_VAULT"], FileManager.default.fileExists(atPath: vaultPath) else {
            print("[LiveChatTests] env not set — skipping diaries test.")
            return
        }
        let client = OpenRouterClient(configuration: .init(apiKey: key, referer: "https://noto.app", title: "Noto"))
        let agent = ChatAgent(client: client, tools: VaultTools(root: URL(fileURLWithPath: vaultPath)))

        let question = "What are my diary entries from the last 5 days? List them by date."
        print("\n[LiveChatTests] Q: \(question)")
        var result: AgentResult?
        for try await event in agent.sendStreaming(question) {
            switch event {
            case .toolCallStarted(let name, let args): print("  → \(name)(\(args))")
            case .toolCallFinished(let name, let summary, _): print("  ✓ \(name): \(summary)")
            case .editProposal(let p): print("  ✎ proposed \(p.blocks.count) edit(s) to \(p.path)")
            case .textDelta: break
            case .finished(let r): result = r
            }
        }
        let r = try #require(result)
        print("[LiveChatTests] ANSWER:\n\(r.answer)")
        print("[LiveChatTests] SOURCES: \(r.sources)")
        #expect(!r.answer.isEmpty)
    }
}
