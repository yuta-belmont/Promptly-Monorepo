import SwiftUI
import Combine

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject private var focusManager: FocusManager
    @State private var lastSentMessageId: UUID?
    @State private var messageOffset: [UUID: CGFloat] = [:]
    @State private var inputFieldHeight: CGFloat = 0
    @State private var height: CGFloat = UIScreen.main.bounds.height * 0.45
    @State private var keyboardHeight: CGFloat = 0
    @State private var isHoveringClose: Bool = false
    @State private var isDragging = false
    @State private var viewUpdateTrigger: Bool = false
    @State private var currentGeometry: GeometryProxy?
    @Binding var isKeyboardActive: Bool
    @Binding var isExpanded: Bool
    
    // Animation state for floating text
    @State private var animatingText: String = ""
    @State private var animatingTextOpacity: Double = 0
    @State private var animatingTextPosition: CGPoint = .zero
    @State private var animatingTextSize: CGFloat = 16
    
    private let snapThreshold: CGFloat = UIScreen.main.bounds.height * 0.20
    private let initialHeight: CGFloat = UIScreen.main.bounds.height * 0.45

    // Computed property for isFullyExpanded
    private var isFullyExpanded: Bool {
        get { viewModel.isFullyExpanded }
        set { viewModel.isFullyExpanded = newValue }
    }
    
    // State management functions
    private func resetChatState() {
        height = initialHeight
        viewModel.isExpanded = isExpanded
        if isExpanded {
            viewModel.clearUnreadCount()
        }
    }
    
    private func RemoveAllFocus() {
        focusManager.removeAllFocus()
    }

    var body: some View {
        
        return GeometryReader { geometry in
            let availableHeight = geometry.size.height
            let maxHeight = availableHeight -  20
            
            // Main chat content without the dark background (that's now in BaseView)
            ZStack {
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        ChatHeaderView(
                            isFullyExpanded: Binding(
                                get: { viewModel.isFullyExpanded },
                                set: { viewModel.isFullyExpanded = $0 }
                            ),
                            isExpanded: $isExpanded,
                            height: $height,
                            isDragging: $isDragging,
                            viewModel: viewModel,
                            maxHeight: maxHeight,
                            initialHeight: initialHeight,
                            snapThreshold: snapThreshold
                        )
                        
                        // Main content
                        VStack(spacing: 0) {
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
                                .onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
                                    if newValue == .chat {
                                        isKeyboardActive = true
                                        // Wait for keyboard animation to complete (typically 0.25s)
                                        let animationDuration = 0.25
                                        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                                            if let geometry = currentGeometry {
                                                let availableHeight = geometry.size.height - 20
                                                withAnimation(.easeOut(duration: 0.1)) {
                                                    if height > availableHeight {
                                                        height = availableHeight
                                                    }
                                                }
                                            }
                                            // Scroll to bottom after height adjustment
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                withAnimation {
                                                    proxy.scrollTo("bottom", anchor: .bottom)
                                                }
                                            }
                                        }
                                    } else if oldValue == .chat {
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            isKeyboardActive = false
                                            height = initialHeight // Reset to initial height when losing focus
                                        }
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
                                    
                                    // Calculate the distance from bottom of screen to where message will appear
                                    let distanceFromBottom = geometry.size.height - inputFieldHeight
                                    messageOffset[messageId] = distanceFromBottom
                                    
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
                            .background(GlassBackground(opacity: 0.1))
                            .opacity(1.0)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isPendingResponse)
                            .background(
                                GeometryReader { inputGeometry in
                                    Color.clear.onAppear {
                                        inputFieldHeight = inputGeometry.size.height
                                    }
                                    .onChange(of: inputGeometry.size.height) { oldValue, newValue in
                                        inputFieldHeight = newValue
                                    }
                                }
                            )
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
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(height: isKeyboardActive ? 
                        min(height, availableHeight) :
                        height
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 0)
                .onAppear {
                    currentGeometry = geometry
                    setupKeyboardNotifications()
                    resetChatState()
                }
                .onChange(of: geometry.size) { oldValue, newValue in
                    currentGeometry = geometry
                }
                .onChange(of: geometry.safeAreaInsets) { oldValue, newValue in
                    currentGeometry = geometry
                }
                .onChange(of: isExpanded) { _, newValue in
                    if newValue {
                        resetChatState()
                    }
                }
                .manageFocus(for: .chat)
                .onDisappear {
                    removeKeyboardNotifications()
                }
            }
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
            let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
            let animationDuration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            
            keyboardHeight = keyboardFrame.height
            
            // Wait for keyboard animation to complete before adjusting height
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                if let geometry = currentGeometry {
                    let availableHeight = geometry.size.height - 20
                    
                    if height > availableHeight {
                        withAnimation(.easeOut(duration: 0.1)) {
                            height = availableHeight
                        }
                    }
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            keyboardHeight = 0
        }
    }
    
    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
}

