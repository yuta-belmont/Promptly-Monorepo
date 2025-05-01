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
    var onOutlineTap: (() -> Void)? = nil
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
                        
                        // Add "Go To" arrow for outline messages
                        if message.outline != nil {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.white.opacity(0.9))
                                .font(.system(size: 14))
                        }
                    }
                    .padding(8)
                    .foregroundColor(.white)
                    .background(
                        ZStack {
                            // Make tappable bubbles darker
                            if message.isReportMessage || message.outline != nil {
                                Color.gray.opacity(0.2)  // Darker background for tappable bubbles
                            } else {
                                Color.gray.opacity(0.5)  // Regular background for non-tappable bubbles
                            }
                            
                            // Glow effect when tapped
                            if isGlowing && (message.isReportMessage || message.outline != nil) {
                                Color.white
                                    .blur(radius: 8)
                                    .opacity(0.15)
                            }
                        }
                    )
                    .cornerRadius(16)
                    .overlay(
                        Group {
                            if message.isReportMessage || message.outline != nil {
                                // More prominent outline for report/outline messages
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)  // More visible outline
                                
                                // Animated outline that appears when tapped
                                if isGlowing {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)  // Even more prominent when tapped
                                }
                            }
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()) // Ensure the entire area is tappable
                .onTapGesture {
                    if message.isReportMessage || message.outline != nil {
                        // Create haptic feedback
                        let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
                        feedbackGenerator.prepare()
                        feedbackGenerator.impactOccurred()
                        
                        // Start the glow animation
                        isGlowing = true
                        
                        // Call the appropriate handler
                        if message.isReportMessage {
                            onReportTap?()
                        } else if message.outline != nil {
                            onOutlineTap?()
                        }
                        
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
