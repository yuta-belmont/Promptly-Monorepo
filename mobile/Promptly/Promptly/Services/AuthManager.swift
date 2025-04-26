import Foundation
import SwiftUI
import Firebase
import FirebaseAuth
import KeychainSwift

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
    
    // Keychain keys
    private let keychainEmailKey = "keychain_email"
    private let keychainPasswordKey = "keychain_password"
    
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
    
    /// Attempts to silently authenticate the user using stored credentials
    func silentAuthentication() async {
        // Skip if already loading or in guest mode
        if isLoading || isGuestUser { return }
        
        let keychain = KeychainSwift()
        
        // Check for stored credentials
        guard let email = keychain.get(keychainEmailKey),
              let password = keychain.get(keychainPasswordKey) else {
            print("No stored credentials found for silent authentication")
            return
        }
        
        print("Attempting silent authentication with stored credentials")
        
        // Silent login attempt
        let success = await login(email: email, password: password, silentMode: true)
        
        if success {
            print("Silent authentication successful")
        } else {
            print("Silent authentication failed, will use existing token if available")
        }
    }
    
    /// Login with email and password
    func login(email: String, password: String, silentMode: Bool = false) async -> Bool {
        if !silentMode {
            DispatchQueue.main.async {
                self.isLoading = true
                self.error = nil
            }
        }
        
        // Create form data for OAuth2 password flow
        let formData = "username=\(email)&password=\(password)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "\(baseURL)/v1/auth/login") else {
            DispatchQueue.main.async {
                if !silentMode {
                    self.error = "Invalid URL"
                    self.isLoading = false
                }
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
                    if !silentMode {
                        self.error = "Invalid response"
                        self.isLoading = false
                    }
                }
                return false
            }
            
            if httpResponse.statusCode == 200 {
                // Parse the response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["access_token"] as? String {
                    
                    // Save the token and user email in UserDefaults
                    UserDefaults.standard.set(token, forKey: tokenKey)
                    UserDefaults.standard.set(email, forKey: userEmailKey)
                    UserDefaults.standard.set(false, forKey: guestModeKey)
                    
                    // Save credentials in Keychain for auto-renewal
                    let keychain = KeychainSwift()
                    keychain.set(email, forKey: keychainEmailKey)
                    keychain.set(password, forKey: keychainPasswordKey)
                    
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
                        if !silentMode {
                            self.isLoading = false
                        }
                    }
                    return true
                } else {
                    DispatchQueue.main.async {
                        if !silentMode {
                            self.error = "Invalid response format"
                            self.isLoading = false
                        }
                    }
                    return false
                }
            } else {
                // Handle error response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = json["detail"] as? String {
                    DispatchQueue.main.async {
                        if !silentMode {
                            self.error = detail
                            self.isLoading = false
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        if !silentMode {
                            self.error = "Login failed with status code: \(httpResponse.statusCode)"
                            self.isLoading = false
                        }
                    }
                }
                return false
            }
        } catch {
            DispatchQueue.main.async {
                if !silentMode {
                    self.error = "Network error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
            return false
        }
    }
    
    /// Enable guest mode (continue without account)
    func enableGuestMode() {
        // Set guest mode in UserDefaults
        UserDefaults.standard.set(true, forKey: guestModeKey)
        
        // Remove Firebase anonymous authentication for guest users
        // Guest users shouldn't need Firestore access
        // If there's an existing Firebase auth, sign out
        do {
            if Auth.auth().currentUser != nil {
                try Auth.auth().signOut()
                print("Signed out of Firebase for guest mode")
            }
        } catch {
            print("Error signing out from Firebase: \(error.localizedDescription)")
        }
        
        // Update state
        DispatchQueue.main.async {
            self.isAuthenticated = true
            self.userEmail = nil
            self.isGuestUser = true
        }
    }
    
    /// Check if the user has Firebase Authentication
    func hasFirebaseAuth() -> Bool {
        return Auth.auth().currentUser != nil
    }
    
    /// Ensure Firebase Authentication is set up
    /// This can be called when needed to ensure Firebase Auth is available
    func ensureFirebaseAuth() async -> Bool {
        // Only attempt Firebase auth if not in guest mode
        if isGuestUser {
            return false
        }
        
        // If already authenticated with Firebase, return true
        if Auth.auth().currentUser != nil {
            return true
        }
        
        // Otherwise try to sign in anonymously
        do {
            try await Auth.auth().signInAnonymously()
            return true
        } catch {
            print("Error signing in to Firebase anonymously: \(error.localizedDescription)")
            return false
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
        
        // Clear stored credentials from UserDefaults
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: guestModeKey)
        
        // Note: We're intentionally NOT clearing Keychain credentials
        // This allows for faster re-login in the future
        
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
    
    /// Handles expired token errors by attempting to refresh the token
    func handleExpiredToken(originalRequest: URLRequest) async -> URLRequest? {
        print("Token expired, attempting to refresh")
        
        let keychain = KeychainSwift()
        
        // Check for stored credentials
        guard let email = keychain.get(keychainEmailKey),
              let password = keychain.get(keychainPasswordKey) else {
            print("No stored credentials found for token refresh")
            return nil
        }
        
        // Try to get a new token
        let success = await login(email: email, password: password, silentMode: true)
        
        if success, let newToken = getToken() {
            // Create a new request with the updated token
            var newRequest = originalRequest
            newRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            print("Token refresh successful, retrying request")
            return newRequest
        }
        
        print("Token refresh failed")
        return nil
    }
    
    /// Get a Firebase custom token from the server
    private func getFirebaseToken(serverToken: String) async -> String? {
        // This method is no longer used since we're using anonymous authentication
        return nil
    }
} 
