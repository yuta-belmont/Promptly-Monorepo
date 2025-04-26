import Foundation

/// Handles network requests with automatic token refresh
class NetworkManager {
    // Singleton instance
    static let shared = NetworkManager()
    
    // API base URL - should match with AuthManager
    private let baseURL = "http://192.168.1.166:8080/api"
    
    // Private initializer for singleton
    private init() {}
    
    /// Make an authenticated request with automatic token renewal
    func makeAuthenticatedRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> Data {
        // Construct the full URL
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        // Set content type
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        // Add authentication token if available
        if let token = AuthManager.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            // Make the request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for token expiration
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 401 {
                // Convert data to string to check for token expiration
                if let responseString = String(data: data, encoding: .utf8),
                   responseString.contains("Token has expired") {
                    
                    print("Token expired error detected")
                    
                    // Attempt to refresh token and retry
                    if let newRequest = await AuthManager.shared.handleExpiredToken(originalRequest: request) {
                        // Retry with the new token
                        let (newData, _) = try await URLSession.shared.data(for: newRequest)
                        return newData
                    }
                }
                
                // If we couldn't refresh the token, throw the original error
                throw NetworkError.unauthorized
            }
            
            // Check for other error status codes
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 400 {
                throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
            }
            
            return data
        } catch {
            if let networkError = error as? NetworkError {
                throw networkError
            }
            throw NetworkError.requestFailed(error)
        }
    }
}

/// Network-related errors
enum NetworkError: Error {
    case invalidURL
    case unauthorized
    case httpError(statusCode: Int, data: Data)
    case requestFailed(Error)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .unauthorized:
            return "Unauthorized access"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        }
    }
} 