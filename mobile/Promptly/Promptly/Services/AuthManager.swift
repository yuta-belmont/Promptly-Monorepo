import Foundation
import SwiftUI
import Firebase
import FirebaseAuth

/// Manages user authentication and session state
class AuthManager: ObservableObject {
    // Singleton instance
    static let shared = AuthManager()
    
    // Published properties to track authentication state
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    // User information
    @Published var userEmail: String? = nil
    @Published var isGuestUser: Bool = false
    
    // API base URL
    private let baseURL = "http://192.168.1.166:8080/api"
    
    // UserDefaults keys
    private let tokenKey = "auth_token"
    private let userEmailKey = "user_email"
    private let guestModeKey = "guest_mode"
    
    private init() {
        // Check if user is already logged in
        checkAuthStatus()
    }
    
    /// Check if the user is already authenticated
    private func checkAuthStatus() {
        if UserDefaults.standard.string(forKey: tokenKey) != nil {
            // Token exists, validate it
            self.isAuthenticated = true
            self.userEmail = UserDefaults.standard.string(forKey: userEmailKey)
            self.isGuestUser = false
        } else if UserDefaults.standard.bool(forKey: guestModeKey) {
            // Guest mode is enabled
            self.isAuthenticated = true
            self.userEmail = nil
            self.isGuestUser = true
        } else {
            // No token found and not in guest mode
            self.isAuthenticated = false
            self.userEmail = nil
            self.isGuestUser = false
        }
    }
    
    /// Login with email and password
    func login(email: String, password: String) async -> Bool {
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        // Create form data for OAuth2 password flow
        let formData = "username=\(email)&password=\(password)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "\(baseURL)/v1/auth/login") else {
            DispatchQueue.main.async {
                self.error = "Invalid URL"
                self.isLoading = false
            }
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.error = "Invalid response"
                    self.isLoading = false
                }
                return false
            }
            
            if httpResponse.statusCode == 200 {
                // Parse the response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["access_token"] as? String {
                    
                    // Save the token and user email
                    UserDefaults.standard.set(token, forKey: tokenKey)
                    UserDefaults.standard.set(email, forKey: userEmailKey)
                    UserDefaults.standard.set(false, forKey: guestModeKey)
                    
                    // Sign in to Firebase anonymously
                    do {
                        try await Auth.auth().signInAnonymously()
                    } catch {
                        print("Error signing in to Firebase anonymously: \(error.localizedDescription)")
                        // Continue anyway since we're authenticated with the server
                    }
                    
                    DispatchQueue.main.async {
                        self.isAuthenticated = true
                        self.userEmail = email
                        self.isGuestUser = false
                        self.isLoading = false
                    }
                    return true
                } else {
                    DispatchQueue.main.async {
                        self.error = "Invalid response format"
                        self.isLoading = false
                    }
                    return false
                }
            } else {
                // Handle error response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = json["detail"] as? String {
                    DispatchQueue.main.async {
                        self.error = detail
                        self.isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.error = "Login failed with status code: \(httpResponse.statusCode)"
                        self.isLoading = false
                    }
                }
                return false
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Network error: \(error.localizedDescription)"
                self.isLoading = false
            }
            return false
        }
    }
    
    /// Enable guest mode (continue without account)
    func enableGuestMode() {
        // Set guest mode in UserDefaults
        UserDefaults.standard.set(true, forKey: guestModeKey)
        
        // Sign in to Firebase anonymously
        Task {
            do {
                try await Auth.auth().signInAnonymously()
            } catch {
                print("Error signing in to Firebase anonymously: \(error.localizedDescription)")
                // Continue anyway since we're in guest mode
            }
        }
        
        // Update state
        DispatchQueue.main.async {
            self.isAuthenticated = true
            self.userEmail = nil
            self.isGuestUser = true
        }
    }
    
    /// Logout the current user
    func logout() {
        // Sign out from Firebase
        do {
            try Auth.auth().signOut()
            print("Successfully signed out from Firebase")
        } catch {
            print("Error signing out from Firebase: \(error.localizedDescription)")
            // Continue with logout anyway
        }
        
        // Clear stored credentials
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: guestModeKey)
        
        // Update state
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.userEmail = nil
            self.isGuestUser = false
        }
    }
    
    /// Get the authentication token
    func getToken() -> String? {
        return UserDefaults.standard.string(forKey: tokenKey)
    }
    
    /// Get a Firebase custom token from the server
    private func getFirebaseToken(serverToken: String) async -> String? {
        // This method is no longer used since we're using anonymous authentication
        return nil
    }
} 
