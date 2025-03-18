import Foundation

@MainActor
final class ChecklistViewModel: ObservableObject {
    @Published var checklist: Checklist
    private var originalChecklist: Checklist
    private let persistence = ChecklistPersistence.shared
    private let notificationManager = NotificationManager.shared
    @Published var isEditing: Bool = false
    private var itemsSnapshot: [ChecklistItem] = []
    private var date: Date
    
    init(date: Date = Date()) {
        let loadedChecklist = persistence.loadChecklist(for: date) ?? Checklist(date: date)
        
        self.checklist = loadedChecklist
        self.originalChecklist = loadedChecklist
        self.date = date
        
        // Register for notifications
        setupNotifications()
    }
    
    deinit {
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotifications() {
        // Register for new checklist notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewChecklistNotification(_:)),
            name: Notification.Name("NewChecklistAvailable"),
            object: nil
        )
    }
    
    @objc private func handleNewChecklistNotification(_ notification: Notification) {
        guard let newChecklistDate = notification.object as? Date else { return }
        
        // Check if the notification is for our current date
        let calendar = Calendar.current
        if calendar.isDate(newChecklistDate, inSameDayAs: self.date) {
            print("Received notification for new checklist on current date: \(newChecklistDate)")
            
            // Reload the checklist data
            let loadedChecklist = persistence.loadChecklist(for: date) ?? Checklist(date: date)
            self.checklist = loadedChecklist
            self.originalChecklist = loadedChecklist
            
            // Notify observers
            objectWillChange.send()
        }
    }
    
    // Method to update the date and reload checklist data
    func updateDate(_ newDate: Date) {
        // Save current checklist if needed
        if hasChanges {
            saveChecklist()
        }
        
        // Load checklist for the new date
        let loadedChecklist = persistence.loadChecklist(for: newDate) ?? Checklist(date: newDate)
        self.checklist = loadedChecklist
        self.originalChecklist = loadedChecklist
        
        // Notify observers
        objectWillChange.send()
    }
    
    var items: [ChecklistItem] { checklist.items }
    
    // Check if there are any unsaved changes compared to the snapshot
    var hasChanges: Bool {
        // Compare item counts
        if checklist.items.count != originalChecklist.items.count {
            return true
        }
        
        // Compare each item
        for (index, item) in checklist.items.enumerated() {
            if index >= originalChecklist.items.count || item != originalChecklist.items[index] {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Item Management
    func updateItem(_ item: ChecklistItem) {
        var updatedChecklist = checklist
        if let index = updatedChecklist.items.firstIndex(where: { $0.id == item.id }) {
            let oldItem = updatedChecklist.items[index]
            
            // Always remove existing notifications first
            notificationManager.removeAllNotificationsForItem(oldItem)
            
            // Schedule new notification if:
            // 1. Item has a notification date
            // 2. Item is not completed
            // 3. Notification date is in the future
            if let notification = item.notification,
               !item.isCompleted,
               notification > Date() {
                notificationManager.scheduleNotification(for: item, in: checklist)
            }
            
            // Update the item
            updatedChecklist.items[index] = item
            checklist = updatedChecklist
            saveChecklist()
        }
    }
    
    func deleteItems(at indexSet: IndexSet) {
        // Remove notifications for deleted items
        for index in indexSet {
            if index < checklist.items.count {
                let item = checklist.items[index]
                notificationManager.removeAllNotificationsForItem(item)
            }
        }
        
        var updatedChecklist = checklist
        updatedChecklist.deleteItems(at: indexSet)
        checklist = updatedChecklist
        saveChecklist()
    }
    
    func addItem(_ item: ChecklistItem) {
        var updatedChecklist = checklist
        
        // Schedule notification if needed
        if let notification = item.notification,
           !item.isCompleted,
           notification > Date() {
            notificationManager.scheduleNotification(for: item, in: checklist)
        }
        
        updatedChecklist.items.append(item)
        checklist = updatedChecklist
        saveChecklist()
    }
    
    func addItem(_ item: ChecklistItem, at index: Int) {
        var updatedChecklist = checklist
        
        // Schedule notification if needed
        if let notification = item.notification,
           !item.isCompleted,
           notification > Date() {
            notificationManager.scheduleNotification(for: item, in: checklist)
        }
        
        // Insert at specific index, clamped to valid range
        let safeIndex = min(max(index, 0), updatedChecklist.items.count)
        updatedChecklist.items.insert(item, at: safeIndex)
        checklist = updatedChecklist
        saveChecklist()
    }
    
    func moveItems(from source: IndexSet, to destination: Int) {
        var updatedChecklist = checklist
        updatedChecklist.moveItems(from: source, to: destination)
        checklist = updatedChecklist
        saveChecklist()
    }
    
    func clearItems() {
        // Remove all notifications for this checklist
        for item in checklist.items {
            notificationManager.removeAllNotificationsForItem(item)
        }
        
        var updatedChecklist = checklist
        updatedChecklist.items = []
        checklist = updatedChecklist
        saveChecklist()
    }
    
    func saveSnapshot() {
        originalChecklist = checklist
    }
    
    func restoreSnapshot() {
        // Process notifications for restored items
        notificationManager.processNotificationsForChecklist(checklist)
        
        checklist = originalChecklist
        saveChecklist()
    }
    
    private func saveChecklist() {
        persistence.saveChecklist(checklist)
    }
    
    // MARK: - Data Import
    func importFromYesterday() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: checklist.date) ?? checklist.date
        if let yesterdayChecklist = persistence.loadChecklist(for: yesterday) {
            var updatedChecklist = checklist
            
            // Create new items with new UUIDs to avoid ID conflicts
            let newItems = yesterdayChecklist.items.map { item in
                return ChecklistItem(
                    id: UUID(), // Generate a new UUID
                    title: item.title,
                    date: checklist.date,
                    isCompleted: false, // Reset completion status
                    notification: nil,
                    group: nil
                )
            }
            
            updatedChecklist.items.append(contentsOf: newItems)
            checklist = updatedChecklist
            saveChecklist()
            
            // Process notifications for the updated checklist
            notificationManager.processNotificationsForChecklist(checklist)
        }
    }
    
    func importFromDate(_ date: Date) async {
        if let dateChecklist = persistence.loadChecklist(for: date) {
            var updatedChecklist = checklist
            
            // Create new items with new UUIDs to avoid ID conflicts
            let newItems = dateChecklist.items.map { item in
                return ChecklistItem(
                    id: UUID(), // Generate a new UUID
                    title: item.title,
                    date: checklist.date,
                    isCompleted: false, // Reset completion status
                    notification: item.notification,
                    group: nil
                )
            }
            
            updatedChecklist.items.append(contentsOf: newItems)
            checklist = updatedChecklist
            saveChecklist()
            
            // Process notifications for the updated checklist
            notificationManager.processNotificationsForChecklist(checklist)
        }
    }
    
    @MainActor
    func clearAndImportFromDate(_ date: Date) async {
        // Clear current items by creating an updated checklist with empty items
        var updatedChecklist = checklist
        
        // Remove notifications for all current items
        for item in updatedChecklist.items {
            notificationManager.removeAllNotificationsForItem(item)
        }
        
        updatedChecklist.items = []
        checklist = updatedChecklist
        
        // Import from the selected date
        await importFromDate(date)
    }
    
    @MainActor
    func importFromCalendar() async {
        // This method is no longer used as we're using the date picker popover instead
        // Kept as a placeholder for potential future calendar integration
    }
} 
