#if os(macOS)
import SwiftUI
import NotoVault

struct MacMarkdownDocumentBreadcrumb: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false).accessibilityIdentifier("macDocumentBreadcrumb")
    }
}

struct MacMarkdownMetadataStrip: View {
    let document: EditableFrontmatterDocument
    var dailyDate: Date?
    var showsProperties = true
    var matchCount: Int?
    private var fields: [EditableFrontmatterField] { document.fields }
    var body: some View {
        HStack(spacing: 8) {
            if let dailyDate {
                Text(Calendar.current.isDateInToday(dailyDate) ? "TODAY" : dailyDate.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.system(size: 12, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Color(red: 1, green: 138 / 255, blue: 87 / 255))
            } else {
            if let raw = fields.first(where: { $0.key == "modified" || $0.key == "updated" })?.value,
               let date = NotePropertyClassifier.date(from: raw) {
                Text(Calendar.current.isDateInToday(date) ? "Edited today at " + date.formatted(date: .omitted, time: .shortened) : "Edited " + date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.white.opacity(0.55))
                if showsProperties && !tags.isEmpty { Text("·").foregroundStyle(.white.opacity(0.55)) }
            }
            if showsProperties {
            ForEach(tags, id: \.self) { tag in
                Label(tag, systemImage: "tag").font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            if let status = fields.first(where: { $0.key == "status" })?.value, status != "inbox" {
                Text(status).foregroundStyle(Color.yellow.opacity(0.8)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            }
            }
            if let matchCount, matchCount > 0 {
                Text("· \(matchCount) \(matchCount == 1 ? "match" : "matches")").foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }.font(.system(size: 12)).lineLimit(1).allowsHitTesting(false)
            .accessibilityElement(children: .combine).accessibilityIdentifier("macDocumentMetadata")
    }
    private var tags: [String] { fields.first(where: { $0.key == "tags" }).map { NotePropertyClassifier.parseTags($0.value) } ?? [] }
}
#endif
