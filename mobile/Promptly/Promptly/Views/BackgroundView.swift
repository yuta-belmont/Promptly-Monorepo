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

struct TheEnd: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                Color(.black)
            }
        }
    }
}

struct Dark: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.05) // Dark gray center
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
                        Color(red: 0.4, green: 0.67, blue: 0.47),    // Light pale green in center
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
                        Color(red: 0.3, green: 0.55, blue: 0.37).opacity(0.3),   // Lighter top
                        Color(red: 0.1, green: 0.3, blue: 0.2).opacity(0.3)    // Darker bottom
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.softLight)
                
                // Subtle "glow" near the top to simulate light filtering through leaves
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.8, green: 0.9, blue: 0.7).opacity(0.2).opacity(0.5),   // Light filtered through leaves
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

//Emerald background ===============
struct Emerald: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Deep emerald gradient base - changed to linear gradient, darker at top
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.0133, green: 0.12, blue: 0.08),  // Darkest at top
                        Color(red: 0.03, green: 0.25, blue: 0.18),  // Medium in middle
                        Color(red: 0.05, green: 0.35, blue: 0.25)   // Lightest at bottom
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Shimmering effect
                EmeraldFacets()
                    .blendMode(.overlay)
                
            }
        }
    }
}

// Optimized emerald facets using Canvas
struct EmeraldFacets: View {
    // Pre-generate facet data for consistency
    private let facets: [(x: Double, y: Double, width: Double, height: Double, rotation: Double)] = {
        var facetData: [(x: Double, y: Double, width: Double, height: Double, rotation: Double)] = []
        for _ in 0..<15 {
            let x = Double.random(in: 0...1)
            let y = Double.random(in: 0...1)
            let width = Double.random(in: 50...150)
            let height = Double.random(in: 20...60)
            let rotation = Double.random(in: 0...(.pi * 2))
            facetData.append((x: x, y: y, width: width, height: height, rotation: rotation))
        }
        return facetData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Apply a single blur to the entire context
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 15))
            blurredContext.opacity = 0.2
            
            // Draw all facets in a single pass
            for facet in facets {
                let centerX = facet.x * size.width
                let centerY = facet.y * size.height
                
                // Create a rectangle path
                var path = Path(CGRect(
                    x: centerX - facet.width/2,
                    y: centerY - facet.height/2,
                    width: facet.width,
                    height: facet.height
                ))
                
                // Rotate the path
                let rotation = CGAffineTransform(rotationAngle: facet.rotation)
                let translation = CGAffineTransform(translationX: centerX, y: centerY)
                let transform = CGAffineTransform(translationX: -centerX, y: -centerY)
                    .concatenating(rotation)
                    .concatenating(translation)
                
                path = path.applying(transform)
                
                // Fill with white color for shimmer effect
                blurredContext.fill(path, with: .color(.white))
            }
        }
    }
}

//Gradient background ===============
struct GradientBackground: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Base diagonal gradient with vibrant colors
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(red: 0.2, green: 0.4, blue: 0.8),    // Deep blue in top-left
                        Color(red: 0.5, green: 0.3, blue: 0.8),    // Purple in middle-top
                        Color(red: 0.8, green: 0.2, blue: 0.6),    // Magenta in middle
                        Color(red: 0.9, green: 0.3, blue: 0.2),    // Coral in middle-bottom
                        Color(red: 1.0, green: 0.6, blue: 0.1)     // Gold in bottom-right
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Soft light trails effect
                GradientTrails()
                    .blendMode(.softLight)
                
                // Add subtle highlight
                RadialGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color.white.opacity(0.2),
                        Color.clear
                    ]),
                    center: .init(x: 0.3, y: 0.3),
                    startRadius: 0,
                    endRadius: 300
                )
                .blendMode(.screen)
                
                // Add subtle shadow edges for depth
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color.black.opacity(0.3),
                        Color.clear,
                        Color.clear,
                        Color.black.opacity(0.3)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blendMode(.multiply)
            }
        }
    }
}

