//
//  ChatBubbleView.swift
//  Promptly
//
//  Created by Yuta Belmont on 2/27/25.
//
import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    var onReportTap: (() -> Void)? = nil
    @State private var isGlowing: Bool = false
    
    var body: some View {
        HStack {
            if message.role == MessageRoles.assistant {
                // Assistant's messages on the left
                VStack(alignment: .leading) {
                    // Regular assistant message with optional "Go To" arrow for reports
                    HStack(alignment: .center, spacing: 4) {
                        Text(message.content)
                        
                        // Add "Go To" arrow for report messages
                        if message.isReportMessage {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.white.opacity(0.9))
                                .font(.system(size: 14))
                        }
                    }
                    .padding(8)
                    .foregroundColor(.white)
                    .background(
                        ZStack {
                            Color.gray.opacity(0.5)
                            
                            // Glow effect when tapped
                            if isGlowing && message.isReportMessage {
                                Color.white
                                    .blur(radius: 8)
                                    .opacity(0.15)
                            }
                        }
                    )
                    .cornerRadius(16)
                    .overlay(
                        Group {
                            if message.isReportMessage {
                                // Default subtle outline for report messages
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                                
                                // Animated outline that appears when tapped
                                if isGlowing {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                                }
                            }
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()) // Ensure the entire area is tappable
                .onTapGesture {
                    if message.isReportMessage {
                        // Create haptic feedback
                        let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
                        feedbackGenerator.prepare()
                        feedbackGenerator.impactOccurred()
                        
                        // Start the glow animation
                        isGlowing = true
                        onReportTap?()
                        
                        // End the animation after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                isGlowing = false
                            }
                        }
                    }
                }
                
                Spacer(minLength: 50)
            } else {
                // User's messages on the right
                Spacer(minLength: 50)
                
                VStack(alignment: .trailing) {
                    Text(message.content)
                        .padding(8)
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(16)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
