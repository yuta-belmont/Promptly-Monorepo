import SwiftUI
//BackgroundView.swift

// Replace the cache and CachedBackground with a simpler approach
struct OptimizedBackground<Content: View>: View {
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        content()
            .drawingGroup() // Let SwiftUI handle the optimization
            .ignoresSafeArea()
    }
}

struct Diamond: View {
    var body: some View {
        OptimizedBackground {
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

                // More defined facet patterns - using Canvas instead of Shape
                DiamondField()
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

// Optimized diamond texture with Canvas
struct DiamondField: View {
    // Pre-generate diamond facet data for consistency and performance
    private let facets: [(x: Double, y: Double, size: Double)] = {
        var facetData: [(x: Double, y: Double, size: Double)] = []
        for _ in 0..<10 {
            let x = Double.random(in: 0...1)
            let y = Double.random(in: 0...1)
            let size = Double.random(in: 40...120)
            facetData.append((x: x, y: y, size: size))
        }
        return facetData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Apply a single blur to the entire context
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 20))
            blurredContext.opacity = 0.4
            
            // Draw all diamond facets in a single pass
            for facet in facets {
                let centerX = facet.x * size.width
                let centerY = facet.y * size.height
                let facetSize = facet.size
                
                // Create diamond facet points
                let points = [
                    CGPoint(x: centerX, y: centerY),                               // Top
                    CGPoint(x: centerX + facetSize * 0.6, y: centerY + facetSize), // Bottom right
                    CGPoint(x: centerX, y: centerY + facetSize * 0.7),             // Bottom center
                    CGPoint(x: centerX - facetSize * 0.6, y: centerY + facetSize)  // Bottom left
                ]
                
                // Create a path for the diamond facet
                var path = Path()
                path.move(to: points[0])
                path.addLine(to: points[1])
                path.addLine(to: points[2])
                path.addLine(to: points[3])
                path.closeSubpath()
                
                // Fill the path with white color
                blurredContext.fill(path, with: .color(.white))
            }
        }
    }
}

struct Dark: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Deep dark radial gradient base
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.05), // Dark gray center
                        Color(red: 0.03, green: 0.03, blue: 0.03)  // Almost black edges
                    ]),
                    center: .center,
                    startRadius: 1,
                    endRadius: 400
                )
            }
        }
    }
}

struct Mist: View {
    var body: some View {
        OptimizedBackground {
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

                // Gentle mist shapes - replace Shape with Canvas implementation
                MistField()
                    .blendMode(.screen)
            }
        }
    }
}

// Optimized mist field using Canvas instead of Shape
struct MistField: View {
    // Pre-generate mist data for consistency and performance
    private let mistShapes: [(x: Double, y: Double, width: Double, height: Double)] = {
        var shapes: [(x: Double, y: Double, width: Double, height: Double)] = []
        for _ in 0..<10 {
            let x = Double.random(in: -0.2...1.2) // Relative positioning
            let y = Double.random(in: 0.2...1.0) 
            let width = Double.random(in: 0.6...1.5)
            let height = Double.random(in: 0.1...0.3)
            shapes.append((x: x, y: y, width: width, height: height))
        }
        return shapes
    }()
    
    var body: some View {
        Canvas { context, size in
            // Apply a single blur to the entire context rather than individual shapes
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 35))
            blurredContext.opacity = 0.4
            
            // Draw all mist shapes in a single pass
            for shape in mistShapes {
                let rect = CGRect(
                    x: shape.x * size.width,
                    y: shape.y * size.height,
                    width: shape.width * size.width,
                    height: shape.height * size.height
                )
                
                // Create an elliptical path
                let path = Path(ellipseIn: rect)
                
                // Fill with white color (opacity is set at context level)
                blurredContext.fill(path, with: .color(.white))
            }
        }
    }
}

struct Sunshine: View {
    var body: some View {
        OptimizedBackground {
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
        OptimizedBackground {
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

struct Bubblegum: View {
    var body: some View {
        OptimizedBackground {
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

                // Bubbles rendered in Canvas
                BubbleField()

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
            }
        }
    }
}

// Optimized bubble field using Canvas
struct BubbleField: View {
    // Pre-generate bubble data for consistency
    private let bubbles: [(x: Double, y: Double, size: Double)] = {
        var bubbleData: [(x: Double, y: Double, size: Double)] = []
        for _ in 0..<5 {
            let x = Double.random(in: 0...1)
            let y = Double.random(in: 0...1)
            let size = Double.random(in: 50...150)
            bubbleData.append((x: x, y: y, size: size))
        }
        return bubbleData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Create a new context with blur applied
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 10))
            
            // Set opacity directly on the context
            blurredContext.opacity = 0.2
            
            // Draw all bubbles in a single pass
            for bubble in bubbles {
                let rect = CGRect(
                    x: bubble.x * size.width - bubble.size/2, 
                    y: bubble.y * size.height - bubble.size/2, 
                    width: bubble.size, 
                    height: bubble.size
                )
                
                // Create a path for the bubble
                let path = Path(ellipseIn: rect)
                
                // Draw the bubble with blur applied
                blurredContext.fill(path, with: .color(.white))
            }
        }
    }
}

