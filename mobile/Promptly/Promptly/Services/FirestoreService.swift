import Foundation
import Firebase
import FirebaseFirestore

class FirestoreService {
    // Singleton instance
    static let shared = FirestoreService()
    
    // Firestore database reference
    private let db = Firestore.firestore()
    
    // Active listeners
    private var messageListeners: [String: ListenerRegistration] = [:]
    
    private init() {}
    
    // MARK: - Message Task Listeners
    
    /// Listen for updates to a specific checklist task
    /// - Parameters:
    ///   - taskId: The task ID
    ///   - onUpdate: Callback when the task is updated
    func listenForChecklistTask(taskId: String, onUpdate: @escaping (String, [String: Any]?) -> Void) {
        
        let listener = db.collection("checklist_tasks").document(taskId)
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
                
                onUpdate(status, data)
            }
        
        // Store the listener with a unique key
        messageListeners["checklist_task_\(taskId)"] = listener    }
    
    /// Remove a message listener
    /// - Parameter key: The listener key
    func removeMessageListener(for key: String) {
        if let listener = messageListeners[key] {
            listener.remove()
            messageListeners.removeValue(forKey: key)
        }
    }
    
    /// Remove all message listeners
    func removeAllMessageListeners() {
        for (key, listener) in messageListeners {
            listener.remove()
            messageListeners.removeValue(forKey: key)
        }
    }
} 
