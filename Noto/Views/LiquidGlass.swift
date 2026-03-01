//
//  LiquidGlass.swift
//  Noto
//
//  Reusable Liquid Glass UI components using the native .glassEffect() API (iOS 26+).
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
