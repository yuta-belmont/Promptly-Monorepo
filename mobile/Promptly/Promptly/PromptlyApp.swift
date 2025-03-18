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
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
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
        notificationManager.requestNotificationPermission { granted in }
        
        // Set up background fetch
        notificationManager.setupBackgroundFetch()
        
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
    @State private var showingDayView = false
    @State private var selectedDate = Date()
    @State private var navigationPath = NavigationPath()
    @State private var showLoadingScreen = false // Set to true to enable loading screen
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var authManager = AuthManager.shared
    
    var body: some View {
        ZStack {
            if authManager.isAuthenticated {
                // Show the main app UI when authenticated
                NavigationStack(path: $navigationPath) {
                    ZStack {
                        // Use the current theme from ThemeManager
                        themeManager.currentTheme.backgroundView()
                            .ignoresSafeArea()
                        
                        // Content ZStack
                        ZStack {
                            // Calendar view
                            if !showingDayView {
                                CalendarView(autoNavigateToToday: false, todayID: animation, onDateSelected: { date in
                                    selectedDate = date
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                        showingDayView = true
                                    }
                                })
                                .transition(.opacity)
                                .zIndex(1)
                            }
                            
                            // BaseView instead of DayView
                            if showingDayView {
                                BaseView(date: selectedDate, onBack: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingDayView = false
                                    }
                                })
                                .transition(.opacity)
                                .zIndex(2)
                            }
                        }
                    }
                    .navigationDestination(for: DayView.self) { dayView in
                        BaseView(date: dayView.date)
                    }
                    .onAppear {
                        // Process notifications for the next 7 days
                        let notificationManager = NotificationManager.shared
                        _ = ChecklistPersistence.shared
                        
                        // Get today's date
                        let today = Date()
                        
                        // Process notifications for the next 7 days
                        notificationManager.processNotificationsForDateRange(startDate: today, days: 7)
                        
                        // Show day view after a 0.4 second delay for a more polished transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                showingDayView = true
                            }
                        }
                        
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
    
    // Set up notification observer to handle navigation from notifications
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NavigateToDayView"),
            object: nil,
            queue: .main
        ) { notification in
            if let date = notification.userInfo?["date"] as? Date {
                // Update the selected date
                selectedDate = date
                
                // Ensure we're showing the day view
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showingDayView = true
                }
            }
        }
    }
}
