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
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var placeholder: String = "Ask anything or search"

    private var toolbarForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var toolbarSecondaryColor: Color {
        toolbarForegroundColor.opacity(0.72)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(toolbarForegroundColor)

            TextField(placeholder, text: $text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(toolbarForegroundColor)
                .tint(toolbarForegroundColor)
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Glass Search Bar Trigger

/// Looks like GlassSearchBar but acts as a tappable button to present the search sheet.
struct GlassSearchBarTrigger: View {
    @Environment(\.colorScheme) private var colorScheme
    var placeholder: String = "Ask anything or search"
    let action: () -> Void

    private var toolbarForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var toolbarSecondaryColor: Color {
        toolbarForegroundColor.opacity(0.72)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(toolbarForegroundColor)

                Text(placeholder)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(toolbarSecondaryColor)

                Spacer()
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("searchBarTrigger")
    }
}

// MARK: - Glass Toolbar Button

struct GlassToolbarButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    let action: () -> Void

    private var toolbarForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(toolbarForegroundColor)
                .frame(width: 36, height: 36)
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Glass Today Button

struct GlassTodayButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void

    /// SF Symbol name for the current day of the month (e.g. "1.calendar" for the 1st).
    private var todaySymbolName: String {
        let day = Calendar.current.component(.day, from: Date())
        return "\(day).calendar"
    }

    private var toolbarForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: todaySymbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(toolbarForegroundColor)
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("todayButton")
    }
}