// Glassy Background Effect
struct GlassBackground: View {
    var opacity: Double = 0.1
    
    var body: some View {
        Color.white.opacity(opacity)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: .white.opacity(0.2), radius: 8, x: 0, y: 4)
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

struct CloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            .frame(width: 44, height: 44) // Match the button's touch target size
    }
}

// MARK: - Chat Header Component
private struct ChatHeaderView: View {
    @Binding var isFullyExpanded: Bool
    @Binding var isExpanded: Bool
    @Binding var height: CGFloat
    @Binding var isDragging: Bool
    @ObservedObject var viewModel: ChatViewModel
    let maxHeight: CGFloat
    let initialHeight: CGFloat
    let snapThreshold: CGFloat
    @State private var showingInfoPopover = false
    
    var body: some View {
        ZStack {
            // Center chevrons
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(.white.opacity(0.5))
            
            // Buttons container
            HStack {
                // Info button (left side)
                Button(action: {
                    showingInfoPopover = true
                }) {
                    Image(systemName: "info")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.gray.opacity(0.3)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CloseButtonStyle())
                .frame(width: 44, height: 30)
                .popover(isPresented: $showingInfoPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Alfred helps you set reminders, organize tasks, and achieve your goals.")
                            .font(.subheadline)
                        
                        Text("Messages are automatically deleted after 48 hours.")
                            .font(.subheadline)
                            .padding(.top, 4)
                    }
                    .padding()
                    .frame(width: 280)
                    .background(.ultraThinMaterial)
                    .presentationCompactAdaptation(.none)
                }
                .allowsHitTesting(true)
                .gesture(DragGesture().onChanged { _ in })
                
                Spacer()
                
                // Expand/Contract button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if isFullyExpanded {
                            height = initialHeight
                            isFullyExpanded = false
                            viewModel.isFullyExpanded = false
                        } else {
                            height = maxHeight
                            isFullyExpanded = true
                            viewModel.isFullyExpanded = true
                        }
                    }
                }) {
                    Image(systemName: isFullyExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.gray.opacity(0.3)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CloseButtonStyle())
                .frame(width: 44, height: 30)
                .offset(x: 15)
                .allowsHitTesting(true)
                .gesture(DragGesture().onChanged { _ in })
                
                Spacer()
                    .frame(width: 20)
                
                // Close button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.clearUnreadCount()
                        isExpanded = false
                        viewModel.isExpanded = false
                        isFullyExpanded = false
                        height = initialHeight
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.gray.opacity(0.3)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle().offset(x: 15))
                }
                .buttonStyle(CloseButtonStyle())
                .frame(width: 44, height: 30)
                .allowsHitTesting(true)
                .gesture(DragGesture().onChanged { _ in })
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    let newHeight = height - value.translation.height
                    height = min(max(snapThreshold / 2, newHeight), maxHeight)
                }
                .onEnded { value in
                    isDragging = false
                    
                    // If ending below threshold, close the chat
                    if height < snapThreshold {
                        // First set the height to the current value to prevent expansion
                        let currentHeight = height
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            // Keep the height at its current value during the closing animation
                            height = currentHeight
                            isExpanded = false
                            viewModel.isExpanded = false
                            isFullyExpanded = false
                        }
                    }
                    // If ending above 90%, snap to full height
                    else if height >= maxHeight * 0.9 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            height = maxHeight
                            isFullyExpanded = true
                            viewModel.isFullyExpanded = true
                        }
                    }
                    // Otherwise, just ensure we're not in fully expanded state
                    else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isFullyExpanded = false
                            viewModel.isFullyExpanded = false
                        }
                    }
                }
        )
        .onAppear {
            // Reset to initial height when view appears
            height = initialHeight
            viewModel.isExpanded = isExpanded
            if isExpanded {
                viewModel.clearUnreadCount()
            }
        }
        .onChange(of: isExpanded) { oldValue, newValue in
            // Only reset height when chat is opened, not when closed
            if newValue {
                height = initialHeight
            }
            viewModel.isExpanded = newValue
            if newValue {
                viewModel.clearUnreadCount()
            }
        }
    }
}


