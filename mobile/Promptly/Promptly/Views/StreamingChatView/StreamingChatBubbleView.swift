import SwiftUI

struct StreamingChatBubbleView: View {
    @ObservedObject var message: StreamingChatMessage
    var onReportTap: (() -> Void)? = nil
    var onOutlineTap: (() -> Void)? = nil
    
    @State private var showTimestamp: Bool = false
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
                    .onTapGesture {
                        withAnimation {
                            showTimestamp.toggle()
                        }
                    }
                
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
                
                // Timestamp when visible
                if showTimestamp {
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                        .padding(.horizontal, 8)
                        .transition(.opacity)
                }
                
                // Outline button if available
                if let outline = message.outline, !isUser {
                    Button(action: {
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