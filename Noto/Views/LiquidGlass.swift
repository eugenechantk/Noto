//
//  LiquidGlass.swift
//  Noto
//
//  Reusable liquid glass UI components inspired by Apple's design language.
//

import SwiftUI

// MARK: - Glass Background Modifier

struct GlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 296

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.white.opacity(0.65)
                        )

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.15)
                                : Color.white.opacity(0.5),
                            lineWidth: 0.5
                        )
                }
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.12),
                radius: 20,
                x: 0,
                y: 8
            )
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 296) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Button Style

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Glass Search Bar

struct GlassSearchBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var placeholder: String = "Ask anything or search"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(labelPrimary)

            TextField(placeholder, text: $text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(labelPrimary)
                .tint(labelPrimary)

            Image(systemName: "mic")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(labelSecondary)
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .glassBackground()
    }

    private var labelPrimary: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.9)
            : Color(red: 0.1, green: 0.1, blue: 0.1)
    }

    private var labelSecondary: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.4)
            : Color(red: 0.45, green: 0.45, blue: 0.45)
    }
}

// MARK: - Glass Toolbar Button

struct GlassToolbarButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(labelPrimary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(GlassButtonStyle())
        .frame(height: 44)
        .padding(.horizontal, 4)
        .glassBackground()
    }

    private var labelPrimary: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.9)
            : Color(red: 0.1, green: 0.1, blue: 0.1)
    }
}
