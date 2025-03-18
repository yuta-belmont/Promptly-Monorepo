import SwiftUI

struct AboutView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.75)
                .ignoresSafeArea()
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
            .padding()
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