// Light trails that add motion to the gradient
struct GradientTrails: View {
    // Pre-generate trail data for consistency
    private let trails: [(start: UnitPoint, end: UnitPoint, width: Double, opacity: Double)] = {
        var trailData: [(start: UnitPoint, end: UnitPoint, width: Double, opacity: Double)] = []
        for _ in 0..<10 {
            // Create diagonal trails in the same direction as the gradient
            let x1 = Double.random(in: -0.2...0.6)
            let y1 = Double.random(in: -0.2...0.6)
            let length = Double.random(in: 0.4...1.0)
            let angle = Double.random(in: -0.1...0.1) + 0.785 // Base around 45° (π/4) with slight variation
            
            let x2 = x1 + cos(angle) * length
            let y2 = y1 + sin(angle) * length
            
            let width = Double.random(in: 10...60)
            let opacity = Double.random(in: 0.1...0.4)
            
            trailData.append((
                start: UnitPoint(x: x1, y: y1),
                end: UnitPoint(x: x2, y: y2),
                width: width,
                opacity: opacity
            ))
        }
        return trailData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Apply a single blur to the entire context
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 20))
            
            // Draw all trails in a single pass
            for trail in trails {
                let start = CGPoint(
                    x: trail.start.x * size.width,
                    y: trail.start.y * size.height
                )
                let end = CGPoint(
                    x: trail.end.x * size.width,
                    y: trail.end.y * size.height
                )
                
                // Create a path for the trail
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                
                // Set line width and opacity
                blurredContext.stroke(path, with: .color(.white), lineWidth: trail.width)
                blurredContext.opacity = trail.opacity
            }
        }
    }
}

//RoseGold background ===============
struct RoseGold: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Base diagonal gradient with focused rose gold palette
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(red: 0.85, green: 0.65, blue: 0.65),  // Pale rose in top-left
                        Color(red: 0.93, green: 0.75, blue: 0.65),  // Light rose gold
                        Color(red: 0.85, green: 0.65, blue: 0.55),  // Medium rose gold
                        Color(red: 0.75, green: 0.55, blue: 0.45),  // Deeper rose gold
                        Color(red: 0.60, green: 0.40, blue: 0.35)   // Burnished copper in bottom-right
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Soft metallic gleam effect
                RoseGoldGleam()
                    .blendMode(.softLight)
                
                // Add golden highlight
                RadialGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(red: 1.0, green: 0.95, blue: 0.8).opacity(0.25),  // Gold tint
                        Color.clear
                    ]),
                    center: .init(x: 0.25, y: 0.25),
                    startRadius: 0,
                    endRadius: 300
                )
                .blendMode(.screen)
                
                // Add subtle shadow edges for depth
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color.black.opacity(0.2),
                        Color.clear,
                        Color.clear,
                        Color.black.opacity(0.2)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blendMode(.multiply)
            }
        }
    }
}

// Gleam effect that creates a subtle metallic shine
struct RoseGoldGleam: View {
    // Pre-generate gleam data for consistency
    private let gleams: [(x: Double, y: Double, width: Double, height: Double, rotation: Double, opacity: Double)] = {
        var gleamData: [(x: Double, y: Double, width: Double, height: Double, rotation: Double, opacity: Double)] = []
        for _ in 0..<8 {
            // Create gleams flowing diagonally like the gradient
            let x = Double.random(in: 0...1)
            let y = Double.random(in: 0...1)
            let width = Double.random(in: 80...200)
            let height = Double.random(in: 10...30)
            let baseAngle = 0.785 // 45° (π/4)
            let rotation = Double.random(in: -0.1...0.1) + baseAngle
            let opacity = Double.random(in: 0.1...0.3)
            
            gleamData.append((
                x: x, y: y, width: width, height: height, rotation: rotation, opacity: opacity
            ))
        }
        return gleamData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Apply a single blur to the entire context
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 15))
            
            // Draw all gleams in a single pass
            for gleam in gleams {
                let centerX = gleam.x * size.width
                let centerY = gleam.y * size.height
                
                // Create an oval path for the gleam
                var path = Path(ellipseIn: CGRect(
                    x: centerX - gleam.width/2,
                    y: centerY - gleam.height/2,
                    width: gleam.width,
                    height: gleam.height
                ))
                
                // Rotate the path to follow gradient direction
                let rotation = CGAffineTransform(rotationAngle: gleam.rotation)
                let translation = CGAffineTransform(translationX: centerX, y: centerY)
                let transform = CGAffineTransform(translationX: -centerX, y: -centerY)
                    .concatenating(rotation)
                    .concatenating(translation)
                
                path = path.applying(transform)
                
                // Set opacity and fill with white for shimmer effect
                blurredContext.opacity = gleam.opacity
                blurredContext.fill(path, with: .color(.white))
            }
        }
    }
}

