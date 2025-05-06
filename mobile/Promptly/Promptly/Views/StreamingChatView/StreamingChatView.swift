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
                                        } else if let outline = message.outline, !message.isBuildingOutline {
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
                        HStack(alignment: .center, spacing: 8) {
                            TextField("Message Alfred...", text: $viewModel.userInput, axis: .vertical)
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
                                    
                                    // Set initial offset for animation
                                    messageOffset[messageId] = UIScreen.main.bounds.height * 0.3
                                    
                                    // Send the message
                                    viewModel.sendMessage(viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines))
                                    
                                    // Clear input
                                    DispatchQueue.main.async {
                                        viewModel.userInput = ""
                                    }
                                    
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
