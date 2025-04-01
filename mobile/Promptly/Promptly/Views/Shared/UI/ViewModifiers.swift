import SwiftUI

// MARK: - View Extensions

extension View {
    /// Applies rounded corners to specific corners of a view
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    /// Applies the standard material background with gradient overlay used in headers
    func headerBackground() -> some View {
        background(Color.black.opacity(0.5))
    }
} 
