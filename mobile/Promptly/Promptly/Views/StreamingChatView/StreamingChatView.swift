import SwiftUI
import Combine

struct StreamingChatView: View {
    @StateObject private var viewModel = StreamingChatViewModel.shared
    @EnvironmentObject private var focusManager: FocusManager
    @State private var isKeyboardActive: Bool = false
    @State private var selectedOutline: ChecklistOutline? = nil
    
    // Animation state for messages
    @State private var messageOffset: [UUID: CGFloat] = [:]
    @State private var lastSentMessageId: UUID?
    
    // Add ScrollView proxy reference to control scrolling programmatically
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    
    // Add binding for external control of expanded state
    @Binding var isExpanded: Bool
    
    var onNavigateToReports: (() -> Void)?
    
    // Add an initializer that accepts the binding but provides a default for SwiftUI previews
    init(isKeyboardActive: Binding<Bool> = .constant(false), isExpanded: Binding<Bool> = .constant(true), onNavigateToReports: (() -> Void)? = nil) {
        self._isKeyboardActive = State(initialValue: isKeyboardActive.wrappedValue)
        self._isExpanded = isExpanded
        self.onNavigateToReports = onNavigateToReports
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat header
                HStack {
                    Text("Alfred")
                        .font(.headline)
                    Spacer()
                    // Badge for unread messages
                    if viewModel.unreadCount > 0 {
                        Text("\(viewModel.unreadCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Circle().fill(Color.red))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.3))
                
                // Main content
                ScrollViewReader { proxy in
                    // Scrollable content
                    ScrollView {
                        VStack(spacing: 0) {
                            // Messages
                            ForEach(viewModel.messages) { message in
                                StreamingChatBubbleView(
                                    message: message,
                                    onReportTap: {
                                        onNavigateToReports?()
                                    },
                                    onOutlineTap: {
                                        // When an outline message is tapped, show the ChecklistOutlineView
                                        if let outline = message.outline {
                                            selectedOutline = outline
                                        }
                                    }
                                )
                                .id(message.id)
                                .offset(y: messageOffset[message.id] ?? 0)
                                .padding(.vertical, 2)
                            }
                            
                            // Empty state
                            if viewModel.messages.isEmpty {
                                VStack(spacing: 16) {
                                    Text("No messages yet")
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.top, 40)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            
                            // Space at bottom for scrolling
                            Color.clear
                                .frame(height: 10)
                                .id("bottom")
                        }
                    }
                    .onAppear {
                        // Scroll to bottom when view appears if there are messages
                        if !viewModel.messages.isEmpty {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        
                        // Store the proxy reference for later use
                        scrollViewProxy = proxy
                    }
                    .onChange(of: viewModel.messages.count) { oldValue, newValue in
                        // Animate scrolling to bottom when new messages are added
                        if newValue > oldValue {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } else {
                            // If messages are being removed, scroll without animation
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    // Simultaneous tap gesture to dismiss keyboard
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in
                                focusManager.removeAllFocus()
                            }
                    )
                }
                
                // Input field
                ZStack(alignment: .bottom) {
                    // Background layer that extends into safe area
                    Color.clear
                        .background(.ultraThinMaterial)
                        .cornerRadius(16, corners: [.topLeft, .topRight])
                        .overlay(
                            RoundedCorner(radius: 16, corners: [.topLeft, .topRight])
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .ignoresSafeArea(edges: .bottom)
                    
                    // Outline controls if there's a pending outline
                    if viewModel.hasPendingOutline {
                        VStack(spacing: 8) {
                            Text("Do you want to create this checklist?")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            
                            HStack(spacing: 16) {
                                Button(action: {
                                    viewModel.declineOutline()
                                }) {
                                    Text("No")
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 8)
                                        .background(Color.red.opacity(0.8))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                }
                                
                                Button(action: {
                                    viewModel.acceptOutline()
                                }) {
                                    Text("Yes")
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 8)
                                        .background(Color.green.opacity(0.8))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding()
                    } else {
                        // Standard input field
                        HStack {
                            TextField("Message", text: $viewModel.userInput)
                                .padding(12)
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(20)
                                .foregroundColor(.white)
                                .manageFocus(for: .chat)
                            
                            Button(action: {
                                let text = viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty {
                                    // Generate message ID
                                    let messageId = UUID()
                                    lastSentMessageId = messageId
                                    
                                    // Set initial offset for animation
                                    messageOffset[messageId] = UIScreen.main.bounds.height * 0.3
                                    
                                    // Send the message
                                    viewModel.sendMessage(text)
                                    
                                    // Animate the message
                                    let animationDuration = 0.5
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        withAnimation(.spring(response: animationDuration, dampingFraction: 0.9)) {
                                            messageOffset[messageId] = 0
                                        }
                                        
                                        // Clean up
                                        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.3) {
                                            if lastSentMessageId != messageId {
                                                messageOffset.removeValue(forKey: messageId)
                                            }
                                            
                                            // Remove focus after animation
                                            focusManager.removeAllFocus()
                                        }
                                    }
                                }
                            }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                            }
                            .disabled(viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle().inset(by: -20))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 20 {
                                focusManager.removeAllFocus()
                            }
                        }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isExpanded = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.leading, 12)
                    }
                }
            }
            .sheet(item: $selectedOutline) { outline in
                ChecklistOutlineView(
                    outline: outline,
                    onAccept: {
                        viewModel.acceptOutline()
                        selectedOutline = nil
                    },
                    onDecline: {
                        viewModel.declineOutline()
                        selectedOutline = nil
                    }
                )
            }
        }
        .onAppear {
            setupKeyboardNotifications()
            if viewModel.isExpanded {
                viewModel.clearUnreadCount()
            }
        }
        .onChange(of: viewModel.isExpanded) { oldValue, newValue in
            if newValue {
                viewModel.clearUnreadCount()
            }
        }
        .onDisappear {
            removeKeyboardNotifications()
        }
    }
    
    private func setupKeyboardNotifications() {
        // Remove any existing observers first
        removeKeyboardNotifications()
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            // Set keyboard active flag
            self.isKeyboardActive = true
            
            // Scroll to bottom with a simple animation
            withAnimation(.easeInOut(duration: 0.3)) {
                self.scrollViewProxy?.scrollTo("bottom", anchor: .bottom)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            isKeyboardActive = false
        }
    }
    
    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
}
