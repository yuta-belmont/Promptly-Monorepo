//
//  PromptlyApp.swift
//  Promptly
//
//  Created by Yuta Belmont on 2/26/25.
//

import SwiftUI
import Foundation
import BackgroundTasks
import UserNotifications
import CoreData
import Firebase


// Import Views
import SwiftUI

// Import the LoginView
@main
struct PromptlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Initialize the persistence controller
    let persistenceController = PersistenceController.shared
    
    // Add shared ChatViewModel
    @StateObject private var chatViewModel = ChatViewModel.shared
    
    var body: some Scene {
        
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(chatViewModel) // Provide chatViewModel to all views
                .dynamicTypeSize(.small...DynamicTypeSize.xLarge)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize Firebase
        FirebaseApp.configure()
        
        // Initialize Core Data
        _ = PersistenceController.shared
        
        // Initialize notification manager
        let notificationManager = NotificationManager.shared
        
        // Request notification permissions
        notificationManager.requestNotificationPermission { granted in
            if granted {
                // Schedule check-in notifications if enabled
                let userSettings = UserSettings.shared
                if userSettings.isCheckInNotificationEnabled {
                    notificationManager.scheduleCheckInNotifications()
                }
            }
        }
        
        // Set up background fetch
        notificationManager.setupBackgroundFetch()
        
        // Clean up old chat messages (over 48 hours)
        ChatPersistenceService.shared.deleteMessagesOlderThan48Hours()
        
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Handle device token if needed for remote notifications
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Handle remote notification registration failure silently
    }
    
    // Handle notification responses
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Extract the checklist date from the notification
        let userInfo = response.notification.request.content.userInfo
        if let checklistTimestamp = userInfo["checklistDate"] as? TimeInterval {
            let checklistDate = Date(timeIntervalSince1970: checklistTimestamp)
            
            // Navigate to the correct day view
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("NavigateToDayView"),
                    object: nil,
                    userInfo: ["date": checklistDate]
                )
            }
        }
        
        // Let the NotificationManager handle the rest
        NotificationManager.shared.handleNotificationResponse(response) {
            completionHandler()
        }
    }
    
    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show the notification even when the app is in the foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle background fetch
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        NotificationManager.shared.performBackgroundFetch { result in
            completionHandler(result)
        }
    }
}

struct RootView: View {
    @Namespace private var animation
    @State private var viewState: ViewState = .dayView(date: Date())
    @State private var navigationPath = NavigationPath()
    @State private var showLoadingScreen = false // Set to true to enable loading screen
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var authManager = AuthManager.shared
    
