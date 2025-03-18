import SwiftUI

@MainActor
final class BackgroundCache {
    static let shared = BackgroundCache()
    private var cache: [String: Image] = [:]
    
    private init() {}
    
    func cacheBackground(_ image: Image, for key: String) {
        cache[key] = image
    }
    
    func getCachedBackground(for key: String) -> Image? {
        return cache[key]
    }
    
    func clearCache(except currentKey: String? = nil) {
        let keysToRemove = cache.keys.filter { $0 != currentKey }
        keysToRemove.forEach { cache.removeValue(forKey: $0) }
    }
}

struct CachedBackground<Content: View>: View {
    let key: String
    let content: () -> Content
    @State private var cachedImage: Image?
    
    init(key: String, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.content = content
    }
    
    var body: some View {
        Group {
            if let cached = BackgroundCache.shared.getCachedBackground(for: key) {
                cached
                    .resizable()
                    .ignoresSafeArea()
            } else {
                content()
                    .task {
                        let renderer = ImageRenderer(content: content())
                        renderer.scale = UIScreen.main.scale
                        if let uiImage = renderer.uiImage {
                            let image = Image(uiImage: uiImage)
                            BackgroundCache.shared.cacheBackground(image, for: key)
                            cachedImage = image
                        }
                    }
            }
        }
        .onDisappear {
            BackgroundCache.shared.clearCache(except: key)
        }
    }
}

struct Diamond: View {
    var body: some View {
        CachedBackground(key: "diamond") {
            ZStack {
                // Base gradient with stronger blue tint and darker edges
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.55, green: 0.65, blue: 0.9),    // Bright bluish center
                        Color(red: 0.4, green: 0.55, blue: 0.8),    // Mid-tone blue crystal
                        Color(red: 0.2, green: 0.3, blue: 0.6)      // Darker blue edges
                    ]),
                    center: .center,
                    startRadius: 30,
                    endRadius: 350
                )
                .ignoresSafeArea()

                // More defined facet patterns
                DiamondTexture()
                    .foregroundColor(Color.white.opacity(0.4))  // Increased opacity for visibility
                    .blur(radius: 20)                            // Reduced blur for sharper facets
                    .blendMode(.overlay)

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
            }
        }
    }
}

// Enhanced diamond texture with clearer faceted structure
struct DiamondTexture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let facetCount = 10  // Increased number of facets

        for _ in 0..<facetCount {
            let facetX = CGFloat.random(in: 0...rect.width)
            let facetY = CGFloat.random(in: 0...rect.height)
            let facetSize = CGFloat.random(in: 40...120)  // Slightly larger facets

            // Create more structured diamond facets with outline
            let points = [
                CGPoint(x: facetX, y: facetY),                              // Top
                CGPoint(x: facetX + facetSize * 0.6, y: facetY + facetSize), // Bottom right
                CGPoint(x: facetX, y: facetY + facetSize * 0.7),            // Bottom center
                CGPoint(x: facetX - facetSize * 0.6, y: facetY + facetSize)  // Bottom left
            ]

            path.move(to: points[0])
            path.addLine(to: points[1])
            path.addLine(to: points[2])
            path.addLine(to: points[3])
            path.closeSubpath()
        }

        return path
    }
}

struct Dark: View {
    var body: some View {
        CachedBackground(key: "dark") {
            ZStack {
                // Deep dark radial gradient base
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.05), // Dark gray center
                        //Color(red: 0.05, green: 0.05, blue: 0.05), // Darker gray middle
                        Color(red: 0.03, green: 0.03, blue: 0.03)  // Almost black edges
                    ]),
                    center: .center,
                    startRadius: 1,
                    endRadius: 400
                )
                .ignoresSafeArea()
            }
        }
    }
}

struct Mist: View {
    var body: some View {
        CachedBackground(key: "mist") {
            ZStack {
                // Slightly darker misty gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.6, green: 0.65, blue: 0.7),   // Darker blue-grey mist
                        Color(red: 0.7, green: 0.7, blue: 0.75),  // Muted silvery mist
                        Color.white.opacity(0.7)                   // Less bright fog
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Gentle mist shapes
                MistTexture()
                    .foregroundColor(Color.white.opacity(0.4))
                    .blur(radius: 35)
                    .blendMode(.screen)
            }
        }
    }
}

// Custom mist texture
struct MistTexture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mistCount = 10

        for _ in 0..<mistCount {
            let mistX = CGFloat.random(in: -rect.width * 0.2...rect.width * 1.2)
            let mistY = CGFloat.random(in: rect.height * 0.2...rect.height)
            let mistWidth = CGFloat.random(in: rect.width * 0.6...rect.width * 1.5)
            let mistHeight = CGFloat.random(in: rect.height * 0.1...rect.height * 0.3)

            path.addEllipse(in: CGRect(x: mistX, y: mistY, width: mistWidth, height: mistHeight))
        }

        return path
    }
}

