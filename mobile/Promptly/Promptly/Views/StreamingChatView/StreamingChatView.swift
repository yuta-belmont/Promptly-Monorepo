import SwiftUI
import Combine

struct StreamingChatView: View {
    @StateObject private var viewModel = StreamingChatViewModel.shared
    @EnvironmentObject private var focusManager: FocusManager
    @State private var isKeyboardActive: Bool = false
    @State private var selectedOutline: ChecklistOutline? = nil
    @FocusState private var isTextFieldFocused: Bool
    @StateObject private var inputViewModel = ChatInputViewModel()
    
    // Animation state for messages
    @State private var messageOffset: [UUID: CGFloat] = [:]
    @State private var lastSentMessageId: UUID?
    @State private var lastInputClearTime: Date?
    
    // Add ScrollView proxy reference to control scrolling programmatically
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    @State private var lastContentOffset: CGFloat = 0
    @State private var isScrollingUp: Bool = false
    
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
                                        if let outline = message.checklistOutline, !message.isBuildingOutline {
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
                    // Add simultaneous tap gesture to dismiss keyboard
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in
                                isTextFieldFocused = false
                                focusManager.removeAllFocus()
                            }
                    )
                    .onAppear {
                        // Scroll to bottom when view appears if there are messages
                        if !viewModel.messages.isEmpty {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        
                        // Store the proxy reference for later use
                        scrollViewProxy = proxy
                    }
                    .onChange(of: viewModel.messages.count) { oldValue, newValue in
                        // Scroll to bottom when messages are added/removed
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.shouldScrollToBottom) { oldValue, newValue in
                        if newValue {
                            
                            // Keep the delay to ensure content is rendered
                            DispatchQueue.main.async {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                } completion: {
                                    
                                    // Only set back to false after animation completes
                                    viewModel.shouldScrollToBottom = false
                                    
                                    // Safety scroll since scrolling can be unpredicable while other things are animating
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            proxy.scrollTo("bottom", anchor: .bottom)
                                        } completion: {
                                            
                                        }
                                    }

                                }
                            }
                        }
                    }
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
                            Text("Create plan?")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.subheadline)
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    viewModel.acceptOutline()
                                }) {
                                    Text("Accept")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                Button(action: {
                                    viewModel.declineOutline()
                                }) {
                                    Text("Decline")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.gray.opacity(0.3))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    } else {
                        // Standard input field
                        HStack(alignment: .center, spacing: 8) {
                            TextField("Message Ai...", text: $viewModel.userInput, axis: .vertical)
                                .lineLimit(1...10)
                                .padding(.leading, 12)
                                .padding(.trailing, 12)
                                .padding(.vertical, 16)
                                .focused($isTextFieldFocused)
                                .disabled(inputViewModel.isRecording)
                                .opacity(inputViewModel.isRecording ? 0.6 : 1)
                                .onChange(of: isTextFieldFocused) { oldValue, newValue in
                                    if newValue {
                                        focusManager.requestFocus(for: .chat)
                                    }
                                }
                                .background(
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                )
                                .onTapGesture {
                                    isTextFieldFocused = true
                                }
                            
                            Button(action: {
                                if shouldShowMic || inputViewModel.isRecording {
                                    if inputViewModel.isRecording {
                                        inputViewModel.toggleRecording(directUpdateHandler: { transcription in
                                            viewModel.userInput = transcription
                                        })
                                    } else {
                                        inputViewModel.toggleRecording(directUpdateHandler: { transcription in
                                            viewModel.userInput = transcription
                                        })
                                    }
                                } else if hasText {
                                    // Generate message ID
                                    let messageId = UUID()
                                    lastSentMessageId = messageId
                                    
                                    // Set initial offset for the new message
                                    messageOffset[messageId] = UIScreen.main.bounds.height * 0.3
                                    
                                    // SYNCHRONOUSLY clear the input field before any async operations
                                    let inputText = viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    viewModel.userInput = ""
                                    lastInputClearTime = Date()
                                    
                                    // Force UI update immediately to ensure the text field clears
                                    DispatchQueue.main.async {
                                        // Double-ensure the input is cleared
                                        if !viewModel.userInput.isEmpty {
                                            viewModel.userInput = ""
                                        }
                                    }
                                    
                                    // Create and send the message with the specific ID
                                    let message = StreamingChatMessageFactory.createUserMessage(content: inputText, id: messageId)
                                    viewModel.sendMessage(message)
                                    
                                    // Animation happens after clearing input and starting the send process
                                    let animationDuration = 0.3
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        // Animate the message bubble to its final position
                                        withAnimation(.spring(response: animationDuration, dampingFraction: 0.9)) {
                                            messageOffset[messageId] = 0
                                        }
                                        
                                        // Clean up the messageOffset dictionary after animation completes
                                        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.1) {
                                            // Only remove if this is not the newest message
                                            if lastSentMessageId != messageId {
                                                messageOffset.removeValue(forKey: messageId)
                                            }
                                            
                                            // Remove focus after animation completes
                                            isTextFieldFocused = false
                                            focusManager.removeAllFocus()
                                        }
                                    }
                                }
                            }) {
                                Image(systemName: buttonImageName)
                                    .font(.system(size: 28))
                                    .foregroundColor(buttonColor)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .disabled(buttonDisabled)
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 16)
                        .padding(.vertical, 8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle().inset(by: -20))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 20 {
                                isTextFieldFocused = false
                                focusManager.removeAllFocus()
                            }
                        }
                )
            }
            .navigationTitle("Chat")
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
            
            // Set up speech recognition
            if !inputViewModel.isSpeechSetup {
                inputViewModel.setupSpeechRecognition(directUpdateHandler: { transcription in
                    viewModel.userInput = transcription
                })
            }
        }
        .onChange(of: viewModel.isExpanded) { oldValue, newValue in
            if newValue {
                viewModel.clearUnreadCount()
            }
        }
        .onChange(of: inputViewModel.isRecording) { oldValue, newValue in
            if newValue {
                isTextFieldFocused = false
            }
        }
        .alert("Speech Recognition Error", isPresented: .constant(inputViewModel.errorMessage != nil)) {
            Button("OK") {
                inputViewModel.errorMessage = nil
            }
        } message: {
            Text(inputViewModel.errorMessage ?? "")
        }
        .onDisappear {
            removeKeyboardNotifications()
        }
    }
    
    private var hasText: Bool {
        !viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var shouldShowMic: Bool {
        !hasText && !inputViewModel.isRecording
    }
    
    private var buttonImageName: String {
        if inputViewModel.isRecording {
            return "stop.circle.fill"
        } else if shouldShowMic {
            return "mic.circle.fill"
        } else {
            return "arrow.up.circle.fill"
        }
    }
    
    private var buttonColor: Color {
        if inputViewModel.isRecording {
            return .red
        } else if shouldShowMic {
            return inputViewModel.isSpeechSetup ? .blue : .gray
        } else {
            return .blue
        }
    }
    
    private var buttonDisabled: Bool {
        if shouldShowMic {
            return !inputViewModel.isSpeechSetup
        } else if inputViewModel.isRecording {
            return false
        } else {
            return !hasText
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

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
