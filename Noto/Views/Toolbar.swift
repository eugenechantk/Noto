//
//  LiquidGlass.swift
//  Noto
//
//  Reusable Liquid Glass UI components using the native .glassEffect() API (iOS 26+).
//  Contains all glass-styled toolbar buttons and controls used by OutlineView.
//

import SwiftUI

// MARK: - Glass Search Bar

struct GlassSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Ask anything or search"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)

            TextField(placeholder, text: $text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .tint(.primary)

            Image(systemName: "mic")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Glass Toolbar Button

struct GlassToolbarButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Glass Today Button

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
