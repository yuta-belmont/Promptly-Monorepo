import SwiftUI

struct GeneralSettingsView: View {
    @Binding var isPresented: Bool
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var userSettings = UserSettings.shared
    @State private var dragOffset = CGSize.zero // Add drag offset for swipe gesture
    @State private var showingThemeInfo = false // State for the theme info popup
    @State private var showingCheckInInfo = false // New state for check-in info popover
    @State private var showingChatInfo = false // State for chat info popover
    @State private var showingNotificationPermissionAlert = false
    @State private var isClearingChat = false
    @State private var isAnimating = false // Track if we're currently animating
    
    @FocusState private var isObjectivesFocused: Bool
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("General Settings")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        if isObjectivesFocused {
                            isObjectivesFocused = false
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                    }) {
                        if isObjectivesFocused {
                            Text("Done")
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .opacity(0.7)
                                .padding(.trailing, 12)
                        }
                    }
                }
                .padding()
                .padding(.top, 8)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Settings content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // MARK: - Theme Section
                        themeSection
                        
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.horizontal)
                        
                        // MARK: - Check-in Section
                        checkInSection
                        
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.horizontal)
                        
                        // MARK: - Chat Section
                        chatSection
                    }
                    .padding(.vertical)
                }
                .padding(.horizontal, 0)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.black.opacity(0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
            .offset(x: dragOffset.width)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging to the right if we're not already animating
                        if !isAnimating && value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // Prevent multiple animations from starting
                        guard !isAnimating else { return }
                        isAnimating = true
                        
                        // Use a single animation block for both dismissal and reset
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if value.translation.width > 100 {
                                isPresented = false
                            } else {
                                dragOffset = .zero
                            }
                        }
                        
                        // Reset animation state after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            isAnimating = false
                        }
                    }
            )
            .transition(.move(edge: .trailing))
            .zIndex(999)
        }
        .onAppear {
            // Check notification permission when view appears
            NotificationManager.shared.checkNotificationPermission { isAuthorized in
                if !isAuthorized {
                    showingNotificationPermissionAlert = true
                }
            }
        }
        .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Please enable notifications to receive check-in reminders.")
        }
        .onChange(of: userSettings.isCheckInNotificationEnabled) { _, newValue in
            if newValue {
                // Check if we have permission first
                NotificationManager.shared.checkNotificationPermission { isAuthorized in
                    if isAuthorized {
                        // If we have permission, enable notifications
                        NotificationManager.shared.handleNotificationToggleChange()
                    } else {
                        // If no permission, request it
                        NotificationManager.shared.requestNotificationPermission { granted in
                            if granted {
                                // If granted, enable notifications
                                NotificationManager.shared.handleNotificationToggleChange()
                            } else {
                                // If denied, reset the toggle and show alert
                                userSettings.isCheckInNotificationEnabled = false
                                showingNotificationPermissionAlert = true
                            }
                        }
                    }
                }
            } else {
                // If disabling notifications, just remove them
                NotificationManager.shared.handleNotificationToggleChange()
            }
        }
        .onChange(of: userSettings.checkInTime) { _, _ in
            // Update notifications when time changes
            NotificationManager.shared.handleCheckInTimeChange()
        }
    }
    
    // MARK: - Theme Section View
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // TODO: Remove these development buttons when done
            HStack(spacing: 8) {
                Button(action: {
                    userSettings.streak = 0
                    userSettings.checkinPoints = 0
                }) {
                    Text("Reset")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(6)
                }
                
                Button(action: {
                    userSettings.checkinPoints += 10000
                }) {
                    Text("+10k Points")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.3))
                        .cornerRadius(6)
                }
                
                Button(action: {
                    userSettings.lastCheckin = Date.distantPast
                    userSettings.checkInButtonExpiryTimes = [:]
                }) {
                    Text("Reset Check-in")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.3))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal)
            
            // Theme selection label
            HStack {
                Text("Theme")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Button(action: {
                    showingThemeInfo = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
                .popover(isPresented: $showingThemeInfo, arrowEdge: .top) {
                    ThemeInfoPopover()
                }
                
                Spacer()
                Text(themeManager.currentTheme.rawValue)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            
            // Horizontal theme scroll view
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemePreviewButton(
                            theme: theme,
                            isSelected: themeManager.currentTheme == theme,
                            action: {
                                themeManager.currentTheme = theme
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            // Streak and points display
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .opacity(0.6)
                    Text("\(userSettings.streak) day streak")
                        .font(.caption)
                        .foregroundColor(.white)
                        .opacity(0.6)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .opacity(0.6)
                    Text("\(userSettings.checkinPoints) points")
                        .font(.caption)
                        .foregroundColor(.white)
                        .opacity(0.6)
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Check-in Section View
    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Check-in")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Button(action: {
                    showingCheckInInfo = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
                .popover(isPresented: $showingCheckInInfo, arrowEdge: .top) {
                    CheckInInfoPopover()
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Notification toggle
            HStack {
                Text("Notify?")
                    .foregroundColor(.white)
                
                Spacer()
                
                Toggle("", isOn: $userSettings.isCheckInNotificationEnabled)
                    .labelsHidden()
            }
            .padding(.horizontal)
            
            // Time picker with active check-in check
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Check-in Time")
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    DatePicker("", selection: $userSettings.checkInTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .tint(.blue)
                        .disabled(hasActiveCheckIn)
                }
                
                if hasActiveCheckIn {
                    Text("Check in before updating the time")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            .transition(.opacity)
            
            // Personality selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Alfred's Personality")
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                Picker("Personality", selection: $userSettings.alfredPersonality) {
                    ForEach(CheckInPersonality.allCases, id: \.rawValue) { personality in
                        Text(personality.title)
                            .foregroundColor(.white)
                            .tag(personality.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Personality description
                Text(CheckInPersonality(rawValue: userSettings.alfredPersonality)?.description ?? "")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut, value: userSettings.alfredPersonality)
            }
            .padding(.top, 8)
            
            // Objectives text editor
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Objectives")
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $userSettings.objectives)
                        .foregroundColor(.white)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .focused($isObjectivesFocused)
                    
                    if userSettings.objectives.isEmpty {
                        Text("What are you working towards? (Informs Alfred during check-ins)")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(userSettings.objectives.count)/200")
                                .font(.caption)
                                .foregroundColor(userSettings.objectives.count > 200 ? .red : .gray)
                                .padding(4)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .padding(.horizontal)
                .onChange(of: userSettings.objectives) { _, newValue in
                    if newValue.count > 200 {
                        userSettings.objectives = String(newValue.prefix(200))
                    }
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Chat Section View
    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Chat")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Button(action: {
                    showingChatInfo = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
                .popover(isPresented: $showingChatInfo, arrowEdge: .bottom) {
                    ChatInfoPopover()
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Chat toggle
            HStack {
                Text("Show Chat")
                    .foregroundColor(.white)
                
                Spacer()
                
                Toggle("", isOn: $userSettings.isChatEnabled)
                    .labelsHidden()
            }
            .padding(.horizontal)
            
            // Clear chat button
            Button(action: {
                // Trigger haptic feedback
                let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                feedbackGenerator.prepare()
                feedbackGenerator.impactOccurred()
                
                // Clear the chat history using the ChatViewModel singleton
                ChatViewModel.shared.clearChatHistory()
                
                // Animate the text
                isClearingChat = true
                
                // Reset the animation after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeIn(duration: 0.5)) {
                        isClearingChat = false
                    }
                }
            }) {
                HStack {
                    Text("Clear Chat History")
                        .foregroundColor(.red)
                        .opacity(isClearingChat ? 0.0 : 1.0)
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
        }
    }
    
    // Add this computed property to check for active check-ins
    private var hasActiveCheckIn: Bool {
        let calendar = Calendar.current
        let now = Date()
        
        // Check today and yesterday
        let today = now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        
        // Helper function to check a specific day
        func checkDay(_ day: Date) -> Bool {
            // Skip if user has already checked in for this day
            if calendar.isDate(userSettings.lastCheckin, inSameDayAs: day) {
                return false
            }
            
            // Convert day to string key
            let dayKey = userSettings.dateFormatter.string(from: day)
            
            // Check if we have an expiry time for this day
            guard let expiryTime = userSettings.checkInButtonExpiryTimes[dayKey] else {
                return false
            }
            
            // Get the check-in time for this day
            let checkInTime = userSettings.checkInTime
            let checkInComponents = calendar.dateComponents([.hour, .minute], from: checkInTime)
            
            // Create a date with this day's date but the check-in time
            let dayCheckInTime = calendar.date(bySettingHour: checkInComponents.hour ?? 0,
                                            minute: checkInComponents.minute ?? 0,
                                            second: 0,
                                            of: day) ?? day
            
            // Check if current time is past check-in time and within expiry window
            return now >= dayCheckInTime && now <= expiryTime
        }
        
        // Check both days
        return checkDay(today) || checkDay(yesterday)
    }
    
    private func handleCheckInTimeChange(_ newTime: Date) {
        // Clear all expiry times when check-in time changes
        // We can do this because all check-ins must have been completed prior to clearing this out
        userSettings.updateExpiryTimes([:])
        
        // Update the check-in time
        userSettings.checkInTime = newTime
    }
}

// MARK: - Check-in Personality Enum
enum CheckInPersonality: Int, CaseIterable {
    case cheerleader = 1
    case minimalist = 2
    case disciplinarian = 3
    
    var title: String {
        switch self {
        case .cheerleader: 
            return "Cheerleader"
        case .minimalist: 
            return "Minimalist"
        case .disciplinarian: 
            return "Disciplinarian"
        }
    }
    
    var description: String {
        switch self {
        case .cheerleader:
            return "Positive, encouraging and celebrates your achievements."
        case .minimalist:
            return "Direct and concise with minimal interaction."
        case .disciplinarian:
            return "Strict and focused on accountability and results."
        }
    }
}

// Theme info popover
struct ThemeInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme Unlocking")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 4)
            
            Text("Themes are unlocked with check-in points. For every week streak you start earning +1 more per day.\n\nWeek 1: +1/day\nWeek 2: +2/day\n...\nWeek 5: +5/day\n\nStreaks reset if you miss a day.")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
        }
        .padding()
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .presentationCompactAdaptation(.none)
    }
}

// Theme preview button component
struct ThemePreviewButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                // Theme thumbnail
                theme.thumbnailView()
                    .frame(width: 80, height: 80)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                // Theme name
                Text(theme.rawValue)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            .frame(width: 90)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Check-in info popover
struct CheckInInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Check-ins are a way to keep you accountable.\n\nEach day you will have the opportunity to check in and analyze your progress.\n\nYou have 12 hours from the check-in time to \"check in\" for that day. ")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
        }
        .padding()
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .presentationCompactAdaptation(.none)
    }
}

// Chat info popover
struct ChatInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chat allows you to interact with Alfred, your personalized assistant.\n\nAlfred keeps you accountable during check-ins, but he can also generate reminders, create tasks, and plan out daily steps towards long term goals.")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
        }
        .padding()
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .presentationCompactAdaptation(.popover)
    }
}
