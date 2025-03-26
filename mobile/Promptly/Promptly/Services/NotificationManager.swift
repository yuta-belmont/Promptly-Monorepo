import Foundation
import UserNotifications
import UIKit

class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationCategoryIdentifier = "CHECKLIST_ITEM"
    
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
        let category = UNNotificationCategory(
            identifier: notificationCategoryIdentifier,
            actions: [completeAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register the category
        notificationCenter.setNotificationCategories([category])
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
        content.title = "\(item.title)"
        
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
        let updatedChecklist = checklist
        
        for (_, item) in checklist.items.enumerated() {
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
    
    // MARK: - Notification Handling
    
    func handleNotificationResponse(_ response: UNNotificationResponse, completion: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Extract the item ID and checklist date from the notification
        guard let itemIDString = userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: itemIDString),
              let checklistTimestamp = userInfo["checklistDate"] as? TimeInterval else {
            completion()
            return
        }
        
        _ = Date(timeIntervalSince1970: checklistTimestamp)
        
        // Handle the "Complete" action
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