//HyperVibrant background ===============
struct HyperVibrant: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Base diagonal gradient with intense, saturated colors
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(red: 0.0, green: 0.85, blue: 1.0),    // Bright cyan in top-left
                        Color(red: 0.2, green: 0.0, blue: 1.0),     // Electric blue
                        Color(red: 0.95, green: 0.0, blue: 1.0),    // Hot pink/magenta
                        Color(red: 1.0, green: 0.2, blue: 0.0),     // Vibrant red-orange
                        Color(red: 1.0, green: 0.9, blue: 0.0)      // Electric yellow in bottom-right
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Dynamic energy waves
                EnergyWaves()
                    .blendMode(.screen)
                
                // Pulsing glow center
                RadialGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color.white.opacity(0.4),
                        Color.white.opacity(0.1),
                        Color.clear
                    ]),
                    center: .init(x: 0.5, y: 0.5),
                    startRadius: 0,
                    endRadius: 250
                )
                .blendMode(.overlay)
                
                // Add vibrant edge highlights
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.3),  // Bright cyan edge
                        Color.clear,
                        Color.clear,
                        Color(red: 1.0, green: 0.0, blue: 0.8).opacity(0.3)   // Magenta edge
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
                
                // Sharp contrast boost
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color.black.opacity(0.2),
                        Color.clear,
                        Color.clear,
                        Color.black.opacity(0.2)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blendMode(.multiply)
            }
        }
    }
}

// Dynamic energy waves for the HyperVibrant background
struct EnergyWaves: View {
    // Pre-generate wave data for consistency but with more intense properties
    private let waves: [(start: UnitPoint, end: UnitPoint, width: Double, opacity: Double, color: Color)] = {
        var waveData: [(start: UnitPoint, end: UnitPoint, width: Double, opacity: Double, color: Color)] = []
        
        // Predefined vibrant colors for the waves
        let colors = [
            Color(red: 0.0, green: 1.0, blue: 1.0),  // Cyan
            Color(red: 0.3, green: 0.0, blue: 1.0),  // Electric blue
            Color(red: 1.0, green: 0.0, blue: 1.0),  // Magenta
            Color(red: 1.0, green: 0.3, blue: 0.0),  // Orange-red
            Color(red: 1.0, green: 1.0, blue: 0.0)   // Yellow
        ]
        
        for i in 0..<15 {  // More waves for greater intensity
            // Create diagonal waves in various directions for more dynamic feel
            let x1 = Double.random(in: -0.2...0.6)
            let y1 = Double.random(in: -0.2...0.6)
            let length = Double.random(in: 0.5...1.2)  // Longer waves
            
            // Multiple angles to create more chaotic, energetic pattern
            let baseAngles = [0.785, 0.4, 1.2, 0.0, 1.57]  // 45°, ~23°, ~69°, 0°, 90°
            let angleIndex = i % baseAngles.count
            let angle = baseAngles[angleIndex] + Double.random(in: -0.2...0.2)  // Add variation
            
            let x2 = x1 + cos(angle) * length
            let y2 = y1 + sin(angle) * length
            
            let width = Double.random(in: 15...80)  // Wider for more impact
            let opacity = Double.random(in: 0.2...0.5)  // Higher opacity for visibility
            let color = colors[i % colors.count]  // Cycle through vibrant colors
            
            waveData.append((
                start: UnitPoint(x: x1, y: y1),
                end: UnitPoint(x: x2, y: y2),
                width: width,
                opacity: opacity,
                color: color
            ))
        }
        return waveData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Apply glow effect with blur
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 15))
            
            // Draw all energy waves in a single pass
            for wave in waves {
                let start = CGPoint(
                    x: wave.start.x * size.width,
                    y: wave.start.y * size.height
                )
                let end = CGPoint(
                    x: wave.end.x * size.width,
                    y: wave.end.y * size.height
                )
                
                // Create a path for the wave
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                
                // Set opacity and color
                blurredContext.opacity = wave.opacity
                
                // Use color for each wave instead of just white
                blurredContext.stroke(path, with: .color(wave.color), lineWidth: wave.width)
            }
        }
    }
}

