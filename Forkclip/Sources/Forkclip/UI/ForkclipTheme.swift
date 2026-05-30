import AppKit
import SwiftUI

enum ForkclipTheme {
    static func ink(_ opacity: Double = 1) -> Color {
        dynamicColor(
            light: NSColor(calibratedWhite: 0.08, alpha: opacity),
            dark: NSColor(calibratedWhite: 1.0, alpha: opacity)
        )
    }

    static func surfaceInk(_ opacity: Double) -> Color {
        dynamicColor(
            light: NSColor(calibratedWhite: 0.0, alpha: opacity),
            dark: NSColor(calibratedWhite: 1.0, alpha: opacity)
        )
    }

    static func surfaceShade(_ opacity: Double) -> Color {
        dynamicColor(
            light: NSColor(calibratedWhite: 1.0, alpha: opacity),
            dark: NSColor(calibratedWhite: 0.0, alpha: opacity)
        )
    }

    static func separator(_ opacity: Double = 0.10) -> Color {
        surfaceInk(opacity)
    }

    static var quickPanelBackground: LinearGradient {
        LinearGradient(
            colors: [
                dynamicColor(
                    light: NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.72),
                    dark: NSColor(calibratedWhite: 0.0, alpha: 0.50)
                ),
                dynamicColor(
                    light: NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.0, alpha: 0.94),
                    dark: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 0.94)
                ),
                dynamicColor(
                    light: NSColor(calibratedRed: 0.97, green: 0.94, blue: 1.0, alpha: 0.88),
                    dark: NSColor(calibratedRed: 0.11, green: 0.09, blue: 0.15, alpha: 0.88)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var dashboardBackground: LinearGradient {
        LinearGradient(
            colors: [
                dynamicColor(
                    light: NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.66),
                    dark: NSColor(calibratedWhite: 0.0, alpha: 0.40)
                ),
                dynamicColor(
                    light: NSColor(calibratedRed: 0.91, green: 0.95, blue: 1.0, alpha: 0.92),
                    dark: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 0.92)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            NSColor(name: nil) { appearance in
                let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
                return bestMatch == .darkAqua ? dark : light
            }
        )
    }
}
