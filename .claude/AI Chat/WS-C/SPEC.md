# SPEC: WS-C — Chat Block Extension DTOs (NotoAIChat Models)

## Package Structure

```
Packages/NotoAIChat/
├── Package.swift
├── Sources/NotoAIChat/
│   ├── ChatBlockRole.swift
│   ├── ConversationExtension.swift
│   ├── UserMessageExtension.swift
│   ├── AIResponseExtension.swift
│   ├── SuggestedEditExtension.swift
│   ├── BlockReference.swift
│   ├── ToolCallRecord.swift
│   ├── EditProposal.swift
│   ├── EditOperation.swift
│   ├── EditStatus.swift
│   ├── MetadataKeys.swift
│   └── Block+ExtensionCoding.swift
└── Tests/NotoAIChatTests/
    └── AIChatModelTests.swift
```

## Type Definitions

### ChatBlockRole
```
enum ChatBlockRole: String, Codable, Sendable
  cases: conversation, userMessage, aiResponse, suggestedEdit
```

### ConversationExtension
```
struct: Codable, Sendable
  role: ChatBlockRole (.conversation)
  createdAt: Date
  noteContextBlockId: UUID?
```

### UserMessageExtension
```
struct: Codable, Sendable
  role: ChatBlockRole (.userMessage)
  turnIndex: Int
```

### AIResponseExtension
```
struct: Codable, Sendable
  role: ChatBlockRole (.aiResponse)
  turnIndex: Int
  references: [BlockReference]
  toolCalls: [ToolCallRecord]
```

### SuggestedEditExtension
```
struct: Codable, Sendable
  role: ChatBlockRole (.suggestedEdit)
  proposal: EditProposal
  status: EditStatus
```

### BlockReference
```
struct: Codable, Sendable
  blockId: UUID
  content: String
  relevanceScore: Double?
```

### ToolCallRecord
```
struct: Codable, Sendable
  toolName: String
  input: String (JSON string)
  output: String (JSON string)
```

### EditProposal
```
struct: Codable, Sendable
  operations: [EditOperation]
  summary: String
```

### EditOperation
```
enum: Codable, Sendable
  case addBlock(AddBlockOp)
  case updateBlock(UpdateBlockOp)
```

### AddBlockOp / UpdateBlockOp
```
AddBlockOp: Codable, Sendable
  parentId: UUID, afterBlockId: UUID?, content: String

UpdateBlockOp: Codable, Sendable
  blockId: UUID, newContent: String
```

### EditStatus
```
enum: String, Codable, Sendable
  cases: pending, accepted, dismissed
```

### Block+ExtensionCoding
```
extension Block:
  func decodeExtension<T: Decodable>(_ type: T.Type) -> T?
    - guard let extensionData, decode with JSONDecoder
  static func encodeExtension<T: Encodable>(_ value: T) -> Data?
    - encode with JSONEncoder
```

### MetadataKeys
```
enum AIChatMetadataKeys:
  static let role = "noto.ai.role"
  static let status = "noto.ai.status"
  static let turnIndex = "noto.ai.turnIndex"
```

## Tests
- Round-trip encode/decode for every extension type
- ChatBlockRole raw value serialization
- EditOperation discriminated union coding
- EditStatus raw value coding
- Block extension helpers with mock data
