import SwiftUI
import CoreData
import Firebase

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var userInput: String = ""
    @Published var isLoading: Bool = false
    @Published var isAnimatingSend: Bool = false
    @Published var isPendingResponse: Bool = false
    @Published private var unreadCounts: [String: Int] = [:] // Map of date strings to unread counts
    @Published var isExpanded: Bool = false
    @Published var isFullyExpanded: Bool = false
    
    private let chatService = ChatService.shared
    private let persistenceService = ChatPersistenceService.shared
    private let firestoreService = FirestoreService.shared
    private var chatHistory: ChatHistory!
    private var context: NSManagedObjectContext
    private let authManager = AuthManager.shared
    
    // Track pending responses
    private var pendingResponses: [UUID: Bool] = [:]
    
    // Track if we're currently loading
    private var isCurrentlyLoading: Bool = false
    
    // Animation timing constants
    private let sendAnimationDuration: TimeInterval = 0.9 // Matches the spring animation response time
    private let additionalDelay: TimeInterval = 0.3 // Extra delay after animation before showing typing indicator
    
    // Constants for loading state management
    private let loadingTimeout: TimeInterval = 30 // 30 seconds timeout
    
    // Helper to get the current unread count
    var unreadCount: Int {
        return unreadCounts["main"] ?? 0
    }
    
    init() {
        self.context = ChatPersistenceService.shared.viewContext
        
        // Set this view model on the chat service for callbacks
        chatService.setChatViewModel(self)
        
        // Create or load chat history
        Task {
            await initializeChatHistory()
        }
        
        // Load saved unread counts
        self.unreadCounts = persistenceService.loadUnreadCounts()
        
        // Set up notification observer for chat updates
        setupNotificationObserver()
        
        // Set up callback for real-time message updates
        setupMessageUpdateCallback()
        
        // Set up callback for listener status changes
        setupListenerStatusCallback()
        
        // Initially check if listeners are active (in case we're resuming a session)
        updateLoadingIndicator()
        
        // Check for loading state and handle recovery
        if let loadingState = persistenceService.loadLoadingState() {
            // Check if the loading state is stale (older than timeout)
            if Date().timeIntervalSince(loadingState.timestamp) > loadingTimeout {
                // Loading state is stale, clear it and add error message
                persistenceService.clearLoadingState()
                Task {
                    let errorMsg = ChatMessage.create(
                        in: context,
                        role: MessageRoles.assistant,
                        content: "The request timed out. Please check your internet connection and try again."
                    )
                    await addMessageAndNotify(errorMsg)
                }
            } else {
                // Loading state is still valid, restore it
                self.isCurrentlyLoading = true
                self.isLoading = true
                self.isPendingResponse = true
                
                // Resume the message processing
                Task {
                    await resumeMessageProcessing(messageId: loadingState.messageId)
                }
            }
        }
        
        // Check for pending response (keep this as a fallback)
        if persistenceService.loadPendingResponse() != nil {
            self.isLoading = true
            self.isPendingResponse = true
        }
    }
    
    private func initializeChatHistory() async {
        if let existingHistory = await persistenceService.loadMainChatHistory() {
            self.chatHistory = existingHistory
            self.messages = existingHistory.messages
        } else {
            // Create a new main chat history
            self.chatHistory = ChatHistory.create(in: context, isMainHistory: true)
            try? context.save()
            self.messages = []
        }
    }
    
    deinit {
        // Remove notification observer when view model is deallocated
        NotificationCenter.default.removeObserver(self)
    }
    
    // Set up notification observer to handle chat updates from other sources
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChatMessageAdded),
            name: Notification.Name("ChatMessageAdded"),
            object: nil
        )
    }
    
    @objc private func handleChatMessageAdded(_ notification: Notification) {
        if let role = notification.userInfo?["role"] as? String,
           role == MessageRoles.assistant {  // Updated to use string constant
            
            // Always increment unread count for assistant messages when chat is not expanded
            if !isExpanded {
                incrementUnreadCount()
            }
            
            // Reload messages
            Task {
                await loadMessages()
            }
        }
    }
    
    // Load messages from the main chat history
    private func loadMessages() async {
        if let loadedHistory = await persistenceService.loadMainChatHistory() {
            self.chatHistory = loadedHistory
            self.messages = loadedHistory.messages
        } else {
            // Create a new main chat history if none exists
            self.chatHistory = ChatHistory.create(in: context, isMainHistory: true)
            try? context.save()
            self.messages = []
        }
    }
    
    private func addMessageAndNotify(_ message: ChatMessage) async {
        // Load the main chat history
        if let mainHistory = await persistenceService.loadMainChatHistory() {
            
            // Ensure message is in the same context as the history
            if message.managedObjectContext != mainHistory.managedObjectContext {
                // If contexts don't match, we need to get the message into the history's context
                if let historyContext = mainHistory.managedObjectContext {
                    // Create a new message in the history's context
                    let newMessage = ChatMessage.create(
                        in: historyContext,
                        id: message.id,
                        role: message.role,
                        content: message.content,
                        timestamp: message.timestamp
                    )
                    
                    // Add the new message to the history
                    mainHistory.addMessage(newMessage)
                }
            } else {
                // Add the message directly since contexts match
                mainHistory.addMessage(message)
            }
            
            // Save the history
            persistenceService.saveChatHistory(mainHistory)
            
            // Reload messages from Core Data to ensure consistency
            if let refreshedHistory = await persistenceService.loadMainChatHistory() {
                self.messages = refreshedHistory.messages
                self.chatHistory = refreshedHistory
            } else {
                // Fallback: just append the message
                self.messages.append(message)
            }
            
            // Increment unread count for assistant messages when chat is not expanded
            if message.role == MessageRoles.assistant && !isExpanded {
                incrementUnreadCount()
            }
            
        } else {
            // Create a new main chat history if it doesn't exist
            let newHistory = ChatHistory.create(in: context, isMainHistory: true)
            
            // Ensure message is in the same context
            if message.managedObjectContext != context {
                // Create a new message in the correct context
                let newMessage = ChatMessage.create(
                    in: context,
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    timestamp: message.timestamp
                )
                newHistory.addMessage(newMessage)
            } else {
                newHistory.addMessage(message)
            }
            
            persistenceService.saveChatHistory(newHistory)
            
            // Reload to ensure consistency
            if let refreshedHistory = await persistenceService.loadMainChatHistory() {
                self.messages = refreshedHistory.messages
                self.chatHistory = refreshedHistory
            } else {
                // Fallback
                self.messages = [message]
                self.chatHistory = newHistory
            }
            
            // Increment unread count for assistant messages when chat is not expanded
            if message.role == MessageRoles.assistant && !isExpanded {
                incrementUnreadCount()
            }
        }
    }
    
    private func resumeMessageProcessing(messageId: UUID) async {
        do {
            // Prepare context from recent messages
            let contextMessages = prepareRecentMessagesForContext(minutes: 7)
            
            // Use the updated sendMessage method with additional context
            let (responseMsg, _) = try await chatService.sendMessage(
                messages: messages,
                additionalContext: contextMessages
            )
            
            if let responseMsg = responseMsg {
                await addMessageAndNotify(responseMsg)
            }
            
            // Clear states
            persistenceService.clearLoadingState()
            persistenceService.clearPendingResponse()
        } catch {
            let errorMsg = ChatMessage.create(
                in: context,
                role: MessageRoles.assistant,
                content: "Sorry, I couldn't complete the previous response. Please try again."
            )
            await addMessageAndNotify(errorMsg)
            
            // Clear states
            persistenceService.clearLoadingState()
            persistenceService.clearPendingResponse()
        }
        
        // Reset loading states
        isCurrentlyLoading = false
        isLoading = false
        isPendingResponse = false
    }
    
    // Add this new method to prepare recent messages for context
    private func prepareRecentMessagesForContext(minutes: Int = 10) -> [[String: Any]] {
        // Get current time and calculate cutoff time
        let now = Date()
        let cutoffTime = now.addingTimeInterval(-60.0 * Double(minutes))
        
        // Get recent messages - assume timestamp is not optional in ChatMessage model
        var recentMessages = messages.filter { message in
            // Direct comparison with timestamp
            return message.timestamp >= cutoffTime
        }
        
        // Limit to a maximum of 50 messages to ensure we don't waste bandwidth
        // This aligns with the server's expectation (mobile client limits to 50 max)
        if recentMessages.count > 50 {
            // Keep only the 50 most recent messages
            recentMessages = Array(recentMessages.suffix(50))
        }
        
        // Convert to dictionaries for the API - only include role and content
        return recentMessages.map { message in
            return [
                "role": message.role,
                "content": message.content
            ]
        }
    }
    
    // Update the sendMessageWithText method to use the mobile-centric approach
    func sendMessageWithText(_ text: String, withId id: UUID? = nil) {
        // Check if user is authenticated and not a guest
        guard authManager.isAuthenticated && !authManager.isGuestUser else {
            // User is not authenticated or is a guest, don't send the message
            return
        }
        
        // No need to clear userInput here - it's already cleared in the view
        
        let messageId = id ?? UUID()
        let userMsg = ChatMessage.create(
            in: context,
            id: messageId,
            role: MessageRoles.user,
            content: text
        )
        
        // Add user message through central point
        Task {
            await addMessageAndNotify(userMsg)
        }
        
        // Store the pending response
        pendingResponses[messageId] = true
        
        // Save pending response state
        persistenceService.savePendingResponse(id: messageId)
        
        // Mark that we're animating the send
        isAnimatingSend = true

        Task {
            // Wait for the send animation to complete before showing the typing indicator
            try? await Task.sleep(nanoseconds: UInt64(sendAnimationDuration * 1_000_000_000))
            
            // Now we can show the loading indicator
            isAnimatingSend = false
            
            // Set the loading state
            isCurrentlyLoading = true
            
            // Show loading indicator temporarily until a listener is set up
            // Once a listener is active, updateLoadingIndicator will maintain the state
            isLoading = true
            isPendingResponse = true
            
            // Check connectivity before proceeding
            if !chatService.checkConnectivity() {
                // Show connection error message
                let errorMsg = ChatMessage.create(
                    in: context,
                    role: MessageRoles.assistant,
                    content: "No internet connection. Please check your network settings and try again."
                )
                await addMessageAndNotify(errorMsg)
                
                // Reset states
                isCurrentlyLoading = false
                isLoading = false
                isPendingResponse = false
                
                return
            }
            
            // Save loading state before starting the request
            persistenceService.saveLoadingState(messageId: messageId)
            
            do {
                // Prepare context from recent messages (mobile-centric approach)
                let contextMessages = prepareRecentMessagesForContext(minutes: 7)
                
                // Send the message with context using the existing method
                // This avoids the sendMessageWithContext error
                let (responseMsg, _) = try await chatService.sendMessage(
                    messages: messages, 
                    additionalContext: contextMessages
                )

                if let responseMsg = responseMsg {
                    // Check if the response content is structured JSON
                    var messageContent = responseMsg.content
                    
                    if let data = responseMsg.content.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        // Extract the message content if it exists
                        if let message = json["message"] as? String {
                            messageContent = message
                            
                            // Update the message content to just the message part
                            responseMsg.content = messageContent
                        }
                    }
                    
                    // Add response through central point
                    await addMessageAndNotify(responseMsg)
                }
                
                // Clear states after successful response
                persistenceService.clearLoadingState()
                persistenceService.clearPendingResponse()
            } catch {
                let errorMsg = ChatMessage.create(
                    in: context,
                    role: MessageRoles.assistant,
                    content: "It appears Alfred is currently away. Please try again later."
                )
                // Add error message through central point
                await addMessageAndNotify(errorMsg)
                
                // Clear states after error
                persistenceService.clearLoadingState()
                persistenceService.clearPendingResponse()
            }

            // Clean up the pending response
            pendingResponses.removeValue(forKey: messageId)
            isCurrentlyLoading = false
            
            // Update loading indicator based on current listener state
            // (will turn off if no listeners, stay on if listeners are active)
            updateLoadingIndicator()
        }
    }
    
    private func saveChatHistory() {
        if chatHistory != nil {
            persistenceService.saveChatHistory(chatHistory)
        }
    }
    
    // Add method to increment unread count
    func incrementUnreadCount() {
        DispatchQueue.main.async {
            self.unreadCounts["main"] = (self.unreadCounts["main"] ?? 0) + 1
            // Save the updated counts
            self.persistenceService.saveUnreadCounts(self.unreadCounts)
        }
    }
    
    // Add method to clear unread count
    func clearUnreadCount() {
        DispatchQueue.main.async {
            self.unreadCounts["main"] = 0
            // Save the updated counts
            self.persistenceService.saveUnreadCounts(self.unreadCounts)
        }
    }
    
    // Update the existing message handling to increment unread count
    private func handleNewMessage(_ message: ChatMessage) {
        DispatchQueue.main.async {
            if message.role == MessageRoles.assistant { // Updated to use string constant
                self.incrementUnreadCount()
            }
            self.messages.append(message)
            if self.chatHistory != nil {
                // Don't try to assign to messages property since it's read-only
                // Instead, add the message directly to the chat history
                self.chatHistory.addMessage(message)
                self.persistenceService.saveChatHistory(self.chatHistory)
            }
        }
    }
    
    // Set up callback for real-time message updates from Firebase
    private func setupMessageUpdateCallback() {
        chatService.onMessageUpdate = { [weak self] jsonString in
            guard let self = self else { return }
            
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                if let message = json["message"] as? String {
                    // We received an actual message from Firestore
                    // Update loading indicator to reflect current listener state
                    self.updateLoadingIndicator()
                }
            }
        }
    }
    
    // Set up callback for FirestoreService listener status changes
    private func setupListenerStatusCallback() {
        firestoreService.onListenerStatusChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateLoadingIndicator()
            }
        }
    }
    
    // New method to update loading indicator based on listener state
    func updateLoadingIndicator() {
        let hasActiveListeners = firestoreService.hasActiveListeners()
        
        // Only update UI state if it changed
        if self.isPendingResponse != hasActiveListeners {
            self.isPendingResponse = hasActiveListeners
            self.isLoading = hasActiveListeners
        }
    }
    
    // Update loading indicator methods to work with the new approach
    func showLoadingIndicator() {
        // Only show if it's not already showing
        if !isLoading {
            self.isLoading = true
            self.isPendingResponse = true
        }
    }
    
    func hideLoadingIndicator() {
        // Only hide if there are no active listeners
        if !firestoreService.hasActiveListeners() {
            self.isLoading = false
            self.isPendingResponse = false
        }
    }
    
    // Method to handle messages from ChatService
    @MainActor
    func handleMessage(_ message: String) {
        // Create a new message entity using the proper ChatMessage.create method
        let chatMessage = ChatMessage.create(
            in: context,
            role: MessageRoles.assistant,
            content: message
        )
        
        Task {
            await addMessageAndNotify(chatMessage)
        }
    }
}
