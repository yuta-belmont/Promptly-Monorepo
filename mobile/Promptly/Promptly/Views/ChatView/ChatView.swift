import SwiftUI
import Combine
import CoreData

struct ChatView: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var focusManager: FocusManager
    @State private var lastSentMessageId: UUID?
    @State private var messageOffset: [UUID: CGFloat] = [:]
    @State private var inputFieldHeight: CGFloat = 0
    @State private var isHoveringClose: Bool = false
    @State private var isDragging = false
    @State private var viewUpdateTrigger: Bool = false
    @State private var lastInputClearTime: Date? = nil
    @State private var selectedOutline: ChecklistOutline? = nil
    @Binding var isKeyboardActive: Bool
    @Binding var isExpanded: Bool
    
    // Add a property to handle navigation to ReportsView
    var onNavigateToReports: (() -> Void)?
    
    // Animation state for floating text
    @State private var animatingText: String = ""
    @State private var animatingTextOpacity: Double = 0
    @State private var animatingTextPosition: CGPoint = .zero
    @State private var animatingTextSize: CGFloat = 16
    
    // Add ScrollView proxy reference to control scrolling programmatically
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    
    // State management functions
    private func resetChatState() {
        viewModel.isExpanded = isExpanded
        if isExpanded {
            viewModel.clearUnreadCount()
        }
    }
    
    private func RemoveAllFocus() {
        focusManager.removeAllFocus()
    }
    
    // Helper function to check if timestamp divider is needed
    private func shouldShowTimestampDivider(currentMessage: ChatMessage, previousMessage: ChatMessage?) -> Bool {
        guard let previousMessage = previousMessage else {
            // Always show timestamp for the first message
            return true
        }
        
        let calendar = Calendar.current
        
        // Check if messages are on different days
        if !calendar.isDate(currentMessage.timestamp, inSameDayAs: previousMessage.timestamp) {
            return true
        }
        
        // Check if messages are in different hours
        let currentHour = calendar.component(.hour, from: currentMessage.timestamp)
        let previousHour = calendar.component(.hour, from: previousMessage.timestamp)
        
        return currentHour != previousHour
    }
    
    // Format the timestamp based on how old it is
    private func formatTimestamp(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            // Today - show "Today" with time
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            // Yesterday - show "Yesterday" with time
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday \(formatter.string(from: date))"
        } else if calendar.dateComponents([.day], from: date, to: now).day! < 7 {
            // Within last week - show day of week with time
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE h:mm a"
            return formatter.string(from: date)
        } else {
            // Older - show date with time
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Main content
                ScrollViewReader { proxy in
                    // Scrollable content
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(zip(viewModel.messages.indices, viewModel.messages)), id: \.1.id) { index, msg in
                                // Show timestamp divider if needed
                                if shouldShowTimestampDivider(
                                    currentMessage: msg,
                                    previousMessage: index > 0 ? viewModel.messages[index - 1] : nil
                                ) {
                                    TimestampDividerView(timestamp: formatTimestamp(for: msg.timestamp))
                                        .id("timestamp-\(msg.id)")
                                        .padding(.vertical, 8)
                                }
                                
                                ChatBubbleView(message: msg, onReportTap: {
                                    // When a report message is tapped, navigate to the ReportsView
                                    // Collapse the chat if it's expanded
                                    
                                    // Trigger haptic feedback
                                    let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
                                    feedbackGenerator.prepare()
                                    feedbackGenerator.impactOccurred()
                                    
                                    if isExpanded {
                                        isExpanded = false
                                    }
                                    
                                    onNavigateToReports?()
                                    
                                    // If we don't have the external handler, post a notification
                                    // This will be picked up by RootView to show ReportsView
                                    if onNavigateToReports == nil {
                                        NotificationCenter.default.post(
                                            name: Notification.Name("ShowReportsView"),
                                            object: nil
                                        )
                                    }
                                    
                                }, onOutlineTap: {
                                    // When an outline message is tapped, show the ChecklistOutlineView
                                    if let outline = msg.outline {
                                        selectedOutline = outline
                                    }
                                })
                                .id(msg.id)
                                .offset(y: messageOffset[msg.id] ?? 0)
                            }
                            
                            if viewModel.messages.isEmpty {
                                VStack(spacing: 16) {
                                    Text("No messages yet")
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.top, 40)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            
                            if viewModel.isLoading && !viewModel.isAnimatingSend {
                                HStack {
                                    VStack(alignment: .leading) {
                                        TypingIndicatorView()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                    
                                    Spacer(minLength: 50)
                                }
                            }
                            
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
                        // This creates a smoother experience where content slides up rather than jumping
                        if newValue > oldValue {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } else {
                            // If messages are being removed, scroll without animation
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.isLoading) { oldValue, newValue in
                        if newValue && !viewModel.isAnimatingSend {
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                
                ChatInputFieldView(
                    userInput: $viewModel.userInput,
                    onSend: {
                        // SYNCHRONOUSLY capture the current input value
                        let inputText = viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !inputText.isEmpty else { return }
                        
                        // Generate message ID
                        let messageId = UUID()
                        lastSentMessageId = messageId
                        
                        // SYNCHRONOUSLY clear the input field before any async operations
                        viewModel.userInput = ""
                        lastInputClearTime = Date()
                        
                        // Force UI update immediately to ensure the text field clears
                        // This is crucial for voice input which sometimes doesn't trigger binding updates properly
                        DispatchQueue.main.async {
                            // Double-ensure the input is cleared - fixes voice input issue
                            if !viewModel.userInput.isEmpty {
                                viewModel.userInput = ""
                            }
                        }
                        
                        // Set initial offset for the new message (position it at the input field)
                        messageOffset[messageId] = UIScreen.main.bounds.height * 0.3
                        
                        // Now send the message with the captured text
                        viewModel.sendMessageWithText(inputText, withId: messageId)
                        
                        // Animation happens after clearing input and starting the send process
                        // Use the same animation timing as the scroll animation for coordination
                        let animationDuration = 0.5
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            // Animate the message bubble to its final position
                            // Using the same spring animation as the scroll to create a unified effect
                            withAnimation(.spring(response: animationDuration, dampingFraction: 0.9)) {
                                messageOffset[messageId] = 0
                            }
                            
                            // Clean up the messageOffset dictionary after animation completes
                            // to prevent it from growing indefinitely
                            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.3) {
                                // Only remove if this is not the newest message (avoid disrupting ongoing animations)
                                if lastSentMessageId != messageId {
                                    messageOffset.removeValue(forKey: messageId)
                                }
                            }
                        }
                    },
                    onAccept: {
                        print("🔍 DEBUG: Accept button tapped in ChatView")
                        viewModel.acceptOutline()
                    },
                    onDecline: {
                        print("🔍 DEBUG: Decline button tapped in ChatView")
                        viewModel.declineOutline()
                    },
                    hasPendingOutline: viewModel.hasPendingOutline,
                    isSendDisabled: viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isDragging: isDragging,
                    isDisabled: false
                )
                .background(.ultraThinMaterial)
                .opacity(1.0)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isPendingResponse)
                .contentShape(Rectangle().inset(by: -20))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 20 {
                                RemoveAllFocus()
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
                        viewModel.sendOutlineToServer(outline)
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
            resetChatState()
        }
        .onChange(of: isExpanded) { oldValue, newValue in
            viewModel.isExpanded = newValue
            if newValue {
                resetChatState()
            }
        }
        // Add observer for chat focus changes
        .onChange(of: focusManager.isChatFocused) { oldValue, newValue in
            if newValue {
                // When chat is focused, scroll to bottom
                DispatchQueue.main.async {
                    withAnimation {
                        scrollViewProxy?.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .manageFocus(for: .chat)
        .onDisappear {
            removeKeyboardNotifications()
        }
    }
    
    private func setupKeyboardNotifications() {
        // Remove any existing observers first
        removeKeyboardNotifications()
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            let animationDuration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            
            // Wait for keyboard animation to complete before adjusting height
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                isKeyboardActive = true
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

// Typing indicator that mimics iMessage typing bubbles
struct TypingIndicatorView: View {
    @State private var animationState = 0
    @State private var timer: Timer?
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animationState == index ? 1.2 : 0.8)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animationState
                    )
            }
        }
        .padding(8)
        .foregroundColor(.white)
        .background(Color.gray.opacity(0.5))
        .cornerRadius(16)
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func startAnimation() {
        withAnimation(Animation.easeInOut(duration: 0.6).repeatForever()) {
            animationState = (animationState + 1) % 3
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation {
                animationState = (animationState + 1) % 3
            }
        }
        
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
}

// Timestamp divider view for showing time breaks in the chat
struct TimestampDividerView: View {
    let timestamp: String
    
    var body: some View {
        HStack {
            
            Text(timestamp)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 8)
        }
        .padding(.horizontal)
    }

}


