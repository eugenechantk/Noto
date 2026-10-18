#if os(macOS)
import AppKit
import SwiftUI
import NotoVault

enum MacDesktopStyle {
    static let background = Color(red: 14 / 255, green: 17 / 255, blue: 22 / 255)
    static let accent = Color(red: 1, green: 106 / 255, blue: 46 / 255)
    static let icon = Color(red: 1, green: 138 / 255, blue: 87 / 255)
    static let secondary = Color.white.opacity(0.55)
    static let separator = Color.white.opacity(0.07)
}

struct MacDesktopIconButton: View {
    let symbol: String
    let label: String
    let id: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 30, height: 28) }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(label).accessibilityIdentifier(id).help(label)
    }
}

struct MacDesktopSidebar: View {
    @Bindable var model: MacDesktopModel
    var onHide: () -> Void
    var onNewFolder: () -> Void
    var onSettings: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                MacDesktopIconButton(symbol: "sidebar.left", label: "Hide sidebar", id: "macHideSidebar", action: onHide)
            }.padding(.trailing, 10).frame(height: 52)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    destinationRow(.capture, count: nil)
                    destinationRow(.daily, count: model.library?.notes.filter(\.isDaily).count)
                    destinationRow(.inbox, count: model.library?.notes.filter(\.isInbox).count)
                    destinationRow(.all, count: model.library?.notes.count)
                    section("Pinned")
                    if model.pinned.isEmpty {
                        Text("Pin a note from its menu").font(.system(size: 11)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    ForEach(model.pinned) { note in
                        Button { model.openURL(note.fileURL) } label: {
                            rowLabel(note.title, symbol: "pin", count: nil)
                        }.buttonStyle(.plain).accessibilityIdentifier("macPinned_" + note.id.uuidString)
                    }
                    section("Folders")
                    ForEach(visibleFolders) { folder in
                        HStack(spacing: 0) {
                            if model.library?.folders.contains(where: { $0.url.deletingLastPathComponent() == folder.url }) == true {
                            Button {
                                if model.expandedFolders.contains(folder.url) { model.expandedFolders.remove(folder.url) }
                                else { model.expandedFolders.insert(folder.url) }
                            } label: {
                                Image(systemName: model.expandedFolders.contains(folder.url) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(MacDesktopStyle.secondary).frame(width: 18, height: 28)
                            }.buttonStyle(.plain).accessibilityLabel("Expand " + folder.name).accessibilityIdentifier("macExpand_" + folder.url.path)
                            } else { Color.clear.frame(width: 18, height: 28) }
                            Button { model.select(.folder(folder.url)) } label: {
                                rowLabel(folder.name, symbol: "folder", count: model.library?.noteCount(in: folder.url), inset: 0)
                            }.buttonStyle(.plain).accessibilityIdentifier("macFolder_" + folder.url.path)
                        }
                        .padding(.leading, CGFloat(folder.depth) * 16 + 9)
                        .background(model.destination == .folder(folder.url) ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contextMenu {
                            Button("New Note") { model.select(.folder(folder.url)); model.createNote() }
                            Button("New Folder…") { model.select(.folder(folder.url)); onNewFolder() }
                        }
                    }
                }.padding(.horizontal, 9)
            }
            HStack {
                Button(action: onNewFolder) { Label("New Folder", systemImage: "plus.circle") }
                    .buttonStyle(.plain).accessibilityIdentifier("macNewFolder")
                Spacer()
                Label(model.vaultURL.path.contains("Mobile Documents") ? "iCloud" : "Local", systemImage: "icloud")
                    .font(.system(size: 11))
            }.font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, 19).frame(height: 44)

        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
        .padding(8).frame(width: 264)
        .accessibilityElement(children: .contain).accessibilityIdentifier("macLibrarySidebar")
    }
    private var visibleFolders: [SidebarTreeNode] {
        (model.library?.folders ?? []).filter { folder in
            guard folder.depth > 0 else { return true }
            var parent = folder.url.deletingLastPathComponent()
            while parent.standardizedFileURL != model.vaultURL.standardizedFileURL {
                if !model.expandedFolders.contains(parent) { return false }
                let next = parent.deletingLastPathComponent()
                if next == parent { return false }; parent = next
            }
            return true
        }
    }
    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(MacDesktopStyle.secondary)
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 6)
    }
    private func destinationRow(_ destination: MacLibraryDestination, count: Int?) -> some View {
        Button { model.select(destination) } label: { rowLabel(destination.title, symbol: destination.symbol, count: count) }
            .buttonStyle(.plain)
            .background(model.destination == destination ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityIdentifier("macDestination" + destination.title.replacingOccurrences(of: " ", with: ""))
    }
    private func rowLabel(_ title: String, symbol: String, count: Int?, inset: CGFloat = 27) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(MacDesktopStyle.icon).frame(width: 16)
            Text(title).lineLimit(1)
            Spacer(minLength: 3)
            if let count { Text(count.formatted()).foregroundStyle(MacDesktopStyle.secondary).font(.system(size: 12)) }
        }.font(.system(size: 13)).padding(.leading, inset).padding(.trailing, 9).frame(height: 28).contentShape(Rectangle())
    }
}

