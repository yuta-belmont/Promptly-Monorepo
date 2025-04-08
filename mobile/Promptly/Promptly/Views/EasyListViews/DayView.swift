import SwiftUI
import Combine

// Notification names for checklist minimize/expand
extension Notification.Name {
    static let minimizeChecklist = Notification.Name("minimizeChecklist")
    static let expandChecklist = Notification.Name("expandChecklist")
    static let fullExpandChecklist = Notification.Name("fullExpandChecklist")
    static let showItemDetails = Notification.Name("ShowItemDetails")
}

// Add at the top with other preference keys
struct FocusRemovalAction: Equatable {
    let id = UUID()
    let removeAllFocus: () -> Void
    
    static func == (lhs: FocusRemovalAction, rhs: FocusRemovalAction) -> Bool {
        return lhs.id == rhs.id
    }
}

struct RemoveFocusPreferenceKey: PreferenceKey {
    static var defaultValue: FocusRemovalAction? = nil
    static func reduce(value: inout FocusRemovalAction?, nextValue: () -> FocusRemovalAction?) {
        value = nextValue()
    }
}

// Add at the top with other preference keys and structs
struct WeekViewDay: Identifiable {
    let id = UUID()
    let date: Date
    let isSelected: Bool
    let isToday: Bool
}

struct SlideInTransitionModifier: ViewModifier {
    let isExpanded: Bool
    let geometry: GeometryProxy
    
    func body(content: Content) -> some View {
        content
            .opacity(isExpanded ? 1 : 0)
            .offset(y: isExpanded ? 0 : -20)
    }
}

// Add at the top with other preference keys and structs
struct WaveShape: Shape {
    var progress: CGFloat
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Calculate the y position of the wave center
        let progressHeight = rect.height * progress
        let waveCenter = progressHeight
        
        // Dynamic wave height that grows with progress
        let minHeight: CGFloat = 10
        let maxHeight: CGFloat = 350
        let heightProgress = min(progress, 1.0) // Expand in first half of animation
        let currentHeight = minHeight + (maxHeight - minHeight) * heightProgress
        
        let startY = max(0, waveCenter - currentHeight/2)
        let endY = min(rect.height, waveCenter + currentHeight/2)
        
        path.move(to: CGPoint(x: 0, y: startY))
        path.addLine(to: CGPoint(x: rect.width, y: startY))
        path.addLine(to: CGPoint(x: rect.width, y: endY))
        path.addLine(to: CGPoint(x: 0, y: endY))
        path.closeSubpath()
        
        return path
    }
}

// Add this new view at the top level of the file
struct CheckInButton: View {
    @StateObject private var userSettings = UserSettings.shared
    let currentMinute: Date
    let currentDate: Date
    let onCheckIn: () -> Void
    
    private var shouldShow: Bool {
        
        let calendar = Calendar.current
        let now = currentMinute
        
        // If we've already checked in on the day we're viewing, don't show the button
        if calendar.isDate(userSettings.lastCheckin, inSameDayAs: currentDate) {
            return false
        }
        
        // Don't show button if last check-in is ahead of the current day
        if calendar.compare(userSettings.lastCheckin, to: currentDate, toGranularity: .day) == .orderedDescending {
            return false
        }
        
        // Only show button for today or yesterday
        let isToday = calendar.isDate(currentDate, inSameDayAs: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let isYesterday = calendar.isDate(currentDate, inSameDayAs: yesterday)
        
        if !isToday && !isYesterday {
            return false
        }
        
        // Get the check-in time for the day we're viewing
        let checkInTime = userSettings.checkInTime
        let checkInComponents = calendar.dateComponents([.hour, .minute], from: checkInTime)
        
        // Create a date with the viewed day's date but the check-in time
        let viewedDayCheckInTime = calendar.date(bySettingHour: checkInComponents.hour ?? 0,
                                               minute: checkInComponents.minute ?? 0,
                                               second: 0, 
                                               of: currentDate) ?? currentDate
        
        // If we're past the check-in time for the viewed day
        if now >= viewedDayCheckInTime {
            // Convert current date to string key
            let dayKey = userSettings.dateFormatter.string(from: currentDate)
                        
            // Check if we're within the expiry time
            if let expiryTime = userSettings.checkInButtonExpiryTimes[dayKey] {
                let isWithinExpiry = now <= expiryTime
                return isWithinExpiry
            }
        }
        
        return false
    }
    
    var body: some View {
        Group {
            if shouldShow {
                Button(action: onCheckIn) {
                    Text("check-in")
                        .font(.caption)
                        .fontWeight(.regular)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 1, y: 1)
                }
            }
        }
    }
}

