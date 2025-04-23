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
    
    /// Gets edited checklists from the last 30 days before the given checklist's date
    /// - Parameter referenceDate: The date to count back 30 days from
    /// - Returns: Array of checklists that have been edited
    @MainActor private func getEditedChecklists(referenceDate: Date) -> [Models.Checklist] {
        var editedChecklists: [Models.Checklist] = []
        let calendar = Calendar.current
        
        // Check last 30 days, including the reference date
        for dayOffset in 0...30 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: referenceDate) {
                if let checklist = checklistPersistence.loadChecklist(for: date), checklist.isEdited {
                    editedChecklists.append(checklist)
                }
            }
        }
        
        return editedChecklists
    }
    
    /// Converts multiple checklists to a dictionary format for check-in
    /// - Parameter checklists: Array of checklists to convert
    /// - Returns: Dictionary containing all checklist data
    private func getChecklistsDictionaryForCheckin(_ checklists: [Models.Checklist]) -> [String: Any] {
        let checklistsDict: [[String: Any]] = checklists.map { checklist in
            [
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
            ] as [String: Any]
        }
        
        return ["checklists": checklistsDict]
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
        
        // Populate analytics fields
        analytics.populateReportAnalytics(report: report, forDate: date)
        
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
    ///   - checklist: The current checklist to check in
    ///   - report: The report to update with server response
    @MainActor func performServerCheckIn(checklist: Models.Checklist, report: Report) async {
        do {
            // Get all edited checklists from the last 30 days, using the checklist's date as reference
            let editedChecklists = getEditedChecklists(referenceDate: checklist.date)
            
            // Debug print the dates
            print("📅 Sending checklists for dates:")
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            editedChecklists.forEach { checklist in
                print("  • \(dateFormatter.string(from: checklist.date))")
            }
            
            // Create dictionary with all checklists
            let dictChecklists = getChecklistsDictionaryForCheckin(editedChecklists)
            
            // Try to send the check-in to the server and get the response
            let (summary, analysis, response) = try await chatService.handleCheckin(checklist: dictChecklists)
            
            // Update the report with the server response
            report.summary = summary
            report.analysis = analysis
            report.response = response
            
            // Mark all sent checklists as not edited since they've been processed
            for editedChecklist in editedChecklists {
                if let coreDataChecklist = try? persistence.container.viewContext.fetch(Checklist.fetchRequest())
                    .first(where: { $0.date == editedChecklist.date }) {
                    coreDataChecklist.isEdited = false
                }
            }
            
            // Save all changes to Core Data
            try persistence.container.viewContext.save()
            
            // Send the response to the chat
            ChatViewModel.shared.handleMessage(response)
            
            print("✅ Server check-in successful")
        } catch {
            // Fall back to offline processing
            print("🔄 Falling back to offline check-in")
            
            ChatViewModel.shared.handleMessage("I generated an offline report for you.")
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
        }
    }
} 
