import SwiftUI

struct MainMenu: View {
    @Binding var isPresented: Bool
    @Binding var isClosing: Bool
    @State private var isAnimating = false
    @State private var menuOffset: CGFloat = 0
    @ObservedObject private var authManager = AuthManager.shared
    
    let onMenuAction: (MenuAction) -> Void
    let onLogout: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            // Menu content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Menu")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.title2)
                    }
                    .disabled(isAnimating)
                }
                .padding()
                .padding(.top, 44)
                
                // Menu items
                VStack(spacing: 0) {
                    MenuButton(title: "General", icon: "gearshape", isDisabled: isAnimating) {
                        withAnimation(.spring(response: 2, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                        onMenuAction(.general)
                    }
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    MenuButton(title: "Groups", icon: "folder", isDisabled: isAnimating) {
                        withAnimation(.spring(response: 2, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                        onMenuAction(.manageGroups)
                    }
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    MenuButton(title: "About", icon: "info.circle", isDisabled: isAnimating) {
                        withAnimation(.spring(response: 2, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                        onMenuAction(.about)
                    }
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    // Show Login or Logout button based on authentication status
                    if authManager.isAuthenticated {
                        // User is logged in, show Logout button with appropriate text
                        if authManager.isGuestUser {
                            // Guest user
                            MenuButton(title: "Sign In", icon: "person.fill", isDisabled: isAnimating) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isPresented = false
                                }
                                AuthManager.shared.logout()
                                onLogout()
                            }
                        } else {
                            // Regular user
                            MenuButton(title: "Logout", icon: "rectangle.portrait.and.arrow.right", isDestructive: true, isDisabled: isAnimating) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isPresented = false
                                }
                                AuthManager.shared.logout()
                                onLogout()
                            }
                        }
                    } else {
                        // User is not logged in, show Login button
                        MenuButton(title: "Login", icon: "person.fill", isDestructive: false, isDisabled: isAnimating) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                            onLogout() // Use the same callback to handle navigation
                        }
                    }
                }
                
                Spacer()
            }
            .frame(width: max(geometry.size.width / 3, 200))
            .background(
                ZStack {
                    Color.clear
                        .background(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                }
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .ignoresSafeArea()
    }
}

// Helper view for consistent menu buttons
private struct MenuButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundColor(isDestructive ? .red : .white)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding()
        }
        .disabled(isDisabled)
    }
}
