import SwiftUI

struct GeneralSettingsView: View {
    @Binding var isPresented: Bool
    @StateObject private var themeManager = ThemeManager.shared
    @State private var dragOffset = CGSize.zero // Add drag offset for swipe gesture
    @State private var showingThemeInfo = false // State for the theme info popup
    
    // Check-in settings states
    @State private var isCheckInNotificationEnabled = true
    @State private var checkInTime = Date(timeIntervalSince1970: 
        TimeInterval(8 * 60 * 60)) // Default to 8 AM
    @State private var selectedPersonality: CheckInPersonality = .cheerleader
    @State private var objectives = ""
    
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
                    
                    Button("Done") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
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
                    }
                    .padding(.vertical)
                }
                .padding(.horizontal, 0)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.clear
                    .background(.ultraThinMaterial)
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
                        // Only allow dragging to the right
                        if value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss
                        if value.translation.width > 100 {
                            // Use animation to ensure smooth transition
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                        // If not dragged far enough, animate back to original position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
            )
            .transition(.move(edge: .trailing))
            .zIndex(999)
        }
    }
    
    // MARK: - Theme Section View
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                .popover(isPresented: $showingThemeInfo) {
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
        }
    }
    
    // MARK: - Check-in Section View
    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text("Check-in")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            // Notification toggle
            HStack {
                Text("Daily Reminder")
                    .foregroundColor(.white)
                
                Spacer()
                
                Toggle("", isOn: $isCheckInNotificationEnabled)
                    .labelsHidden()
            }
            .padding(.horizontal)
            
            // Time picker - only visible when notifications are enabled
            if isCheckInNotificationEnabled {
                HStack {
                    Text("Reminder Time")
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    DatePicker("", selection: $checkInTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .tint(.blue)
                }
                .padding(.horizontal)
                .transition(.opacity)
            }
            
            // Personality selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Assistant Personality")
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                Picker("Personality", selection: $selectedPersonality) {
                    ForEach(CheckInPersonality.allCases, id: \.self) { personality in
                        Text(personality.title)
                            .foregroundColor(.white)
                            .tag(personality)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Personality description
                Text(selectedPersonality.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut, value: selectedPersonality)
            }
            .padding(.top, 8)
            
            // Objectives text editor
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Objectives")
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $objectives)
                        .foregroundColor(.white)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    
                    if objectives.isEmpty {
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
                            Text("\(objectives.count)/200")
                                .font(.caption)
                                .foregroundColor(objectives.count > 200 ? .red : .gray)
                                .padding(4)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .padding(.horizontal)
                .onChange(of: objectives) { _, newValue in
                    if newValue.count > 200 {
                        objectives = String(newValue.prefix(200))
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Check-in Personality Enum
enum CheckInPersonality: String, CaseIterable {
    case cheerleader
    case minimalist
    case disciplinarian
    
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
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            .frame(width: 90)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
