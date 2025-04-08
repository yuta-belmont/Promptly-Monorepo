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
    case sunrise = "Sunrise"
    case roseGold = "RoseGold"
    case emerald = "Emerald"
    case diamond = "Crystalline"
    case starryNight = "Starry"
    case vibrant = "Vibrant"
    case hallucination = "Daydream"
    case hyperVibrant = "HyperVibrant"
    case nightmare = "Dusk"
    case theEnd = "The End"
    
    var id: String { self.rawValue }
    
    // Return the appropriate background view for each theme
    @ViewBuilder
    func backgroundView() -> some View {
        switch self {
        case .theEnd:
            TheEnd()
        case .nightmare:
            Nightmare()
        case .hallucination:
            Hallucination()
        case .hyperVibrant:
            HyperVibrant()
        case .roseGold:
            RoseGold()
        case .vibrant:
            GradientBackground()
        case .emerald:
            Emerald()
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
        case .theEnd:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.black))
        case .nightmare:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.05),  // Near black
                        Color(white: 0.1),   // Very dark gray
                        Color(white: 0.03)   // Even darker 
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    // Eerie red glow
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.4, green: 0.0, blue: 0.0).opacity(0.2),  // Deep red glow
                            Color.clear
                        ]),
                        center: .init(x: 0.5, y: 0.5),
                        startRadius: 0,
                        endRadius: 30
                    )
                    .blendMode(.screen)
                )
        case .hallucination:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.8).opacity(0.92).blended(with: Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.15)),    // Hint of cyan (slightly stronger)
                        Color(white: 0.3).opacity(0.92).blended(with: Color(red: 0.2, green: 0.0, blue: 1.0).opacity(0.15)),     // Hint of blue (slightly stronger)
                        Color(white: 0.7).opacity(0.92).blended(with: Color(red: 0.95, green: 0.0, blue: 1.0).opacity(0.15)),    // Hint of magenta (slightly stronger)
                        Color(white: 0.5).opacity(0.92).blended(with: Color(red: 1.0, green: 0.2, blue: 0.0).opacity(0.15)),     // Hint of orange-red (slightly stronger)
                        Color(white: 0.9).opacity(0.92).blended(with: Color(red: 1.0, green: 0.9, blue: 0.0).opacity(0.15))      // Hint of yellow (slightly stronger)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    // Subtle highlight to mimic the effect in the actual background
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        center: .init(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: 30
                    )
                    .blendMode(.screen)
                )
        case .hyperVibrant:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.0, green: 0.85, blue: 1.0),    // Bright cyan in top-left
                        Color(red: 0.2, green: 0.0, blue: 1.0),     // Electric blue
                        Color(red: 0.95, green: 0.0, blue: 1.0),    // Hot pink/magenta
                        Color(red: 1.0, green: 0.2, blue: 0.0),     // Vibrant red-orange
                        Color(red: 1.0, green: 0.9, blue: 0.0)      // Electric yellow in bottom-right
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    // Pulsing glow center
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1),
                            Color.clear
                        ]),
                        center: .init(x: 0.5, y: 0.5),
                        startRadius: 0,
                        endRadius: 40
                    )
                    .blendMode(.overlay)
                )
        case .roseGold:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.85, green: 0.65, blue: 0.65),  // Pale rose in top-left
                        Color(red: 0.93, green: 0.75, blue: 0.65),  // Light rose gold
                        Color(red: 0.75, green: 0.55, blue: 0.45),  // Deeper rose gold
                        Color(red: 0.60, green: 0.40, blue: 0.35)   // Burnished copper in bottom-right
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    // Subtle golden gleam
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1.0, green: 0.95, blue: 0.8).opacity(0.25),  // Gold tint
                            Color.clear
                        ]),
                        center: .init(x: 0.25, y: 0.25),
                        startRadius: 0,
                        endRadius: 50
                    )
                    .blendMode(.screen)
                )
        case .vibrant:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.2, green: 0.4, blue: 0.8),    // Deep blue in top-left
                        Color(red: 0.5, green: 0.3, blue: 0.8),    // Purple in middle-top
                        Color(red: 0.8, green: 0.2, blue: 0.6),    // Magenta in middle
                        Color(red: 0.9, green: 0.3, blue: 0.2),    // Coral in middle-bottom
                        Color(red: 1.0, green: 0.6, blue: 0.1)     // Gold in bottom-right
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    // Add subtle highlight as in the actual background
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.2),
                            Color.clear
                        ]),
                        center: .init(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: 50
                    )
                    .blendMode(.screen)
                )
        case .emerald:
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.02, green: 0.18, blue: 0.12),  // Darkest at top
                        Color(red: 0.03, green: 0.25, blue: 0.18),  // Medium in middle
                        Color(red: 0.05, green: 0.35, blue: 0.25)   // Lightest at bottom
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    // Subtle shine effect
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.25),
                            Color.clear
                        ]),
                        center: .init(x: 0.3, y: 0.7),
                        startRadius: 5,
                        endRadius: 40
                    )
                    .blendMode(.softLight)
                )
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
