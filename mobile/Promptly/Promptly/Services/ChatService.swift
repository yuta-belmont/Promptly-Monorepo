import Foundation
import CoreData
import Firebase
import Network

final class ChatService {
    // Replace OpenAI endpoint with our server endpoint
    private let authManager = AuthManager.shared
    private let serverBaseURL = "http://192.168.1.166:8080/api/v1"
    private let persistenceService = ChatPersistenceService.shared
    private let firestoreService = FirestoreService.shared
    
    // Network path monitor for connectivity checking
    private let networkMonitor = NWPathMonitor()
    private var isConnected = true
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    // Track the current chat ID on the server
    private var currentChatId: String?
    // Track the current checklist task ID
    private var currentChecklistTaskId: String?
    
    // Callback for message updates
    var onMessageUpdate: ((String) -> Void)?
    
    init() {
        // Set up network path monitor
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            print("Network connection status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // Check if we have an internet connection
    func checkConnectivity() -> Bool {
        return isConnected
    }

    func sendMessage(messages: [ChatMessage]) async throws -> (ChatMessage?, [Models.ChecklistItem]?) {
        print("ChatService: Sending \(messages.count) messages to server")
        
        // Check for connectivity first
        guard checkConnectivity() else {
            throw NSError(domain: "ChatService", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet connection. Please check your network settings and try again."])
        }
        
        // Print all messages before sending
        print("BEFORE SENDING - All messages:")
        for (index, msg) in messages.enumerated() {
            print("[\(index)] Role: \(msg.role), Content: \(msg.content)")
        }
        
        guard let token = authManager.getToken() else {
            throw NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // If we don't have a chat ID yet, create a new chat
        if currentChatId == nil {
            currentChatId = try await createNewChat(token: token)
        }
        
        guard let chatId = currentChatId else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to create chat"])
        }
        
        // Get the last user message
        guard let lastMessage = messages.last, lastMessage.role == MessageRoles.user else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No user message to send"])
        }
        
        // Send the message to the server
        let responseMessage = try await sendMessageToServer(chatId: chatId, content: lastMessage.content, token: token)
        
        // Try to parse the response as JSON
        var messageContent: String = responseMessage
        var checklistItems: [Models.ChecklistItem]? = nil
        
        // Check if the response is structured as JSON
        if let data = responseMessage.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            // Extract the message content if it exists
            if let message = json["message"] as? String {
                messageContent = message
            }
            
            // Check for checklist task ID
            if let checklistTaskId = json["checklist_task_id"] as? String {
                print("CHECKLIST DEBUG: Found checklist_task_id: \(checklistTaskId)")
                
                // Store the task ID
                self.currentChecklistTaskId = checklistTaskId
                
                // Set up a listener for this task
                setupChecklistTaskListener(taskId: checklistTaskId)
                
                print("Set up listener for checklist task: \(checklistTaskId)")
            } else {
                print("CHECKLIST DEBUG: No checklist_task_id found in response")
            }
        }
        
        // Create a new ChatMessage using Core Data with NSEntityDescription
        let context = persistenceService.viewContext
        
        // Use NSEntityDescription.insertNewObject instead of ChatMessage.create
        let aiResponse = NSEntityDescription.insertNewObject(forEntityName: "ChatMessage", into: context) as! ChatMessage
        aiResponse.id = UUID()
        aiResponse.role = MessageRoles.assistant
        aiResponse.content = messageContent
        aiResponse.timestamp = Date()
        
        return (aiResponse, checklistItems)
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
    
    private func sendMessageToServer(chatId: String, content: String, token: String) async throws -> String {
        let url = URL(string: "\(serverBaseURL)/chat/\(chatId)/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15 // 15 second timeout for request
        
        // We don't need to specify sequence as the server will handle that
        let body: [String: Any] = [
            "content": content
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Log the raw response data
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("RAW SERVER RESPONSE: \(rawResponse)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                          userInfo: [NSLocalizedDescriptionKey: "Failed to send message: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        // Parse the response to get the assistant's message
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        // Print all messages from server response
        print("AFTER SENDING - Server response messages:")
        for (index, msg) in messages.enumerated() {
            let role = msg["role"] as? String ?? "unknown"
            let content = msg["content"] as? String ?? "no content"
            print("[\(index)] Role: \(role), Content: \(content)")
        }
        
        // Find the assistant's message (should be the last one)
        if let assistantMessage = messages.last(where: { ($0["role"] as? String) == "assistant" }),
           let content = assistantMessage["content"] as? String {
            
            print("ASSISTANT MESSAGE CONTENT (PRE-PARSING): \(content)")
            
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
    
    private func parseChecklist(from text: String) -> [Models.ChecklistItem]? {
        print("CHECKLIST DEBUG: Attempting to parse checklist from: \(text)")
        
        // Try to parse as JSON first
        if let data = text.data(using: .utf8) {
            do {
                // Try to parse as JSON
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("CHECKLIST DEBUG: Successfully parsed text as JSON")
                    
                    // Check if this is our structured response format
                    if let message = json["message"] as? String,
                       let checklists = json["checklists"] as? [String: [String: Any]] {
                        
                        print("CHECKLIST DEBUG: Found structured checklist format with message and checklists")
                        var allItems: [Models.ChecklistItem] = []
                        
                        // Process each checklist
                        for (dateKey, checklistData) in checklists {
                            // Parse the date from the key
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd"
                            if let date = dateFormatter.date(from: dateKey),
                               let items = checklistData["items"] as? [[String: Any]] {
                                
                                print("CHECKLIST DEBUG: Processing checklist for date: \(dateKey) with \(items.count) items")
                                
                                // Process each item in the checklist
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
                                                notificationDate = calendar.date(bySettingHour: timeComponents.hour ?? 0, 
                                                                                minute: timeComponents.minute ?? 0, 
                                                                                second: 0, 
                                                                                of: date)
                                            }
                                        }
                                        
                                        // Create the checklist item
                                        allItems.append(Models.ChecklistItem(
                                            title: title,
                                            date: date,
                                            isCompleted: false,
                                            notification: notificationDate,
                                            group: nil
                                        ))
                                        
                                        print("CHECKLIST DEBUG: Added item: \(title)")
                                    }
                                }
                            }
                        }
                        
                        if !allItems.isEmpty {
                            print("CHECKLIST DEBUG: Successfully parsed \(allItems.count) checklist items")
                            return allItems
                        } else {
                            print("CHECKLIST DEBUG: No checklist items found in structured format")
                        }
                    } else {
                        print("CHECKLIST DEBUG: JSON does not contain expected 'message' and 'checklists' fields")
                    }
                }
            } catch {
                print("CHECKLIST DEBUG: Error parsing JSON: \(error)")
            }
        }
        
        print("CHECKLIST DEBUG: Falling back to text parsing")
        
        // Fallback to the original text parsing if JSON parsing fails
        let lines = text.components(separatedBy: "\n")
        var checklistItems: [Models.ChecklistItem] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                let taskText = trimmed.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                checklistItems.append(Models.ChecklistItem(
                    title: String(taskText), 
                    date: Date(),
                    isCompleted: false,
                    notification: nil,
                    group: nil
                ))
                
                print("CHECKLIST DEBUG: Added item from text parsing: \(taskText)")
            }
        }
        
        if checklistItems.isEmpty {
            print("CHECKLIST DEBUG: No checklist items found in text format")
            return nil
        } else {
            print("CHECKLIST DEBUG: Successfully parsed \(checklistItems.count) checklist items from text")
            return checklistItems
        }
    }
    
