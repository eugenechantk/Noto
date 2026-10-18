import SwiftUI
import UIKit
import os

struct DailyCalendarSheet: View {
    let selectedDate: Date
    let today: Date
    let calendar: Calendar
    let writtenDays: Set<Date>
    var onSelect: (Date) -> Void
    var onMonthChange: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var calendarHeight: CGFloat = 0
    @State private var navigationHeight: CGFloat = 0

    var body: some View {
        GeometryReader { sheetGeometry in
            NavigationStack {
                ScrollView {
                    calendarView
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { calendarHeight = $0 }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { contentFrame in
                    let rootFrame = sheetGeometry.frame(in: .global)
                    navigationHeight = max(0, contentFrame.minY - rootFrame.minY)
                    #if DEBUG
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.eugenechan.Noto2", category: "DailyCalendar")
                        .debug("Sheet root y \(rootFrame.minY), content y \(contentFrame.minY), chrome \(navigationHeight)")
                    #endif
                }
                .navigationTitle("Go to a day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) { dismiss() }
                            .accessibilityLabel("Close calendar")
                            .accessibilityIdentifier("dailyCalendarCloseButton")
                    }
                }
                .accessibilityIdentifier("dailyCalendarSheet")
            }
        }
        // Native date cells have a minimum height even when their outer view is
        // compressed. Fit that content, and retain scrolling at larger text sizes.
        .presentationDetents(calendarHeight > 0
            ? [.height(calendarHeight + navigationHeight + 12), .large]
            : [.medium, .large])
        .tint(NotoTheme.accent)
    }

    private var calendarView: some View {
        DailyCalendarView(
            selectedDate: selectedDate,
            today: today,
            calendar: calendar,
            writtenDays: writtenDays,
            onSelect: onSelect,
            onMonthChange: onMonthChange
        )
    }
}

/// Native calendar supplies month navigation, VoiceOver, and date selection.
private struct DailyCalendarView: UIViewRepresentable {
    let selectedDate: Date
    let today: Date
    let calendar: Calendar
    let writtenDays: Set<Date>
    var onSelect: (Date) -> Void
    var onMonthChange: (Date) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.timeZone = calendar.timeZone
        view.locale = .current
        view.tintColor = NotoTheme.uiAccent
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.availableDateRange = DateInterval(start: .distantPast, end: today.addingTimeInterval(1))
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        let components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        selection.setSelected(components, animated: false)
        view.setVisibleDateComponents(components, animated: false)
        view.accessibilityIdentifier = "dailyCalendarView"
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let previousDays = context.coordinator.parent.writtenDays
        context.coordinator.parent = self
        if previousDays != writtenDays {
            let changedDays = previousDays.symmetricDifference(writtenDays)
            view.reloadDecorations(forDateComponents: changedDays.map {
                calendar.dateComponents([.year, .month, .day], from: $0)
            }, animated: true)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        let size = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #if DEBUG
        context.coordinator.recordFitting(size, category: uiView.traitCollection.preferredContentSizeCategory)
        #endif
        return size
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: DailyCalendarView
        init(parent: DailyCalendarView) { self.parent = parent }

        #if DEBUG
        private var lastFittingSize: CGSize?
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.eugenechan.Noto2", category: "DailyCalendar")
        func recordFitting(_ size: CGSize, category: UIContentSizeCategory) {
            guard size != lastFittingSize else { return }
            lastFittingSize = size
            logger.debug("Native calendar fitted \(size.width) × \(size.height), content size \(category.rawValue, privacy: .public)")
        }
        #endif

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let date = parent.calendar.date(from: dateComponents),
                  parent.writtenDays.contains(parent.calendar.startOfDay(for: date)) else { return nil }
            return .default(color: NotoTheme.uiAccent, size: .small)
        }

        func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {
            guard let date = parent.calendar.date(from: calendarView.visibleDateComponents) else { return }
            parent.onMonthChange(date)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = parent.calendar.date(from: dateComponents) else { return }
            parent.onSelect(date)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            guard let dateComponents, let date = parent.calendar.date(from: dateComponents) else { return false }
            return parent.calendar.startOfDay(for: date) <= parent.today
        }
    }
}
