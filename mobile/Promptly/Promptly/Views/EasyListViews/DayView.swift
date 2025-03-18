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
    
    private func updateToNewDate(_ newDate: Date) {
        currentDate = newDate
    }
    
    private func removeAllFocus() {
        focusManager.removeAllFocus()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content
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
                                    
                                    Text("go to today")
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
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .zIndex(2)
                    
                    // EasyListView replacing ChecklistView
                    EasyListView(date: currentDate)
                        .frame(height: geometry.size.height - 52)
                        .id(currentDate)
                        .onPreferenceChange(IsEditingPreferenceKey.self) { isEditing in
                            isListEditing = isEditing
                        }
                }
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
                            if abs(horizontalAmount) > 90 && abs(verticalAmount) < 70 {
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
        }
        .navigationBarBackButtonHidden(true)
        .preference(key: RemoveFocusPreferenceKey.self, value: FocusRemovalAction(removeAllFocus: removeAllFocus))
    }
} 

