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
        
        // Get the last user message
        guard let lastMessage = messages.last(where: { $0.role == MessageRoles.user }) else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No user message to send"])
        }
        
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
        
        // Print the size of the outgoing message
        print("📤 OUTGOING MESSAGE SIZE: \(bodyData.count) bytes")
        
        // Print the entire outgoing payload for debugging
        if let payloadString = String(data: bodyData, encoding: .utf8) {
            print("📤 OUTGOING PAYLOAD: \(payloadString)")
        }
        
        do {
            // Use NetworkManager instead of direct URLSession to handle token expiration
            let data = try await NetworkManager.shared.makeAuthenticatedRequest(
                endpoint: "/v1/chat/messages",
                method: "POST",
                body: bodyData,
                contentType: "application/json"
            )
            
            // Print the size of the incoming response
            print("📥 INCOMING RESPONSE SIZE: \(data.count) bytes")
            
            // Log the raw response data
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("RAW SERVER RESPONSE: \(rawResponse)")
            }
            
            // Try parsing the optimized response format
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for the streamlined format with "response" and optional "metadata"
                if let responseData = json["response"] as? [String: Any] {
                    // Check for metadata with message_id
                    if let metadata = json["metadata"] as? [String: Any] {
                        if let messageId = metadata["message_id"] as? String {
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
        } catch {
            print("ERROR SENDING MESSAGE: \(error.localizedDescription)")
            
            // Create a more user-friendly error message
            var errorMessage = "Unable to send message. Please try again later."
            
            if let networkError = error as? NetworkError {
                switch networkError {
                case .unauthorized:
                    errorMessage = "You are not authorized. Please log in again."
                case .httpError(let statusCode, _):
                    errorMessage = "Server error (code: \(statusCode)). Please try again later."
                case .requestFailed(let underlyingError):
                    errorMessage = "Network error: \(underlyingError.localizedDescription)"
                default:
                    errorMessage = "Unexpected error occurred. Please try again."
                }
            }
            
            throw NSError(domain: "ChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
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
        request.timeoutInterval = 10
        
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
        
        // Print raw response for standard messages
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("📥 RAW MESSAGE RESPONSE: \(rawResponse)")
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
        request.timeoutInterval = 10 // 10 second timeout for request
        
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
    
    // Add this struct at the top of the file with other structs
    struct StandardResponse: Codable {
        let response: ResponseContent
        let metadata: ResponseMetadata
        
        struct ResponseContent: Codable {
            let content: String
            let type: String?
            let data: [String: String]?  // Changed from [String: Any] to [String: String]
            
            private enum CodingKeys: String, CodingKey {
                case content, type, data
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                content = try container.decode(String.self, forKey: .content)
                type = try container.decodeIfPresent(String.self, forKey: .type)
                data = try container.decodeIfPresent([String: String].self, forKey: .data)
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(content, forKey: .content)
                try container.encodeIfPresent(type, forKey: .type)
                try container.encodeIfPresent(data, forKey: .data)
            }
        }
        
        struct ResponseMetadata: Codable {
            let message_id: String
            let status: String
            let timestamp: String
        }
    }

    private func parseStandardResponse(_ data: Data) -> StandardResponse? {
        do {
            // First check if it's valid JSON
            if let _ = try? JSONSerialization.jsonObject(with: data) {
                let decoder = JSONDecoder()
                return try decoder.decode(StandardResponse.self, from: data)
            }
            return nil
        } catch {
            print("Error parsing standard response: \(error)")
            return nil
        }
    }

    private func handleResponse(_ data: Data) {
        // Print raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("📥 RAW SERVER RESPONSE: \(rawResponse)")
        }
        
        // First try to parse as JSON
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Print the complete JSON structure for debugging
            if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📥 COMPLETE RESPONSE STRUCTURE:\n\(jsonString)")
            }
            
            // Check for pending status response
            if let response = json["response"] as? [String: Any],
               let content = response["content"] as? String,
               let metadata = json["metadata"] as? [String: Any],
               let status = metadata["status"] as? String,
               status == "pending" {
                print("Received pending status response, waiting for completion...")
                return
            }
            
            // Check for checklist task response
            if let response = json["response"] as? [String: Any],
               let content = response["content"] as? String,
               let metadata = json["metadata"] as? [String: Any],
               let checklistId = metadata["checklist_id"] as? String {
                setupChecklistTaskListener(taskId: checklistId)
                notifyAllViewModels(content)
                return
            }
            
            // Try parsing as standard response
            if let response = parseStandardResponse(data) {
                switch response.response.type {
                case "checklist":
                    if let checklistTaskId = response.response.data?["checklist_task_id"] {
                        setupChecklistTaskListener(taskId: checklistTaskId)
                    }
                    notifyAllViewModels(response.response.content)
                    
                case "checkin":
                    if let checkinData = response.response.data {
                        notifyAllViewModels(response.response.content)
                    }
                    
                case "outline":
                    // Create a combined JSON structure with both response and outline
                    let combinedData: [String: Any] = [
                        "response": response.response.content,
                        "outline": response.response.data ?? [:]
                    ]
                    
                    if let jsonData = try? JSONSerialization.data(withJSONObject: combinedData),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        notifyAllViewModels(jsonString)
                    }
                    
                default: // "message" or nil
                    notifyAllViewModels(response.response.content)
                }
            }
        } else {
            // If JSON parsing fails, try to handle as plain text
            if let plainText = String(data: data, encoding: .utf8) {
                // Check if it's a simple message
                if !plainText.isEmpty {
                    notifyAllViewModels(plainText)
                    return
                }
            }
            
            // If all else fails, try legacy parsing
            handleLegacyResponse(data)
        }
    }

    private func handleLegacyResponse(_ data: Data) {
        // Existing legacy response handling code
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let responseData = json["response"] as? [String: Any] {
                if let content = responseData["content"] as? String {
                    notifyAllViewModels(content)
                }
            }
        }
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
        
        request.timeoutInterval = 10 // 10 second timeout for request
        
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
        handleResponse(data)
        return ""
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
        firestoreService.listenForMessageTask(taskId: taskId) { [weak self] status, data in
            if status == "completed", let data = data {
                // Print the complete Firestore document data for debugging
                if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("📥 FIRESTORE DOCUMENT DATA:\n\(jsonString)")
                }
                
                // Check if we have an outline
                if let outline = data["outline"] as? [String: Any] {
                    print("📥 FOUND OUTLINE DATA")
                    // Create a combined JSON structure with both response and outline
                    let combinedData: [String: Any] = [
                        "response": data["response"] as? String ?? "",
                        "outline": outline
                    ]
                    
                    if let jsonData = try? JSONSerialization.data(withJSONObject: combinedData),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        self?.notifyAllViewModels(jsonString)
                    }
                } else if let responseData = data["response"] as? Data {
                    self?.handleResponse(responseData)
                } else if let responseString = data["response"] as? String,
                          let responseData = responseString.data(using: .utf8) {
                    self?.handleResponse(responseData)
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
                    // Print raw response for checklist tasks
                    print("📥 RAW CHECKLIST TASK RESPONSE: \(data)")
                    
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
                            
                            // Create outline notes if outline data exists
                            var outlineNotes = ""
                            if let outlineData = data["outline_data"] as? [String: Any] {
                                print("OUTLINE DEBUG: Found outline data: \(outlineData)")
                                
                                // Add summary
                                if let summary = outlineData["summary"] as? String {
                                    outlineNotes += summary + "\n\n"
                                }
                                
                                // Add line items - fixed to handle different possible structures
                                if let lineItems = outlineData["line_item"] as? [Any] {
                                    print("OUTLINE DEBUG: Found line items: \(lineItems)")
                                    
                                    for item in lineItems {
                                        if let itemDict = item as? [String: Any], 
                                           let title = itemDict["title"] as? String {
                                            // Handle standard dictionary format with title key
                                            outlineNotes += "- " + title + "\n"
                                        } else if let itemString = item as? String {
                                            // Handle simple string format
                                            outlineNotes += "- " + itemString + "\n"
                                        } else {
                                            // Log for debugging if format is unexpected
                                            print("OUTLINE DEBUG: Unexpected line item format: \(item)")
                                        }
                                    }
                                } else {
                                    print("OUTLINE DEBUG: No line items found or unexpected format")
                                }
                                
                                print("OUTLINE DEBUG: Final notes: \(outlineNotes)")
                            }
                            
                            // Convert and save the checklist data, passing the outline notes
                            if let checklists = self.convertFirebaseChecklistToModel(
                                checklistData: checklistData, 
                                outlineNotes: outlineNotes
                            ) {
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
    /// - Parameters:
    ///   - checklistData: The raw checklist data from Firebase
    ///   - outlineNotes: Optional notes from outline data to include in group notes
    /// - Returns: A Models.Checklist object or nil if the data can't be parsed
    func convertFirebaseChecklistToModel(checklistData: [String: Any], outlineNotes: String = "") -> [Models.Checklist]? {
        print("CHECKLIST DEBUG: Converting Firebase checklist data to model: \(checklistData)")
        
        // Verify we have data to process
        guard !checklistData.isEmpty else {
            print("CHECKLIST DEBUG: Empty checklist data received")
            return nil
        }
        
        // First, create a dictionary to store the group information
        var groupsByKey: [String: (UUID, String, String)] = [:]  // Updated to include notes
        
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
                // Include the outline notes with the group info
                groupsByKey[groupKey] = (groupId, groupName, outlineNotes)
                
            }
        }
        
        // PHASE 2: Create checklists and items, using the group info
        for (groupKey, groupData) in checklistData {
            if let groupData = groupData as? [String: Any] {
                // Find the corresponding group info
                let groupInfo = groupsByKey[groupKey]
                var group: Models.ItemGroup? = nil
                
                if let (groupId, groupTitle, groupNotes) = groupInfo {
                    // Create a temporary group object for item creation
                    // Include the notes from the outline
                    group = Models.ItemGroup(id: groupId, title: groupTitle, items: [:], notes: groupNotes)
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
        var groupsToCreate: [UUID: (String, String)] = [:]  // Updated to include notes
        
        // Extract all unique groups from items
        for checklist in checklists {
            for item in checklist.items {
                if let group = item.group {
                    groupsToCreate[group.id] = (group.title, group.notes)
                }
            }
        }
        
        // Create all groups first (using @MainActor-isolated GroupStore)
        for (groupId, groupInfo) in groupsToCreate {
            let (groupTitle, groupNotes) = groupInfo
            print("GROUP DEBUG: Creating group in GroupStore - ID: \(groupId), Title: \(groupTitle)")
            
            // Use the new method to create a group with a specific ID and notes
            let createdGroup = groupStore.createGroupWithID(id: groupId, title: groupTitle, notes: groupNotes)
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
            DispatchQueue.main.asyncAfter(deadline: .now()) {
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
        
        do {
            // Use NetworkManager to handle token expiration automatically
            let data = try await NetworkManager.shared.makeAuthenticatedRequest(
                endpoint: "/v1/chat/checkin",
                method: "POST",
                body: jsonData
            )
            
            // Print raw response for check-ins
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("📥 RAW CHECKIN RESPONSE: \(rawResponse)")
            }
            
            // Parse response to get task ID
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = json["response"] as? [String: Any],
                  let taskId = response["id"] as? String else {
                throw ChatServiceError.invalidResponse("Failed to get task ID from response")
            }
            
            return taskId
        } catch {
            print("ERROR SENDING CHECKIN: \(error.localizedDescription)")
            
            // Create a more user-friendly error message
            var errorMessage = "Unable to send check-in. Please try again later."
            
            if let networkError = error as? NetworkError {
                switch networkError {
                case .unauthorized:
                    errorMessage = "You are not authorized. Please log in again."
                case .httpError(let statusCode, _):
                    errorMessage = "Server error (code: \(statusCode)). Please try again later."
                case .requestFailed(let underlyingError):
                    errorMessage = "Network error: \(underlyingError.localizedDescription)"
                default:
                    errorMessage = "Unexpected error occurred. Please try again."
                }
            }
            
            throw ChatServiceError.invalidResponse(errorMessage)
        }
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

    // Method to send an outline to create a checklist
    func sendOutline(_ outline: ChecklistOutline) async throws -> String {
        // Check for connectivity first
        guard checkConnectivity() else {
            throw NSError(domain: "ChatService", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet connection. Please check your network settings and try again."])
        }
        
        // Get current date and time
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        let currentTimeString = dateFormatter.string(from: currentDate)
        
        // Convert outline to dictionary
        let outlineDict: [String: Any] = [
            "summary": outline.summary ?? "",
            "period": outline.period ?? "",
            "start_date": outline.startDate?.ISO8601Format() ?? "",
            "end_date": outline.endDate?.ISO8601Format() ?? "",
            "line_item": outline.lineItem as? [String] ?? []
        ]
        
        // Create payload
        let payload: [String: Any] = [
            "outline": outlineDict,
            "current_time": currentTimeString
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        
        do {
            // Use NetworkManager to make the authenticated request
            let data = try await NetworkManager.shared.makeAuthenticatedRequest(
                endpoint: "/v1/chat/outlines",
                method: "POST",
                body: bodyData,
                contentType: "application/json"
            )
            
            // Print raw response for outlines
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("📥 RAW OUTLINE RESPONSE: \(rawResponse)")
            }
            
            // Parse the response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let metadata = json["metadata"] as? [String: Any],
               let taskId = metadata["task_id"] as? String {
                
                // Store the task ID
                self.currentChecklistTaskId = taskId
                
                // Set up a listener for this checklist task
                setupChecklistTaskListener(taskId: taskId)
                
                return taskId
            }
            
            throw NSError(domain: "ChatService", code: 400, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse server response"])
            
        } catch {
            print("ERROR SENDING OUTLINE: \(error.localizedDescription)")
            throw error
        }
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

