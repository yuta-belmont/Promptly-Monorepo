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
    /// - Returns: A dictionary representation of the checklist
    func getChecklistDictionaryForCheckin(_ checklist: Models.Checklist) -> [String: Any] {
        return [
            "date": checklist.date.ISO8601Format(),
            "items": checklist.items.map { item in
                var itemDict: [String: Any] = [
                    "title": item.title,
                    "isCompleted": item.isCompleted,
                    "group": item.group?.title ?? "Uncategorized"
                ]
                
                // Add notification if exists
                if let notification = item.notification {
                    itemDict["notification"] = notification.ISO8601Format()
                }
                
                // Add subitems if they exist
                itemDict["subitems"] = item.subItems.map { subItem in
                    [
                        "title": subItem.title,
                        "isCompleted": subItem.isCompleted
                    ]
                }
                
                return itemDict
            }
        ]
    }
    
    /// Performs a check-in for the specified date and checklist
    /// - Parameters:
    ///   - date: The date of the check-in
    ///   - checklist: The checklist to check in
    @MainActor func performCheckIn(for date: Date, checklist: Models.Checklist) async {
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
        
        // Calculate and display analytics first
        let stats = analytics.calculateStats()
        ChatViewModel.shared.handleMessage(stats.formattedString)
        
        // Try server check-in first
        do {
            // Get the checklist dictionary using our local method
            let dictChecklist = getChecklistDictionaryForCheckin(checklist)
            
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
            
            // If we get here, server check-in was successful
            print("✅ Server check-in successful")
        } catch {
            print("❌ Check-in failed with error: \(error)")
            print("❌ Error type: \(type(of: error))")
            if let urlError = error as? URLError {
                print("❌ URLError code: \(urlError.code)")
                print("❌ URLError localizedDescription: \(urlError.localizedDescription)")
            }
            
            // Fall back to offline processing
            print("🔄 Falling back to offline check-in")
            await ChatViewModel.shared.handleOfflineCheckIn(checklist: checklist)
        }
    }
} 
