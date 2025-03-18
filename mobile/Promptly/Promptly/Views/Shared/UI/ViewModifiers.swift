import SwiftUI

// MARK: - View Extensions

extension View {
    /// Applies rounded corners to specific corners of a view
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    /// Applies the standard material background with gradient overlay used in headers
    func headerBackground() -> some View {
        background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.5)
                .overlay(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
    }
} 
