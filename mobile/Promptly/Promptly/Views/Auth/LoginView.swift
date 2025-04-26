import SwiftUI

struct LoginView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoggingIn = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
                // Add tap gesture to dismiss keyboard
                .onTapGesture {
                    focusedField = nil
                }
            
            VStack(spacing: 30) {
                // App name only
                VStack(spacing: 10) {
                    Text("Alfred")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.top, 50)
                
                // Login form
                VStack(spacing: 20) {
                    // Email field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("Enter your email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        SecureField("Enter your password", text: $password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.done)
                            .onSubmit {
                                login()
                            }
                    }
                    
                    // Error message
                    if let error = authManager.error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .padding(.top, 5)
                    }
                    
                    // Login button
                    Button(action: login) {
                        if isLoggingIn {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        } else {
                            Text("Login")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                    .disabled(isLoggingIn || email.isEmpty || password.isEmpty)
                    
                    // Continue without account button
                    Button(action: continueWithoutAccount) {
                        Text("Continue without Account")
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 30)
                
                Spacer()
            }
        }
    }
    
    private func login() {
        isLoggingIn = true
        focusedField = nil // Dismiss keyboard when login is attempted
        
        Task {
            _ = await authManager.login(email: email, password: password, silentMode: false)
            
            DispatchQueue.main.async {
                isLoggingIn = false
                // No need to show alert as error is displayed in the UI
            }
        }
    }
    
    private func continueWithoutAccount() {
        // Use the proper method to enable guest mode instead of directly setting isAuthenticated
        authManager.enableGuestMode()
    }
}