    // MARK: - Firestore Listeners
    
    /// Set up a real-time listener for a checklist task
    /// - Parameter taskId: The task ID to listen for
    private func setupChecklistTaskListener(taskId: String) {
        print("CHECKLIST DEBUG: Setting up listener for checklist task: \(taskId)")
        
        firestoreService.listenForChecklistTask(taskId: taskId) { [weak self] status, data in
            guard let self = self else { return }
            
            print("CHECKLIST DEBUG: Checklist task status updated: \(status)")
            print("CHECKLIST DEBUG: Checklist task data: \(String(describing: data))")
            
            if status == "completed", let data = data {
                print("CHECKLIST DEBUG: Checklist task completed!")
                
                // Log all data fields to help debug
                for (key, value) in data {
                    print("CHECKLIST DEBUG: Field \(key): \(value)")
                }
                
                // Check for checklist_data field, which contains the structured checklist
                if let checklistData = data["checklist_data"] as? [String: Any] {
                    print("CHECKLIST DEBUG: Found checklist_data: \(checklistData)")
                    
                    // Convert the Firebase checklist data to our app's model
                    if let modelChecklist = self.convertFirebaseChecklistToModel(checklistData: checklistData) {
                        print("CHECKLIST DEBUG: Successfully converted checklist with \(modelChecklist.items.count) items")
                        
                        // Save the checklist to persistence
                        Task { @MainActor in
                            self.saveOrAppendChecklist(modelChecklist)
                        }
                    } else {
                        print("CHECKLIST DEBUG: Failed to convert checklist data to model")
                        
                        // Provide an error message
                        let errorMessage = """
                        {"message": "Failed to create checklist. The data format was unexpected."}
                        """
                        self.onMessageUpdate?(errorMessage)
                    }
                } else if let content = data["generated_content"] as? String {
                    // This is the old format - try to parse it as a JSON string
                    print("CHECKLIST DEBUG: Found generated_content: \(content)")
                    
                    // Try to parse the content as JSON
                    if let contentData = content.data(using: .utf8),
                       let jsonData = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] {
                        
                        // Look for a date key pattern (YYYY-MM-DD) directly in the top level
                        let dateKeys = jsonData.keys.filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
                        
                        if !dateKeys.isEmpty {
                            // This looks like a direct checklist format with date as top level key
                            print("CHECKLIST DEBUG: Found direct checklist format with date at top level")
                            
                            // Send it directly to the converter
                            if let modelChecklist = self.convertFirebaseChecklistToModel(checklistData: jsonData) {
                                print("CHECKLIST DEBUG: Successfully converted direct checklist with \(modelChecklist.items.count) items")
                                
                                // Save the checklist to persistence
                                Task { @MainActor in
                                    self.saveOrAppendChecklist(modelChecklist)
                                }
                            } else {
                                print("CHECKLIST DEBUG: Failed to convert direct checklist data to model")
                                self.onMessageUpdate?("""
                                {"message": "\(content.replacingOccurrences(of: "\"", with: "\\\""))"}
                                """)
                            }
                        }
                        else if let checklistData = jsonData["checklists"] as? [String: Any] {
                            // Original code path for the wrapped format
                            // Convert the Firebase checklist data to our app's model
                            if let modelChecklist = self.convertFirebaseChecklistToModel(checklistData: checklistData) {
                                print("CHECKLIST DEBUG: Successfully converted checklist with \(modelChecklist.items.count) items")
                                
                                // Save the checklist to persistence
                                Task { @MainActor in
                                    self.saveOrAppendChecklist(modelChecklist)
                                }
                            } else {
                                // Fallback: If we can't parse the structured data, just show the content as a regular message
                                print("CHECKLIST DEBUG: Falling back to showing raw content")
                                self.onMessageUpdate?("""
                                {"message": "\(content.replacingOccurrences(of: "\"", with: "\\\""))"}
                                """)
                            }
                        } else {
                            // Fallback: Just show the content as a regular message
                            print("CHECKLIST DEBUG: Falling back to showing raw content")
                            self.onMessageUpdate?("""
                            {"message": "\(content.replacingOccurrences(of: "\"", with: "\\\""))"}
                            """)
                        }
                    } else {
                        // Fallback: Just show the content as a regular message
                        print("CHECKLIST DEBUG: Falling back to showing raw content")
                        self.onMessageUpdate?("""
                        {"message": "\(content.replacingOccurrences(of: "\"", with: "\\\""))"}
                        """)
                    }
                } else {
                    print("CHECKLIST DEBUG: No checklist_data or generated_content found in task data")
                    let errorMessage = """
                    {"message": "Failed to create checklist. No data was received from the server."}
                    """
                    self.onMessageUpdate?(errorMessage)
                }
                
                // Remove the listener since we don't need it anymore
                self.firestoreService.removeMessageListener(for: "checklist_task_\(taskId)")
                self.currentChecklistTaskId = nil
            } else if status == "failed" {
                print("CHECKLIST DEBUG: Checklist task failed")
                
                // If we have error details, show them to the user
                let errorDetails = (data?["error"] as? String) ?? "Unknown error"
                let errorMessage = """
                {"message": "Failed to create checklist: \(errorDetails)"}
                """
                
                DispatchQueue.main.async {
                    self.onMessageUpdate?(errorMessage)
                }
                
                // Remove the listener since we don't need it anymore
                self.firestoreService.removeMessageListener(for: "checklist_task_\(taskId)")
                self.currentChecklistTaskId = nil
            }
        }
        
