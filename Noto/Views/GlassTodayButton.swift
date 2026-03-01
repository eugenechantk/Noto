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

    var body: some View {
        Button(action: action) {
            Image(systemName: "calendar")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("todayButton")
    }
}
