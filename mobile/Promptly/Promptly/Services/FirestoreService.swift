import Foundation
import Firebase
import FirebaseFirestore

typealias FirestoreTaskCallback = (String, [String: Any]?) -> Void

class FirestoreService {
    // Collection names
    private static let MESSAGE_TASKS_COLLECTION = "message_tasks"
    private static let CHECKLIST_TASKS_COLLECTION = "checklist_tasks"
    private static let CHECKIN_TASKS_COLLECTION = "checkin_tasks"
    
    // Singleton instance
    static let shared = FirestoreService()
    
    // Firestore database reference
    private let db = Firestore.firestore()
    
    // Active listeners
    private var messageListeners: [String: ListenerRegistration] = [:]
    
    // Track current active task IDs
    private var activeMessageTaskId: String?
    private var activeChecklistTaskId: String?
    private var activeCheckinTaskId: String?
    
    // Callback for when listener status changes
    var onListenerStatusChanged: (() -> Void)?
    
    private init() {}
    
    // MARK: - Task Listeners
    
    /// Returns true if any listener is active (either message, checklist, or checkin)
    func hasActiveListeners() -> Bool {
        return activeMessageTaskId != nil || activeChecklistTaskId != nil || activeCheckinTaskId != nil
    }
    
    /// Checks if a listener for a message task is already active
    /// - Parameter taskId: The task ID to check
    /// - Returns: Whether a listener for this task is already active
    func isMessageTaskActive(_ taskId: String) -> Bool {
        return activeMessageTaskId == taskId
    }
    
    /// Checks if a listener for a checklist task is already active
    /// - Parameter taskId: The task ID to check
    /// - Returns: Whether a listener for this task is already active
    func isChecklistTaskActive(_ taskId: String) -> Bool {
        return activeChecklistTaskId == taskId
    }
    
    /// Checks if a listener for a checkin task is already active
    /// - Parameter taskId: The task ID to check
    /// - Returns: Whether a listener for this task is already active
    func isCheckinTaskActive(_ taskId: String) -> Bool {
        return activeCheckinTaskId == taskId
    }
    
    /// Returns the active message task ID if one exists
    /// - Returns: The active message task ID or nil
    func getActiveMessageTaskId() -> String? {
        return activeMessageTaskId
    }
    
    /// Returns the active checklist task ID if one exists
    /// - Returns: The active checklist task ID or nil
    func getActiveChecklistTaskId() -> String? {
        return activeChecklistTaskId
    }
    
    /// Returns the active checkin task ID if one exists
    /// - Returns: The active checkin task ID or nil
    func getActiveCheckinTaskId() -> String? {
        return activeCheckinTaskId
    }
    
    /// Listen for updates to a message task
    /// - Parameters:
    ///   - taskId: The task ID
    ///   - onUpdate: Callback when the task is updated
    /// - Returns: True if a new listener was set up, false if one was already active
    func listenForMessageTask(taskId: String, onUpdate: @escaping FirestoreTaskCallback) -> Bool {
        // Check if we're already listening to this task
        if isMessageTaskActive(taskId) {
            return false
        }
        
        // Check if we have a listener registered but it's not marked as active
        if messageListeners["message_task_\(taskId)"] != nil {
            removeMessageListener(for: "message_task_\(taskId)")
        }
                
        let listener = db.collection(FirestoreService.MESSAGE_TASKS_COLLECTION).document(taskId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("MESSAGE DEBUG: Error listening for message task: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("MESSAGE DEBUG: Snapshot is nil for task: \(taskId)")
                    return
                }
                
                if !snapshot.exists {
                    print("MESSAGE DEBUG: Message task document doesn't exist: \(taskId)")
                    return
                }
                
                let data = snapshot.data()
                let status = data?["status"] as? String ?? "unknown"
                
                // If the task is completed or failed, automatically clean up the listener after callback
                if status == "completed" || status == "failed" {
                    // Call the callback first
                    onUpdate(status, data)
                    
                    // Then remove the listener
                    self.removeMessageListener(for: "message_task_\(taskId)")
                    print("MESSAGE DEBUG: Auto-removed listener after task completion/failure")
                } else {
                    // For other statuses, just call the callback
                    onUpdate(status, data)
                }
            }
        
        // Store the listener with a unique key
        messageListeners["message_task_\(taskId)"] = listener
        
        // Track the active message task ID
        activeMessageTaskId = taskId
        
        // Notify that listener status changed
        onListenerStatusChanged?()
        
        return true
    }
    
