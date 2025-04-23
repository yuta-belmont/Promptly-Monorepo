import Foundation
import CoreData
import Firebase
import FirebaseAuth
import Network
import SwiftUI

enum ChatServiceError: Error {
    case notAuthenticated
    case invalidResponse(String)
    case networkError(String)
    case invalidRequest
}

final class ChatService {
    // Add shared singleton instance
    static let shared = ChatService()
    
    // Replace OpenAI endpoint with our server endpoint
    private let authManager = AuthManager.shared
    private let serverBaseURL = "http://192.168.1.166:8080/api/v1"
    private let persistenceService = ChatPersistenceService.shared
    private let firestoreService = FirestoreService.shared
    
    // Access the shared view model directly
    private var chatViewModel: ChatViewModel { ChatViewModel.shared }
    
    // Network path monitor for connectivity checking
    private let networkMonitor = NWPathMonitor()
    private var isConnected = true
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    // Track the current chat ID on the server
    private var currentChatId: String?
    // Track the current checklist task ID
    private var currentChecklistTaskId: String?
    // Track the current message task ID
    private var currentMessageTaskId: String?
    
    // Callback for message updates
    var onMessageUpdate: ((String) -> Void)?
    
    private init() {
        // Set up network path monitor
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            print("Network connection status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    // This method is maintained for backward compatibility, but now just a no-op
    func setChatViewModel(_ viewModel: ChatViewModel) {
        // No need to do anything since we use the shared instance
    }
    
    // Helper method to notify the view model
    public func notifyAllViewModels(_ message: String) {
        Task { @MainActor in
            chatViewModel.handleMessage(message)
        }
        // Also call the general callback if set
        onMessageUpdate?(message)
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // Check if we have an internet connection
    func checkConnectivity() -> Bool {
        return isConnected
    }

    // Method to send a message with additional context
    func sendMessage(messages: [ChatMessage], additionalContext: [[String: Any]]) async throws -> (ChatMessage?, Bool) {
        // Log the message that's about to be sent (usually the last one)
        if let lastMessage = messages.last {
            print("📤 SENDING MESSAGE WITH CONTEXT: \(lastMessage.content)")
            print("📤 MESSAGE SIZE: \(lastMessage.content.utf8.count) bytes")
            print("📤 CONTEXT SIZE: \(additionalContext.count) messages")
        }
        
        // Check for connectivity first
        guard checkConnectivity() else {
            throw NSError(domain: "ChatService", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet connection. Please check your network settings and try again."])
        }
        
        guard let token = authManager.getToken() else {
            throw NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Get the last user message
        guard let lastMessage = messages.last(where: { $0.role == MessageRoles.user }) else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No user message to send"])
        }
        
        // Use the stateless endpoint directly
        let url = URL(string: "\(serverBaseURL)/chat/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.promptly.optimized+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        // Get current date and time
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone.current  // Use the device's local time zone
        let currentTimeString = dateFormatter.string(from: currentDate)
        
        // Create payload with context and current_time
        let payload: [String: Any] = [
            "message": lastMessage.content,
            "context_messages": additionalContext,
            "current_time": currentTimeString
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = bodyData
        
        // Print the size of the outgoing message
        print("📤 OUTGOING MESSAGE SIZE: \(bodyData.count) bytes")
        
        // Print the entire outgoing payload for debugging
        if let payloadString = String(data: bodyData, encoding: .utf8) {
            print("📤 OUTGOING PAYLOAD: \(payloadString)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Print the size of the incoming response
        print("📥 INCOMING RESPONSE SIZE: \(data.count) bytes")
        
        // Log the raw response data
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("RAW SERVER RESPONSE: \(rawResponse)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                        userInfo: [NSLocalizedDescriptionKey: "Failed to send message: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        // Try parsing the optimized response format
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for the streamlined format with "response" and optional "metadata"
            if let responseData = json["response"] as? [String: Any] {
                // Check for metadata with message_id
                if let metadata = json["metadata"] as? [String: Any] {
                    if let messageId = metadata["message_id"] as? String {
                        print("MESSAGE DEBUG: Found message_id in metadata: \(messageId)")
                        
                        // Store the task ID
                        self.currentMessageTaskId = messageId
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: messageId)
        
        // We no longer create an AI message here since it will come from the Firestore listener
                        // Return nil for the message and false for the flag
                        return (nil, false)
                    }
                }
            }
        }
        
        // If we reach here, something unexpected happened with the response
        print("WARNING: Could not properly parse server response for stateless message")
        throw NSError(domain: "ChatService", code: 400, 
                     userInfo: [NSLocalizedDescriptionKey: "Failed to parse server response"])
    }

    /// Sends a message with context to the server and parses the response.
    /// This is a specialized version of sendMessageToServer that includes context messages.
    private func sendMessageWithContextToServer(
        chatId: String, 
        content: String, 
        contextMessages: [[String: Any]], 
        nextSequence: Int, 
        token: String
    ) async throws -> String {
        let url = URL(string: "\(serverBaseURL)/chat/\(chatId)/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.promptly.optimized+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        // Get current date and time
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone.current  // Use the device's local time zone
        let currentTimeString = dateFormatter.string(from: currentDate)
        
        // Create payload with context and current_time instead of next_sequence
        let payload: [String: Any] = [
            "message": content,
            "context_messages": contextMessages,
            "current_time": currentTimeString
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = bodyData
        
        // Print the size of the outgoing message
        print("📤 OUTGOING MESSAGE SIZE: \(bodyData.count) bytes")
        
        // Print the entire outgoing payload for debugging
        if let payloadString = String(data: bodyData, encoding: .utf8) {
            print("📤 OUTGOING PAYLOAD: \(payloadString)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Print the size of the incoming response
        print("📥 INCOMING RESPONSE SIZE: \(data.count) bytes")
        
        // Log the raw response data
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("RAW SERVER RESPONSE: \(rawResponse)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                        userInfo: [NSLocalizedDescriptionKey: "Failed to send message: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        // Try parsing the optimized response format first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for the new streamlined format with "response" and optional "metadata"
            if let responseData = json["response"] as? [String: Any],
               let responseContent = responseData["content"] as? String {
                                
                // Check for metadata with message_id or checklist_id
                if let metadata = json["metadata"] as? [String: Any] {
                    if let messageId = metadata["message_id"] as? String {
                        print("MESSAGE DEBUG: Found message_id in metadata: \(messageId)")
                        
                        // Store the task ID
                        self.currentMessageTaskId = messageId
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: messageId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                    else if let checklistId = metadata["checklist_id"] as? String {
                        print("CHECKLIST DEBUG: Found checklist_id in metadata: \(checklistId)")
                        
                        // Store the task ID
                        self.currentChecklistTaskId = checklistId
                        
                        // Set up a listener for this task
                        setupChecklistTaskListener(taskId: checklistId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                    else if let taskId = metadata["task_id"] as? String {
                        // Legacy format - assume it's a message task
                        print("MESSAGE DEBUG: Found task_id in metadata (legacy format): \(taskId)")
                        
                        // Store the task ID
                        self.currentMessageTaskId = taskId
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: taskId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                }
                
                // Return placeholder content for display purposes only
                // The actual content will come from the Firestore listener
                // Instead of returning the content directly, return an empty string to avoid displaying placeholders
                return ""
            }
        }
        
        // If we reach here, either the response wasn't in the optimized format,
        // or it didn't contain the expected fields, or we couldn't parse it properly.
        // In any case, return an empty string and log a warning
        print("WARNING: Could not properly parse server response for message with context")
        return ""
    }
    
    private func createNewChat(token: String) async throws -> String {
        let url = URL(string: "\(serverBaseURL)/chat/")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15 // 15 second timeout for request
        
        let body: [String: Any] = [
            "title": "Mobile Chat \(Date())"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create chat: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chatId = json["id"] as? String else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return chatId
    }
    
    /// Sends a message to the server and parses the response.
    /// 
    /// This method supports two response formats:
    /// 
    /// 1. Optimized format (preferred):
    /// ```
    /// {
    ///   "response": {
    ///     "id": "message-id",
    ///     "content": "Hello, how can I help you?"
    ///   },
    ///   "metadata": {
    ///     "checklist_task_id": "optional-task-id" // Only present for checklist requests
    ///   }
    /// }
    /// ```
    /// 
    /// 2. Legacy format (fallback):
    /// ```
    /// {
    ///   "id": "chat-id",
    ///   "title": "Chat title",
    ///   "messages": [
    ///     { "role": "user", "content": "User message", ... },
    ///     { "role": "assistant", "content": "Assistant response", ... }
    ///   ]
    /// }
    /// ```
    /// 
    /// - Parameters:
    ///   - chatId: The ID of the chat session
    ///   - content: The user's message content
    ///   - token: The authentication token
    /// - Returns: The assistant's response message content
    private func sendMessageToServer(chatId: String, content: String, token: String) async throws -> String {
        let url = URL(string: "\(serverBaseURL)/chat/\(chatId)/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Set an Accept header to indicate preference for the optimized response format
        // If server supports content negotiation, it can return the optimized format
        request.setValue("application/vnd.promptly.optimized+json", forHTTPHeaderField: "Accept")
        
        request.timeoutInterval = 15 // 15 second timeout for request
        
        // We don't need to specify sequence as the server will handle that
        let body: [String: Any] = [
            "content": content
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        
        // Print the size of the outgoing message
        print("📤 OUTGOING MESSAGE SIZE: \(bodyData.count) bytes")
        
        // Print the entire outgoing payload for debugging
        if let payloadString = String(data: bodyData, encoding: .utf8) {
            print("📤 OUTGOING PAYLOAD: \(payloadString)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Print the size of the incoming response
        print("📥 INCOMING RESPONSE SIZE: \(data.count) bytes")
        
        // Log the raw response data
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("RAW SERVER RESPONSE: \(rawResponse)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                          userInfo: [NSLocalizedDescriptionKey: "Failed to send message: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        // Try parsing the optimized response format first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for the new streamlined format with "response" and optional "metadata"
            if let responseData = json["response"] as? [String: Any],
               let responseContent = responseData["content"] as? String {
                
                print("📥 ASSISTANT MESSAGE SIZE: \(responseContent.utf8.count) bytes")
                
                // The optimized format eliminates redundant data like:
                // - The user's message which we already have
                // - Chat metadata (title, is_active, etc.)
                // - Timestamps and sequence numbers
                // This can reduce payload size by 70-80% in most cases
                
                // Check for metadata with message_id or checklist_id
                if let metadata = json["metadata"] as? [String: Any] {
                    if let messageId = metadata["message_id"] as? String {
                        print("MESSAGE DEBUG: Found message_id in metadata: \(messageId)")
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: messageId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                    else if let checklistId = metadata["checklist_id"] as? String {
                        print("CHECKLIST DEBUG: Found checklist_id in metadata: \(checklistId)")
                        
                        // Store the task ID
                        self.currentChecklistTaskId = checklistId
                        
                        // Set up a listener for this task
                        setupChecklistTaskListener(taskId: checklistId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                    else if let taskId = metadata["task_id"] as? String {
                        // Legacy format - assume it's a message task
                        print("MESSAGE DEBUG: Found task_id in metadata (legacy format): \(taskId)")
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: taskId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                }
                
                // Return placeholder content for display purposes only
                // The actual content will come from the Firestore listener
                // Instead of returning the content directly, return an empty string to avoid displaying placeholders
                return ""
            }
        }
        
        // If we reach here, it means we need to fall back to the old format
        print("FALLING BACK TO LEGACY RESPONSE FORMAT")
        
        // Parse the response to get the assistant's message (legacy format)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        // Find the assistant's message (should be the last one)
        if let assistantMessage = messages.last(where: { ($0["role"] as? String) == "assistant" }),
           let content = assistantMessage["content"] as? String {
            
            print("ASSISTANT MESSAGE CONTENT (PRE-PARSING): \(content)")
            
            // Print the size of the assistant message content
            print("📥 ASSISTANT MESSAGE SIZE: \(content.utf8.count) bytes")
            
            // Check if the response is structured as JSON with a flag
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messageContent = json["message"] as? String {
                
                print("PARSED JSON FROM CONTENT: \(json)")
                
                // Check if the response includes task info
                if let taskInfo = json["task_info"] as? [String: Any] {
                    print("Found task_info in response: \(taskInfo)")
                    
                    // Check for checklist task ID
                    if let checklistTaskId = taskInfo["checklist_task_id"] as? String {
                        print("CHECKLIST DEBUG: Found checklist_task_id: \(checklistTaskId)")
                        
                        // Store the task ID
                        self.currentChecklistTaskId = checklistTaskId
                        
                        // Set up a listener for this task
                        setupChecklistTaskListener(taskId: checklistTaskId)
                        
                        print("Set up listener for checklist task: \(checklistTaskId)")
                    } else {
                        print("CHECKLIST DEBUG: No checklist_task_id found in task_info")
                    }
                } else {
                    // Check if task IDs are directly in the message JSON
                    if let checklistTaskId = json["checklist_task_id"] as? String {
                        print("CHECKLIST DEBUG: Found checklist_task_id in message JSON: \(checklistTaskId)")
                        
                        // Store the task ID
                        self.currentChecklistTaskId = checklistTaskId
                        
                        // Set up a listener for this task
                        setupChecklistTaskListener(taskId: checklistTaskId)
                        
                        print("Set up listener for checklist task from message JSON: \(checklistTaskId)")
                    }
                }
                
                // Return just the message content, not the whole JSON
                return messageContent
            }
            
            return content
        }
        
        throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No assistant message found in response"])
    }
    
    private func parseChecklist(from text: String) -> [Models.Checklist]? {
        print("CHECKLIST DEBUG: Attempting to parse checklist from: \(text)")
        
        if let data = text.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let checklistData = json["checklist_data"] as? [String: [String: Any]] {
                    
                    print("CHECKLIST DEBUG: Found structured checklist format with groups")
                    var allChecklists: [Models.Checklist] = []
                    
                    // Process each group
                    for (groupKey, groupData) in checklistData {
                        // Only create a group if we have a valid name
                        let groupName = groupData["name"] as? String
                        let group: Models.ItemGroup? = groupName?.isEmpty == false ? Models.ItemGroup(id: UUID(), title: groupName!, items: [:]) : nil
                        
                        // Process dates within the group
                        if let dates = groupData["dates"] as? [String: [String: Any]] {
                            for (dateString, dateData) in dates {
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "yyyy-MM-dd"
                                
                                if let date = dateFormatter.date(from: dateString),
                                   let items = dateData["items"] as? [[String: Any]] {
                                    
                                    let notes = dateData["notes"] as? String ?? ""
                                    var checklistItems: [Models.ChecklistItem] = []
                                    
                                    // Process each item
                                    for itemData in items {
                                        if let title = itemData["title"] as? String {
                                            // Parse notification time if present
                                            var notificationDate: Date? = nil
                                            if let notificationTime = itemData["notification"] as? String,
                                               notificationTime != "null" {
                                                let timeFormatter = DateFormatter()
                                                timeFormatter.dateFormat = "HH:mm"
                                                if let time = timeFormatter.date(from: notificationTime) {
                                                    let calendar = Calendar.current
                                                    let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                                                    notificationDate = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                                                  minute: timeComponents.minute ?? 0,
                                                                                  second: 0,
                                                                                  of: date)
                                                }
                                            }
                                            
                                            // Parse subitems if present
                                            var subitems: [Models.SubItem] = []
                                            if let subitemsData = itemData["subitems"] as? [[String: Any]] {
                                                for subitemData in subitemsData {
                                                    if let subitemTitle = subitemData["title"] as? String {
                                                        subitems.append(Models.SubItem(
                                                            title: subitemTitle,
                                                            isCompleted: false
                                                        ))
                                                    }
                                                }
                                            }
                                            
                                            // Create the main checklist item
                                            checklistItems.append(Models.ChecklistItem(
                                                title: title,
                                                date: date,
                                                isCompleted: false,
                                                notification: notificationDate,
                                                group: group,
                                                subItems: subitems
                                            ))
                                        }
                                    }
                                    
                                    // Create and add the checklist for this date
                                    let checklist = Models.Checklist(
                                        id: UUID(),
                                        date: date,
                                        items: checklistItems,
                                        notes: notes
                                    )
                                    
                                    allChecklists.append(checklist)
                                    print("CHECKLIST DEBUG: Added checklist for group '\(groupName ?? "unnamed")' date: \(dateString)")
                                }
                            }
                        }
                    }
                    
                    if !allChecklists.isEmpty {
                        print("CHECKLIST DEBUG: Successfully parsed \(allChecklists.count) checklists")
                        return allChecklists
                    }
                }
            } catch {
                print("CHECKLIST DEBUG: Error parsing JSON: \(error)")
            }
        }
        
        print("CHECKLIST DEBUG: Failed to parse checklist data")
        return nil
    }
    
    // MARK: - Firestore Listeners
    
    /// Set up a real-time listener for a message task
    /// - Parameter taskId: The task ID to listen for
    private func setupMessageTaskListener(taskId: String) {
        // First ensure we have Firebase authentication
        Task {
            guard await authManager.ensureFirebaseAuth() else {
                print("MESSAGE DEBUG: Cannot set up listener - no Firebase authentication")
                return
            }
            
            // Use the enhanced FirestoreService which now tracks active listeners
            // The method will return false if a listener is already active for this task ID
            let listenerSetup = firestoreService.listenForMessageTask(taskId: taskId) { [weak self] status, data in
                guard let self = self else { return }
                
                
                if status == "completed", let data = data {
                    print("🔍 DEBUG: Firestore message task completed, data: \(data.keys)")
                    
                    // Update loading indicator based on listener status
                    // This will automatically hide if no listeners are active
                    Task { @MainActor in
                        self.chatViewModel.updateLoadingIndicator()
                    }
                    
                    // Check for response field, which contains the message content
                    if let response = data["response"] as? String {
                        print("🔍 DEBUG: Received response from Firestore: \(response.prefix(30))...")
                        
                        // Try to parse the response as JSON first
                        if let responseData = response.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                            
                            // Extract the actual message content
                            if let message = json["message"] as? String {
                                // Send only the message content to the chat UI
                                Task { @MainActor in
                                    self.notifyAllViewModels(message)
                                }
                            }
                            
                            // Check for checklist task ID in both the response JSON and the task data
                            if let checklistTaskId = json["checklist_task_id"] as? String ?? data["checklist_task_id"] as? String {
                                // Set up a listener for the checklist task
                                self.setupChecklistTaskListener(taskId: checklistTaskId)
                            }
                        } else {
                            print("🔍 DEBUG: About to call notifyAllViewModels with raw response")
                            // If not JSON, treat the entire response as the message
                            Task { @MainActor in
                                self.notifyAllViewModels(response)
                            }
                        }
                    }
                    
                    // Listener cleanup is now handled by FirestoreService automatically
                } else if status == "failed", let data = data {
                    
                    // Update loading indicator based on listener status
                    // This will automatically hide if no listeners are active
                    Task { @MainActor in
                        self.chatViewModel.updateLoadingIndicator()
                    }
                    
                    // If we have error details, show them to the user
                    let errorDetails = (data["error"] as? String) ?? "Unknown error"
                    
                    // Add an error message to the chat
                    Task { @MainActor in
                        self.notifyAllViewModels("Sorry, I encountered an error: \(errorDetails)")
                    }
                    
                    // Listener cleanup is now handled by FirestoreService automatically
                }
            }
            
            if listenerSetup {
                // Only update our local tracking if a new listener was actually set up
                currentMessageTaskId = taskId
                
                // Update the loading indicator since we just set up a listener
                Task { @MainActor in
                    self.chatViewModel.updateLoadingIndicator()
                }
            }
        }
    }
    
    /// Set up a real-time listener for a checklist task
    /// - Parameter taskId: The task ID to listen for
    private func setupChecklistTaskListener(taskId: String) {
        // First ensure we have Firebase authentication
        Task {
            guard await authManager.ensureFirebaseAuth() else {
                print("CHECKLIST DEBUG: Cannot set up listener - no Firebase authentication")
                return
            }
            
            // Use the enhanced FirestoreService which now tracks active listeners
            let listenerSetup = firestoreService.listenForChecklistTask(taskId: taskId) { [weak self] status, data in
                guard let self = self else { return }
                
                if status == "completed", let data = data {
                    // Update loading indicator based on listener status
                    Task { @MainActor in
                        self.chatViewModel.updateLoadingIndicator()
                    }
                    
                    // First check for a direct response field
                    if let response = data["response"] as? String {
                        // Try to parse the response as JSON
                        if let responseData = response.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                           let message = json["message"] as? String {
                            // Send the parsed message to the chat
                            Task { @MainActor in
                                self.notifyAllViewModels(message)
                            }
                        } else {
                            // If not JSON or no message field, use the response as is
                            Task { @MainActor in
                                self.notifyAllViewModels(response)
                            }
                        }
                    }
                    // Then check for checklist data
                    else if let checklistData = data["checklist_data"] as? [String: Any] {
                        // Process the checklist data
                        if let jsonData = try? JSONSerialization.data(withJSONObject: checklistData),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            // Convert and save the checklist data
                            if let checklists = self.convertFirebaseChecklistToModel(checklistData: checklistData) {
                                Task { @MainActor in
                                    // Save the checklists
                                    self.saveOrAppendChecklists(checklists)
                                }
                            }
                        }
                    }
                } else if status == "failed", let data = data {
                    // Update loading indicator based on listener status
                    Task { @MainActor in
                        self.chatViewModel.updateLoadingIndicator()
                    }
                    
                    // If we have error details, show them to the user
                    let errorDetails = (data["error"] as? String) ?? "Unknown error"
                    Task { @MainActor in
                        self.notifyAllViewModels("Sorry, I encountered an error processing the checklist: \(errorDetails)")
                    }
                }
            }
            
            if listenerSetup {
                // Only update our local tracking if a new listener was actually set up
                currentChecklistTaskId = taskId
                
                // Update the loading indicator since we just set up a listener
                Task { @MainActor in
                    self.chatViewModel.updateLoadingIndicator()
                }
            }
        }
    }
    
    // Helper method to format a date for display
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    /// Clean up all listeners when the service is no longer needed
    func cleanup() {
        // No need to manually remove specific listeners - just use the FirestoreService method
        firestoreService.removeAllMessageListeners()
        
        // Reset our task ID tracking
        currentMessageTaskId = nil
        currentChecklistTaskId = nil
    }

    // MARK: - Firebase Checklist Conversion

    /// Converts a Firebase checklist JSON structure to a local model Checklist
    /// - Parameter checklistData: The raw checklist data from Firebase
    /// - Returns: A Models.Checklist object or nil if the data can't be parsed
    func convertFirebaseChecklistToModel(checklistData: [String: Any]) -> [Models.Checklist]? {
        print("CHECKLIST DEBUG: Converting Firebase checklist data to model: \(checklistData)")
        
        // Verify we have data to process
        guard !checklistData.isEmpty else {
            print("CHECKLIST DEBUG: Empty checklist data received")
            return nil
        }
        
        // First, create a dictionary to store the group information
        var groupsByKey: [String: (UUID, String)] = [:]
        
        // Create an array to hold all checklists
        var allChecklists: [Models.Checklist] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // PHASE 1: Extract group information from checklist data
        for (groupKey, groupData) in checklistData {
            print("CHECKLIST DEBUG: Processing group: \(groupKey)")
            
            // Get the group name if available
            if let groupData = groupData as? [String: Any],
               let groupName = groupData["name"] as? String,
               !groupName.isEmpty {
                
                // Create a UUID for the group
                let groupId = UUID()
                
                // Store group info for later use - we'll create the actual group later
                groupsByKey[groupKey] = (groupId, groupName)
                
            }
        }
        
        // PHASE 2: Create checklists and items, using the group info
        for (groupKey, groupData) in checklistData {
            if let groupData = groupData as? [String: Any] {
                // Find the corresponding group info
                let groupInfo = groupsByKey[groupKey]
                var group: Models.ItemGroup? = nil
                
                if let (groupId, groupTitle) = groupInfo {
                    // Create a temporary group object for item creation
                    // We'll handle the actual GroupStore registration separately
                    group = Models.ItemGroup(id: groupId, title: groupTitle, items: [:])
                }
                
                // Process dates within the group
                if let dates = groupData["dates"] as? [String: [String: Any]] {
                    for (dateString, dateData) in dates {
                        // Skip any keys that aren't date strings
                        guard dateFormatter.date(from: dateString) != nil else {
                            continue
                        }
                        
                        // Parse the date
                        guard let date = dateFormatter.date(from: dateString) else {
                            continue
                        }
                        
                        // Get the notes from the checklist
                        let notes = (dateData["notes"] as? String) ?? ""
                        
                        // Parse the items array
                        var checklistItems: [Models.ChecklistItem] = []
                        if let items = dateData["items"] as? [[String: Any]] {
                            for itemData in items {
                                if let title = itemData["title"] as? String {
                                    // Parse notification time if present
                                    var notificationDate: Date? = nil
                                    if let notificationTime = itemData["notification"] as? String, notificationTime != "null" {
                                        // Combine the date with the time
                                        let timeFormatter = DateFormatter()
                                        timeFormatter.dateFormat = "HH:mm"
                                        if let time = timeFormatter.date(from: notificationTime) {
                                            let calendar = Calendar.current
                                            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                                            let hour = timeComponents.hour ?? 0
                                            let minute = timeComponents.minute ?? 0
                                            
                                            notificationDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
                                        }
                                    }
                                    
                                    // Parse subitems if present
                                    var subitems: [Models.SubItem] = []
                                    if let subitemsData = itemData["subitems"] as? [[String: Any]] {
                                        for subitemData in subitemsData {
                                            if let subitemTitle = subitemData["title"] as? String {
                                                subitems.append(Models.SubItem(
                                                    title: subitemTitle,
                                                    isCompleted: false
                                                ))
                                            }
                                        }
                                    }
                                    
                                    // Create the checklist item with the group
                                    checklistItems.append(Models.ChecklistItem(
                                        title: title,
                                        date: date,
                                        isCompleted: false,
                                        notification: notificationDate,
                                        group: group,
                                        subItems: subitems
                                    ))
                                    
                                    print("CHECKLIST DEBUG: Added item: \(title)" + (group != nil ? " with group: \(group!.title) (ID: \(group!.id))" : " without group"))
                                }
                            }
                        }
                        
                        // Create and add the checklist
                        let checklist = Models.Checklist(
                            id: UUID(),
                            date: date,
                            items: checklistItems,
                            notes: notes
                        )
                        
                        allChecklists.append(checklist)
                        print("CHECKLIST DEBUG: Created checklist for \(dateString) with \(checklistItems.count) items" + (checklistItems.filter { $0.group != nil }.count > 0 ? " (\(checklistItems.filter { $0.group != nil }.count) with groups)" : "") + " and notes: \(notes)")
                    }
                }
            }
        }
        
        // PHASE 3: Create all groups in GroupStore on the main actor
        // We'll do this in saveOrAppendChecklists which is already @MainActor isolated
        
        print("CHECKLIST DEBUG: Processed \(allChecklists.count) checklists in total with \(groupsByKey.count) groups")
        
        // Store group info for later use in saveOrAppendChecklists
        return allChecklists.isEmpty ? nil : allChecklists
    }

    // MARK: - Adding Messages to Chat
    
    /// Add a simple text message from the assistant to the chat
    /// This method follows the exact same pattern as ChatViewModel.addMessageAndNotify:
    /// 1. Creates a proper ChatMessage entity using ChatMessage.create
    /// 2. Adds it to the main chat history
    /// 3. Saves the chat history through the persistence service
    /// 4. Posts a notification via NotificationCenter to update the UI
    /// This ensures messages appear properly in the chat interface and are persisted in Core Data
    @MainActor
    private func addAssistantMessage(_ message: String) {
        print("🔍 DEBUG: addAssistantMessage called with: \(message.prefix(30))...")
        
        let context = persistenceService.viewContext
        
        // Check if the message is a JSON string and extract just the message content
        var messageContent = message
        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let extractedMessage = json["message"] as? String {
            messageContent = extractedMessage
        }
        
        // Log the message being added to chat history
        print("💬 ADDING MESSAGE TO CHAT: \(messageContent)")
        print("💬 CHAT MESSAGE SIZE: \(messageContent.utf8.count) bytes")
        
        // Create a new message entity using the proper ChatMessage.create method
        let chatMessage = ChatMessage.create(
            in: context,
            role: MessageRoles.assistant,
            content: messageContent
        )
        
        // Get the main chat history
        Task {
            if let mainHistory = await persistenceService.loadMainChatHistory() {
                // Add message to history
                mainHistory.addMessage(chatMessage)
                
                // Save the chat history
                persistenceService.saveChatHistory(mainHistory)
                
                // Notify that a message was added
                DispatchQueue.main.async {
                    print("🔍 DEBUG: Posting ChatMessageAdded notification")
                    NotificationCenter.default.post(
                        name: Notification.Name("ChatMessageAdded"),
                        object: nil,
                        userInfo: [
                            "role": MessageRoles.assistant
                        ]
                    )
                }
            } else {
                // Create a new main chat history if it doesn't exist
                let newHistory = ChatHistory.create(in: context, isMainHistory: true)
                newHistory.addMessage(chatMessage)
                persistenceService.saveChatHistory(newHistory)
                
                // Notify that a message was added
                DispatchQueue.main.async {
                    print("🔍 DEBUG: Posting ChatMessageAdded notification (new history)")
                    NotificationCenter.default.post(
                        name: Notification.Name("ChatMessageAdded"),
                        object: nil,
                        userInfo: [
                            "role": MessageRoles.assistant
                        ]
                    )
                }
            }
            
            // Also send the message through the callback for real-time updates
            self.notifyAllViewModels("""
            {"message": "\(messageContent)"}
            """)
        }
    }

    @MainActor
    private func saveOrAppendChecklists(_ checklists: [Models.Checklist]) {
        let persistence = ChecklistPersistence.shared
        let groupStore = GroupStore.shared
        var updatedDates: [Date] = []
        var totalItemsAdded = 0
        
        // STEP 1: Create all required groups in GroupStore
        var groupsToCreate: [UUID: String] = [:]
        
        // Extract all unique groups from items
        for checklist in checklists {
            for item in checklist.items {
                if let group = item.group {
                    groupsToCreate[group.id] = group.title
                }
            }
        }
        
        // Create all groups first (using @MainActor-isolated GroupStore)
        for (groupId, groupTitle) in groupsToCreate {
            print("GROUP DEBUG: Creating group in GroupStore - ID: \(groupId), Title: \(groupTitle)")
            
            // Use the new method to create a group with a specific ID
            let createdGroup = groupStore.createGroupWithID(id: groupId, title: groupTitle)
            print("GROUP DEBUG: Group created/retrieved in GroupStore - ID: \(createdGroup.id), Title: \(createdGroup.title)")
        }
        
        // STEP 2: Save all the checklists
        for checklist in checklists {
            // Check if a checklist already exists for this date
            if let existingChecklist = persistence.loadChecklist(for: checklist.date) {
                print("CHECKLIST DEBUG: Found existing checklist for date: \(checklist.date)")
                
                // Create an updated checklist by appending the new items
                var updatedChecklist = existingChecklist
                updatedChecklist.items.append(contentsOf: checklist.items)
                totalItemsAdded += checklist.items.count
                
                // Update notes if the new checklist has notes
                if !checklist.notes.isEmpty {
                    if !updatedChecklist.notes.isEmpty {
                        updatedChecklist.notes += "\n\n" + checklist.notes
                    } else {
                        updatedChecklist.notes = checklist.notes
                    }
                }
                
                // Save the updated checklist
                persistence.saveChecklist(updatedChecklist)
                print("CHECKLIST DEBUG: Updated existing checklist for date: \(checklist.date), now with \(updatedChecklist.items.count) items")
                
                updatedDates.append(checklist.date)
            } else {
                // No existing checklist, save the new one
                persistence.saveChecklist(checklist)
                totalItemsAdded += checklist.items.count
                print("CHECKLIST DEBUG: Saved new checklist to persistence for date: \(checklist.date)")
                
                updatedDates.append(checklist.date)
            }
        }
        
        // Ensure GroupStore is up-to-date before notifying UI
        groupStore.loadGroups {
            // Now that groups are loaded, send notifications for each date
            for date in updatedDates {
                NotificationCenter.default.post(name: Notification.Name("NewChecklistAvailable"), object: date)
            }
            // After a short delay, add the simple "Done." message properly to the chat
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task { @MainActor in
                    // Properly add the confirmation message to chat history
                    self.notifyAllViewModels("Done.")
                }
            }
        }
    }

    // Add this method before the setupMessageTaskListener method
    func sendCheckin(checklist: [String: Any]) async throws -> String {
        // Prepare the request data
        let requestData: [String: Any]
        
        // If the checklist contains a "checklists" key, it's already an array of checklists
        if let nestedChecklists = checklist["checklists"] as? [[String: Any]] {
            requestData = [
                "checklists": nestedChecklists,  // Use the array directly
                "current_time": Date().ISO8601Format(),
                "alfred_personality": String(UserSettings.shared.alfredPersonality),
                "user_objectives": UserSettings.shared.objectives
            ]
        } else {
            // If it's a single checklist, wrap it in an array
            requestData = [
                "checklists": [checklist],
                "current_time": Date().ISO8601Format(),
                "alfred_personality": String(UserSettings.shared.alfredPersonality),
                "user_objectives": UserSettings.shared.objectives
            ]
        }
        
        // Convert request data to JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData) else {
            throw ChatServiceError.invalidRequest
        }
        
        // Print the size of the checkin data being sent
        print("📊 CHECKIN DATA SIZE: \(jsonData.count) bytes")
        
        // Create the request
        let url = URL(string: "\(serverBaseURL)/chat/checkin")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authManager.getToken() ?? "")", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        // Send the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response status
        guard let httpResponse = response as? HTTPURLResponse,
              (httpResponse.statusCode == 200 || httpResponse.statusCode == 201) else {
            if let errorString = String(data: data, encoding: .utf8) {
                throw ChatServiceError.invalidResponse("Failed to send checkin: \(errorString)")
            }
            throw ChatServiceError.invalidResponse("Failed to send checkin")
        }
        
        // Parse response to get task ID
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let taskId = response["id"] as? String else {
            throw ChatServiceError.invalidResponse("Failed to get task ID from response")
        }
        
        return taskId
    }

    // Add new struct for structured check-in response
    struct CheckInResponse {
        let summary: String
        let analysis: String
        let response: String
    }

    // Add new method to handle check-ins end-to-end
    public func handleCheckin(checklist: [String: Any]) async throws -> (String, String, String) {
        // 1. Send check-in and get task ID
        let taskId = try await sendCheckin(checklist: checklist)
        
        // 2. Set up listener and handle response internally
        var responseMessage: String? = nil
        let semaphore = DispatchSemaphore(value: 0)
        
        firestoreService.listenForCheckinTask(taskId: taskId) { [weak self] status, data in
            if status == "completed", let data = data {
                if let response = data["response"] as? String {
                    responseMessage = response
                } else if status == "failed", let error = data["error"] as? String {
                    responseMessage = "Sorry, I encountered an error processing your check-in: \(error)"
                }
                semaphore.signal()
            }
        }
        
        // Wait for the response
        semaphore.wait()
        
        guard let message = responseMessage else {
            throw ChatServiceError.invalidResponse("No response received")
        }
        
        // Try to parse as JSON
        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // If we have all three fields, use them
            if let summary = json["summary"] as? String,
               let analysis = json["analysis"] as? String,
               let response = json["response"] as? String {
                return (summary, analysis, response)
            }
        }
        
        // Fallback to using the message as the response with default values for summary and analysis
        return ("Daily Check-in Report", "Check-in completed", message)
    }
}

// MARK: - Server API Response Models

struct ChatResponse: Codable {
    let id: String
    let title: String
    let messages: [MessageResponse]?
}

struct MessageResponse: Codable {
    let id: String
    let role: String
    let content: String
    let sequence: Int
}