struct MacDesktopNoteList: View {
    @Bindable var model: MacDesktopModel
    var isNarrow: Bool
    var onSidebar: () -> Void
    var onClose: (() -> Void)?
    var onSelect: () -> Void
    var onMove: () -> Void
    var onPin: (VaultLibraryNote) -> Void
    var onTrash: (VaultLibraryNote) -> Void
    var onRename: (VaultLibraryNote) -> Void
    @State private var weekOffset = 0
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let selectedID = model.selectedNote?.id
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                if isNarrow && onClose == nil { MacDesktopIconButton(symbol: "sidebar.left", label: "Show sidebar", id: "macShowSidebar", action: onSidebar) }
                if !isNarrow {
                    title
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                if model.destination != .inbox {
                Menu {
                    Picker("Sort By", selection: $model.sortOrder) { ForEach(VaultLibrarySortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline).labelsHidden()
                    Toggle("Include Subfolders", isOn: $model.includeSubfolders)
                } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 32, height: 26) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Sort notes").accessibilityIdentifier("macSortNotes")
                }
                MacDesktopIconButton(symbol: model.destination == .inbox ? "plus" : "square.and.pencil", label: model.destination == .inbox ? "New capture" : "New note", id: "macCreateNote") {
                    if model.destination == .inbox { model.select(.capture) } else { model.createNote() }
                }
                }.padding(.horizontal, onClose == nil ? 3 : 0)
                    .frame(width: onClose == nil ? model.destination == .inbox ? 34 : 74 : nil, height: onClose == nil ? 34 : 28)
                    .background(onClose == nil ? Color.white.opacity(0.07) : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(onClose == nil ? Color.white.opacity(0.08) : .clear))
                if let onClose { MacDesktopIconButton(symbol: "xmark", label: "Hide notes", id: "macHideNotes", action: onClose) }
            }.padding(.leading, isNarrow ? 82 : 16).padding(.trailing, 12).frame(height: onClose == nil ? 52 : 44)
            if isNarrow {
                MacDesktopDestinationMenu(model: model, isListTitle: true).padding(.horizontal, 10).padding(.bottom, 8)
            }
            if model.destination == .daily { weekStrip }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.self) { section in
                            Text(section).font(.system(size: 11, weight: .semibold)).foregroundStyle(MacDesktopStyle.secondary)
                                .padding(.horizontal, 12).padding(.top, section == sections.first ? 10 : 16).padding(.bottom, 6)
                            ForEach(notes.filter { sectionTitle($0) == section }) { note in
                                noteRow(note, selected: selectedID == note.id).id(note.id)
                            }
                        }
                        if notes.isEmpty {
                            ContentUnavailableView("No notes", systemImage: model.destination.symbol, description: Text("Create a note to start writing."))
                                .accessibilityIdentifier("macEmptyNoteList")
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 12).id(selectedID)
                }.onChange(of: model.selectedNote?.id) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }.padding(.trailing, 1).frame(maxHeight: .infinity)
        .background(onClose == nil ? MacDesktopStyle.background : Color(red: 24/255, green: 28/255, blue: 35/255))
        .overlay(alignment: .trailing) { if onClose == nil { MacDesktopStyle.separator.frame(width: 1) } }
        .onChange(of: model.selectedNote?.id) { _, _ in if model.destination == .daily { weekOffset = 0 } }
        .accessibilityElement(children: .contain).accessibilityIdentifier("macNoteList")
    }
    private var title: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.destination.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
            Text("\(notes.count) \(model.destination == .inbox ? "waiting" : "notes")").font(.system(size: 11.5)).foregroundStyle(MacDesktopStyle.secondary)
        }
    }
    private var notes: [VaultLibraryNote] { model.visibleNotes }
    private func sectionTitle(_ note: VaultLibraryNote) -> String {
        if model.sortOrder == .title { return "Notes" }
        if let snoozed = note.snoozedUntil, snoozed > Date(), model.destination == .inbox { return "Snoozed" }
        return VaultLibraryNote.dateSection(for: model.destination == .daily ? note.dailyDate() ?? note.record.modifiedDate : note.record.modifiedDate)
    }
    private var sections: [String] { var seen = Set<String>(); return notes.map(sectionTitle).filter { seen.insert($0).inserted } }
    private func noteRow(_ note: VaultLibraryNote, selected: Bool) -> some View {
        Button { model.open(note); onSelect() } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayTitle(note)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if model.destination == .daily, note.isDaily(on: Date()) {
                        Text("TODAY").font(.system(size: 9, weight: .bold)).foregroundStyle(MacDesktopStyle.icon)
                    }
                }
                Text(note.record.modifiedDate.formatted(date: .omitted, time: .shortened) + "  " + (note.isAvailable ? note.preview : "Downloading from iCloud…"))
                    .font(.system(size: 12)).lineSpacing(4).foregroundStyle(MacDesktopStyle.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .background(selected ? MacDesktopStyle.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottom) {
            if !selected && note.id != notes.last?.id { MacDesktopStyle.separator.frame(height: 1).padding(.horizontal, 12) }
        }
        .accessibilityIdentifier("macNote_" + note.id.uuidString)
        .accessibilityValue(selected ? "Selected" : "")
        .contextMenu {
            Button("Open in New Window") { openWindow(id: "main", value: note.relativePath) }.keyboardShortcut(.return, modifiers: .option)
            Button("Copy Link") {
                guard let url = NotoDeepLink.webURL(vaultRelativePath: note.relativePath) else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }.keyboardShortcut("c", modifiers: [.command, .control])
            Divider()
            Menu("Move To") {
                Button("Choose Folder…") { model.open(note); onMove() }
                Divider()
                Toggle(model.vaultURL.lastPathComponent, isOn: Binding(get: { note.fileURL.deletingLastPathComponent().standardizedFileURL.path == model.vaultURL.standardizedFileURL.path }, set: { if $0 { model.requestMove(note, to: model.vaultURL) } }))
                ForEach(model.library?.folders ?? []) { folder in
                    Toggle(isOn: Binding(get: { note.fileURL.deletingLastPathComponent().standardizedFileURL.path == folder.url.standardizedFileURL.path }, set: { if $0 { model.requestMove(note, to: folder.url) } })) {
                        Label(String(repeating: "  ", count: folder.depth) + folder.name, systemImage: "folder")
                    }
                }
                Divider()
                Button("New Folder…") { model.open(note); model.paletteNeedsNewFolder = true; onMove() }
            }
            Button("Duplicate") { model.duplicate(note) }.keyboardShortcut("d")
            Button("Rename…") { model.open(note); onRename(note) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.fileURL]) }.keyboardShortcut("r", modifiers: [.command, .shift])
            ShareLink(item: note.fileURL) { Text("Share") }
            Divider()
            Button("Move to Trash", role: .destructive) { onTrash(note) }.keyboardShortcut(.delete, modifiers: .command)
        }
    }
    private func displayTitle(_ note: VaultLibraryNote) -> String {
        guard note.isDaily else { return note.title }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: note.fileURL.deletingPathExtension().lastPathComponent) else { return note.title }
        f.dateFormat = "d MMM, yy (EEE)"; return f.string(from: date)
    }
    private var selectedDailyDate: Date? {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        return model.selectedNote.flatMap { formatter.date(from: $0.fileURL.deletingPathExtension().lastPathComponent) }
    }
    private var weekStart: Date {
        let base = VaultLibraryNote.mondayWeekStart(containing: selectedDailyDate ?? Date())
        return Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: base) ?? base
    }
    private var weekStrip: some View {
        let availableDays = Set((model.library?.notes ?? []).filter(\.isDaily).map { $0.fileURL.deletingPathExtension().lastPathComponent })
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Text(weekStart.formatted(.dateTime.month(.wide).year())).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 22, height: 20) }.accessibilityLabel("Previous week").accessibilityIdentifier("macPreviousWeek")
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 22, height: 20) }.accessibilityLabel("Next week").accessibilityIdentifier("macNextWeek")
            }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 2).padding(.bottom, 8)
            HStack(spacing: 2) {
                ForEach(0...6, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) ?? Date()
                    let selected = selectedDailyDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true
                    let hasNote = availableDays.contains(formatter.string(from: date))
                    Button { model.openDaily(date) } label: {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.weekday(.narrow))).font(.system(size: 10, weight: .semibold)).foregroundStyle(MacDesktopStyle.secondary).frame(height: 12)
                            Text(date.formatted(.dateTime.day())).font(.system(size: 12.5, weight: selected ? .bold : .regular)).monospacedDigit().frame(width: 26, height: 26)
                                .foregroundStyle(selected || hasNote ? Color.white : MacDesktopStyle.secondary)
                                .background(selected ? MacDesktopStyle.accent : .clear, in: Circle())
                            Circle().fill(hasNote && !selected ? MacDesktopStyle.icon : .clear).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                }
            }
        }.padding(.horizontal, 10).padding(.top, 11).padding(.bottom, 13)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06)))
            .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 8)
    }
}