        currentChecklistTaskId = taskId
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
        firestoreService.removeAllMessageListeners()
    }

    // MARK: - Firebase Checklist Conversion

    /// Converts a Firebase checklist JSON structure to a local model Checklist
    /// - Parameter checklistData: The raw checklist data from Firebase
    /// - Returns: A Models.Checklist object or nil if the data can't be parsed
    func convertFirebaseChecklistToModel(checklistData: [String: Any]) -> Models.Checklist? {
        print("CHECKLIST DEBUG: Converting Firebase checklist data to model: \(checklistData)")
        
        // Our example structure:
        // ["2025-03-17": {
        //     items =     (
        //               {
        //             notification = "15:00";
        //             title = "Write down your top goal for the week and break it into actionable steps";
        //         }
        //     );
        //     notes = "Focus on setting a clear intention for the day. Remember: 'Well begun is half done.' Use this opportunity to start the week off strong and make meaningful progress.";
        // }]
        
        // Verify we have data to process
        guard !checklistData.isEmpty else {
            print("CHECKLIST DEBUG: Empty checklist data received")
            return nil
        }
        
        // First key should be the date
        guard let dateString = checklistData.keys.first,
              let checklistInfo = checklistData[dateString] as? [String: Any] else {
            print("CHECKLIST DEBUG: Invalid checklist format, missing date key or checklist info")
            return nil
        }
        
        // Parse the date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = dateFormatter.date(from: dateString) else {
            print("CHECKLIST DEBUG: Failed to parse date: \(dateString)")
            return nil
        }
        
        // Get the notes from the checklist
        let notes = checklistInfo["notes"] as? String ?? ""
        
        // Parse the items array
        var checklistItems: [Models.ChecklistItem] = []
        if let items = checklistInfo["items"] as? [[String: Any]] {
            for itemData in items {
                if let title = itemData["title"] as? String {
                    // Parse notification time if present
                    var notificationDate: Date? = nil
                    if let notificationTime = itemData["notification"] as? String, notificationTime != "null" {
                        print("CHECKLIST DEBUG: Processing notification time: \(notificationTime)")
                        // Combine the date with the time
                        let timeFormatter = DateFormatter()
                        timeFormatter.dateFormat = "HH:mm"
                        if let time = timeFormatter.date(from: notificationTime) {
                            let calendar = Calendar.current
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                            let hour = timeComponents.hour ?? 0
                            let minute = timeComponents.minute ?? 0
                            
                            notificationDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
                            
                            print("CHECKLIST DEBUG: Parsed time \(notificationTime) to components - hour: \(hour), minute: \(minute)")
                            print("CHECKLIST DEBUG: Created notification date: \(notificationDate?.description ?? "nil")")
                        } else {
                            print("CHECKLIST DEBUG: Failed to parse time format: \(notificationTime)")
                        }
                    }
                    
                    // Create the checklist item
                    checklistItems.append(Models.ChecklistItem(
                        title: title,
                        date: date,
                        isCompleted: false,
                        notification: notificationDate,
                        group: nil
                    ))
                    
                    print("CHECKLIST DEBUG: Added item: \(title)")
                }
            }
        }
        
        // Create and return the checklist
        let checklist = Models.Checklist(
            id: UUID(),
            date: date,
            items: checklistItems,
            notes: notes
        )
        
        print("CHECKLIST DEBUG: Created checklist for \(dateString) with \(checklistItems.count) items and notes: \(notes)")
        return checklist
    }

    /// Helper method to save or append a checklist
    /// - Parameter checklist: The checklist to save or append to an existing one
    @MainActor
    private func saveOrAppendChecklist(_ checklist: Models.Checklist) {
        let persistence = ChecklistPersistence.shared
        
        // Check if a checklist already exists for this date
        if let existingChecklist = persistence.loadChecklist(for: checklist.date) {
            print("CHECKLIST DEBUG: Found existing checklist for date: \(checklist.date)")
            
            // Create an updated checklist by appending the new items
            var updatedChecklist = existingChecklist
            updatedChecklist.items.append(contentsOf: checklist.items)
            
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
            
            // Notify the UI that a checklist was updated
            NotificationCenter.default.post(name: Notification.Name("NewChecklistAvailable"), object: checklist.date)
            
            // Provide a message to the user about the updated checklist
            let message = "Updated checklist for \(self.formatDate(checklist.date)) with \(checklist.items.count) new items."
            self.onMessageUpdate?("""
            {"message": "\(message)"}
            """)
        } else {
            // No existing checklist, save the new one
            persistence.saveChecklist(checklist)
            print("CHECKLIST DEBUG: Saved new checklist to persistence for date: \(checklist.date)")
            
            // Notify the UI that a new checklist is available
            NotificationCenter.default.post(name: Notification.Name("NewChecklistAvailable"), object: checklist.date)
            
            // Provide a message to the user about the new checklist
            let message = "A checklist has been created for \(self.formatDate(checklist.date)) with \(checklist.items.count) items."
            self.onMessageUpdate?("""
            {"message": "\(message)"}
            """)
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

