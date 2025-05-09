import SwiftUI

struct StreamingChatBubbleView: View {
    @ObservedObject var message: StreamingChatMessage
    var onReportTap: (() -> Void)? = nil
    var onOutlineTap: (() -> Void)? = nil
    var onAccept: (() -> Void)? = nil
    var onDecline: (() -> Void)? = nil
    
    @State private var timeString: String = ""
    @State private var glowOpacity: Double = 0.1
    @State private var glowRadius: CGFloat = 2
    
    private var isUser: Bool {
        return message.role == "user"
    }
    
    private var backgroundColor: Color {
        if message.isError {
            return Color.red.opacity(0.8)
        } else if isUser {
            return Color.blue.opacity(0.8)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
    
    private var alignment: Alignment {
        return isUser ? .trailing : .leading
    }
    
    private var textAlignment: TextAlignment {
        return isUser ? .trailing : .leading
    }
    
    var body: some View {
        HStack {
            if isUser {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                // Debug printing for outline property
                let hasOutline = message.checklistOutline != nil || message.isBuildingOutline
                
                // For outline building messages, show a special outline building bubble
                if message.isBuildingOutline || message.checklistOutline != nil {
                    OutlineBuildingBubble(message: message, onOutlineTap: onOutlineTap)
                }
                // For empty streaming messages, show a glowing loading circle
                else if message.isStreaming && message.content.isEmpty && !isUser && !message.isBuildingOutline {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 19, height: 19)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(glowOpacity), lineWidth: 2)
                                .blur(radius: glowRadius)
                        )
                        .padding(8)
                        .onAppear {
                            // Create a more pronounced pulsing effect
                            withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                                glowOpacity = 0.9
                                glowRadius = 4
                            }
                        }
                }
                // For regular messages, show the standard bubble
                else {
                    // Message content
                    Text(message.content)
                        .font(.body)
                        .fontWeight(.regular)
                        .foregroundColor(message.isStreaming ? .white.opacity(0.4) : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if isUser {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(backgroundColor)
                                }
                            }
                        )
                        .frame(maxWidth: isUser ? UIScreen.main.bounds.width * 0.75 : .infinity, alignment: alignment)
                        .contentShape(Rectangle())
                        .onChange(of: message.isStreaming) { oldValue, newValue in
                            if !newValue {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    glowOpacity = 0.1
                                    glowRadius = 2
                                }
                            }
                        }
                        .onAppear {
                            if !message.isStreaming {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    glowOpacity = 0.1
                                    glowRadius = 2
                                }
                            }
                        }
                }
                
                // Report button for report messages
                if message.isReportMessage && !isUser {
                    Button(action: {
                        onReportTap?()
                    }) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("View Report")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.3))
                        )
                        .foregroundColor(.white)
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75)
                }
            }
            
            if !isUser {
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Add a specialized bubble view for outline building
struct OutlineBuildingBubble: View {
    @ObservedObject var message: StreamingChatMessage
    var onOutlineTap: (() -> Void)? = nil
    @State private var isPulsing = false
    @State private var animationTimer: Timer? = nil
    @State private var isTapped = false
    
    // Create and configure formatter outside the body
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with title and spinner
            HStack {
                Text(message.checklistOutline != nil ? "Created Outline" : "Creating Outline")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Add chevron indicator if outline is complete
                if message.checklistOutline != nil {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.bottom, 4)
            
            // Divide line
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 1)
                .padding(.vertical, 2)
            
            // Summary section
            VStack(alignment: .leading, spacing: 4) {
                Text("Summary")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                // Use temporary properties during streaming, falling back to CoreData properties if needed
                if let summary = message.outlineSummary, summary != "Building outline..." {
                    Text(summary)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.leading, 4)
                } else if let outline = message.checklistOutline, outline.summary != "Building outline..." {
                    Text(outline.summary ?? "")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.leading, 4)
                } else {
                    Text("Preparing summary...")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.leading, 4)
                }
            }
            
            // Time Period section
            VStack(alignment: .leading, spacing: 4) {
                Text("Time Period")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                // Use temporary properties during streaming, falling back to CoreData properties if needed
                if let startDate = message.outlineStartDate, let endDate = message.outlineEndDate {
                    Text("\(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.leading, 4)
                } else if let outline = message.checklistOutline, let startDate = outline.startDate, let endDate = outline.endDate {
                    Text("\(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.leading, 4)
                } else {
                    // Show a more descriptive placeholder
                    Text("Calculating date range...")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.leading, 4)
                }
            }
            
            // Items section
            VStack(alignment: .leading, spacing: 4) {
                Text("Details")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                // Use temporary properties during streaming, falling back to CoreData properties if needed
                if !message.outlineLineItems.isEmpty && !message.outlineLineItems.contains("Gathering items...") {
                    ForEach(message.outlineLineItems, id: \.self) { item in
                        Text("• \(item)")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.leading, 4)
                            .lineLimit(1)
                    }
                } else if let outline = message.checklistOutline, let lineItems = outline.lineItem as? [String], !lineItems.contains("Gathering items...") {
                    ForEach(lineItems, id: \.self) { item in
                        Text("• \(item)")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.leading, 4)
                            .lineLimit(1)
                    }
                } else {
                    // Replace animated circles with static placeholder text
                    Text("Creating detail items...")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.leading, 4)
                }
            }
            
            // Status message
            Text(message.content)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(message.isBuildingOutline ? (isPulsing ? 0.15 : 0.05) : (isTapped ? 0.2 : 0.1)))
        )
        .overlay(
            Group {
                if message.checklistOutline != nil {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(isTapped ? 0.15 : 0))
                        .blur(radius: isTapped ? 10 : 0)
                }
            }
        )
        .overlay(
            Group {
                if message.checklistOutline != nil {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(isTapped ? 0.4 : 0.2), lineWidth: isTapped ? 2 : 1)
                }
            }
        )
        .frame(maxWidth: UIScreen.main.bounds.width)
        .contentShape(Rectangle())
        .onTapGesture {
            // Only allow tapping if we have a complete outline
            if message.checklistOutline != nil {
                // Trigger haptic feedback
                let feedback = UIImpactFeedbackGenerator(style: .light)
                feedback.prepare()
                feedback.impactOccurred()
                
                // Animate the tap effect
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTapped = true
                }
                
                // Call the tap handler
                onOutlineTap?()
                
                // Reset the tap effect after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTapped = false
                    }
                }
            }
        }
        .onAppear {
            startPulsingAnimation()
        }
        .onDisappear {
            stopPulsingAnimation()
        }
        .onChange(of: message.isBuildingOutline) { oldValue, newValue in
            if newValue {
                startPulsingAnimation()
            } else {
                stopPulsingAnimation()
            }
        }
    }
    
    private func startPulsingAnimation() {
        guard message.isBuildingOutline else { return }
        
        // Cancel any existing timer
        animationTimer?.invalidate()
        
        // Create a new timer that toggles the pulsing state
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.7)) {
                isPulsing.toggle()
            }
        }
    }
    
    private func stopPulsingAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPulsing = false
    }
} 
