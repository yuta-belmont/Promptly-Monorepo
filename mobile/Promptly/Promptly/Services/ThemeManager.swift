import SwiftUI
import Combine

// Define available themes
enum AppTheme: String, CaseIterable, Identifiable {
    case dark = "Night"
    case slate = "Slate"
    case mist = "Mist"
    case nature = "Jungle"
    case blueVista = "Ocean"
    case purple = "Royal"
    case lava = "Lava"
    case sunshine = "Sunshine"
    case bubblegum = "Bubblegum"
    case starryNight = "Starry"
    case diamond = "Crystaline"
    case sunrise = "Sunrise"
    
    var id: String { self.rawValue }
    
    // Return the appropriate background view for each theme
    @ViewBuilder
    func backgroundView() -> some View {
        switch self {
        case .mist:
            Mist()
        case .sunshine:
            Sunshine()
        case .purple:
            Purple()
        case .dark:
            Dark()
        case .lava:
            Lava()
        case .starryNight:
            StarryNight()
        case .nature:
            NatureBackground()
        case .slate:
            SlateBackground()
        case .sunrise:
            SunriseBackground()
        case .blueVista:
            BlueVista()
        case .bubblegum:
            Bubblegum()
        case .diamond:
            Diamond()
        }
    }
    
    // Return a preview thumbnail for the theme
    @ViewBuilder
    func thumbnailView() -> some View {
        switch self {
        case .mist:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.8, green: 0.85, blue: 0.9),   // Light blue-grey mist
                        Color(red: 0.9, green: 0.9, blue: 0.95),  // Pale silvery mist
                        Color.white.opacity(0.9)                   // Almost white fog
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ))
        case .sunshine:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.8, blue: 0.2),  // Warm golden yellow
                        Color(red: 1.0, green: 1.0, blue: 0.4),  // Bright sunshine yellow
                        Color(red: 1.0, green: 0.9, blue: 0.3)   // Slightly muted yellow
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                ))
                .overlay(
                    // Subtle sun rays
                    RaysTexture()
                        .foregroundColor(Color(red: 1.0, green: 1.0, blue: 0.6).opacity(0.3))
                        .blendMode(.overlay)
                        .blur(radius: 10)
                )
        case .purple:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.25, green: 0.05, blue: 0.45),  // Deep royal purple
                        Color(red: 0.45, green: 0.15, blue: 0.7),   // Rich vibrant purple
                        Color(red: 0.35, green: 0.1, blue: 0.55)    // Luxurious muted purple
                    ]),
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ))
        case .dark:
            RoundedRectangle(cornerRadius: 8)
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.06, green: 0.06, blue: 0.06), // Dark gray center
                        Color(red: 0.03, green: 0.03, blue: 0.03)  // Almost black edges
                    ]),
                    center: .center,
                    startRadius: 1,
                    endRadius: 50
                ))
        case .lava:
            RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.15, green: 0.0, blue: 0.0),  // Dark red-black
                                Color(red: 0.9, green: 0.1, blue: 0.0),   // Deep crimson
                                Color(red: 1.0, green: 0.3, blue: 0.05)   // Bright red glow
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        ))
                        .overlay(
                            // Redder glow
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 1.0, green: 0.4, blue: 0.1).opacity(0.4),
                                    Color.clear
                                ]),
                                center: .init(x: 0.5, y: 0.7),
                                startRadius: 10,
                                endRadius: 60
                            )
                            .blendMode(.screen)
                        )
        case .starryNight:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.02, green: 0.02, blue: 0.05),  // Near-black base
                        Color(red: 0.05, green: 0.05, blue: 0.15),  // Dark blue-tinted black
                        Color(red: 0.1, green: 0.1, blue: 0.25)     // Slightly lighter blackish-blue
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                ))
                .overlay(
                    // Subtle stars (scaled down)
                    ForEach(0..<5) { _ in
                        Circle()
                            .frame(width: CGFloat.random(in: 1...3), height: CGFloat.random(in: 1...3))
                            .foregroundColor(Color.white.opacity(CGFloat.random(in: 0.5...1.0)))
                            .blur(radius: CGFloat.random(in: 0...0.5))
                            .position(
                                x: CGFloat.random(in: 0...100),
                                y: CGFloat.random(in: 0...100)
                            )
                    }
                )
                .frame(width: 100, height: 100) // Compact summary size
        case . bubblegum:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.9, green: 0.4, blue: 0.6),  // Deep bubblegum pink
                        Color(red: 1.0, green: 0.7, blue: 0.8),  // Light pastel pink
                        Color(red: 0.95, green: 0.85, blue: 0.9) // Almost-white candy tint
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                ))
        case .nature:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.15, blue: 0.1),
                        Color(red: 0.2, green: 0.5, blue: 0.25)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                ))
        case .slate:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.2, green: 0.25, blue: 0.3),
                        Color(red: 0.25, green: 0.3, blue: 0.35)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        case .sunrise:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.05, blue: 0.3),
                        Color(red: 0.9, green: 0.3, blue: 0.1),
                        Color(red: 1.0, green: 0.7, blue: 0.4)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                ))
        case .blueVista:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.1, blue: 0.4),  // Midnight blue (base)
                        Color(red: 0.1, green: 0.3, blue: 0.7),   // Rich cerulean (middle)
                        Color(red: 0.2, green: 0.5, blue: 0.9)    // Vibrant sky blue (top)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                ))
        case .diamond:
            RoundedRectangle(cornerRadius: 8)
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.55, green: 0.65, blue: 0.9),    // Bright bluish center
                        Color(red: 0.4, green: 0.55, blue: 0.8),    // Mid-tone blue crystal
                        Color(red: 0.2, green: 0.3, blue: 0.6)      // Darker blue edges
                    ]),
                    center: .center,
                    startRadius: 5,
                    endRadius: 50
                ))
                .overlay(
                    // Enhanced sparkle with blue tint
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.8, green: 0.9, blue: 1.0).opacity(0.4),
                            Color.clear,
                            Color(red: 0.7, green: 0.85, blue: 1.0).opacity(0.3)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.softLight)
                )
        }
    }
}

// Theme manager class
class ThemeManager: ObservableObject {
    // Published property for the current theme
    @Published var currentTheme: AppTheme {
        didSet {
            // Save the theme selection to UserDefaults
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "appTheme")
        }
    }
    
    // Singleton instance
    static let shared = ThemeManager()
    
    // Initialize with the saved theme or default to nature
    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.nature.rawValue
        if let theme = AppTheme(rawValue: savedTheme) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .nature
        }
    }
} 