    /// Listen for updates to a checklist task
    /// - Parameters:
    ///   - taskId: The task ID
    ///   - onUpdate: Callback when the task is updated
    /// - Returns: True if a new listener was set up, false if one was already active
    func listenForChecklistTask(taskId: String, onUpdate: @escaping FirestoreTaskCallback) -> Bool {
        // Check if we're already listening to this task
        if isChecklistTaskActive(taskId) {
            print("CHECKLIST DEBUG: Already listening for checklist task: \(taskId)")
            return false
        }
        
        // Check if we have a listener registered but it's not marked as active
        if messageListeners["checklist_task_\(taskId)"] != nil {
            print("CHECKLIST DEBUG: Removing stale listener for checklist task: \(taskId)")
            removeMessageListener(for: "checklist_task_\(taskId)")
        }
                
        let listener = db.collection(FirestoreService.CHECKLIST_TASKS_COLLECTION).document(taskId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("CHECKLIST DEBUG: Error listening for checklist task: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("CHECKLIST DEBUG: Snapshot is nil for task: \(taskId)")
                    return
                }
                
                if !snapshot.exists {
                    print("CHECKLIST DEBUG: Checklist task document doesn't exist: \(taskId)")
                    return
                }
                
                let data = snapshot.data()
                let status = data?["status"] as? String ?? "unknown"
                
                // If the task is completed or failed, automatically clean up the listener after callback
                if status == "completed" || status == "failed" {
                    // Call the callback first
                    onUpdate(status, data)
                    
                    // Then remove the listener
                    self.removeMessageListener(for: "checklist_task_\(taskId)")
                    print("CHECKLIST DEBUG: Auto-removed listener after task completion/failure")
                } else {
                    // For other statuses, just call the callback
                    onUpdate(status, data)
                }
            }
        
        // Store the listener with a unique key
        messageListeners["checklist_task_\(taskId)"] = listener
        
        // Track the active checklist task ID
        activeChecklistTaskId = taskId
        
        // Notify that listener status changed
        onListenerStatusChanged?()
        
        return true
    }
    
    /// Listen for updates to a checkin task
    /// - Parameters:
    ///   - taskId: The task ID
    ///   - onUpdate: Callback when the task is updated
    /// - Returns: True if a new listener was set up, false if one was already active
    func listenForCheckinTask(taskId: String, onUpdate: @escaping FirestoreTaskCallback) -> Bool {
        // Check if we're already listening to this task
        if isCheckinTaskActive(taskId) {
            print("CHECKIN DEBUG: Already listening for checkin task: \(taskId)")
            return false
        }
        
        // Check if we have a listener registered but it's not marked as active
        if messageListeners["checkin_task_\(taskId)"] != nil {
            print("CHECKIN DEBUG: Removing stale listener for checkin task: \(taskId)")
            removeMessageListener(for: "checkin_task_\(taskId)")
        }
                
        let listener = db.collection(FirestoreService.CHECKIN_TASKS_COLLECTION).document(taskId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("CHECKIN DEBUG: Error listening for checkin task: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("CHECKIN DEBUG: Snapshot is nil for task: \(taskId)")
                    return
                }
                
                if !snapshot.exists {
                    print("CHECKIN DEBUG: Checkin task document doesn't exist: \(taskId)")
                    return
                }
                
                let data = snapshot.data()
                let status = data?["status"] as? String ?? "unknown"
                
                // If the task is completed or failed, automatically clean up the listener after callback
                if status == "completed" || status == "failed" {
                    // Call the callback first
                    onUpdate(status, data)
                    
                    // Then remove the listener
                    self.removeMessageListener(for: "checkin_task_\(taskId)")
                    print("CHECKIN DEBUG: Auto-removed listener after task completion/failure")
                } else {
                    // For other statuses, just call the callback
                    onUpdate(status, data)
                }
            }
        
        // Store the listener with a unique key
        messageListeners["checkin_task_\(taskId)"] = listener
        
        // Track the active checkin task ID
        activeCheckinTaskId = taskId
        
        // Notify that listener status changed
        onListenerStatusChanged?()
        
        return true
    }
    
    /// Remove a message listener
    /// - Parameter key: The listener key
    /// - Returns: True if a listener was removed, false otherwise
    @discardableResult
    func removeMessageListener(for key: String) -> Bool {
        if let listener = messageListeners[key] {
            listener.remove()
            messageListeners.removeValue(forKey: key)
            
            // Clear active task IDs if they match
            if key.hasPrefix("message_task_") && activeMessageTaskId == key.replacingOccurrences(of: "message_task_", with: "") {
                activeMessageTaskId = nil
            } else if key.hasPrefix("checklist_task_") && activeChecklistTaskId == key.replacingOccurrences(of: "checklist_task_", with: "") {
                activeChecklistTaskId = nil
            } else if key.hasPrefix("checkin_task_") && activeCheckinTaskId == key.replacingOccurrences(of: "checkin_task_", with: "") {
                activeCheckinTaskId = nil
            }
            
            // Notify that listener status changed
            onListenerStatusChanged?()
            
            return true
        }
        return false
    }
    
    /// Remove all message listeners
    func removeAllMessageListeners() {
        for (key, listener) in messageListeners {
            listener.remove()
            print("Removed listener for key: \(key)")
        }
        messageListeners.removeAll()
        
        // Reset active task IDs
        activeMessageTaskId = nil
        activeChecklistTaskId = nil
        activeCheckinTaskId = nil
        
        // Notify that listener status changed
        onListenerStatusChanged?()
    }
} 
