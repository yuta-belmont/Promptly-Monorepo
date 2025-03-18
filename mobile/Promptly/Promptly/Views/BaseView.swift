import SwiftUI

struct BaseView: View {
    @StateObject private var focusManager = FocusManager.shared
    @State private var showingMenu = false
    @State private var isMenuClosing = false
    @StateObject private var themeManager = ThemeManager.shared
    // Chat-related states
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var isChatExpanded = false
    @State private var isKeyboardActive = false
    
    // Global sheet states
    @State private var showingGeneralSheet = false
    @State private var showingManageGroups = false
    @State private var showingAboutSheet = false
    @StateObject private var authManager = AuthManager.shared
    
    let date: Date
    var onBack: (() -> Void)?
    
    init(date: Date = Date(), onBack: (() -> Void)? = nil) {
        self.date = date
        self.onBack = onBack
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Main content area
            DayView(date: date, showMenu: $showingMenu, onBack: onBack)
                .environmentObject(focusManager)
                .zIndex(0)
            
            // Chat overlay
            VStack {
                Spacer()
                
                HStack {
                    // When chat is expanded, use the full width
                    if isChatExpanded {
                        ChatView(
                            viewModel: chatViewModel,
                            isKeyboardActive: $isKeyboardActive,
                            isExpanded: $isChatExpanded
                        )
                        .environmentObject(focusManager)
                        .frame(maxWidth: .infinity)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    } else if !focusManager.isEasyListFocused && authManager.isAuthenticated && !authManager.isGuestUser {
                        // Only show chat button when:
                        // 1. EasyListView is not focused
                        // 2. User is authenticated
                        // 3. User is NOT a guest user
                        Spacer()
                        
                        Button(action: {
                            // Remove all focus when opening the chat
                            focusManager.removeAllFocus()
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isChatExpanded.toggle()
                            }
                        }) {
                            ZStack {
                                // Bubble background
                                Circle()
                                    .fill(Color.blue)
                                    .opacity(0.8)
                                    .frame(width: 56, height: 56)
                                    .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                                
                                // Chat icon
                                Image(systemName: "message.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                
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
                        .padding(.bottom, 30) // Increased bottom padding to move the bubble up
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity) // Ensure HStack uses full width
            }
            .frame(maxWidth: .infinity) // Ensure VStack uses full width
            .zIndex(1)
            .animation(.easeInOut(duration: 0.2), value: focusManager.isEasyListFocused) // Animate based on focus state
            
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
            
            // Overlays
            if showingManageGroups {
                ManageGroupsView(isPresented: $showingManageGroups)
                    .transition(.opacity)
                    .zIndex(3)
            }
            
            if showingGeneralSheet {
                GeneralSettingsView(isPresented: $showingGeneralSheet)
                    .transition(.opacity)
                    .zIndex(3)
            }
            
            if showingAboutSheet {
                AboutView(isPresented: $showingAboutSheet)
                    .transition(.opacity)
                    .zIndex(3)
            }
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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingMenu)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingManageGroups)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingGeneralSheet)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingAboutSheet)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isChatExpanded)
        // Listen for theme changes to update the UI
        .onChange(of: themeManager.currentTheme) { oldValue, newValue in
            // This will trigger a redraw when the theme changes
        }
        // Listen for notification to show ManageGroupsView
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowManageGroupsView"))) { _ in
            withAnimation {
                showingManageGroups = true
            }
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
        
        switch action {
        case .general:
            withAnimation {
                showingMenu = false
                showingGeneralSheet = true
            }
        case .manageGroups:
            withAnimation {
                showingMenu = false  // Close the menu first
                showingManageGroups = true  // Then show manage groups
            }
        case .about:
            withAnimation {
                showingMenu = false
                showingAboutSheet = true
            }
        }
    }
    
    private func handleLogout() {
        // AuthManager will handle the actual logout
        // No need to do anything here as RootView will automatically show LoginView
        // when authManager.isAuthenticated changes to false
    }
}
