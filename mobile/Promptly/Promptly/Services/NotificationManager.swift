import Foundation
import UserNotifications
import UIKit

class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationCategoryIdentifier = "CHECKLIST_ITEM"
    private let checkInCategoryIdentifier = "CHECK_IN" // New category for check-ins
    
    private override init() {
        super.init()
        setupNotificationCategories()
        notificationCenter.delegate = self
    }
    
    // MARK: - Permission Handling
    
    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func checkNotificationPermission(completion: @escaping (Bool) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            let isAuthorized = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                completion(isAuthorized)
            }
        }
    }
    
    // MARK: - Notification Setup
    
    func setupNotificationCategories() {
        // Create a "Complete" action for notifications
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_ACTION",
            title: "Mark as Complete",
            options: .foreground
        )
        
        // Create a category with the complete action
        let checklistCategory = UNNotificationCategory(
            identifier: notificationCategoryIdentifier,
            actions: [completeAction],
            intentIdentifiers: [],
            options: []
        )
        
        // New check-in category setup
        let checkInAction = UNNotificationAction(
            identifier: "CHECK_IN_ACTION",
            title: "Check In",
            options: .foreground
        )
        
        let checkInCategory = UNNotificationCategory(
            identifier: checkInCategoryIdentifier,
            actions: [checkInAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register both categories
        notificationCenter.setNotificationCategories([checklistCategory, checkInCategory])
    }
    
    // MARK: - Notification Scheduling
    
    func updateNotificationForEditedItem(_ item: Models.ChecklistItem, in checklist: Models.Checklist) {
        // First remove any existing notifications for this item
        removeAllNotificationsForItem(item)
        
        // Then schedule a new notification if needed
        if !item.isCompleted, let notification = item.notification, notification > Date() {
            scheduleNotification(for: item, in: checklist)
        }
    }
    
    func scheduleNotification(for item: Models.ChecklistItem, in checklist: Models.Checklist) {
        guard let notificationDate = item.notification else {
            return
        }
        
        // Don't schedule notifications for past dates or completed items
        if notificationDate < Date() || item.isCompleted {
            return
        }
        
        // Use the item's ID directly as the notification identifier
        let identifier = item.id.uuidString
        
        // Create the notification content
        let content = UNMutableNotificationContent()
        content.title = "Alfred: \(item.title)"
        
        // Format the current time for the notification body
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let currentTimeString = timeFormatter.string(from: notificationDate)
        content.body = currentTimeString
        
        content.sound = .default
        content.categoryIdentifier = notificationCategoryIdentifier
        
        // Add the item ID and checklist date as user info
        content.userInfo = [
            "itemID": item.id.uuidString,
            "checklistDate": checklist.date.timeIntervalSince1970,
            "itemTitle": item.title
        ]
        
        // Create a calendar-based trigger that respects time zones
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notificationDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule the notification
        notificationCenter.add(request) { error in }
    }
    
    func removeNotification(withIdentifier identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    
    func removeAllNotificationsForItem(_ item: Models.ChecklistItem) {
        // Remove notification using the item's ID as identifier
        removeNotification(withIdentifier: item.id.uuidString)
    }
    
    // MARK: - Batch Operations
    
    func processNotificationsForDateRange(from startDate: Date, to endDate: Date) {
        // This would be called with the ChecklistPersistence to get all checklists in the date range
        // For each checklist, process all items with notifications
    }
    
    func processNotificationsForDateRange(startDate: Date, days: Int) {
        guard let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate) else {
            return
        }
        processNotificationsForDateRange(from: startDate, to: endDate)
    }
    
    func processNotificationsForChecklist(_ checklist: Models.Checklist) -> Models.Checklist {
        var updatedChecklist = checklist
        
        for (index, item) in checklist.items.enumerated() {
            if let notification = item.notification {
                // Remove existing notification
                removeAllNotificationsForItem(item)
                
                // Schedule new notification if needed
                if notification > Date() && !item.isCompleted {
                    scheduleNotification(for: item, in: checklist)
                }
            } else {
                // No notification date, so remove any existing notification
                removeAllNotificationsForItem(item)
            }
        }
        
        return updatedChecklist
    }
    
    func rescheduleAllNotifications(for checklists: [Models.Checklist]) -> [Models.Checklist] {
        // First, remove all pending notifications
        notificationCenter.removeAllPendingNotificationRequests()
        
        // Then reschedule notifications for all items in all checklists
        return checklists.map { processNotificationsForChecklist($0) }
    }
    
    // MARK: - Background Processing
    
    func setupBackgroundFetch() {
        // Configure the app for background fetch
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    }
    
    func performBackgroundFetch(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        // Get the current date
        let today = Date()
        
        // Look ahead 7 days
        guard let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today) else {
            completion(.failed)
            return
        }
        
        // Process notifications for the next 7 days
        processNotificationsForDateRange(from: today, to: nextWeek)
        
        completion(.newData)
    }
    
    // MARK: - Check-in Notifications
    
    func scheduleCheckInNotifications() {
        // First remove any existing check-in notifications
        removeAllCheckInNotifications()
        
        // Get user settings
        let userSettings = UserSettings.shared
        
        // Only schedule if notifications are enabled
        guard userSettings.isCheckInNotificationEnabled else { return }
        
        // Get the check-in time
        let checkInTime = userSettings.checkInTime
        
        // Schedule for next 7 days
        for dayOffset in 0..<7 {
            guard let notificationDate = Calendar.current.date(
                byAdding: .day,
                value: dayOffset,
                to: checkInTime
            ) else { continue }
            
            scheduleCheckInNotification(for: notificationDate)
        }
    }
    
    private func scheduleCheckInNotification(for date: Date) {
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Check In"
        content.sound = .default
        content.categoryIdentifier = checkInCategoryIdentifier
        
        // Create date components for the trigger
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        
        // Create the trigger
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // Create the request with a unique identifier
        let identifier = "check-in-\(date.timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule the notification
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling check-in notification: \(error)")
            }
        }
    }
    
    func removeAllCheckInNotifications() {
        // Get all pending notifications
        notificationCenter.getPendingNotificationRequests { requests in
            // Filter for check-in notifications
            let checkInIdentifiers = requests
                .filter { $0.identifier.hasPrefix("check-in-") }
                .map { $0.identifier }
            
            // Remove them
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: checkInIdentifiers)
        }
    }
    
    // MARK: - Settings Change Handlers
    
    func handleCheckInTimeChange() {
        // Reschedule all check-in notifications with new time
        scheduleCheckInNotifications()
    }
    
    func handleNotificationToggleChange() {
        let userSettings = UserSettings.shared
        
        if userSettings.isCheckInNotificationEnabled {
            // Schedule new notifications
            scheduleCheckInNotifications()
        } else {
            // Remove all notifications
            removeAllCheckInNotifications()
        }
    }
    
    // MARK: - Notification Handling
    
    func handleNotificationResponse(_ response: UNNotificationResponse, completion: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle check-in notification response
        if response.notification.request.content.categoryIdentifier == checkInCategoryIdentifier {
            if response.actionIdentifier == "CHECK_IN_ACTION" {
                // Handle check-in action
                // This would need to be implemented based on your app's navigation
            }
            completion()
            return
        }
        
        // Handle existing checklist item responses
        guard let itemIDString = userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: itemIDString),
              let checklistTimestamp = userInfo["checklistDate"] as? TimeInterval else {
            completion()
            return
        }
        
        let checklistDate = Date(timeIntervalSince1970: checklistTimestamp)
        
        if response.actionIdentifier == "COMPLETE_ACTION" {
            // Mark the item as complete
            // This would need to be implemented with the ChecklistPersistence
            // ChecklistPersistence.shared.markItemAsComplete(itemID: itemID, checklistDate: checklistDate)
        }
        
        completion()
    }
    
    // Helper method to get the current title of an item from its checklist
    @MainActor
    func getItemTitle(itemID: UUID, checklistDate: Date) -> String? {
        let persistence = ChecklistPersistence.shared
        guard let checklist = persistence.loadChecklist(for: checklistDate),
              let item = checklist.items.first(where: { $0.id == itemID }) else {
            return nil
        }
        return item.title
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                              willPresent notification: UNNotification, 
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                              didReceive response: UNNotificationResponse, 
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        handleNotificationResponse(response, completion: completionHandler)
    }
} 
