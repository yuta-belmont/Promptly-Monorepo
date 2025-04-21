import Foundation
import CoreData

final class CheckInService {
    // MARK: - Singleton
    static let shared = CheckInService()
    
    // MARK: - Dependencies
    private let persistence = PersistenceController.shared
    private let chatService = ChatService.shared
    private let analytics = CheckInAnalytics.shared
    private let checklistPersistence = ChecklistPersistence.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Gets the checklist for a specific date
    /// - Parameter date: The date to get the checklist for
    /// - Returns: The checklist for the specified date
    @MainActor func getChecklist(for date: Date) -> Models.Checklist {
        return checklistPersistence.loadChecklist(for: date) ?? Models.Checklist(date: date)
    }
    
    /// Converts a checklist to a dictionary format for check-in
    /// - Parameter checklist: The checklist to convert
    /// - Returns: A dictionary representation of the checklist matching server format
    func getChecklistDictionaryForCheckin(_ checklist: Models.Checklist) -> [String: Any] {
        // Create the checklist dictionary with fields at top level
        let checklistDict: [String: Any] = [
            "date": formatDateToYYYYMMDD(checklist.date),
            "notes": checklist.notes,
            "items": checklist.items.map { item in
                var itemDict: [String: Any] = [
                    "title": item.title,
                    "is_completed": item.isCompleted,
                    "group_name": item.group?.title ?? "Uncategorized"
                ]
                
                // Add notification if exists
                if let notification = item.notification {
                    itemDict["notification"] = notification.ISO8601Format()
                }
                
                // Add subitems if they exist
                itemDict["subitems"] = item.subItems.map { subItem in
                    [
                        "title": subItem.title,
                        "is_completed": subItem.isCompleted
                    ] as [String: Any]
                }
                
                return itemDict
            }
        ]
        return checklistDict
    }
    
    /// Formats a date to YYYY-MM-DD string
    /// - Parameter date: The date to format
    /// - Returns: A string in YYYY-MM-DD format
    private func formatDateToYYYYMMDD(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    /// Creates a report for the checklist without server interaction
    /// - Parameters:
    ///   - date: The date of the check-in
    ///   - checklist: The checklist to create a report for
    /// - Returns: The created report
    @MainActor func createReport(for date: Date, checklist: Models.Checklist) -> Report {
        // Count total and completed items
        let totalItems = checklist.items.count
        let completedItems = checklist.items.filter { $0.isCompleted }.count
        let completionPercentage = totalItems > 0 ? Int((Double(completedItems) / Double(totalItems)) * 100) : 0
        
        // Generate summary text
        let summaryText: String
        if totalItems == 0 {
            summaryText = "No items in checklist."
        } else if completedItems == totalItems {
            summaryText = "All items completed."
        } else {
            summaryText = "\(completedItems)/\(totalItems) items completed (\(completionPercentage)%)."
        }
        
        // Create report
        let report = Report(context: persistence.container.viewContext)
        report.id = UUID()
        report.date = date
        report.summary = summaryText
        
        // Create snapshot items for completed items and their subitems
        var snapshotItems: [SnapshotItem] = []
        
        for item in checklist.items {
            // Only include items that are completed or have completed subitems
            if item.isCompleted || item.subItems.contains(where: { $0.isCompleted }) {
                let snapshotItem = SnapshotItem(context: persistence.container.viewContext)
                snapshotItem.id = UUID()
                snapshotItem.title = item.title
                snapshotItem.isCompleted = item.isCompleted
                
                // Create snapshot subitems for completed subitems
                for subItem in item.subItems where subItem.isCompleted {
                    let snapshotSubitem = SnapshotSubItem(context: persistence.container.viewContext)
                    snapshotSubitem.id = UUID()
                    snapshotSubitem.title = subItem.title
                    
                    // Add to snapshot item's subitems
                    snapshotItem.addToSubitems(snapshotSubitem)
                }
                
                snapshotItems.append(snapshotItem)
            }
        }
        
        // Add all snapshot items to the report
        report.addToSnapshotItems(NSSet(array: snapshotItems))
        
        // Save to Core Data
        do {
            try persistence.container.viewContext.save()
        } catch {
            print("Error saving report: \(error)")
        }
        
        return report
    }
    
    /// Performs server check-in and updates the report with server response
    /// - Parameters:
    ///   - checklist: The checklist to check in
    ///   - report: The report to update with server response
    @MainActor func performServerCheckIn(checklist: Models.Checklist, report: Report) async {
        // Calculate and display analytics first
        let stats = analytics.calculateStats()
        
        do {
            // Get the checklist dictionary using our local method
            let dictChecklist = getChecklistDictionaryForCheckin(checklist)
            
            print("📤 DEBUG - Dictionary being sent to ChatService.handleCheckin:")
            if let jsonData = try? JSONSerialization.data(withJSONObject: dictChecklist, options: .prettyPrinted),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                print(jsonStr)
            }
            
            // Try to send the check-in to the server and get the response
            let (summary, analysis, response) = try await chatService.handleCheckin(checklist: dictChecklist)
            
            // Update the report with the server response
            report.summary = summary
            report.analysis = analysis
            report.response = response
            
            // Save the updated report
            try persistence.container.viewContext.save()
            
            // Send the response to the chat
            ChatViewModel.shared.handleMessage(response)
            
            print("✅ Server check-in successful")
        } catch {
            // Fall back to offline processing
            print("🔄 Falling back to offline check-in")
            report.analysis = stats.formattedString
            
            do {
                try persistence.container.viewContext.save()
            } catch {
                print("Error saving report after offline fallback: \(error)")
            }
            
            ChatViewModel.shared.handleMessage("I generated a report for you.")
        }
    }

    /// Performs a check-in for the specified date and checklist
    /// - Parameters:
    ///   - date: The date of the check-in
    ///   - checklist: The checklist to check in
    @MainActor func performCheckIn(for date: Date, checklist: Models.Checklist) async {
        // Always create the report
        let report = createReport(for: date, checklist: checklist)
        
        // Only do server check-in if chat is enabled
        if UserSettings.shared.isChatEnabled {
            await performServerCheckIn(checklist: checklist, report: report)
        } else {
            
            let stats = analytics.calculateStats()
            report.analysis = stats.formattedString
            
            do {
                try persistence.container.viewContext.save()
            } catch {
                print("Error saving report after offline fallback: \(error)")
            }
            // For non-chat users, just show the basic completion message
            ChatViewModel.shared.handleMessage("I generated a report for you.")
        }
    }
} 