struct Sunshine: View {
    var body: some View {
        CachedBackground(key: "sunshine") {
            ZStack {
                // Bright yellow gradient base
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1, green: 0.7, blue: 0.16),  // Warm golden yellow
                        Color(red: 1, green: 0.75, blue: 0.3),  // Bright sunshine yellow
                        Color(red: 1, green: 0.85, blue: 0.35)   // Brightest
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()

                // Subtle sun rays from the top
                RaysTexture()
                    .foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0)) // Pale yellow rays
                    .blendMode(.overlay)
                    .blur(radius: 10)
                
                // Soft edge vignette - unchanged
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(red: 0.6, green: 0.35, blue: 0.08)
                    ]),
                    center: .center,
                    startRadius: 300,
                    endRadius: 500
                )
                .ignoresSafeArea()
            }
        }
    }
}

struct RaysTexture: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: -size.height * 0.3) // Higher above screen
                let rayCount = 80 // Increased number of rays
                let rayWidth: CGFloat = 3*size.width / CGFloat(rayCount)
                
                for i in 0..<rayCount {
                    let angle = CGFloat(i) * (.pi * 2 / CGFloat(rayCount))
                    let x = center.x + cos(angle) * size.height * 2
                    let y = center.y + sin(angle) * size.height * 2
                    
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: x - rayWidth / 2, y: y))
                    path.addLine(to: CGPoint(x: x + rayWidth / 2, y: y))
                    path.closeSubpath()
                    
                    context.fill(path, with: .color(Color.white.opacity(0.5)))
                }
            }
        }
        .blendMode(.overlay)
    }
}

struct Purple: View {
    var body: some View {
        CachedBackground(key: "purple") {
            ZStack {
                // Royal and opulent purple gradient base
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.25, green: 0.05, blue: 0.45),  // Deep royal purple
                        Color(red: 0.45, green: 0.15, blue: 0.7),   // Rich vibrant purple
                        Color(red: 0.35, green: 0.1, blue: 0.55)    // Luxurious muted purple
                    ]),
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                .ignoresSafeArea()
                // Soft edge vignette - unchanged
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.black.opacity(0.8)
                    ]),
                    center: .center,
                    startRadius: 150,
                    endRadius: 500
                )
                .ignoresSafeArea()
            }
        }
    }
}

struct PerlinNoise {
    static func noise(x: Double, y: Double, z: Double) -> Double {
        let n = sin(x * 12.9898 + y * 78.233 + z * 45.123) * 43758.5453123
        return n - floor(n)
    }
}

struct Red: View {
    var body: some View {
        CachedBackground(key: "red") {
            ZStack {
                // Red gradient base
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.8, green: 0.1, blue: 0.1),  // Deep red
                        Color(red: 1.0, green: 0.2, blue: 0.2),  // Bright red
                        Color(red: 0.9, green: 0.15, blue: 0.15) // Slightly muted red
                    ]),
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                .ignoresSafeArea()

                // Subtle red texture
                NoiseTextureRed()
                    .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.2)) // Light red tint
                    .blendMode(.overlay)
                    .blur(radius: 3)
            }
        }
    }
}

// Simple noise texture for subtle grain
struct NoiseTextureRed: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let noiseScale: CGFloat = 0.04
        for x in stride(from: 0, to: rect.width, by: 5) {
            for y in stride(from: 0, to: rect.height, by: 5) {
                let noise = PerlinNoise.noise(x: Double(x) * noiseScale, y: Double(y) * noiseScale, z: 0)
                let offset = CGFloat(noise) * 3
                path.move(to: CGPoint(x: x, y: y))
                path.addRect(CGRect(x: x + offset, y: y + offset, width: 2, height: 2))
            }
        }
        return path
    }
}

struct Bubblegum: View {
    var body: some View {
        CachedBackground(key: "bubblegum") {
            ZStack {
                // Bubblegum pink gradient base
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.9, green: 0.4, blue: 0.6),  // Deep bubblegum pink
                        Color(red: 1.0, green: 0.7, blue: 0.8),  // Light pastel pink
                        Color(red: 0.9, green: 0.55, blue: 0.7) // Almost-white candy tint
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()

                // Subtle bubble effect
                ForEach(0..<5) { _ in
                    Circle()
                        .frame(width: CGFloat.random(in: 50...150), height: CGFloat.random(in: 50...150))
                        .foregroundColor(Color.white.opacity(0.2))
                        .blur(radius: 10)
                        .position(
                            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                            y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                        )
                }

                // Glossy overlay
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.4),
                        Color.clear
                    ]),
                    center: .init(x: 0.3, y: 0.2),
                    startRadius: 50,
                    endRadius: 300
                )
                .blendMode(.overlay)
                .ignoresSafeArea()
            }
        }
    }
}

