import SwiftUI
import Combine

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
    @Binding var isKeyboardActive: Bool
    @Binding var isExpanded: Bool
    
    // Animation state for floating text
    @State private var animatingText: String = ""
    @State private var animatingTextOpacity: Double = 0
    @State private var animatingTextPosition: CGPoint = .zero
    @State private var animatingTextSize: CGFloat = 16
    
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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Main content
                ScrollViewReader { proxy in
                    // Scrollable content
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.messages) { msg in
                                ChatBubbleView(message: msg)
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
                    }
                    .onChange(of: viewModel.messages.count) { oldValue, newValue in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    /*
                    .onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
                        if newValue == .chat {
                            isKeyboardActive = true
                            // Wait for keyboard animation to complete (typically 0.25s)
                            let animationDuration = 0.25
                            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                                // Scroll to bottom after height adjustment
                                withAnimation {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        } else if oldValue == .chat {
                            withAnimation(.easeOut(duration: 0.25)) {
                                isKeyboardActive = false
                            }
                        }
                    }
                     */
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
                        
                        // Now send the message with the captured text
                        viewModel.sendMessageWithText(inputText, withId: messageId)
                        
                        // Animation happens after clearing input and starting the send process
                        let animationDuration = 0.5
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            // Animate the message bubble to its final position
                            withAnimation(.spring(response: animationDuration, dampingFraction: 0.9)) {
                                messageOffset[messageId] = 0
                            }
                        }
                    },
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
                            .foregroundColor(.white)
                    }
                }
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