struct BlueVista: View {
    var body: some View {
        OptimizedBackground {
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
                .blur(radius: 10) // Reduced from 30 to 10
                
                // Add a subtle blue overlay for depth instead of heavy blur
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.3),
                        Color.clear
                    ]),
                    center: .init(x: 0.3, y: 0.3),
                    startRadius: 100,
                    endRadius: 400
                )
                .blendMode(.screen)
                
                // Add soft vignette for depth
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(red: 0.05, green: 0.1, blue: 0.3).opacity(0.7)
                    ]),
                    center: .center,
                    startRadius: 200,
                    endRadius: 500
                )
                .blendMode(.multiply)
            }
        }
    }
}

//Slate background ===============
struct SlateBackground: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Replace LinearGradient with RadialGradient to create darker edges
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.18, green: 0.21, blue: 0.26),  // Lighter slate center
                        Color(red: 0.15, green: 0.17, blue: 0.22),  // Medium slate
                        Color(red: 0.12, green: 0.15, blue: 0.20)   // Darker slate edges
                    ]),
                    center: .center,
                    startRadius: 1,
                    endRadius: 600
                )
            }
        }
    }
}

//Sunrise background ===============
struct SunriseBackground: View {
    var body: some View {
        OptimizedBackground {
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
            }
        }
    }
}

//======================================
struct NatureBackground: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Simplified base with radial gradient for organic feel
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.5, green: 0.8, blue: 0.6),    // Light pale green in center
                        Color(red: 0.3, green: 0.6, blue: 0.4),    // Medium jungle green
                        Color(red: 0.1, green: 0.3, blue: 0.15)     // Deep vibrant jungle green for edges
                    ]),
                    center: .center,
                    startRadius: 50,
                    endRadius: 500
                )
                
                // Subtle linear gradient overlay to add depth
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.4, green: 0.7, blue: 0.5).opacity(0.3),   // Lighter top
                        Color(red: 0.1, green: 0.3, blue: 0.2).opacity(0.3)    // Darker bottom
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.softLight)
                
                // Subtle "glow" near the top to simulate light filtering through leaves
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.8, green: 0.9, blue: 0.7).opacity(0.2),   // Light filtered through leaves
                        Color.clear
                    ]),
                    center: UnitPoint(x: 0.5, y: 0.2),  // Positioned near top
                    startRadius: 50,
                    endRadius: 350
                )
                .blendMode(.screen)
                
                // Very soft vignette for depth
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(red: 0.05, green: 0.15, blue: 0.1).opacity(0.7)
                    ]),
                    center: .center,
                    startRadius: 250,
                    endRadius: 500
                )
                .blendMode(.multiply)
            }
        }
    }
}

struct Lava: View {
    var body: some View {
        OptimizedBackground {
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
            }
        }
    }
}

struct StarryNight: View {
    var body: some View {
        OptimizedBackground {
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

                // Stars rendered in Canvas
                StarField()

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
            }
        }
    }
}

// Optimized star field using Canvas
struct StarField: View {
    // Pre-generate star data for consistency
    private let stars: [(x: Double, y: Double, size: Double, opacity: Double, blur: Double)] = {
        var starData: [(x: Double, y: Double, size: Double, opacity: Double, blur: Double)] = []
        for _ in 0..<100 {
            let x = Double.random(in: 0...1)
            let y = Double.random(in: 0...1)
            let size = Double.random(in: 1...4)
            let opacity = Double.random(in: 0.3...0.9)
            let blur = Double.random(in: 0.2...1.0)
            starData.append((x: x, y: y, size: size, opacity: opacity, blur: blur))
        }
        return starData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Group stars by blur radius to minimize context changes
            let groupedStars = Dictionary(grouping: stars) { $0.blur }
            
            // Draw stars grouped by blur level
            for (blurRadius, starsGroup) in groupedStars {
                // Create a separate context with the specific blur
                var blurredContext = context
                if blurRadius > 0 {
                    blurredContext.addFilter(.blur(radius: blurRadius))
                }
                
                // Draw all stars with the same blur in one pass
                for star in starsGroup {
                    let rect = CGRect(
                        x: star.x * size.width, 
                        y: star.y * size.height, 
                        width: star.size, 
                        height: star.size
                    )
                    
                    // Create a path for the star
                    let path = Path(ellipseIn: rect)
                    
                    // Set the opacity and draw the star
                    var starContext = blurredContext
                    starContext.opacity = star.opacity
                    starContext.fill(path, with: .color(.white))
                }
            }
        }
    }
}
