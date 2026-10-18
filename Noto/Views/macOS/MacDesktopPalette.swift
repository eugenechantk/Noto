#if os(macOS)
import AppKit
import SwiftUI
import NotoVault
import NotoSearch
import NotoDigest

private struct MacPaletteItem: Identifiable {
    var title: String
    var detail: String
    var snippet = ""
    var section: String
    var url: URL
    var isFolder = false
    var symbol = "doc.text"
    var trailingLabel = ""
    var id: String { url.path }
}

struct MacDesktopPalette: View {
    @Bindable var model: MacDesktopModel
    var onOpenInNewWindow: (String) -> Void
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var allMatches = false
    @State private var indexedResults: [SearchResult] = []
    @State private var indexedQuery = ""
    @State private var semanticResults: [SemanticSearchHit] = []
    @State private var folder: URL?
    @State private var showNewFolder = false
    @State private var folderName = ""
    @State private var measuredResultHeight: CGFloat = 0
    var isCompact = false
    var isNarrow = false
    private var purpose: MacPalettePurpose { model.palette ?? .search }

    var body: some View {
        let currentItems = items
        return VStack(spacing: 0) {
            queryBar
            Divider().overlay(MacDesktopStyle.separator)
            if purpose == .append {
                Text("“\(captureTitle)” goes at the end of the note you pick.").font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).frame(height: !isCompact && isNarrow ? 30 : 28)
            }
            if purpose == .create || purpose == .move {
                HStack {
                    if let current = folder, current != model.vaultURL { Button { folder = current.deletingLastPathComponent(); selectedIndex = 0 } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Parent folder") }
                    Image(systemName: purpose == .create ? "doc.text" : "folder")
                    Text(folder.map { $0 == model.vaultURL ? model.vaultURL.lastPathComponent : $0.lastPathComponent } ?? (purpose == .create ? (DigestMarkdown.filename(forTitle: captureTitle) ?? "Untitled.md") + " · named from the first line" : "Choose a destination folder.")).lineLimit(1)
                    Spacer()
                    if let folder {
                        Button(purpose == .move ? "Move Here" : "Create Here") { model.file(to: folder, purpose: purpose) }
                            .buttonStyle(.plain).foregroundStyle(MacDesktopStyle.icon).accessibilityIdentifier("macPaletteChooseFolder")
                    }
                }.font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, 18).frame(height: !isCompact && isNarrow ? 30 : 28)
            }
            if allMatches {
                Text("\(currentItems.count) notes mention “\(query)”").font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).frame(height: 24)
            }
            resultList(currentItems)
            Divider().overlay(MacDesktopStyle.separator)
            HStack(spacing: isNarrow ? 14 : 18) {
                Text("↑↓ Move")
                if purpose == .create || purpose == .move {
                    Text("→ Open folder")
                    Text(purpose == .move ? "↵ Move here" : "↵ Create here")
                } else {
                    Text(allMatches ? "↵ Open at the match" : purpose == .append ? "↵ Add to the end" : "↵ Open")
                }
                if purpose == .search, !allMatches, !isCompact || query.isEmpty { Text("⌥↵ Open in New Window") }
                if purpose == .search, !query.isEmpty, !allMatches { Text("⌘↵ New Note") }
                if allMatches || purpose != .search { Text(allMatches ? "esc Close" : "esc Cancel") }
                Spacer()
            }.font(.system(size: 11.5)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, 16).frame(height: 36)
        }
        .background(Color(red: 27/255, green: 31/255, blue: 39/255), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 15)
        .task(id: query + "|" + String(allMatches)) { await search() }
        .onAppear {
            if model.paletteNeedsNewFolder {
                model.paletteNeedsNewFolder = false
                showNewFolder = purpose == .move
            }
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $folderName)
            Button("Create") {
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return }
                let parent = folder ?? model.vaultURL
                let store = MarkdownNoteStore(directoryURL: parent, vaultRootURL: model.vaultURL, autoload: false)
                let created = store.createFolder(name: name)
                folder = created.folderURL; folderName = ""; model.scheduleRefresh()
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("macPalette")
    }

    private var queryBar: some View {
        HStack(spacing: 12) {
                Image(systemName: purpose == .search ? "magnifyingglass" : purpose == .append ? "text.badge.plus" : "folder")
                    .font(.system(size: 18)).foregroundStyle(purpose == .append ? Color.blue : purpose == .create || purpose == .move ? Color.green : MacDesktopStyle.secondary)
                MacDesktopQueryField(text: $query, placeholder: purpose.placeholder, onKey: handleKey)
                    .frame(height: 26)
                Button("esc") { model.palette = nil }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(MacDesktopStyle.secondary).accessibilityIdentifier("macClosePalette")
            }.padding(.horizontal, 16).frame(height: 54)
    }

    private func resultList(_ items: [MacPaletteItem]) -> some View {
        ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || items[index - 1].section != item.section {
                                Text(item.section).font(.system(size: 11, weight: .semibold)).foregroundStyle(MacDesktopStyle.secondary)
                                    .padding(.horizontal, 10).padding(.top, index == 0 ? 6 : 12).padding(.bottom, 4)
                            }
                            Button { selectedIndex = index; choose(openInNewWindow: false) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isFolder ? "folder" : item.symbol)
                                        .foregroundStyle(item.isFolder && purpose == .create ? Color.green : index == selectedIndex || item.symbol != "doc.text" ? MacDesktopStyle.icon : MacDesktopStyle.secondary).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(item.title).font(.system(size: 14)).lineLimit(1)
                                            if !item.detail.isEmpty { Text(item.detail).font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary).lineLimit(1) }
                                        }
                                        if allMatches, !item.snippet.isEmpty {
                                            Text(highlighted(VaultLibraryNote.plainTextSnippet(from: item.snippet)))
                                                .font(.system(size: 12.5)).foregroundStyle(MacDesktopStyle.secondary)
                                                .lineSpacing(3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if query.isEmpty, purpose == .search { Text(item.trailingLabel).font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary) }
                                    if index == selectedIndex { Text("↵").foregroundStyle(MacDesktopStyle.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
                                    .frame(height: allMatches ? nil : 40).padding(.vertical, allMatches ? 9 : 0)
                                    .frame(minHeight: allMatches ? 54 : nil)
                                    .background(index == selectedIndex ? MacDesktopStyle.accent.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("macPaletteResult_\(index)").id(index)
                        }
                        if items.isEmpty { Text("No results").foregroundStyle(MacDesktopStyle.secondary).padding(20).accessibilityIdentifier("macPaletteNoResults") }
                        if purpose == .search && !query.isEmpty && !allMatches {
                            Text("Actions").font(.system(size: 11, weight: .semibold)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
                            actionRow("New note “\(query)”", symbol: "square.and.pencil", shortcut: "⌘↵", id: "macPaletteNewNote", action: createNamedNote)
                            actionRow("Show every match for “\(query)”", symbol: "magnifyingglass", shortcut: "⇧↵", id: "macPaletteEveryMatch") { allMatches = true }
                        }
                        if purpose == .create || purpose == .move {
                            actionRow("New Folder…", symbol: "folder.badge.plus", shortcut: "⇧⌘N", id: "macPaletteNewFolder") { showNewFolder = true }
                        }
                    }.padding(8).id(query + "|" + String(allMatches) + "|" + String(selectedIndex))
                        .background(GeometryReader { geometry in Color.clear.preference(key: MacPaletteContentHeight.self, value: geometry.size.height) })
                }.frame(height: resultHeight)
                    .onPreferenceChange(MacPaletteContentHeight.self) { height in if abs(measuredResultHeight - height) > 0.5 { measuredResultHeight = height } }
                    .onChange(of: selectedIndex) { _, index in proxy.scrollTo(index) }
            }
    }

    private var captureTitle: String {
        DigestMarkdown.noteTitle(fromFirstLineOf: model.paletteUsesDraft ? model.draft : VaultMarkdown.stripFrontmatter(model.document)) ?? "Untitled"
    }
    private func actionRow(_ title: String, symbol: String, shortcut: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(MacDesktopStyle.secondary)
                Text(title).font(.system(size: 14)).lineLimit(1)
                Spacer(minLength: 4)
                Text(shortcut).font(.system(size: 11)).foregroundStyle(MacDesktopStyle.secondary)
            }.padding(.horizontal, 10).frame(height: 40).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func handleKey(_ key: MacDesktopPaletteKey, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case .up: move(-1)
        case .down: move(1)
        case .right:
            guard purpose == .create || purpose == .move, items.indices.contains(selectedIndex), items[selectedIndex].isFolder else { return false }
            folder = items[selectedIndex].url; selectedIndex = 0
        case .left:
            guard purpose == .create || purpose == .move, query.isEmpty, let current = folder, current != model.vaultURL else { return false }
            folder = current.deletingLastPathComponent(); selectedIndex = 0
        case .escape: model.palette = nil
        case .enter:
            if modifiers.contains(.shift), purpose == .search { allMatches = true }
            else if modifiers.contains(.command), purpose == .search { createNamedNote() }
            else { choose(openInNewWindow: modifiers.contains(.option)) }
        }
        return true
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var start = text.startIndex
        while let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex) {
            if let attributedRange = Range(range, in: result) {
                result[attributedRange].backgroundColor = MacDesktopStyle.accent.opacity(0.32)
                result[attributedRange].foregroundColor = .white
            }
            start = range.upperBound
        }
        return result
    }
    private var resultHeight: CGFloat {
        let limit: CGFloat
        switch purpose {
        case .append: limit = 371
        case .create, .move: limit = 313
        case .search: limit = allMatches ? 373 : query.isEmpty ? 201 : 339
        }
        return measuredResultHeight > 0 ? min(limit, measuredResultHeight + 2) : limit
    }
    private var items: [MacPaletteItem] {
        guard let library = model.library else { return [] }
        if purpose == .create || purpose == .move {
            let parent = folder ?? model.vaultURL
            let folders = library.folders.filter { item in
                query.isEmpty ? item.url.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL : item.name.localizedCaseInsensitiveContains(query)
            }
            var items = folders.map { MacPaletteItem(title: $0.name, detail: $0.url.deletingLastPathComponent().lastPathComponent, section: query.isEmpty ? "Folders" : "Matching folders", url: $0.url, isFolder: true) }
            if folder == nil, query.isEmpty { items.insert(MacPaletteItem(title: model.vaultURL.lastPathComponent, detail: "Vault root", section: "Folders", url: model.vaultURL, isFolder: true), at: 0) }
            return items
        }
        let notes: [VaultLibraryNote]
        if query.isEmpty { notes = purpose == .append ? library.notes.filter { !$0.isInbox } : Array(library.notes.prefix(4)) }
        else { notes = library.matching(query).filter { purpose != .append || !$0.isInbox } }
        var rows = notes.map { note in
            MacPaletteItem(title: note.title, detail: note.breadcrumb, snippet: note.snippet(matching: query),
                section: query.isEmpty ? purpose == .append ? note.isDaily(on: Date()) ? "Today" : note.isPinned ? "Pinned" : "Recent" : "Recent" : "Notes", url: note.fileURL,
                symbol: note.isDaily ? "calendar" : note.isPinned ? "pin" : "doc.text", trailingLabel: note.record.modifiedDate.formatted(.relative(presentation: .named)))
        }
        var existing = Set(rows.map { $0.url.standardizedFileURL })
        rows += (indexedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) ? indexedResults : []).filter {
            (purpose != .append || !$0.fileURL.path.contains("/inbox/")) && existing.insert($0.fileURL.standardizedFileURL).inserted
        }
            .map { MacPaletteItem(title: $0.title, detail: $0.breadcrumb, snippet: $0.snippet, section: allMatches ? "Every match" : "Notes", url: $0.fileURL) }
        if query.isEmpty && purpose == .append {
            let similarIDs = Set(semanticResults.map(\.noteID))
            rows = rows.map { row in
                var updated = row
                if let note = library.notes.first(where: { $0.fileURL == row.url }), !note.isDaily, !note.isPinned, similarIDs.contains(note.id) { updated.section = "Similar" }
                return updated
            }
            let order = ["Today": 0, "Pinned": 1, "Similar": 2, "Recent": 3]
            rows.sort { (order[$0.section] ?? 4) < (order[$1.section] ?? 4) }
        } else if allMatches {
            if !rows.isEmpty { rows[0].section = "Top hit" }
            var urls = Set(rows.map(\.url))
            for hit in semanticResults where hit.score > 0.3 {
                let url = model.vaultURL.appendingPathComponent(hit.relativePath)
                if urls.insert(url).inserted { rows.append(MacPaletteItem(title: hit.noteTitle, detail: URL(fileURLWithPath: hit.relativePath).deletingLastPathComponent().lastPathComponent, snippet: hit.snippet, section: "Similar meaning", url: url)) }
            }
        }
        if purpose == .search, !query.isEmpty, !allMatches {
            rows = Array(rows.prefix(3))
            rows += library.folders.filter { $0.name.localizedCaseInsensitiveContains(query) }.map { MacPaletteItem(title: $0.name, detail: $0.url.deletingLastPathComponent().lastPathComponent, section: "Folders", url: $0.url, isFolder: true) }
        }
        return Array(rows.prefix(allMatches ? 100 : 30))
    }
    private func move(_ delta: Int) { guard !items.isEmpty else { return }; selectedIndex = (selectedIndex + delta + items.count) % items.count }
    private func choose(openInNewWindow: Bool) {
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        if purpose == .search {
            if item.isFolder { model.select(.folder(item.url)) }
            else if openInNewWindow, let path = VaultPathResolver(vaultRootURL: model.vaultURL).relativePath(for: item.url) { onOpenInNewWindow(path) }
            else { model.openURL(item.url, query: query.isEmpty ? nil : query) }
            model.palette = nil
        } else { model.file(to: item.url, purpose: purpose) }
    }
    private func createNamedNote() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let store = MarkdownNoteStore(directoryURL: model.vaultURL, vaultRootURL: model.vaultURL, autoload: false)
        var note = store.createNote()
        let content = store.readContent(of: note).replacingOccurrences(of: "# ", with: "# " + query)
        _ = store.saveContent(content, for: note)
        note = store.updateTitleFromContent(content, for: note); note = store.renameFileIfNeeded(for: note)
        model.destination = .all; model.open(note, isNew: true); model.palette = nil; model.scheduleRefresh()
    }
    private func search() async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            indexedResults = []
            guard purpose == .append else { semanticResults = []; return }
            let text = String((model.paletteUsesDraft ? model.draft : model.document).prefix(1000))
            let root = model.vaultURL
            let hits = await Task.detached { SemanticSearch.hits(for: text, vaultURL: root, limit: 5) }.value
            guard !Task.isCancelled else { return }; semanticResults = hits
            return
        }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        let root = model.vaultURL
        let results = await Task.detached(priority: .userInitiated) {
            let indexer = MarkdownSearchIndexer(vaultURL: root)
            guard let store = try? indexer.openStore() else { return [SearchResult]() }
            return (try? MarkdownSearchEngine(store: store, vaultURL: root).search(query, limit: 100)) ?? []
        }.value
        guard !Task.isCancelled else { return }; indexedQuery = query; indexedResults = results
        if allMatches {
            let hits = await Task.detached { SemanticSearch.hits(for: query, vaultURL: root, limit: 10) }.value
            guard !Task.isCancelled else { return }; semanticResults = hits
        }
    }
}
private struct MacPaletteContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
#endif