struct DayView: View, Hashable {
    @EnvironmentObject private var focusManager: FocusManager
    
    @State private var currentDate: Date
    @State private var dragOffset = CGSize.zero
    @State private var rotation = Angle.zero
    @State private var isListEditing = false
    @Binding var showMenu: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showCheckInButton = true
    @State private var isAnimatingCheckIn = false
    @State private var waveProgress: CGFloat = -0.1 // Start slightly above screen
    @StateObject private var userSettings = UserSettings.shared
    @State private var currentMinute = Date()  // Add state for current minute
    
    // Timer to update current minute
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // Create a StateObject for the EasyListViewModel
    @StateObject private var easyListViewModel: EasyListViewModel
    
    // State for ItemDetailsView
    @State private var showingItemDetails = false
    @State private var selectedItem: Models.ChecklistItem?
    
    let date: Date
    var animationID: Namespace.ID? = nil
    var onBack: (() -> Void)? = nil
    
    // Date formatter for consistent logging
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private let calendar = Calendar.current
    private var isToday: Bool {
        calendar.isDateInToday(currentDate)
    }
    
    private var isPastDay: Bool {
        calendar.compare(currentDate, to: Date(), toGranularity: .day) == .orderedAscending
    }
    
    private var isFutureDay: Bool {
        calendar.compare(currentDate, to: Date(), toGranularity: .day) == .orderedDescending
    }
    
    private var dateID: String {
        let components = calendar.dateComponents([.year, .month, .day], from: currentDate)
        return "day-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
    
    // Hashable conformance
    static func == (lhs: DayView, rhs: DayView) -> Bool {
        return Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(Calendar.current.startOfDay(for: date))
    }
    
    init(date: Date = Date(), showMenu: Binding<Bool> = .constant(false), animationID: Namespace.ID? = nil, onBack: (() -> Void)? = nil) {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        self.date = date
        self._currentDate = State(initialValue: date)
        self._showMenu = showMenu
        self.animationID = animationID
        self.onBack = onBack
        // Initialize the EasyListViewModel with the current date
        self._easyListViewModel = StateObject(wrappedValue: EasyListViewModel(date: date))
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: currentDate)
    }
    
    // Haptic feedback generator for go to today button only
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // Add a second haptic feedback generator specifically for the date header interactions
    private let dateHeaderFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    private func updateToNewDate(_ newDate: Date) {
        // Do this first to minimize time between UI updates
        easyListViewModel.updateToDate(newDate)
        
        // Update UI state after data is ready
        currentDate = newDate
        
        // If week view is expanded, update the week dates to show the week containing the new date
        if isDateHeaderExpanded {
            // Use async to avoid layout issues during transitions
            DispatchQueue.main.async {
                self.updateWeekDates(for: newDate)
            }
        }
    }
    
