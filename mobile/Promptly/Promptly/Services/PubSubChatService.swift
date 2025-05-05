import Foundation
import SwiftUI

enum PubSubChatError: Error {
    case notAuthenticated
    case invalidResponse(String)
    case networkError(String)
    case sseError(String)
}

class PubSubChatService {
    // Shared instance
    static let shared = PubSubChatService()
    
    // Private properties
    private let sseManager = SSEManager()
    private let authManager = AuthManager.shared
    private let networkManager = NetworkManager.shared
    private let serverBaseURL = "http://192.168.1.166:8080"
    
    // Callbacks for streaming updates
    var onChunkReceived: ((String) -> Void)?
    var onMessageCompleted: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    // Active request IDs
    private var activeRequestIds: Set<String> = []
    
    // Private initializer for singleton pattern
    private init() {}
    
    // MARK: - Message Tasks
    
    /// Send a message using the PubSub API and handle streaming response
    /// - Parameters:
    ///   - content: The message content to send
    ///   - messageHistory: Optional message history context
    ///   - userFullName: Optional user's full name
    ///   - clientTime: Optional client time
    /// - Returns: Request ID for tracking
    func sendMessage(
        content: String,
        messageHistory: [[String: Any]]? = nil,
        userFullName: String? = nil,
        clientTime: String? = nil
    ) async throws -> String {
        print("📤 PUBSUB: Sending message: \(content)")
        
        // Prepare the request payload
        var payload: [String: Any] = [
            "message": content
        ]
        
        // Add optional fields if provided
        if let messageHistory = messageHistory {
            payload["context_messages"] = messageHistory
        }
        
        if let userFullName = userFullName {
            payload["user_full_name"] = userFullName
        }
        
        // Always include current time
        payload["current_time"] = clientTime ?? ISO8601DateFormatter().string(from: Date())
        
        // Convert to JSON data
        guard let requestData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw PubSubChatError.invalidResponse("Failed to create request data")
        }
        
