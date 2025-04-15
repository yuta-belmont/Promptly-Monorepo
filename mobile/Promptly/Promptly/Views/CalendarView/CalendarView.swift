import SwiftUI

struct CalendarView: View, Hashable {
    @State private var selectedDate: Date?
    @State private var currentMonth: Date
    @State private var slideOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @State private var hasNavigatedToToday = false
    
    // Auto-navigation flag
    let autoNavigateToToday: Bool
    
    // Animation namespace
    var todayID: Namespace.ID?
    
    // Date selection callback
    var onDateSelected: ((Date) -> Void)?
    
    init(autoNavigateToToday: Bool = false, todayID: Namespace.ID? = nil, onDateSelected: ((Date) -> Void)? = nil, initialDate: Date = Date()) {
        self.autoNavigateToToday = autoNavigateToToday
        self.todayID = todayID
        self.onDateSelected = onDateSelected
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: initialDate)
        self._currentMonth = State(initialValue: calendar.date(from: components) ?? Date())
    }
    
    // Hashable conformance
    static func == (lhs: CalendarView, rhs: CalendarView) -> Bool {
        return true // CalendarView instances are considered equal
    }
    
    func hash(into hasher: inout Hasher) {
        // Use a constant value since all instances are considered equal
        hasher.combine(0)
    }
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    private func saveCurrentMonth() {
        // No need to save current month as it's recalculated on each view appearance
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Calendar section (top ~60%)
                    VStack(spacing: 20) {
                        // Month navigation
                        HStack {
                            Button(action: previousMonth) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            Text(monthYearString(from: currentMonth))
                                .font(.title2)
                                .bold()
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button(action: nextMonth) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Days of week header
                        HStack {
                            ForEach(daysOfWeek, id: \.self) { day in
                                Text(day)
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        // Calendar grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                            ForEach(daysInMonth(), id: \.self) { date in
                                if let date = date {
                                    // All days use the same animation approach
                                    DayCell(date: date, isToday: calendar.isDateInToday(date), animationID: todayID, onDateSelected: onDateSelected)
                                } else {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fill)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 20)
                    .frame(height: geometry.size.height * 0.5)
                    .offset(x: slideOffset)
                    .contentShape(Rectangle())  // Make the entire area tappable
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Update slide offset based on drag
                                slideOffset = value.translation.width
                            }
                            .onEnded { value in
                                // Determine if we should change months based on drag distance and velocity
                                let threshold: CGFloat = 50
                                let velocity = value.predictedEndLocation.x - value.location.x
                                
                                if abs(value.translation.width) > threshold || abs(velocity) > 100 {
                                    let isNext = value.translation.width < 0
                                    
                                    // First, animate the current view off screen
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        slideOffset = isNext ? -geometry.size.width : geometry.size.width
                                    }
                                    
                                    // Update the month while the view is off screen
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        if isNext {
                                            nextMonth()
                                        } else {
                                            previousMonth()
                                        }
                                        
                                        // Start from the opposite side
                                        slideOffset = isNext ? geometry.size.width : -geometry.size.width
                                        
                                        // Animate back to center
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            slideOffset = 0
                                        }
                                    }
                                } else {
                                    // Return to original position if not dragged far enough
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        slideOffset = 0
                                    }
                                }
                            }
                    )
                    
                    // Dashboard section (bottom ~50%)
                    DashboardView(onTodayButtonTapped: {
                        // Add haptic feedback
                        let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
                        feedbackGenerator.impactOccurred()
                        
                        if let onDateSelected = onDateSelected {
                            onDateSelected(Date())
                        } else {
                            NavigationUtil.navigationPath.append(DayView(date: Date()))
                        }
                    })
                    .frame(height: geometry.size.height * 0.5)
                    .padding(.top, 5)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: currentMonth) { _ in
            saveCurrentMonth()
        }
        .onAppear {
            if autoNavigateToToday && !hasNavigatedToToday {
                // Use a timer to navigate after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let todayView = DayView(date: Date())
                    NavigationUtil.navigationPath.append(todayView)
                    hasNavigatedToToday = true
                }
            }
        }
    }
    
    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func daysInMonth() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: interval.start))
        else { return [] }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let numberOfDaysInMonth = calendar.range(of: .day, in: .month, for: firstDayOfMonth)?.count ?? 0
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        
        for day in 1...numberOfDaysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        let remainingDays = 42 - days.count // 6 weeks * 7 days = 42
        days.append(contentsOf: Array(repeating: nil, count: remainingDays))
        
        return days
    }
}

struct DayCell: View {
    let date: Date
    let isToday: Bool
    var animationID: Namespace.ID? = nil
    @State private var isGlowing: Bool = false
    @State private var showOutline: Bool = false
    let onDateSelected: ((Date) -> Void)?
    
    private var dayNumber: String {
        let calendar = Calendar.current
        return "\(calendar.component(.day, from: date))"
    }
    
    private var dateID: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "day-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
    
    var body: some View {
        ZStack {
            // Add black background with white stroke
            Circle()
                .fill(Color.black.opacity(0.4))
                .overlay(
                    Group {
                        // Default outline
                        Circle()
                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                        
                        // Animated outline that appears with the glow
                        if showOutline {
                            Circle()
                                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                        }
                    }
                )
            
            // Glow effect
            if isGlowing {
                Circle()
                    .fill(Color.white)
                    .blur(radius: 8)
                    .opacity(0.15)
            }
            
            if animationID != nil {
                Circle()
                    .fill(isToday ? Color.blue.opacity(0.3) : Color.clear)
                    .matchedGeometryEffect(id: "background-\(dateID)", in: animationID!)
                
                // Use a container with fixed size for the text to prevent truncation during animation
                Text(dayNumber)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
                    .matchedGeometryEffect(id: "text-\(dateID)", in: animationID!, properties: .position)
                    .frame(maxWidth: .infinity)
            } else {
                Circle()
                    .fill(isToday ? Color.blue.opacity(0.3) : Color.clear)
                
                Text(dayNumber)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .contentShape(Rectangle()) // Make the entire view tappable
        .onTapGesture {
            // Trigger tap glow animation and outline
            isGlowing = true
            showOutline = true
            
            // Handle navigation
            if let onDateSelected = onDateSelected {
                onDateSelected(date)
            } else {
                NavigationUtil.navigationPath.append(DayView(date: date))
            }
            
            // Animate the glow and outline back
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isGlowing = false
                    showOutline = false
                }
            }
        }
    }
} 