    // Optimized swipe handling - reduce animation complexity
    private func handleSwipe(horizontalAmount: CGFloat, in geometry: GeometryProxy) {
        focusManager.removeAllFocus() //should save off everything in the EasyListView
        
        // Check if the swipe is far enough horizontally
        if abs(horizontalAmount) > 50 {
            let isLeftSwipe = horizontalAmount < 0
            let nextDay = Calendar.current.date(
                byAdding: .day, 
                value: isLeftSwipe ? 1 : -1, 
                to: currentDate
            ) ?? currentDate
            
            // Start updating the data model immediately
            let animationDuration: Double = 0.3
            
            // Animate the card off screen with simpler animation
            withAnimation(.easeOut(duration: animationDuration)) {
                dragOffset = CGSize(
                    width: isLeftSwipe ? -geometry.size.width * 1.5 : geometry.size.width * 1.5,
                    height: 0
                )
                // Use smaller rotation for better performance
                rotation = Angle(degrees: isLeftSwipe ? -5 : 5)
            }
            
            // Update the date while animation is happening
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration / 2) {
                updateToNewDate(nextDay)
            }
            
            // Reset position with animation
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                dragOffset = CGSize(
                    width: isLeftSwipe ? geometry.size.width * 1.5 : -geometry.size.width * 1.5,
                    height: 0
                )
                rotation = Angle(degrees: isLeftSwipe ? 5 : -5)
                
                // Use a simpler animation for the incoming view
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = .zero
                    rotation = .zero
                }
            }
        } else {
            // Reset position if swipe wasn't far enough - use simpler animation
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffset = .zero
                rotation = .zero
            }
        }
    }
    
    private func removeAllFocus() {
        focusManager.removeAllFocus()
    }
    
    // Inside DayView struct, add these state variables
    @State private var isDateHeaderExpanded = false
    @State private var weekViewDates: [WeekViewDay] = []
    @State private var weekOffset = 0
    @State private var weekDragOffset = CGSize.zero
    @State private var weekVerticalDragOffset: CGFloat = 0
    @State private var weekAnimationDirection: Int = 0 // -1 for left, 1 for right, 0 for none
    
    // Add this function inside DayView struct to calculate week dates
    private func updateWeekDates(for baseDate: Date = Date()) {
        // Get the first day of the week (Sunday) for the week containing baseDate
        var calendarForWeek = Calendar.current
        calendarForWeek.firstWeekday = 1 // Make sure Sunday is first day of week
        
        let dateComponents = calendarForWeek.dateComponents([.yearForWeekOfYear, .weekOfYear], from: baseDate)
        guard let startOfWeek = calendarForWeek.date(from: dateComponents) else { return }
        
        // If the calculated start date isn't a Sunday, adjust to the previous Sunday
        let weekday = calendarForWeek.component(.weekday, from: startOfWeek)
        let daysToSubtract = weekday - 1
        
        // Get the actual Sunday start of the week
        guard let sundayStartOfWeek = calendarForWeek.date(byAdding: .day, value: -daysToSubtract, to: startOfWeek) else { return }
        
        var newWeekDates: [WeekViewDay] = []
        for dayOffset in 0..<7 {
            if let dayDate = calendarForWeek.date(byAdding: .day, value: dayOffset, to: sundayStartOfWeek) {
                let isSelected = calendarForWeek.isDate(dayDate, inSameDayAs: currentDate)
                let isToday = calendarForWeek.isDateInToday(dayDate)
                newWeekDates.append(WeekViewDay(date: dayDate, isSelected: isSelected, isToday: isToday))
            }
        }
        
        weekViewDates = newWeekDates
    }
    
    // Lazy initializer for week dates - only called when needed
    private var lazyWeekDates: [WeekViewDay] {
        if weekViewDates.isEmpty && isDateHeaderExpanded {
            // This runs only once when needed
            DispatchQueue.main.async {
                self.updateWeekDates(for: self.currentDate)
            }
        }
        return weekViewDates
    }
    
    // Update the handleCheckIn method
    private func handleCheckIn() {
        let calendar = Calendar.current
        let now = Date()
        
        // Check if last check-in was today or yesterday
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let isLastCheckInToday = calendar.isDate(userSettings.lastCheckin, inSameDayAs: now)
        let isLastCheckInYesterday = calendar.isDate(userSettings.lastCheckin, inSameDayAs: yesterday)
        
        // Set lastCheckin to the exact day we're viewing in the DayView
        userSettings.lastCheckin = currentDate
        
        // Prepare and trigger haptic feedback
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
        
        // Hide button and start animation immediately
        withAnimation(.easeInOut(duration: 0.3)) {
            showCheckInButton = false
            isAnimatingCheckIn = true
        }
        
        // Start wave animation immediately
        withAnimation(.easeOut(duration: 1.0)) {
            waveProgress = 1.1 // Move past bottom of screen
        }
        
        // Update check-in stats
        if isLastCheckInToday || isLastCheckInYesterday {
            // Increment streak if last check-in was today or yesterday
            userSettings.streak += 1
        } else {
            // Reset streak if not consecutive
            userSettings.streak = 1
        }
        
        // Calculate and update check-in points
        let streakBonus = Int(ceil(Double(userSettings.streak) / 7.0))
        userSettings.checkinPoints += streakBonus
        
        // Clean up after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                isAnimatingCheckIn = false
                waveProgress = -0.1 // Reset for next time
                showCheckInButton = true // Show the button again
            }
        }
        
        // Only proceed with chat-related operations if chat is enabled
        if userSettings.isChatEnabled {
            // Get the current checklist data
            let checklist = easyListViewModel.getChecklistForCheckin()
            
            // Try server check-in first
            Task {
                do {
                    let dictChecklist = easyListViewModel.getChecklistDictionaryForCheckin()
                    try await _ = ChatService.shared.handleCheckin(checklist: dictChecklist)
                } catch {
                    // If server check-in fails, fall back to offline processing
                    await ChatViewModel.shared.handleOfflineCheckIn(checklist: checklist)
                }
            }
        }
    }
    
    private func setupExpiryTimeIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        
        // Get the check-in time for the day we're viewing
        let checkInTime = userSettings.checkInTime
        let checkInComponents = calendar.dateComponents([.hour, .minute], from: checkInTime)
        
        // Helper function to set up expiry time for a specific day
        func setupExpiryTime(for day: Date) {
            // Convert day to string key
            let dayKey = userSettings.dateFormatter.string(from: day)
            
            // Only set up if we don't have an expiry time for this day
            guard userSettings.checkInButtonExpiryTimes[dayKey] == nil else {
                print("[Check-in] Expiry time already set for \(dayKey): \(userSettings.checkInButtonExpiryTimes[dayKey]?.description ?? "nil")")
                return
            }
            
            // Create a date with the day's date but the check-in time
            let dayCheckInTime = calendar.date(bySettingHour: checkInComponents.hour ?? 0,
                                            minute: checkInComponents.minute ?? 0,
                                            second: 0,
                                            of: day) ?? day
            
            // Set expiry time to 12 hours after check-in time
            let expiryTime = calendar.date(byAdding: .hour, value: 12, to: dayCheckInTime) ?? dayCheckInTime
            
            // Create a new dictionary with the updated expiry time
            var updatedTimes = userSettings.checkInButtonExpiryTimes
            updatedTimes[dayKey] = expiryTime
            
            // Update using the proper method
            userSettings.updateExpiryTimes(updatedTimes)
            print("[Check-in] Set expiry time for \(dayKey) to: \(expiryTime.description)")
        }
        
        // Set up expiry time for today
        setupExpiryTime(for: now)
        
        // Set up expiry time for yesterday
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
            setupExpiryTime(for: yesterday)
        }
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 10) {
                    // Header
                    HStack {
                        Button(action: {
                            if let onBack = onBack {
                                onBack()
                            } else {
                                // Fallback to dismiss if no onBack provided
                                dismiss()
                            }
                        }) {
                            Image(systemName: "calendar")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 0) {
                            // Date header with chevron (stays in place)
                            HStack {
                                if animationID != nil {
                                    Text(formattedDate)
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                        .matchedGeometryEffect(id: "text-\(dateID)", in: animationID!, properties: .position)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .lineLimit(1)
                                } else {
                                    Text(formattedDate)
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                        .fixedSize(horizontal: true, vertical: false)
                                        .lineLimit(1)
                                }
                                
                                Image(systemName: isDateHeaderExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Trigger haptic feedback
                                dateHeaderFeedbackGenerator.prepare()
                                dateHeaderFeedbackGenerator.impactOccurred()
                                
                                // Toggle the expanded state first
                                isDateHeaderExpanded.toggle()
                                
                                // Use a consistent animation throughout
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    // Only populate week dates if expanding
                                    if isDateHeaderExpanded {
                                        updateWeekDates(for: currentDate)
                                    }
                                }
                            }
                        }
                        
                        Spacer()

                        CheckInButton(currentMinute: currentMinute, currentDate: currentDate, onCheckIn: handleCheckIn)
                        
                        if !isToday {
                            Button(action: {
                                // Prepare and trigger haptic feedback
                                feedbackGenerator.prepare()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    feedbackGenerator.impactOccurred()
                                }
                                updateToNewDate(Date())
                            }) {
                                HStack(spacing: 4) {
                                    if isFutureDay {
                                        Image(systemName: "arrow.left")
                                            .font(.system(size: 10))
                                    }
                                    
                                    Text("today")
                                        .font(.caption)
                                        .fontWeight(.regular)
                                    
                                    if !isFutureDay {
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10))
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 1, y: 1)
                            }
                        }

                        // Main Menu Button
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showMenu = true
                            }
                        }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(.leading, 16)
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 0)
                    .zIndex(2)
                    
                    // Week view between header and EasyListView
                    if isDateHeaderExpanded {
                        // Swipeable week view
                        ZStack {
                            // Day circles - centered
                            HStack(spacing: 16) {
                                ForEach(lazyWeekDates) { weekDay in
                                    Button(action: {
                                        // Trigger haptic feedback when selecting a new day
                                        selectionFeedbackGenerator.prepare()
                                        selectionFeedbackGenerator.impactOccurred()
                                        
                                        // Only update the date without modifying the week view
                                        updateToNewDate(weekDay.date)
                                    }) {
                                        VStack(spacing: 2) {
                                            // Day of week
                                            Text(dayOfWeekLetter(for: weekDay.date))
                                                .font(.system(size: 10))
                                                .foregroundColor(weekDay.isToday ? .white : .white.opacity(0.9))
                                                .fontWeight(weekDay.isToday ? .bold : .regular)
                                            
                                            // Day number
                                            Text("\(dayNumber(for: weekDay.date))")
                                                .font(.system(size: weekDay.isToday ? 15 : 14, weight: weekDay.isToday ? .bold : .medium))
                                                .foregroundColor(.white)
                                        }
                                        .frame(width: 28, height: 40)
                                        .background(
                                            ZStack {
                                                // Background circle
                                                Circle()
                                                    .fill(weekDay.isSelected ? Color.black.opacity(0.15) : Color.clear)
                                                    .frame(width: 36, height: 36)
                                                
                                                // Border for selected day
                                                if weekDay.isSelected {
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: 0.5)
                                                        .opacity(0.3)
                                                        .frame(width: 36, height: 36)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .offset(
                                x: weekDragOffset.width,
                                y: 0 // No vertical movement at all
                            )
                        }
                        .frame(height: 46)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    // Only track horizontal movement
                                    weekDragOffset.width = value.translation.width
                                    // Set animation direction based on drag direction
                                    weekAnimationDirection = weekDragOffset.width > 0 ? -1 : 1
                                }
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let threshold: CGFloat = 50
                                    
                                    // Check if drag was significant enough to trigger week change
                                    if abs(horizontalAmount) > threshold {
                                        // Determine direction
                                        let isSwipingToPreviousWeek = horizontalAmount > 0
                                        
                                        // Animate to edge to complete the transition
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            weekDragOffset.width = isSwipingToPreviousWeek ? 
                                                geometry.size.width : -geometry.size.width
                                        }
                                        
                                        // Update to new week
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            if isSwipingToPreviousWeek {
                                                // Previous week
                                                if let previousWeekDate = Calendar.current.date(
                                                    byAdding: .weekOfYear,
                                                    value: -1,
                                                    to: weekViewDates.first?.date ?? currentDate
                                                ) {
                                                    updateWeekDates(for: previousWeekDate)
                                                }
                                            } else {
                                                // Next week
                                                if let nextWeekDate = Calendar.current.date(
                                                    byAdding: .weekOfYear,
                                                    value: 1,
                                                    to: weekViewDates.first?.date ?? currentDate
                                                ) {
                                                    updateWeekDates(for: nextWeekDate)
                                                }
                                            }
                                            
                                            // Reset position but from opposite side for transition
                                            weekDragOffset.width = isSwipingToPreviousWeek ? 
                                                -geometry.size.width : geometry.size.width
                                            
                                            // Animate back to center
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                weekDragOffset.width = 0
                                            }
                                            
                                            // Reset animation direction
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                weekAnimationDirection = 0
                                            }
                                        }
                                    } else {
                                        // Not enough to trigger week change, animate back to center
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            weekDragOffset.width = 0
                                        }
                                        
                                        // Reset animation direction
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            weekAnimationDirection = 0
                                        }
                                    }
                                }
                        )
                        .modifier(SlideInTransitionModifier(isExpanded: isDateHeaderExpanded, geometry: geometry))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDateHeaderExpanded)
                        .padding(.bottom, 4)
                        .zIndex(1)
                    }
                    
                    // Wrap in Group with animation for smooth transitions
                    Group {
                        if !showingItemDetails {
                            // Only show EasyListView when not showing item details
                            EasyListView()
                                .environmentObject(easyListViewModel) // Make the view model available
                                .frame(height: max(0, geometry.size.height - (isDateHeaderExpanded ? 110 : 52))) // Adjust height when week view is visible
                                .offset(x: dragOffset.width, y: dragOffset.height)
                                .rotationEffect(rotation)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                .id("easyListView-\(currentDate.timeIntervalSince1970)") // Force complete view reconstruction
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            // Only track horizontal movement, ignore vertical
                                            dragOffset = CGSize(width: value.translation.width, height: 0)
                                            // Calculate rotation based only on horizontal movement
                                            let rotationFactor = Double(dragOffset.width / 40)
                                            rotation = Angle(degrees: rotationFactor)
                                        }
                                        .onEnded { value in
                                            handleSwipe(horizontalAmount: value.translation.width, in: geometry)
                                        }
                                )
                        } else {
                            // Using a clear spacer to maintain layout structure when EasyListView is removed
                            Color.clear
                                .frame(height: geometry.size.height - (isDateHeaderExpanded ? 110 : 52))
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: showingItemDetails)
                }
                .opacity(showingItemDetails ? 0 : 1) // Make the entire VStack transparent when showing item details
                .animation(.easeInOut(duration: 0.25), value: showingItemDetails)
                .onChange(of: showMenu) { oldValue, newValue in
                    if newValue {
                        removeAllFocus()
                    }
                }
                .onAppear {
                    // Set up expiry time if needed (when the check-in button expires)
                    setupExpiryTimeIfNeeded()
                    
                    // Prepare all haptic feedback generators
                    feedbackGenerator.prepare()
                    dateHeaderFeedbackGenerator.prepare()
                    selectionFeedbackGenerator.prepare()
                    
                    // Load data after the view has appeared and layout is complete
                    DispatchQueue.main.async {
                        easyListViewModel.loadData()
                    }
                    
                    let calendar = Calendar.current
                    let now = Date()
                    
                    // Get the check-in time components
                    let checkInTime = userSettings.checkInTime
                    let checkInComponents = calendar.dateComponents([.hour, .minute], from: checkInTime)
                    
                    // Create a date with today's date but the check-in time
                    let todayCheckInTime = calendar.date(bySettingHour: checkInComponents.hour ?? 0,
                                                       minute: checkInComponents.minute ?? 0,
                                                       second: 0,
                                                       of: now) ?? now
                    
                    // Add 1 second to the check-in time
                    let triggerTime = calendar.date(byAdding: .second, value: 1, to: todayCheckInTime) ?? todayCheckInTime
                    
                    // Calculate delay until trigger time
                    let delay = triggerTime.timeIntervalSince(now)
                    
                    if delay > 0 {
                        print("[Check-in] Setting timer to trigger in \(delay) seconds")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            print("\n[Check-in] Timer triggered at \(Date().description)")
                            currentMinute = Date()
                            print("[Check-in] Updated currentMinute to: \(currentMinute.description)")
                        }
                    }
                }
                .onDisappear {
                    // Reset any active animations and states when view disappears
                    weekDragOffset = .zero
                    weekVerticalDragOffset = 0
                    weekAnimationDirection = 0
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Save state or perform cleanup when app enters background
                    if !isDateHeaderExpanded {
                        // Ensure week view state is clean when not expanded
                        weekDragOffset = .zero
                        weekVerticalDragOffset = 0
                        weekAnimationDirection = 0
                        weekViewDates = []
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Restore state when app comes back to foreground
                    if isDateHeaderExpanded {
                        // Ensure week dates are updated
                        updateWeekDates(for: currentDate)
                    } else {
                        // Make sure week view is fully reset when not expanded
                        weekDragOffset = .zero
                        weekVerticalDragOffset = 0
                        weekAnimationDirection = 0
                        weekViewDates = []
                    }
                }
                // Listen for ShowItemDetails notification
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name.showItemDetails)) { notification in
                    // Handle receiving item ID instead of the full item
                    if let itemId = notification.object as? UUID {
                        // Clear all focus to ensure data is saved
                        removeAllFocus()
                        
                        // Fetch the latest version of the item directly from the view model
                        if let freshItem = easyListViewModel.getItem(id: itemId) {
                            // Update the selected item with the fresh version
                            selectedItem = freshItem
                            showingItemDetails = true
                        }
                    }
                }
                // Listen for ItemDetailsUpdated notification
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ItemDetailsUpdated"))) { notification in
                    if let updatedItemId = notification.object as? UUID {
                        // Reload the checklist data
                        DispatchQueue.main.async {
                            easyListViewModel.reloadChecklist()
                            
                            // Close the details view with animation
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showingItemDetails = false
                            }
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .preference(key: RemoveFocusPreferenceKey.self, value: FocusRemovalAction(removeAllFocus: removeAllFocus))
            
            // Wave overlay
            if isAnimatingCheckIn {
                ZStack {
                    // Main wave
                    WaveShape(progress: waveProgress)
                        .fill(Color.white)
                        .opacity(0.2 * (1 - waveProgress))
                        .blur(radius: 30)
                        .edgesIgnoringSafeArea(.all)
                    
                    // Glowing overlay
                    WaveShape(progress: waveProgress)
                        .fill(Color.white)
                        .opacity(0.15 * (1 - waveProgress))
                        .blur(radius: 60)
                        .edgesIgnoringSafeArea(.all)
                    
                    // Sharp center wave
                    WaveShape(progress: waveProgress)
                        .fill(Color.blue)
                        .opacity(0.1 * (1 - waveProgress))
                        .blur(radius: 10)
                        .edgesIgnoringSafeArea(.all)
                }
                .zIndex(997)
            }
            
            // ItemDetails overlay
            if showingItemDetails, let item = selectedItem {
                // Semi-transparent backdrop for closing the details view
                Color.black.opacity(0.01)
                    .edgesIgnoringSafeArea(.all)
                    .allowsHitTesting(true)
                    .transition(.opacity)
                    .zIndex(998)
                    .onTapGesture {
                        // Close if tap is outside the details view
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingItemDetails = false
                        }
                    }
                
                // ItemDetailsView overlay with matching transition
                ItemDetailsView(
                    item: item,
                    isPresented: $showingItemDetails
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingItemDetails)
    }
    
    // Add these helper functions inside DayView struct
    private func dayOfWeekLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(1))
    }
    
    private func dayNumber(for date: Date) -> Int {
        return Calendar.current.component(.day, from: date)
    }
} 

