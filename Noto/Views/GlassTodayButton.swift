//
//  GlassTodayButton.swift
//  Noto
//
//  Liquid Glass "Today" button for the bottom toolbar.
//  Navigates directly to today's day block from anywhere in the app.
//

import SwiftUI

struct GlassTodayButton: View {
    let action: () -> Void

    /// SF Symbol name for the current day of the month (e.g. "1.circle" for the 1st).
    private var todaySymbolName: String {
        let day = Calendar.current.component(.day, from: Date())
        return "\(day).circle"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: todaySymbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("todayButton")
    }
}
