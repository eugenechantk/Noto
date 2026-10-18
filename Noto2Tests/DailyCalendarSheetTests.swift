import SwiftUI
import Testing
import UIKit
@testable import Noto2

@MainActor
@Suite(.serialized)
struct DailyCalendarSheetTests {
    @Test func calendarFitsAllDateCellsForFiveAndSixWeekMonths() async throws {
        for month in [8, 10] {
            let host = makeHost(month: month, typeSize: .large)
            let window = present(host)
            defer { window.isHidden = true; window.rootViewController = nil }
            let calendar = try await renderedCalendar(in: window)
            let sheet = try #require(host.presentedViewController?.view)
            #expect(calendar.traitCollection.preferredContentSizeCategory == .large)
            let calendarFrame = calendar.convert(calendar.bounds, to: sheet)
            let unusedHeight = sheet.bounds.maxY - sheet.safeAreaInsets.bottom - calendarFrame.maxY
            #expect(unusedHeight <= 16, "Calendar sheet leaves \(unusedHeight) points below native content")
            let labels = dateLabels(in: calendar)
            #expect(Set(labels.compactMap { Int($0.text ?? "") }) == Set(1...31))
            for label in labels {
                // Check the native date-cell hit area, not merely the calendar's
                // outer frame: that frame previously fit while its days clipped.
                let cell = try #require(ancestor(UICollectionViewCell.self, of: label))
                let frame = cell.convert(cell.bounds, to: sheet)
                #expect(frame.minY >= 0)
                #expect(frame.maxY <= sheet.bounds.maxY - sheet.safeAreaInsets.bottom + 1,
                        "Month \(month), day \(label.text ?? ""), cell \(frame), sheet \(sheet.bounds)")
            }
        }
    }

    @Test func accessibilityCalendarRetainsScrollableNativeDateCells() async throws {
        let host = makeHost(month: 8, typeSize: .accessibility3)
        let window = present(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        let calendar = try await renderedCalendar(in: window)
        #expect(calendar.traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
        let scroll = try #require(ancestor(UIScrollView.self, of: calendar))
        let lastDay = try #require(dateLabels(in: calendar).first { $0.text == "31" })
        let cell = try #require(ancestor(UICollectionViewCell.self, of: lastDay))
        scroll.scrollRectToVisible(cell.convert(cell.bounds, to: scroll), animated: false)
        window.layoutIfNeeded()
        let frame = cell.convert(cell.bounds, to: scroll)
        #expect(scroll.bounds.inset(by: scroll.adjustedContentInset).contains(frame))
        #expect(calendar.selectionBehavior is UICalendarSelectionSingleDate)
    }

    private func present(_ host: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        return window
    }

    private func renderedCalendar(in window: UIWindow) async throws -> UICalendarView {
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if let calendar = descendants(UICalendarView.self, in: window).first {
                try await Task.sleep(for: .milliseconds(300))
                window.layoutIfNeeded()
                return calendar
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try #require(descendants(UICalendarView.self, in: window).first)
    }

    private func makeHost(month: Int, typeSize: DynamicTypeSize) -> UIViewController {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18))!
        let selected = calendar.date(from: DateComponents(year: 2026, month: month, day: 15))!
        return UIHostingController(rootView: Color.clear.sheet(isPresented: .constant(true)) {
            DailyCalendarSheet(
                selectedDate: selected,
                today: today,
                calendar: calendar,
                writtenDays: [],
                onSelect: { _ in },
                onMonthChange: { _ in }
            )
            .presentationDragIndicator(.visible)
            .environment(\.dynamicTypeSize, typeSize)
        })
    }

    private func dateLabels(in calendar: UICalendarView) -> [UILabel] {
        descendants(UILabel.self, in: calendar).filter {
            guard let day = Int($0.text ?? ""), (1...31).contains(day) else { return false }
            var view: UIView? = $0
            while let current = view {
                if current.isHidden || current.alpha == 0 { return false }
                view = current.superview
            }
            return true
        }
    }

    private func descendants<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }

    private func ancestor<T: UIView>(_ type: T.Type, of view: UIView) -> T? {
        var parent = view.superview
        while let current = parent {
            if let found = current as? T { return found }
            parent = current.superview
        }
        return nil
    }
}
