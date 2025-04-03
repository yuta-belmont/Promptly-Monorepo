import SwiftUI

struct AboutView: View {
    @Binding var isPresented: Bool
    @State private var dragOffset = CGSize.zero // Add drag offset for swipe gesture
    
    var body: some View {
        ZStack {
            // Semi-transparent backdrop for closing the view
            Color.black.opacity(0.01)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(true)
                .transition(.opacity)
                .zIndex(998)
                .onTapGesture {
                    isPresented = false
                }
            
            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("About")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Done") {
                        isPresented = false
                    }
                }
                .padding()
                .padding(.top, 8)
                
                // About content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Promptly")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Text("Version 1.0")
                            .foregroundColor(.gray)
                        
                        Text("Promptly is a simple and elegant task management app that helps you stay organized and focused.")
                            .foregroundColor(.white)
                        
                        Text("Features:")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(text: "Create and manage daily tasks")
                            FeatureRow(text: "Organize tasks into groups")
                            FeatureRow(text: "Set reminders for important tasks")
                            FeatureRow(text: "Import tasks from previous days")
                            FeatureRow(text: "Dark mode support")
                        }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.clear
                    .background(.ultraThinMaterial)
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
                        // Only allow dragging from the left edge (first 88 points) and only to the right
                        if value.startLocation.x < 88 && value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss
                        if value.startLocation.x < 44 && value.translation.width > 100 {
                            // Use animation to ensure smooth transition
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isPresented = false
                            }
                        }
                        // If not dragged far enough, animate back to original position
                        withAnimation(.easeOut(duration: 0.2)) {
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