//HyperGray background ===============
struct Hallucination: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Base diagonal gradient with grayscale equivalents plus subtle color hints
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(white: 0.8).opacity(0.92).blended(with: Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.08)),    // Hint of cyan
                        Color(white: 0.3).opacity(0.92).blended(with: Color(red: 0.2, green: 0.0, blue: 1.0).opacity(0.08)),     // Hint of blue
                        Color(white: 0.7).opacity(0.92).blended(with: Color(red: 0.95, green: 0.0, blue: 1.0).opacity(0.08)),    // Hint of magenta
                        Color(white: 0.5).opacity(0.92).blended(with: Color(red: 1.0, green: 0.2, blue: 0.0).opacity(0.08)),     // Hint of orange-red
                        Color(white: 0.9).opacity(0.92).blended(with: Color(red: 1.0, green: 0.9, blue: 0.0).opacity(0.08))      // Hint of yellow
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Dynamic energy waves in grayscale with subtle color hints
                GrayWavesWithColorHints()
                    .blendMode(.screen)
                 
                
                // Add grayscale edge highlights with subtle color hints
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color.clear,
                        Color.clear,
                        Color.clear,
                        Color(white: 0.8).opacity(0.28).blended(with: Color(red: 1.0, green: 0.0, blue: 0.8).opacity(0.02))   // Hint of magenta
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
                
                // Sharp contrast boost (black, so remains unchanged)
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color.black.opacity(0.2),
                        Color.clear,
                        Color.clear,
                        Color.black.opacity(0.2)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blendMode(.multiply)
            }
        }
    }
}

// Helper extension to blend colors
extension Color {
    func blended(with color: Color) -> Color {
        return self.opacity(1.0).opacity(1.0) + color.opacity(1.0)
    }
    
    static func + (lhs: Color, rhs: Color) -> Color {
        let components1 = lhs.components
        let components2 = rhs.components
        
        return Color(
            red: components1.red + components2.red,
            green: components1.green + components2.green,
            blue: components1.blue + components2.blue
        )
    }
    
    var components: (red: Double, green: Double, blue: Double, opacity: Double) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var o: CGFloat = 0
        
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &o) else {
            return (0, 0, 0, 0)
        }
        
        return (Double(r), Double(g), Double(b), Double(o))
    }
}

