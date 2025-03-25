import SwiftUI

// Notification names for checklist minimize/expand
extension Notification.Name {
    static let minimizeChecklist = Notification.Name("minimizeChecklist")
    static let expandChecklist = Notification.Name("expandChecklist")
    static let fullExpandChecklist = Notification.Name("fullExpandChecklist")
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

struct DayView: View, Hashable {
    @EnvironmentObject private var focusManager: FocusManager
    @State private var currentDate: Date
    @State private var dragOffset = CGSize.zero
    @State private var rotation = Angle.zero
    @State private var isListEditing = false
    @Binding var showMenu: Bool
    @Environment(\.dismiss) private var dismiss
    
    let date: Date
    var animationID: Namespace.ID? = nil
    var onBack: (() -> Void)? = nil
    
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
        self.date = date
        self._currentDate = State(initialValue: date)
        self._showMenu = showMenu
        self.animationID = animationID
        self.onBack = onBack
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
        currentDate = newDate
        
        // If week view is expanded, update the week dates to show the week containing the new date
        if isDateHeaderExpanded {
            updateWeekDates(for: newDate)
        }
    }
    
    private func removeAllFocus() {
        focusManager.removeAllFocus()
    }
    
    // Inside DayView struct, add these state variables
    @State private var isDateHeaderExpanded = true
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
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                // Header
                HStack {
                    Button(action: {
                        if let onBack = onBack {
                            onBack()
                        } else {
                            NavigationUtil.navigationPath.removeLast()
                            NavigationUtil.navigationPath.append(CalendarView(initialDate: currentDate))
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
                            
                            // Use a consistent animation throughout
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isDateHeaderExpanded.toggle()
                                if isDateHeaderExpanded {
                                    updateWeekDates(for: currentDate)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
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
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
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
                            ForEach(weekViewDates) { weekDay in
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
                                            .font(.system(size: 14, weight: weekDay.isToday ? .bold : .medium))
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 28, height: 40)
                                    .background(
                                        ZStack {
                                            // Background circle
                                            Circle()
                                                .fill(weekDay.isSelected ? Color.black.opacity(0.15) : Color.clear)
                                                .frame(width: 32, height: 32)
                                            
                                            // Border for selected day
                                            if weekDay.isSelected {
                                                Circle()
                                                    .stroke(Color.white, lineWidth: 0.5)
                                                    .opacity(0.3)
                                                    .frame(width: 32, height: 32)
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
                
                // EasyListView with gesture and animation
                EasyListView(date: currentDate)
                    .frame(height: geometry.size.height - (isDateHeaderExpanded ? 110 : 52)) // Adjust height when week view is visible
                    .id(currentDate)
                    .offset(x: dragOffset.width, y: dragOffset.height)
                    .rotationEffect(rotation)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                                // Calculate rotation based on horizontal and vertical movement
                                let rotationFactor = Double(dragOffset.width / 40)
                                let verticalFactor = Double(dragOffset.height / 55)
                                rotation = Angle(degrees: rotationFactor + verticalFactor)
                            }
                            .onEnded { value in
                                focusManager.removeAllFocus() //should save off everything in the EasyListView
                                let horizontalAmount = value.translation.width
                                let verticalAmount = value.translation.height
                                
                                // Check if the swipe is primarily horizontal
                                if abs(horizontalAmount) > 50 && abs(verticalAmount) < 100 {
                                    let isLeftSwipe = horizontalAmount < 0
                                    
                                    // Animate the card off screen
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        dragOffset = CGSize(
                                            width: isLeftSwipe ? -geometry.size.width * 1.5 : geometry.size.width * 1.5,
                                            height: 0
                                        )
                                        rotation = Angle(degrees: isLeftSwipe ? -10 : 10)
                                    }
                                    
                                    // Update to new date after a short delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        if isLeftSwipe {
                                            updateToNewDate(Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate)
                                        } else {
                                            updateToNewDate(Calendar.current.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate)
                                        }
                                        
                                        // Reset position with animation, but with inverted rotation for incoming view
                                        dragOffset = CGSize(
                                            width: isLeftSwipe ? geometry.size.width * 1.5 : -geometry.size.width * 1.5,
                                            height: 0
                                        )
                                        // Set initial rotation in opposite direction for incoming view
                                        rotation = Angle(degrees: isLeftSwipe ? 10 : -10)
                                        
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                            dragOffset = .zero
                                            rotation = .zero
                                        }
                                    }
                                } else {
                                    // Reset position if swipe wasn't far enough
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        dragOffset = .zero
                                        rotation = .zero
                                    }
                                }
                            }
                    )
            }
            .onChange(of: showMenu) { oldValue, newValue in
                if newValue {
                    removeAllFocus()
                }
            }
            .onAppear {
                // Prepare all haptic feedback generators
                feedbackGenerator.prepare()
                dateHeaderFeedbackGenerator.prepare()
                selectionFeedbackGenerator.prepare()
                
                // Ensure week dates are updated if the week view is expanded
                if isDateHeaderExpanded {
                    updateWeekDates(for: currentDate)
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
        }
        .navigationBarBackButtonHidden(true)
        .preference(key: RemoveFocusPreferenceKey.self, value: FocusRemovalAction(removeAllFocus: removeAllFocus))
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

