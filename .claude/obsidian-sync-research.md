# Obsidian Sync — Technical Architecture Research

## 1. Sync Architecture

**Model: File-level last-write-wins with version counter.**

Obsidian Sync is **not** CRDT-based and does **not** use Operational Transforms. It uses a straightforward file-level synchronization model:

- Each vault has a monotonically increasing **version number** on the server.
- When a client connects, it sends its last-known version. If the server's version is higher, the server pushes all current files (metadata) to the client so it can reconcile.
- When a client pushes a file change, the server bumps the vault version by 1 and broadcasts the change to all other connected clients via WebSocket.
- The server stores **whole file revisions**, not diffs or deltas. Each push creates a new row in the database with the full file content.

There is no merge logic on the server. The server is a relay + version store. The client is responsible for deciding what to push and what to accept.

### Connection Flow (from reverse-engineered protocol)

1. Client opens WebSocket to sync server
2. Client sends initialization message: `{op, token, id (vault ID), keyhash, version, initial, device}`
3. Server validates JWT token and vault access
4. If server version > client version: server pushes all current file metadata to client
5. Server sends `{op: "ready", version: <server_version>}`
6. Server takes a snapshot (marks current files as snapshot point)
7. If client version > server version: server updates its version to match
8. Bidirectional message loop begins

## 2. Conflict Resolution

**Strategy: Last-write-wins at the file level. No automatic merging.**

- There is no line-level or block-level merge. The entire file is the unit of sync.
- When two devices edit the same file offline and both push, the **last push wins** on the server — the previous version is marked as `newest=False` and kept in history.
- The losing version is preserved in version history and can be manually restored.
- Obsidian does **not** attempt automatic 3-way merging or diff-based conflict resolution.
- In practice, because sync happens in near-real-time over WebSocket, conflicts are rare for single-user vaults — edits are pushed as soon as they happen and broadcast immediately.

**For shared vaults:** The same model applies. Real-time WebSocket broadcast means all connected clients see changes quickly, but simultaneous offline edits to the same file will result in last-write-wins.

## 3. Sync Granularity

**File-level. Not chunk-level, not line-level.**

- Each sync operation (`push`/`pull`) transfers a complete file.
- The push message includes: `path, extension, hash, ctime, mtime, folder, deleted, size, pieces`
- Binary content is sent as one or more binary WebSocket frames (the `pieces` field indicates how many frames to expect).
- Files with `size=0` skip the binary transfer.
- Folder operations are tracked as metadata-only entries (`folder: true`).
- Deletions are soft-deletes: the file is marked `deleted: true` but retained in the database.

**Contrast with Obsidian LiveSync (community plugin):** LiveSync uses CouchDB and chunk-level sync with CRDT-like conflict resolution. This is fundamentally different from official Obsidian Sync.

## 4. End-to-End Encryption

**Yes. AES-256-GCM with scrypt key derivation.**

### Encryption Details (from Obsidian's official blog)

- **Cipher:** AES-256 in Galois/Counter Mode (GCM)
- **Key size:** 256-bit (32 bytes)
- **Key derivation:** scrypt with parameters N=32768, r=8, p=1
- **Input:** User-chosen vault password (separate from account password) + per-vault salt
- **Encryption versions:**
  - Version 0: scrypt-derived base key used directly
  - Version 3: Base key further processed through HKDF-SHA256 with context string "ObsidianAesGcm"

### Encrypted Payload Format

```
[IV: 12 bytes] [Encrypted Data: variable] [Auth Tag: 16 bytes]
```

### What Is Encrypted

- File content (the binary data in push/pull operations)
- Encryption/decryption happens entirely on the client device

### What Is NOT Encrypted (visible to server)

- File paths
- File extensions
- File sizes
- Timestamps (created, modified)
- Folder structure
- Vault name
- User email/account info
- File hashes

### Key Management

- Vault password never leaves the client
- Salt is stored server-side and retrieved during connection
- The `keyhash` is sent during WebSocket initialization for vault access validation — this is a hash of the key, not the key itself
- Obsidian provides a way for users to manually verify E2EE by intercepting WebSocket messages and decrypting them locally

## 5. Protocol / Transport