// Dynamic energy waves for the HyperGray background with color hints
struct GrayWavesWithColorHints: View {
    // Pre-generate wave data for consistency but with more intense properties
    private let waves: [(start: UnitPoint, end: UnitPoint, width: Double, opacity: Double, grayValue: Double, colorHint: Color)] = {
        var waveData: [(start: UnitPoint, end: UnitPoint, width: Double, opacity: Double, grayValue: Double, colorHint: Color)] = []
        
        // Subtle color hints for the waves
        let colorHints = [
            Color(red: 0.0, green: 1.0, blue: 1.0),  // Cyan
            Color(red: 0.3, green: 0.0, blue: 1.0),  // Electric blue
            Color(red: 1.0, green: 0.0, blue: 1.0),  // Magenta
            Color(red: 1.0, green: 0.3, blue: 0.0),  // Orange-red
            Color(red: 1.0, green: 1.0, blue: 0.0)   // Yellow
        ]
        
        for i in 0..<15 {  // More waves for greater intensity
            // Create diagonal waves in various directions for more dynamic feel
            let x1 = Double.random(in: -0.2...0.6)
            let y1 = Double.random(in: -0.2...0.6)
            let length = Double.random(in: 0.5...1.2)  // Longer waves
            
            // Multiple angles to create more chaotic, energetic pattern
            let baseAngles = [0.785, 0.4, 1.2, 0.0, 1.57]  // 45°, ~23°, ~69°, 0°, 90°
            let angleIndex = i % baseAngles.count
            let angle = baseAngles[angleIndex] + Double.random(in: -0.2...0.2)  // Add variation
            
            let x2 = x1 + cos(angle) * length
            let y2 = y1 + sin(angle) * length
            
            let width = Double.random(in: 15...80)  // Wider for more impact
            let opacity = Double.random(in: 0.2...0.5)  // Higher opacity for visibility
            let grayValue = Double.random(in: 0.7...1.0) // Use bright grays for the waves
            let colorHint = colorHints[i % colorHints.count].opacity(0.08)  // Very subtle color hint
            
            waveData.append((
                start: UnitPoint(x: x1, y: y1),
                end: UnitPoint(x: x2, y: y2),
                width: width,
                opacity: opacity,
                grayValue: grayValue,
                colorHint: colorHint
            ))
        }
        return waveData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Apply glow effect with blur
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 15))
            
            // Draw all energy waves in a single pass
            for wave in waves {
                let start = CGPoint(
                    x: wave.start.x * size.width,
                    y: wave.start.y * size.height
                )
                let end = CGPoint(
                    x: wave.end.x * size.width,
                    y: wave.end.y * size.height
                )
                
                // Create a path for the wave
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                
                // Set opacity and use the grayscale color with a hint of color
                // For the Canvas API, we'll just use the color hint directly with very low opacity
                blurredContext.opacity = wave.opacity
                
                // First stroke with the grayscale color
                blurredContext.stroke(path, with: .color(Color(white: wave.grayValue)), lineWidth: wave.width)
                
                // Then add a second pass with the color hint at very low opacity
                var colorContext = blurredContext
                colorContext.opacity = wave.opacity * 0.15  // Even lower opacity for the color hint
                colorContext.stroke(path, with: .color(wave.colorHint), lineWidth: wave.width)
            }
        }
    }
}

//Nightmare background ===============
struct Nightmare: View {
    var body: some View {
        OptimizedBackground {
            ZStack {
                // Base diagonal gradient with dark colors and subtle color hints
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(white: 0.05).opacity(0.92).blended(with: Color(red: 0.0, green: 0.1, blue: 0.3).opacity(0.08)),    // Hint of dark blue
                        Color(white: 0.1).opacity(0.92).blended(with: Color(red: 0.2, green: 0.0, blue: 0.3).opacity(0.08)),     // Hint of deep purple
                        Color(white: 0.03).opacity(0.92).blended(with: Color(red: 0.3, green: 0.0, blue: 0.2).opacity(0.08)),    // Hint of deep crimson
                        Color(white: 0.08).opacity(0.92).blended(with: Color(red: 0.2, green: 0.05, blue: 0.0).opacity(0.08)),   // Hint of dark red
                        Color(white: 0.0).opacity(0.92).blended(with: Color(red: 0.1, green: 0.05, blue: 0.0).opacity(0.08))     // Hint of deep amber
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Dynamic energy waves in dark grayscale with subtle color hints
                NightmareWaves()
                    .blendMode(.screen)
                
                // Eerie glow center
                RadialGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(red: 0.4, green: 0.0, blue: 0.0).opacity(0.15),  // Deep red glow
                        Color.clear
                    ]),
                    center: .init(x: 0.5, y: 0.5),
                    startRadius: 0,
                    endRadius: 250
                )
                .blendMode(.screen)
                
