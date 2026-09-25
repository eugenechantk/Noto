import Foundation
import NotoShareCapture
import NotoSocialMedia

// noto-share-media — Hermes' worker for share-sheet media jobs.
//
//   noto-share-media run    --vault <dir> --state-dir <dir>   pull the queue, download, append
//   noto-share-media accept --vault <dir> --state-dir <dir> --job <file.json>   one job, no queue
//   noto-share-media append --vault <dir> --state-dir <dir>   only append parked blocks
//
// `run` reads CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_QUEUES_TOKEN and
// NOTO_SHARE_MEDIA_QUEUE_ID from the environment. Stdout stays empty when
// there was nothing to do, so the Hermes job is silent when idle; the exit
// status is non-zero only for failures that need a human.

struct Options {
    var command = ""
    var vault: URL?
    var stateDir: URL?
    var job: URL?
}

func parse(_ arguments: [String]) -> Options? {
    var options = Options()
    var iterator = arguments.dropFirst().makeIterator()
    guard let command = iterator.next() else { return nil }
    options.command = command
    while let flag = iterator.next() {
        guard let value = iterator.next() else { return nil }
        let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        switch flag {
        case "--vault": options.vault = url
        case "--state-dir": options.stateDir = url
        case "--job": options.job = url
        default: return nil
        }
    }
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func describe(_ post: SocialPost) -> String {
    let media = post.allMedia
    let videos = media.filter { $0.kind == .video }.count
    let images = media.count - videos
    var parts: [String] = []
    if images > 0 { parts.append("\(images) image\(images == 1 ? "" : "s")") }
    if videos > 0 { parts.append("\(videos) video\(videos == 1 ? "" : "s")") }
    return parts.isEmpty ? "no media" : parts.joined(separator: ", ")
}

/// Permanent failures are acknowledged (retrying cannot help); anything else
/// goes back to the queue, which dead-letters it after its retry limit.
func isPermanent(_ error: Error) -> Bool {
    switch error as? SocialPostError {
    case .unsupportedURL, .unreadable: return true
    case .badResponse(let status): return status == 404 || status == 410
    case nil: return error is DecodingError
    }
}

@discardableResult
func report(_ outcomes: [ShareMediaProcessor.AppendOutcome]) -> Bool {
    var ok = true
    for outcome in outcomes {
        switch outcome {
        case .appended(_, let note): print("Added media to \(note)")
        case .restored(_, let note): print("Put media back into \(note) (an edit had overwritten it)")
        case .gaveUp(let id): print("Gave up on share \(id.uuidString): its capture note never appeared in 7 days")
        case .failed(let id, let reason): print("Could not update the note for share \(id.uuidString): \(reason)"); ok = false
        case .alreadyPresent, .waiting: break
        }
    }
    return ok
}

guard let options = parse(CommandLine.arguments), let vault = options.vault, let stateDir = options.stateDir else {
    fail("usage: noto-share-media (run|accept|append) --vault <dir> --state-dir <dir> [--job <file.json>]")
}
guard FileManager.default.fileExists(atPath: vault.path) else { fail("vault not found: \(vault.path)") }
try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
let processor = ShareMediaProcessor(vaultURL: vault, stateDirectory: stateDir)
var healthy = true

switch options.command {
case "accept":
    guard let file = options.job, let data = try? Data(contentsOf: file),
          let job = try? ShareMediaJob.decoder.decode(ShareMediaJob.self, from: data) else { fail("--job must be a ShareMediaJob JSON file") }
    do {
        let post = try await processor.accept(job)
        print("Saved \(describe(post)) from \(job.url.absoluteString)")
    } catch {
        print("Could not fetch \(job.url.absoluteString): \(error)")
        healthy = false
    }
    healthy = report(processor.appendPending()) && healthy

case "append":
    healthy = report(processor.appendPending())

case "run":
    let env = ProcessInfo.processInfo.environment
    guard let account = env["CLOUDFLARE_ACCOUNT_ID"], let token = env["CLOUDFLARE_QUEUES_TOKEN"],
          let queue = env["NOTO_SHARE_MEDIA_QUEUE_ID"], !account.isEmpty, !token.isEmpty, !queue.isEmpty else {
        fail("run needs CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_QUEUES_TOKEN and NOTO_SHARE_MEDIA_QUEUE_ID")
    }
    let client = CloudflareQueueClient(accountID: account, queueID: queue, token: token)
    do {
        // Drain at most a few batches per run; the next run picks up the rest.
        for _ in 0..<5 {
            let messages = try await client.pull()
            if messages.isEmpty { break }
            var acks: [String] = []
            var retries: [CloudflareQueueClient.Retry] = []
            for message in messages {
                guard let job = try? ShareMediaJob.decoder.decode(ShareMediaJob.self, from: message.body) else {
                    print("Dropped an unreadable queue message")
                    acks.append(message.leaseID)
                    continue
                }
                do {
                    let post = try await processor.accept(job)
                    print("Saved \(describe(post)) from \(job.url.absoluteString)")
                    acks.append(message.leaseID)
                } catch where isPermanent(error) {
                    print("Skipped \(job.url.absoluteString): \(error)")
                    acks.append(message.leaseID)
                } catch {
                    // Transient: back off; the queue dead-letters after max retries.
                    retries.append(.init(leaseID: message.leaseID, delaySeconds: 60 * max(1, message.attempts + 1)))
                    FileHandle.standardError.write(Data("retrying \(job.url.absoluteString): \(error)\n".utf8))
                }
            }
            try await client.acknowledge(acks: acks, retries: retries)
        }
    } catch {
        print("Queue error: \(error)")
        healthy = false
    }
    healthy = report(processor.appendPending()) && healthy

default:
    fail("unknown command \(options.command)")
}

exit(healthy ? 0 : 1)
