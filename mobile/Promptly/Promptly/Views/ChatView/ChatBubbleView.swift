//
//  ChatBubbleView.swift
//  Promptly
//
//  Created by Yuta Belmont on 2/27/25.
//
import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == MessageRoles.assistant {
                // Assistant's messages on the left
                VStack(alignment: .leading) {
                    Text(message.content)
                        .padding(8)
                        .foregroundColor(.white)
                        .background(Color.gray.opacity(0.5))
                        .cornerRadius(16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
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
