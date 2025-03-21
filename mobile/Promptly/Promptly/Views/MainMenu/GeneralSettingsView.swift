import SwiftUI

struct GeneralSettingsView: View {
    @Binding var isPresented: Bool
    @StateObject private var themeManager = ThemeManager.shared
    
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
                    Text("General")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Done") {
                        isPresented = false
                    }
                }
                .padding()
                .padding(.top, 8)
                
                // Settings content
                VStack(alignment: .leading, spacing: 16) {
                    // Theme selection label
                    HStack {
                        Text("Theme")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text(themeManager.currentTheme.rawValue)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    
                    // Horizontal theme scroll view
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(AppTheme.allCases) { theme in
                                ThemePreviewButton(
                                    theme: theme,
                                    isSelected: themeManager.currentTheme == theme,
                                    action: {
                                        themeManager.currentTheme = theme
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical)
                
                Spacer()
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

// Theme preview button component
struct ThemePreviewButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                // Theme thumbnail
                theme.thumbnailView()
                    .frame(width: 80, height: 80)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                // Theme name
                Text(theme.rawValue)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.top, 4)
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            .frame(width: 90)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