                // Add dark edge highlights with subtle color hints
                LinearGradient(
                    gradient: SwiftUI.Gradient(colors: [
                        Color(white: 0.0).opacity(0.5),
                        Color.clear,
                        Color.clear,
                        Color(white: 0.0).opacity(0.5).blended(with: Color(red: 0.3, green: 0.0, blue: 0.0).opacity(0.05))   // Hint of deep red
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.multiply)
            }
        }
    }
}

// Sinister waves for the Nightmare background
struct NightmareWaves: View {
    // Pre-generate wave data for consistency but with more intense properties
    private let waves: [(start: UnitPoint, end: UnitPoint, width: Double, opacity: Double, grayValue: Double, colorHint: Color)] = {
        var waveData: [(start: UnitPoint, end: UnitPoint, width: Double, opacity: Double, grayValue: Double, colorHint: Color)] = []
        
        // Dark color hints for the waves
        let colorHints = [
            Color(red: 0.1, green: 0.0, blue: 0.2),  // Deep purple
            Color(red: 0.2, green: 0.0, blue: 0.0),  // Dark red
            Color(red: 0.0, green: 0.1, blue: 0.2),  // Dark blue
            Color(red: 0.1, green: 0.05, blue: 0.0), // Deep amber
            Color(red: 0.05, green: 0.0, blue: 0.05) // Dark magenta
        ]
        
        for i in 0..<15 {
            // Create diagonal waves in various disturbing directions
            let x1 = Double.random(in: -0.2...0.6)
            let y1 = Double.random(in: -0.2...0.6)
            let length = Double.random(in: 0.5...1.2)
            
            // Multiple angles for chaotic, unsettling pattern
            let baseAngles = [0.785, 0.4, 1.2, 0.0, 1.57]
            let angleIndex = i % baseAngles.count
            let angle = baseAngles[angleIndex] + Double.random(in: -0.2...0.2)
            
            let x2 = x1 + cos(angle) * length
            let y2 = y1 + sin(angle) * length
            
            let width = Double.random(in: 15...80)
            let opacity = Double.random(in: 0.1...0.3)  // Lower opacity for darker feel
            let grayValue = Double.random(in: 0.1...0.4) // Dark grays for the waves
            let colorHint = colorHints[i % colorHints.count].opacity(0.1)  // Subtle dark color hint
            
            waveData.append((
                start: UnitPoint(x: x1, y: y1),
                end: UnitPoint(x: x2, y: y2),
                width: width,
                opacity: opacity,
                grayValue: grayValue,
                colorHint: colorHint
            ))
        }
        return waveData
    }()
    
    var body: some View {
        Canvas { context, size in
            // Apply glow effect with blur
            var blurredContext = context
            blurredContext.addFilter(.blur(radius: 15))
            
            // Draw all waves in a single pass
            for wave in waves {
                let start = CGPoint(
                    x: wave.start.x * size.width,
                    y: wave.start.y * size.height
                )
                let end = CGPoint(
                    x: wave.end.x * size.width,
                    y: wave.end.y * size.height
                )
                
                // Create a path for the wave
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                
                // Set opacity for dark gray waves
                blurredContext.opacity = wave.opacity
                blurredContext.stroke(path, with: .color(Color(white: wave.grayValue)), lineWidth: wave.width)
                
                // Then add a second pass with the dark color hint
                var colorContext = blurredContext
                colorContext.opacity = wave.opacity * 0.2
                colorContext.stroke(path, with: .color(wave.colorHint), lineWidth: wave.width)
            }
        }
    }
}