struct BlueVista: View {
    var body: some View {
        CachedBackground(key: "bluevista") {
            ZStack {
                // Deep blue gradient base
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.1, blue: 0.4),  // Midnight blue
                        Color(red: 0.1, green: 0.3, blue: 0.7),   // Rich cerulean
                        Color(red: 0.2, green: 0.5, blue: 0.9)    // Vibrant sky blue
                    ]),
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
                .ignoresSafeArea()
                .blur(radius: 30)
                .blendMode(.screen)

                // Subtle wave-like texture
                WaveTexture()
                    .foregroundColor(Color.white.opacity(0.05))
                    .blendMode(.overlay)
                    .blur(radius: 10)
            }
        }
    }
}

// Custom wave texture for depth
struct WaveTexture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let waveHeight: CGFloat = 20
        let waveLength: CGFloat = 40

        for x in stride(from: 0, to: rect.width, by: 5) {
            let y = rect.height * 0.5 + sin(x / waveLength) * waveHeight
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

//Slate background ===============
struct SlateBackground: View {
    var body: some View {
        CachedBackground(key: "slate") {
            ZStack {
                // Base gradient with slight color depth
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.18, green: 0.22, blue: 0.27), // Dark slate
                        Color(red: 0.24, green: 0.28, blue: 0.33)  // Slightly lighter slate
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .blur(radius: 2)
        }
    }
}

// Noise texture shape
struct NoiseTexture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let noiseScale: CGFloat = 0.02
        for x in stride(from: 0, to: rect.width, by: 5) {
            for y in stride(from: 0, to: rect.height, by: 5) {
                let noise = PerlinNoise.noise(x: Double(x) * noiseScale, y: Double(y) * noiseScale, z: 0)
                let offset = CGFloat(noise) * 2
                path.move(to: CGPoint(x: x, y: y))
                path.addRect(CGRect(x: x + offset, y: y + offset, width: 2, height: 2))
            }
        }
        return path
    }
}

// Freckles shape
struct Freckles: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let freckleScale: CGFloat = 0.03
        let maxFreckles = 50

        for _ in 0..<maxFreckles {
            let x = CGFloat.random(in: 0..<rect.width)
            let y = CGFloat.random(in: 0..<rect.height)
            let noise = PerlinNoise.noise(x: Double(x) * freckleScale, y: Double(y) * freckleScale, z: 1)
            
            if noise > 0.7 {
                let size = CGFloat.random(in: 1...3)
                path.addEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            }
        }
        return path
    }
}

// Custom freckle style
struct FreckleStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.blue.opacity(0.6),
                Color.green.opacity(0.6)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

//Sunrise background ===============
struct SunriseBackground: View {
    var body: some View {
        CachedBackground(key: "sunrise") {
            ZStack {
                // Sky gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.05, blue: 0.3), // Deep midnight blue
                        Color(red: 0.9, green: 0.3, blue: 0.1), // Warm orange horizon
                        Color(red: 1.0, green: 0.7, blue: 0.4)  // Soft sunrise glow
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()

                // Sun rising with a subtle glow
                Circle()
                    .frame(width: 100, height: 100)
                    .foregroundColor(Color(red: 1.0, green: 0.9, blue: 0.6))
                    .blur(radius: 20)
                    .offset(y: 50)
                    .overlay(
                        Circle()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.white.opacity(0.1))
                            .offset(y: 50)
                    )
            }
        }
    }
}

//======================================
struct NatureBackground: View {
    var body: some View {
        CachedBackground(key: "nature") {
            ZStack {
                // Deep jungle gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.15, blue: 0.1),
                        Color(red: 0.1, green: 0.3, blue: 0.15),
                        Color(red: 0.2, green: 0.5, blue: 0.25)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .blur(radius: 30)
                .ignoresSafeArea()

                // Subtle sky peek-through
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.2, green: 0.5, blue: 0.25).opacity(0.8),
                        Color(red: 0.3, green: 0.6, blue: 0.5).opacity(0.3)
                    ]),
                    startPoint: .center,
                    endPoint: .top
                )
                .blur(radius: 40)

                // Layers of mist/fog
                Color(red: 0.8, green: 0.85, blue: 0.8)
                    .opacity(0.4)
                    .blur(radius: 50)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 100)

                Color(red: 0.9, green: 0.95, blue: 0.9)
                    .opacity(0.3)
                    .blur(radius: 60)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: -50)

                // Faint jungle texture
                NoiseTexture2()
                    .foregroundColor(Color.green.opacity(0.1))
                    .blendMode(.overlay)
                    .blur(radius: 5)
            }
            .ignoresSafeArea()
        }
    }
}