        do {
            // Send the request to the PubSub API
            let responseData = try await networkManager.makeAuthenticatedRequest(
                endpoint: "/v1/pubsub/message",
                method: "POST",
                body: requestData,
                contentType: "application/json"
            )
            
            // Parse the response
            guard let responseJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let requestId = responseJson["request_id"] as? String else {
                throw PubSubChatError.invalidResponse("Invalid response format")
            }
            
            print("📥 PUBSUB: Received request_id: \(requestId)")
            
            // Add to active requests
            activeRequestIds.insert(requestId)
            
            // Set up SSE connection for streaming
            setupSSEConnection(for: requestId)
            
            return requestId
        } catch let networkError as NetworkError {
            // Handle network-specific errors
            switch networkError {
            case .unauthorized:
                throw PubSubChatError.notAuthenticated
            case .httpError(let statusCode, let data):
                let errorDetails = String(data: data, encoding: .utf8) ?? "No details"
                throw PubSubChatError.networkError("HTTP error \(statusCode): \(errorDetails)")
            case .requestFailed(let error):
                throw PubSubChatError.networkError("Request failed: \(error.localizedDescription)")
            default:
                throw PubSubChatError.networkError("Unknown network error")
            }
        } catch {
            // Re-throw other errors
            throw error
        }
    }
    
    // MARK: - Checklist Tasks
    
    /// Send a checklist request using the PubSub API
    /// - Parameters:
    ///   - content: The message content requesting a checklist
    ///   - messageHistory: Optional message history context
    ///   - outline: Optional outline data for structured checklists
    ///   - clientTime: Optional client time
    /// - Returns: Request ID for tracking
    func sendChecklistRequest(
        content: String,
        messageHistory: [[String: Any]]? = nil,
        outline: [String: Any]? = nil,
        clientTime: String? = nil
    ) async throws -> String {
        print("📤 PUBSUB: Sending checklist request")
        
        // Prepare the request payload
        var payload: [String: Any] = [
            "message": content
        ]
        
        // Add optional fields if provided
        if let messageHistory = messageHistory {
            payload["context_messages"] = messageHistory
        }
        
        if let outline = outline {
            payload["outline"] = outline
        }
        
        // Always include current time
        payload["current_time"] = clientTime ?? ISO8601DateFormatter().string(from: Date())
        
        // Convert to JSON data
        guard let requestData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw PubSubChatError.invalidResponse("Failed to create request data")
        }
        
        do {
            // Send the request to the PubSub API
            let responseData = try await networkManager.makeAuthenticatedRequest(
                endpoint: "/v1/pubsub/checklist",
                method: "POST",
                body: requestData,
                contentType: "application/json"
            )
            
            // Parse the response
            guard let responseJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let requestId = responseJson["request_id"] as? String else {
                throw PubSubChatError.invalidResponse("Invalid response format")
            }
            
            print("📥 PUBSUB: Received checklist request_id: \(requestId)")
            
            // Add to active requests
            activeRequestIds.insert(requestId)
            
            // Set up SSE connection for streaming
            setupSSEConnection(for: requestId)
            
            return requestId
        } catch {
            throw error
        }
    }
    
    // MARK: - Check-in Tasks
    
    /// Send a check-in analysis request using the PubSub API
    /// - Parameters:
    ///   - checklistData: Checklist data to analyze
    ///   - userFullName: Optional user's full name
    ///   - clientTime: Optional client time
    ///   - alfredPersonality: Optional alfred personality setting
    ///   - userObjectives: Optional user objectives
    /// - Returns: Request ID for tracking
    func sendCheckinRequest(
        checklistData: [String: Any],
        userFullName: String? = nil,
        clientTime: String? = nil,
        alfredPersonality: String? = nil,
        userObjectives: String? = nil
    ) async throws -> String {
        print("📤 PUBSUB: Sending check-in request")
        
        // Prepare the request payload
        var payload: [String: Any] = [
            "checklist_data": checklistData
        ]
        
        // Add optional fields if provided
        if let userFullName = userFullName {
            payload["user_full_name"] = userFullName
        }
        
        if let alfredPersonality = alfredPersonality {
            payload["alfred_personality"] = alfredPersonality
        }
        
        if let userObjectives = userObjectives {
            payload["user_objectives"] = userObjectives
        }
        
        // Always include current time
        payload["current_time"] = clientTime ?? ISO8601DateFormatter().string(from: Date())
        
        // Convert to JSON data
        guard let requestData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw PubSubChatError.invalidResponse("Failed to create request data")
        }
        
        do {
            // Send the request to the PubSub API
            let responseData = try await networkManager.makeAuthenticatedRequest(
                endpoint: "/v1/pubsub/checkin",
                method: "POST",
                body: requestData,
                contentType: "application/json"
            )
            
            // Parse the response
            guard let responseJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let requestId = responseJson["request_id"] as? String else {
                throw PubSubChatError.invalidResponse("Invalid response format")
            }
            
            print("📥 PUBSUB: Received check-in request_id: \(requestId)")
            
            // Add to active requests
            activeRequestIds.insert(requestId)
            
            // Set up SSE connection for streaming
            setupSSEConnection(for: requestId)
            
            return requestId
        } catch {
            throw error
        }
    }
    
    // MARK: - SSE Handling
    
    /// Set up an SSE connection for a given request ID
    /// - Parameter requestId: The request ID to listen for
    private func setupSSEConnection(for requestId: String) {
        print("🔌 PUBSUB: Setting up SSE connection for request ID: \(requestId)")
        
        sseManager.connect(
            requestId: requestId,
            baseURL: serverBaseURL,
            onEvent: { [weak self] chunk in
                print("📥 PUBSUB: Received chunk of length: \(chunk.count)")
                print("📥 PUBSUB: Chunk preview: \(chunk.prefix(50))...")
                self?.onChunkReceived?(chunk)
            },
            onComplete: { [weak self] fullText in
                print("📥 PUBSUB: Completed with full text length: \(fullText.count)")
                print("📥 PUBSUB: Full text preview: \(fullText.prefix(50))...")
                self?.activeRequestIds.remove(requestId)
                self?.onMessageCompleted?(fullText)
            },
            onError: { [weak self] error in
                print("📥 PUBSUB: Error: \(error.localizedDescription)")
                self?.activeRequestIds.remove(requestId)
                self?.onError?(error)
            }
        )
        print("🔌 PUBSUB: SSE connection setup complete for request ID: \(requestId)")
    }
    
    /// Clean up any active SSE connections
    func cleanup() {
        print("🧹 PUBSUB: Cleaning up all SSE connections")
        sseManager.disconnect()
        activeRequestIds.removeAll()
    }
    
    /// Check if any requests are currently active
    var hasActiveRequests: Bool {
        let result = !activeRequestIds.isEmpty
        print("🔍 PUBSUB: Has active requests: \(result), count: \(activeRequestIds.count)")
        return result
    }
} 
