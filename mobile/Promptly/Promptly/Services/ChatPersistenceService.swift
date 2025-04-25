import Foundation
import CoreData

class ChatPersistenceService {
    static let shared = ChatPersistenceService()
    
    // MARK: - Core Data Stack
    
    // Use the existing PersistenceController instead of creating a new stack
    private let persistenceController = PersistenceController.shared
    
    var viewContext: NSManagedObjectContext {
        return persistenceController.container.viewContext
    }
    
    // For background operations
    func backgroundContext() -> NSManagedObjectContext {
        return persistenceController.backgroundContext()
    }
    
    // MARK: - Chat History Operations
    
    func loadMainChatHistory() async -> ChatHistory? {
        let context = viewContext
        
        let request: NSFetchRequest<ChatHistory> = ChatHistory.fetchRequest()
        request.predicate = NSPredicate(format: "isMainHistory == %@", NSNumber(value: true))
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            if let history = results.first {
                return history
            } else {
                // Create main chat history if it doesn't exist
                return createMainChatHistory()
            }
        } catch {
            print("ChatPersistenceService: Failed to load main chat history: \(error)")
            return createMainChatHistory()
        }
    }
    
    private func createMainChatHistory() -> ChatHistory {
        let context = viewContext
        
        let history = NSEntityDescription.insertNewObject(forEntityName: "ChatHistory", into: context) as! ChatHistory
        history.id = UUID()
        history.isMainHistory = true
        
        do {
            try context.save()
            return history
        } catch {
            print("ChatPersistenceService: Failed to create main chat history: \(error)")
            // Return unsaved history as fallback
            return history
        }
    }
    
    func saveChatHistory(_ chatHistory: ChatHistory) {
        let context = chatHistory.managedObjectContext ?? viewContext
        
        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            print("ChatPersistenceService: Failed to save chat history: \(error)")
        }
    }
    
    // MARK: - Messages Cleanup
    
    /// Deletes all chat messages older than 48 hours
    func deleteMessagesOlderThan72Hours() {
        // Calculate the cutoff date (72 hours ago)
        let cutoffDate = Calendar.current.date(byAdding: .hour, value: -72, to: Date())!
        
        // Create a background context for this operation to avoid blocking the main thread
        let context = backgroundContext()
        
        // Create a batch delete request for better performance
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ChatMessage")
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
        
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        // Execute the request in background
        Task {
            do {
                try await context.perform {
                    // Execute the batch delete
                    let result = try context.execute(batchDeleteRequest)
                    
                    // Log the number of deleted messages if available
                    if let batchResult = result as? NSBatchDeleteResult,
                       let objectIDs = batchResult.result as? [NSManagedObjectID] {
                        print("Successfully deleted \(objectIDs.count) messages older than 48 hours")
                    } else {
                        print("Successfully deleted messages older than 48 hours")
                    }
                }
            } catch {
                print("Error deleting old messages: \(error)")
            }
        }
    }
    
    // MARK: - Pending Response Management
    
    private let pendingResponseKey = "pendingResponse"
    
    func loadPendingResponse() -> UUID? {
        let userDefaults = UserDefaults.standard
        guard let idString = userDefaults.string(forKey: "\(pendingResponseKey)_id"),
              let id = UUID(uuidString: idString) else {
            return nil
        }
        return id
    }
    
    func savePendingResponse(id: UUID) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(id.uuidString, forKey: "\(pendingResponseKey)_id")
    }
    
    func clearPendingResponse() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "\(pendingResponseKey)_id")
    }
    
    // MARK: - Unread Counts Management
    
    private let unreadCountsKey = "unreadCounts"
    
    func loadUnreadCounts() -> [String: Int] {
        let userDefaults = UserDefaults.standard
        return userDefaults.dictionary(forKey: unreadCountsKey) as? [String: Int] ?? [:]
    }
    
    func saveUnreadCounts(_ counts: [String: Int]) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(counts, forKey: unreadCountsKey)
    }
    
    // MARK: - Loading State Management
    
    private let loadingStateKey = "loadingState"
    
    func saveLoadingState(messageId: UUID, timestamp: Date = Date()) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(messageId.uuidString, forKey: "\(loadingStateKey)_id")
        userDefaults.set(timestamp, forKey: "\(loadingStateKey)_timestamp")
    }
    
    func loadLoadingState() -> (messageId: UUID, timestamp: Date)? {
        let userDefaults = UserDefaults.standard
        guard let idString = userDefaults.string(forKey: "\(loadingStateKey)_id"),
              let id = UUID(uuidString: idString),
              let timestamp = userDefaults.object(forKey: "\(loadingStateKey)_timestamp") as? Date else {
            return nil
        }
        return (id, timestamp)
    }
    
    func clearLoadingState() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "\(loadingStateKey)_id")
        userDefaults.removeObject(forKey: "\(loadingStateKey)_timestamp")
    }
} 