// Reusing your NoiseTexture for subtle texture
struct NoiseTexture2: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let noiseScale: CGFloat = 0.02
        for x in stride(from: 0, to: rect.width, by: 10) {
            for y in stride(from: 0, to: rect.height, by: 10) {
                let noise = PerlinNoise.noise(x: Double(x) * noiseScale, y: Double(y) * noiseScale, z: 0)
                let offset = CGFloat(noise) * 5
                path.move(to: CGPoint(x: x, y: y))
                path.addRect(CGRect(x: x + offset, y: y + offset, width: 3, height: 3))
            }
        }
        return path
    }
}

struct Paper: View {
    var body: some View {
        CachedBackground(key: "paper") {
            ZStack {
                // Darker paper gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 0.88, blue: 0.85),
                        Color(red: 0.95, green: 0.94, blue: 0.91),
                        Color(red: 0.98, green: 0.97, blue: 0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Subtle paper texture
                PaperNoiseTexture()
                    .blendMode(.overlay)
                    .opacity(0.1)

                // Faint shadow for depth
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.05),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blur(radius: 10)
                .ignoresSafeArea()

                // Soft edge vignette
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.black.opacity(0.08)
                    ]),
                    center: .center,
                    startRadius: 100,
                    endRadius: 400
                )
                .ignoresSafeArea()
            }
        }
    }
}

// Function to create paper noise texture
func PaperNoiseTexture() -> some View {
GeometryReader { geo in
    Canvas { context, size in
        for _ in 0..<Int(size.width * size.height / 500) {
            let x = CGFloat.random(in: 0...size.width)
            let y = CGFloat.random(in: 0...size.height)
            let rect = CGRect(x: x, y: y, width: 1, height: 1)
            context.fill(Path(rect), with: .color(Color.black.opacity(0.05)))
        }
    }
}
}

struct Lava: View {
    var body: some View {
        CachedBackground(key: "lava") {
            ZStack {
                // Redder lava gradient base
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.15, green: 0.0, blue: 0.0),
                        Color(red: 0.9, green: 0.1, blue: 0.0),
                        Color(red: 1.0, green: 0.3, blue: 0.05)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()

                // Redder flowing lava texture
                FlowTexture()
                    .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.0).opacity(0.3))
                    .blendMode(.overlay)
                    .blur(radius: 5)

                // Radiant glow
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.4, blue: 0.1).opacity(0.5),
                        Color.clear
                    ]),
                    center: .init(x: 0.5, y: 0.7),
                    startRadius: 50,
                    endRadius: 300
                )
                .blendMode(.screen)
                .ignoresSafeArea()
                
                // Dark vignette around edges
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(red: 0.15, green: 0.0, blue: 0.0).opacity(0.8)
                    ]),
                    center: .center,
                    startRadius: 150,
                    endRadius: 400
                )
                .ignoresSafeArea()
            }
        }
    }
}

struct FlowTexture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let waveHeight: CGFloat = 30
        let waveLength: CGFloat = 60

        for x in stride(from: 0, to: rect.width, by: 5) {
            let y = rect.height * 0.8 + sin(x / waveLength) * waveHeight
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

struct StarryNight: View {
    var body: some View {
        CachedBackground(key: "starrynight") {
            ZStack {
                // Deep space gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.02, green: 0.02, blue: 0.05),  // Near-black base
                        Color(red: 0.05, green: 0.05, blue: 0.15),  // Dark blue-tinted black
                        Color(red: 0.1, green: 0.1, blue: 0.25)     // Slightly lighter blackish-blue
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()

                // Stars
                ForEach(0..<100) { _ in
                    Circle()
                        .frame(width: CGFloat.random(in: 1...4), height: CGFloat.random(in: 1...4))
                        .foregroundColor(Color.white.opacity(CGFloat.random(in: 0.5...1.0)))
                        .blur(radius: CGFloat.random(in: 0...0.5))
                        .position(
                            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                            y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                        )
                }

                // Cosmic glow
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.15, blue: 0.35).opacity(0.2), // Darker blue glow
                        Color.clear
                    ]),
                    center: .init(x: 0.5, y: 0.3),
                    startRadius: 100,
                    endRadius: 300
                )
                .blendMode(.screen)
                .ignoresSafeArea()
            }
        }
    }
}
