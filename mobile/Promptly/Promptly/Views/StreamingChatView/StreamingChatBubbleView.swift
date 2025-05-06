import SwiftUI

struct StreamingChatBubbleView: View {
    @ObservedObject var message: StreamingChatMessage
    var onReportTap: (() -> Void)? = nil
    var onOutlineTap: (() -> Void)? = nil
    
    @State private var timeString: String = ""
    
    private var isUser: Bool {
        return message.role == "user"
    }
    
    private var backgroundColor: Color {
        if message.isError {
            return Color.red.opacity(0.8)
        } else if isUser {
            return Color.blue.opacity(0.8)
        } else {
            return Color.gray.opacity(0.8)
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
                let hasOutline = message.outline != nil || message.checklistOutline != nil
                let outlineStatus = hasOutline ? "HAS OUTLINE" : "NO OUTLINE"
                let messageText = message.content.prefix(20)
                
                // For outline building messages, show a special outline building bubble
                if message.isBuildingOutline {
                    OutlineBuildingBubble(message: message)
                }
                // For regular messages, show the standard bubble
                else {
                    // Message content
                    Text(message.content)
                        .font(.body)
                        .fontWeight(isUser ? .medium : .regular)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(backgroundColor)
                        )
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: alignment)
                        .contentShape(Rectangle())
                    
                    // Streaming indicator
                    if message.isStreaming {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 4, height: 4)
                                .opacity(0.7)
                                .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.0), value: message.isStreaming)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 4, height: 4)
                                .opacity(0.7)
                                .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.2), value: message.isStreaming)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 4, height: 4)
                                .opacity(0.7)
                                .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.4), value: message.isStreaming)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(backgroundColor.opacity(0.6))
                        )
                    }
                }
                
                // Outline button if available and complete
                if (message.outline != nil || message.checklistOutline != nil) && !isUser && !message.isBuildingOutline {
                    let _ = print("DEBUG BUBBLE VIEW: Showing outline button for message \(message.id)")
                    Button(action: {
                        print("DEBUG BUBBLE VIEW: Outline button tapped for message \(message.id)")
                        onOutlineTap?()
                    }) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("View Outline")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                        )
                        .foregroundColor(.white)
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75)
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
        .padding(.horizontal, 8)
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
                Text("Creating Outline")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                if !message.isComplete {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
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
                HStack {
                    Image(systemName: "text.quote")
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Summary")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
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
                } else if let outline = message.outline, outline.summary != "Building outline..." {
                    Text(outline.summary ?? "")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.leading, 4)
                } else {
                    Text("Building outline...")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.leading, 4)
                }
            }
            
            // Time Period section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Time Period")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Use temporary properties during streaming, falling back to CoreData properties if needed
                if let period = message.outlinePeriod, period != "Calculating..." {
                    HStack {
                        Text(period)
                            .font(.body)
                            .foregroundColor(.white)
                        
                        if let startDate = message.outlineStartDate, let endDate = message.outlineEndDate {
                            Text("\(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))")
                                .font(.body)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.leading, 4)
                } else if let outline = message.outline, outline.period != "Calculating..." {
                    HStack {
                        Text(outline.period ?? "")
                            .font(.body)
                            .foregroundColor(.white)
                        
                        if let startDate = outline.startDate, let endDate = outline.endDate {
                            Text("\(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))")
                                .font(.body)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.leading, 4)
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .opacity(0.7)
                            .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.0))
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .opacity(0.7)
                            .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.2))
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .opacity(0.7)
                            .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.4))
                    }
                    .padding(.leading, 4)
                }
            }
            
            // Items section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Details")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Use temporary properties during streaming, falling back to CoreData properties if needed
                if !message.outlineLineItems.isEmpty && !message.outlineLineItems.contains("Gathering items...") {
                    ForEach(message.outlineLineItems.prefix(3), id: \.self) { item in
                        Text("• \(item)")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.leading, 4)
                            .lineLimit(1)
                    }
                    
                    if message.outlineLineItems.count > 3 {
                        Text("+ \(message.outlineLineItems.count - 3) more items")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.leading, 4)
                    }
                } else if let outline = message.checklistOutline, let lineItems = outline.lineItem as? [String], !lineItems.contains("Gathering items...") {
                    ForEach(lineItems.prefix(3), id: \.self) { item in
                        Text("• \(item)")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.leading, 4)
                            .lineLimit(1)
                    }
                    
                    if lineItems.count > 3 {
                        Text("+ \(lineItems.count - 3) more items")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.leading, 4)
                    }
                } else if let outline = message.outline, let lineItems = outline.lineItem as? [String], !lineItems.contains("Gathering items...") {
                    ForEach(lineItems.prefix(3), id: \.self) { item in
                        Text("• \(item)")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.leading, 4)
                            .lineLimit(1)
                    }
                    
                    if lineItems.count > 3 {
                        Text("+ \(lineItems.count - 3) more items")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.leading, 4)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .opacity(0.7)
                            .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.0))
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .opacity(0.7)
                            .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.2))
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .opacity(0.7)
                            .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.4))
                    }
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
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.blue.opacity(0.6))
        )
        .frame(maxWidth: UIScreen.main.bounds.width * 0.75)
    }
} 
