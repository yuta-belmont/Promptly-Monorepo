import SwiftUI

struct LoadingView: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.7
    
    var body: some View {
        ZStack {
            // Solid black background
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            // Simple pulsating "Alfred" text
            Text("Alfred")
                .font(.system(size: 42, weight: .semibold, design: .default)) // Standard Apple font (SF Pro)
                .foregroundColor(.white)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    // Start pulsating animation
                    withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        scale = 1.1
                        opacity = 1.0
                    }
                }
        }
        .transition(.opacity)
    }
}
