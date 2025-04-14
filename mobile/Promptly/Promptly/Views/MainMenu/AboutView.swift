import SwiftUI

struct AboutView: View {
    @Binding var isPresented: Bool
    @State private var dragOffset = CGSize.zero // Add drag offset for swipe gesture
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("About")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // About content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Alfred")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Text("Version 1.0")
                            .foregroundColor(.gray)
                        
                        Text("Get to know Alfred.")
                            .foregroundColor(.white)
                        
                        Text("Features:")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(text: "Create and manage daily tasks")
                            FeatureRow(text: "Organize")
                            FeatureRow(text: "Set reminders")
                            FeatureRow(text: "Track and analyze progress")
                        }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.clear
                    .background(Color.black.opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
            .offset(x: dragOffset.width)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging to the right
                        if value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss
                        if value.translation.width > 50 {
                            // Use animation to ensure smooth transition
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                        // If not dragged far enough, animate back to original position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
            )
            .transition(.move(edge: .trailing))
            .zIndex(999)
        }
    }
}

struct FeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(text)
                .foregroundColor(.white)
        }
    }
}