    // Define view states
    enum ViewState: Equatable {
        case calendar
        case dayView(date: Date)
        case manageGroups
        case generalSettings
        case about
        case reports
        
        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.calendar, .calendar):
                return true
            case (.manageGroups, .manageGroups):
                return true
            case (.generalSettings, .generalSettings):
                return true
            case (.about, .about):
                return true
            case (.dayView(let date1), .dayView(let date2)):
                return Calendar.current.isDate(date1, inSameDayAs: date2)
            case (.reports, .reports):
                return true
            default:
                return false
            }
        }
    }
    
    // Helper to extract the current date
    private var currentDate: Date {
        if case .dayView(let date) = viewState {
            return date
        }
        return Date() // Fallback
    }
    
    // Date formatter for logging
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        ZStack {
            if authManager.isAuthenticated {
                // Show the main app UI when authenticated
                NavigationStack(path: $navigationPath) {
                    ZStack {
                        // Use the current theme from ThemeManager
                        themeManager.currentTheme.backgroundView()
                            .ignoresSafeArea()
                        
                        // Main content based on current view state
                        switch viewState {
                        case .calendar:
                            CalendarView(
                                autoNavigateToToday: false, 
                                todayID: animation,
                                onDateSelected: { date in
                                    print("[RootView] Calendar selected date: \(dateFormatter.string(from: date))")
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        viewState = .dayView(date: date)
                                    }
                                }
                            )
                            .zIndex(1)
                            
                        case .dayView(let date):
                            BaseView(
                                date: date,
                                onBack: {
                                    print("[RootView] DayView back button pressed")
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        viewState = .calendar
                                    }
                                },
                                onMenuAction: handleMenuAction
                            )
                            .zIndex(2)
                            
                        case .manageGroups:
                            ManageGroupsView(
                                isPresented: Binding(
                                    get: { viewState == .manageGroups },
                                    set: { if !$0 { 
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            viewState = .dayView(date: currentDate)
                                        }
                                    }}
                                ),
                                onNavigateToDate: { date in
                                    print("[RootView] ManageGroups navigating to date: \(dateFormatter.string(from: date))")
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        viewState = .dayView(date: date)
                                    }
                                }
                            )
                            .transition(.move(edge: .trailing))
                            .zIndex(3)
                            
                        case .generalSettings:
                            GeneralSettingsView(
                                isPresented: Binding(
                                    get: { viewState == .generalSettings },
                                    set: { if !$0 { 
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            viewState = .dayView(date: currentDate)
                                        }
                                    }}
                                )
                            )
                            .transition(.move(edge: .trailing))
                            .zIndex(3)
                            
                        case .about:
                            AboutView(
                                isPresented: Binding(
                                    get: { viewState == .about },
                                    set: { if !$0 { 
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            viewState = .dayView(date: currentDate)
                                        }
                                    }}
                                )
                            )
                            .transition(.move(edge: .trailing))
                            .zIndex(3)
                            
                        case .reports:
                            ReportsView(
                                isPresented: Binding(
                                    get: { viewState == .reports },
                                    set: { if !$0 { 
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            viewState = .dayView(date: currentDate)
                                        }
                                    }}
                                )
                            )
                            .transition(.move(edge: .trailing))
                            .zIndex(3)
                        }
                    }
                    .navigationDestination(for: DayView.self) { dayView in
                        // Create a simple DayViewDestination that will update the viewState
                        DayViewDestination(date: dayView.date) { date in
                            viewState = .dayView(date: date)
                        }
                    }
                    .onAppear {
                        // Setup code...
                        let notificationManager = NotificationManager.shared
                        _ = ChecklistPersistence.shared
                        
                        // Get today's date
                        let today = Date()
                        
                        // Process notifications for the next 7 days
                        notificationManager.processNotificationsForDateRange(startDate: today, days: 7)
                        
                        // If loading screen is enabled, show it briefly then fade out
                        if showLoadingScreen {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    showLoadingScreen = false
                                }
                            }
                        }
                        
                        // Set up notification observer
                        setupNotificationObserver()
                    }
                }
                .preferredColorScheme(.dark)
            } else {
                // Show the login view when not authenticated
                LoginView()
                    .transition(.opacity)
            }
            
            // Full-screen loading overlay that will cover everything
            if showLoadingScreen {
                LoadingView()
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
        // Listen for theme changes to update the UI
        .onChange(of: themeManager.currentTheme) { oldValue, newValue in
            // This will trigger a redraw when the theme changes
        }
    }
    
    private func handleMenuAction(_ action: MenuAction) {
        print("[RootView] Handling menu action: \(action)")
        switch action {
        case .general:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewState = .generalSettings
            }
        case .manageGroups:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewState = .manageGroups
            }
        case .reports:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewState = .reports
            }
        case .about:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewState = .about
            }
        }
    }
    
    // Set up notification observer to handle navigation from notifications
    private func setupNotificationObserver() {
        // Listen for NavigateToDayView notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NavigateToDayView"),
            object: nil,
            queue: .main
        ) { notification in
            if let date = notification.userInfo?["date"] as? Date {
                print("[RootView] Received NavigateToDayView notification with date: \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))")
                
                // Update the view state to show day view with the correct date
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewState = .dayView(date: date)
                }
            }
        }
        
        // Also listen for ShowManageGroupsView notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ShowManageGroupsView"),
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewState = .manageGroups
            }
        }
        
        // Listen for ShowGeneralSettingsView notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ShowGeneralSettingsView"),
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewState = .generalSettings
            }
        }
        
        // Listen for ShowAboutView notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ShowAboutView"),
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewState = .about
            }
        }
        
        // Listen for ShowReportsView notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ShowReportsView"),
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewState = .reports
            }
        }
    }
}

// Helper view for navigation destination
struct DayViewDestination: View {
    let date: Date
    let onAppear: (Date) -> Void
    
    var body: some View {
        Color.clear
            .onAppear {
                print("[DayViewDestination] Appearing with date: \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))")
                
                // Use DispatchQueue to avoid any potential view update conflicts
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onAppear(date)
                    }
                }
            }
    }
}
