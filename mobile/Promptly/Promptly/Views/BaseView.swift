import SwiftUI
import UIKit

// Make sure NavigationUtil and DayView are accessible - sometimes these are in separate files
// so we import them directly. If they are already accessible, the compiler will ignore redundant imports.

// Add preference key to track ItemDetailsView visibility
struct IsItemDetailsViewShowingPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

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
    // Add a state for the current detent selection
    @State private var chatDetent: PresentationDetent = .medium
    
    @StateObject private var authManager = AuthManager.shared
    
    // Add state to track which view is showing
    @State private var isItemDetailsViewShowing: Bool = false
    
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
                .onPreferenceChange(IsItemDetailsViewShowingPreferenceKey.self) { newValue in
                    isItemDetailsViewShowing = newValue
                }
            
            // Only show chat if no menu is showing, not editing, and chat is enabled
            if !showingMenu && !isEditing {
                // Chat button
                if !focusManager.isEasyListFocused && authManager.isAuthenticated && !authManager.isGuestUser {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            //plus button
                            Button(action: onPlusTapped) {
                                ZStack {
                                    // Bubble background
                                    Circle()
                                        .fill(Color.white)
                                        .opacity(0.03)
                                        .frame(width: 56, height: 56)
                                        .shadow(color: .black.opacity(0.2), radius: 5, x: -1, y: 1)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                                        )
                                    
                                    // Chat icon
                                    Image("PlusIcon")
                                        .frame(width: 56, height: 56)
                                        .opacity(0.9)
                                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: -1, y: 1)
                                    
                                }
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, userSettings.isChatEnabled ? 16 : 64)
                            
                            
                        }
                        if userSettings.isChatEnabled {
                            HStack {
                                Spacer()
                                //chat button
                                Button(action: {
                                    // Remove all focus when opening the chat
                                    focusManager.removeAllFocus()
                                    
                                    // Save EasyListView state before opening chat
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("SaveEasyListState"),
                                        object: nil
                                    )
                                    
                                    isChatExpanded = true
                                }) {
                                    ZStack {
                                        // Bubble background
                                        Circle()
                                            .fill(Color.blue)
                                            .opacity(0.9)
                                            .frame(width: 56, height: 56)
                                            .shadow(color: .black.opacity(0.2), radius: 5, x: -1, y: 1)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                                            )
                                        
                                        // Chat icon
                                        Image("ChatIcon")
                                            .frame(width: 56, height: 56)
                                            .padding(.top, 2)
                                            .padding(.leading, 1)
                                            .opacity(0.9)
                                            .shadow(color: Color.black.opacity(0.2), radius: 2, x: -1, y: 1)
                                        
                                        
                                        
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
            .presentationDetents([.medium, .large], selection: $chatDetent)
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
        // Reset chat detent to medium when chat is closed
        .onChange(of: isChatExpanded) { oldValue, newValue in
            if !newValue {
                // Reset to medium detent when chat is closed
                chatDetent = .medium
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
        // Expand chat to large detent when chat gets focus
        .onChange(of: focusManager.isChatFocused) { oldValue, newValue in
            if newValue {
                chatDetent = .large
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
            case .reports:
                NotificationCenter.default.post(name: NSNotification.Name("ShowReportsView"), object: nil)
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
    
    // Add function to handle plus button tap
    private func onPlusTapped() {
        
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
                    
        if isItemDetailsViewShowing {
            // Post notification to trigger ItemDetailsView's plus button functionality
            NotificationCenter.default.post(
                name: NSNotification.Name("TriggerItemDetailsPlusButton"),
                object: nil
            )
        } else {
            // Post notification to trigger EasyListView's plus button functionality
            NotificationCenter.default.post(
                name: NSNotification.Name("TriggerEasyListPlusButton"),
                object: nil
            )
        }
    }
}
