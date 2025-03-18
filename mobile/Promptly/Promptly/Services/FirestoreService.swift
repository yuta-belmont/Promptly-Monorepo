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
        print("CHECKLIST DEBUG: FirestoreService setting up listener for checklist task: \(taskId)")
        print("CHECKLIST DEBUG: Firestore path: checklist_tasks/\(taskId)")
        
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
                
                print("CHECKLIST DEBUG: FirestoreService received update for checklist task: \(taskId), status: \(status)")
                print("CHECKLIST DEBUG: Metadata: isFromCache=\(snapshot.metadata.isFromCache), hasPendingWrites=\(snapshot.metadata.hasPendingWrites)")
                
                onUpdate(status, data)
            }
        
        // Store the listener with a unique key
        messageListeners["checklist_task_\(taskId)"] = listener
        print("CHECKLIST DEBUG: FirestoreService stored listener for checklist task: \(taskId)")
    }
    
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