struct MacDesktopDestinationMenu: View {
    @Bindable var model: MacDesktopModel
    var isListTitle = false
    private var subtitle: String {
        if model.destination == .capture { return "Goes to Inbox" }
        let count = model.visibleNotes.count
        if case .folder(let url) = model.destination {
            return (url == model.vaultURL ? "Vault" : url.deletingLastPathComponent().lastPathComponent) + " · \(count) notes"
        }
        return "\(count) " + (model.destination == .inbox ? "waiting" : "notes")
    }
    var body: some View {
        Group {
            if isListTitle {
                VStack(alignment: .leading, spacing: 2) {
                    // AppKit fixes the pop-up label font. Keep its native menu beneath the larger source heading.
                    destinationMenu
                        .opacity(0.02)
                        .allowsHitTesting(true).accessibilityHidden(false)
                        .overlay(alignment: .leading) {
                            HStack(spacing: 7) {
                                Image(systemName: model.destination.symbol).font(.system(size: 17)).foregroundStyle(MacDesktopStyle.icon).frame(width: 17)
                                Text(model.destination.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(MacDesktopStyle.secondary).frame(width: 11)
                            }.frame(height: 21).fixedSize().allowsHitTesting(false).accessibilityHidden(true)
                        }
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(MacDesktopStyle.secondary)
                        .frame(height: 13)
                        .padding(.leading, 24)
                }.padding(.horizontal, 8).padding(.vertical, 6)
            } else {
                destinationMenu.background(.white.opacity(0.07), in: Capsule())
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var destinationMenu: some View {
        Menu {
            ForEach([MacLibraryDestination.capture, .daily, .inbox, .all], id: \.self) { destination in
                Toggle(isOn: Binding(get: { model.destination == destination }, set: { if $0 { model.select(destination) } })) {
                    Label(destination.title, systemImage: destination.symbol)
                }
            }
            Divider()
            Section("Pinned") { ForEach(model.pinned) { note in Button(note.title) { model.openURL(note.fileURL) } } }
            Section("Folders") {
                Button(model.vaultURL.lastPathComponent) { model.select(.folder(model.vaultURL)) }
                ForEach(model.library?.folders ?? []) { folder in
                    Button(String(repeating: "  ", count: folder.depth) + folder.name) { model.select(.folder(folder.url)) }
                }
            }
            Divider()
            Button("New Folder…") { NotificationCenter.default.post(name: MacDesktopCommands.action, object: NotoCommandTarget.activeWindow, userInfo: ["action": "folder"]) }
            Button("Show Sidebar") { NotificationCenter.default.post(name: MacDesktopCommands.action, object: NotoCommandTarget.activeWindow, userInfo: ["action": "sidebar"]) }
        } label: {
            if isListTitle {
                Label(model.destination.title, systemImage: model.destination.symbol).font(.system(size: 18, weight: .bold))
            } else {
            HStack(spacing: 7) { Image(systemName: model.destination.symbol); Text(model.destination.title).fontWeight(.semibold); Image(systemName: "chevron.down").font(.system(size: 9)); Spacer(minLength: 0) }
                .font(.system(size: 13)).padding(.horizontal, 11).frame(height: 30)
            }
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: isListTitle, vertical: true)
            .font(isListTitle ? .system(size: 18, weight: .bold) : nil)
            .frame(height: isListTitle ? 21 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("macDestinationSwitcher")
    }
}
#endif