**WebSocket over TLS (wss://).**

### Endpoints

- WebSocket: `wss://sync-{N}.obsidian.md/` (load-balanced across multiple servers)
- REST API for vault management: `/vault/create`, `/vault/list`, `/vault/access`, `/vault/delete`
- Authentication: JWT tokens

### WebSocket Message Types (Operations)

| Op | Direction | Purpose |
|---|---|---|
| `init` | Client -> Server | Authenticate and specify vault ID, version, device |
| `ready` | Server -> Client | Server is ready, includes current vault version |
| `push` | Bidirectional | Push file metadata + content (client) or broadcast change (server) |
| `pull` | Client -> Server | Request file content by UID |
| `size` | Client -> Server | Query vault storage usage |
| `history` | Client -> Server | Get version history for a file path |
| `restore` | Client -> Server | Restore a previous version by UID |
| `deleted` | Client -> Server | List all soft-deleted files |
| `ping`/`pong` | Bidirectional | Keepalive |

### Push Message Format

```json
{
  "op": "push",
  "path": "Daily Notes/2026-03-16.md",
  "extension": "md",
  "hash": "abc123...",
  "size": 1234,
  "ctime": 1710578400000,
  "mtime": 1710592800000,
  "folder": false,
  "deleted": false,
  "pieces": 1,
  "uid": 42
}
```

Binary content follows as separate WebSocket binary frame(s).

### Pull Response

Server responds with `{hash, size, pieces}` followed by binary frame(s) containing the file data.

## 6. Version History

**Append-only file revisions, pruned by snapshot.**

- Every push creates a new database row. The previous version is marked `newest=False`.
- History is queryable per file path, ordered by modified time descending.
- **Snapshots:** On each client connection, the server runs a snapshot operation that:
  1. Marks all current (`newest=True`) files as `is_snapshot=True`
  2. Deletes all non-snapshot, non-newest entries (pruning old intermediate versions)
  3. Deletes entries with `size != 0` but no data (orphaned metadata)
- **Retention:** Depends on plan:
  - Sync Standard: 1 month of version history
  - Sync Plus: 12 months of version history
- Deleted files are soft-deleted and recoverable through the `restore` operation.
- The client can browse history via the `history` op and restore any version via the `restore` op.

## 7. Limitations and Quirks

### Storage Limits

| | Standard | Plus |
|---|---|---|
| Total storage | 1 GB | 10 GB (upgradable to 100 GB) |
| Max file size | 5 MB | 200 MB |
| Version history | 1 month | 12 months |

### Known Limitations

- **No merge conflict resolution.** If you edit the same file on two offline devices, you lose one version (though it's preserved in history). There is no automatic merge, no diff view, no conflict markers.
- **File paths are not encrypted.** The server (and potentially Obsidian staff) can see your folder structure and file names. Only file content is E2EE.
- **Metadata is visible.** File sizes, timestamps, and the structure of your vault are visible to the server.
- **No delta sync.** Every edit pushes the entire file, even for a single character change. This is bandwidth-inefficient for large files.
- **Version history pruning on connect.** The snapshot mechanism on each connection prunes intermediate versions, meaning rapid edits between connections may lose intermediate history states.
- **Single-file granularity.** No ability to sync individual blocks, headings, or sections — the smallest unit is a whole file.
- **No offline conflict detection UI.** The app doesn't prominently warn you when a conflict occurred; the "losing" version silently goes to history.
- **Selective sync is coarse.** You can toggle sync for file types (images, audio, video, PDFs) but cannot exclude specific folders or files by path.
- **Shared vault limitations.** Real-time collaboration is broadcast-based (all connected clients see changes) but there is no cursor presence, no operational transform, no real-time co-editing — it's closer to Dropbox than Google Docs.

### Quirks

- The server uses a vault-level version counter, not per-file versions. Any file change bumps the vault version. This means if you have 10,000 files and change one, the entire vault version increments.
- Binary files (images, PDFs) go through the same sync mechanism as text files — no special handling.
- The `pieces` field in push messages suggests large files can be chunked for transfer, but this is transfer-level chunking, not storage-level — the server reassembles and stores the complete binary blob.

## Summary for Noto

If building sync for Noto, the key takeaways from Obsidian's approach:

1. **Simple is viable.** Obsidian's sync is architecturally simple — file-level last-write-wins over WebSocket. No CRDTs, no OT. It works because real-time push minimizes the conflict window.
2. **E2EE is achievable with standard primitives.** AES-256-GCM + scrypt is a well-understood stack. The main design decision is what metadata to leave unencrypted (Obsidian chose to leave paths/sizes visible).
3. **Version history is just append-only storage with pruning.** No fancy VCS — just keep old rows and periodically clean up.
4. **The biggest gap is conflict resolution.** Obsidian's weakest point is silent last-write-wins. A better approach for Noto could be: detect conflicts, present both versions, let the user choose or merge. Or invest in CRDT/OT for real-time co-editing if that's a future goal.
5. **File-level sync is a pragmatic choice** when your data model is files on disk. Going more granular (block-level, line-level) requires a richer data model and significantly more complexity.
