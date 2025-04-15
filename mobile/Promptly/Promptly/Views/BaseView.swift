import SwiftUI
import UIKit

// Make sure NavigationUtil and DayView are accessible - sometimes these are in separate files
// so we import them directly. If they are already accessible, the compiler will ignore redundant imports.

struct BaseView: View {
    @StateObject private var focusManager = FocusManager.shared
    @State private var showingMenu = false
    @State private var isMenuClosing = false
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var userSettings = UserSettings.shared
    // Chat-related states
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var isChatExpanded = false
    @State private var isKeyboardActive = false
    @State private var isEditing: Bool = false
    
    @StateObject private var authManager = AuthManager.shared
    
    let date: Date
    var onBack: (() -> Void)?
    var onMenuAction: ((MenuAction) -> Void)?
    
    // Date formatter for consistent logging
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    init(date: Date = Date(), onBack: (() -> Void)? = nil, onMenuAction: ((MenuAction) -> Void)? = nil) {
        self.date = date
        self.onBack = onBack
        self.onMenuAction = onMenuAction
    }
    
    var body: some View {
        
        ZStack(alignment: .trailing) {
            // Main content area
            DayView(date: date, showMenu: $showingMenu, onBack: onBack)
                .environmentObject(focusManager)
                .zIndex(0)
                .onPreferenceChange(IsEditingPreferenceKey.self) { newValue in
                    isEditing = newValue
                    if newValue && isChatExpanded {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isChatExpanded = false
                        }
                    }
                }
            
            // Only show chat if no menu is showing, not editing, and chat is enabled
            if !showingMenu && !isEditing && userSettings.isChatEnabled {
                // Chat button
                if !focusManager.isEasyListFocused && authManager.isAuthenticated && !authManager.isGuestUser {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                // Remove all focus when opening the chat
                                focusManager.removeAllFocus()
                                isChatExpanded = true
                            }) {
                                ZStack {
                                    // Bubble background
                                    Circle()
                                        .fill(Color.blue)
                                        .opacity(0.9)
                                        .frame(width: 56, height: 56)
                                        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                                    
                                    // Chat icon
                                    Image("ChatGPT Image Apr 13, 2025, 03_40_55 PM")
                                        .frame(width: 56, height: 56)
                                        .padding(.top, 2)
                                        .padding(.leading, 1)
                                        .opacity(0.9)
                                    
                                    // Notification badge - positioned as an overlay
                                    if chatViewModel.unreadCount > 0 {
                                        ZStack {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 22, height: 22)
                                            
                                            Text("\(min(chatViewModel.unreadCount, 99))")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .frame(width: 22, height: 22)
                                        .offset(x: 22, y: -22) // Position at top-right of the chat icon
                                    }
                                }
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 30)
                        }
                    }
                }
            }
            
            // Menu overlay with background
            ZStack(alignment: .trailing) {
                // Background overlay
                if showingMenu {
                    Color.black
                        .opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingMenu = false
                            }
                        }
                        .transition(.opacity)
                }
                
                // Menu
                if showingMenu {
                    MainMenu(
                        isPresented: $showingMenu,
                        isClosing: $isMenuClosing,
                        onMenuAction: handleMenuAction,
                        onLogout: handleLogout
                    )
                    .transition(.move(edge: .trailing))
                    .zIndex(10)
                }
            }
            .zIndex(2)
        }
        .sheet(isPresented: $isChatExpanded) {
            ChatView(
                isKeyboardActive: $isKeyboardActive,
                isExpanded: $isChatExpanded
            )
            .environmentObject(focusManager)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: showingMenu) { oldValue, newValue in
            if newValue {
                focusManager.removeAllFocus()
            }
        }
        .onChange(of: date) { oldValue, newValue in
            // This handler is needed for day navigation to work properly
            // Even though we're not updating the chat view model anymore
            // The presence of this handler seems to trigger necessary side effects
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isChatExpanded)
        // Listen for theme changes to update the UI
        .onChange(of: themeManager.currentTheme) { oldValue, newValue in
            // This will trigger a redraw when the theme changes
        }
        // Close ChatView when EasyListView gains focus
        .onChange(of: focusManager.isEasyListFocused) { oldValue, newValue in
            if newValue && isChatExpanded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isChatExpanded = false
                }
            }
        }
    }
    
    private func handleMenuAction(_ action: MenuAction) {
        focusManager.removeAllFocus()  // Remove focus before showing any sheet
        
        if let onMenuAction = onMenuAction {
            onMenuAction(action)
        } else {
            // Fallback behavior if no callback provided
            switch action {
            case .general:
                NotificationCenter.default.post(name: NSNotification.Name("ShowGeneralSettingsView"), object: nil)
            case .manageGroups:
                NotificationCenter.default.post(name: NSNotification.Name("ShowManageGroupsView"), object: nil)
            case .about:
                NotificationCenter.default.post(name: NSNotification.Name("ShowAboutView"), object: nil)
            }
        }
        
        // Always close the menu
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
            showingMenu = false
        }
    }
    
    private func handleLogout() {
        // AuthManager will handle the actual logout
        // No need to do anything here as RootView will automatically show LoginView
        // when authManager.isAuthenticated changes to false
    }
}
