import SwiftUI

struct ChatInputFieldView: View {
    @StateObject private var viewModel = ChatInputViewModel()
    @EnvironmentObject private var focusManager: FocusManager
    @FocusState private var isTextFieldFocused: Bool
    
    @Binding var userInput: String
    let onSend: () -> Void
    var isSendDisabled: Bool = false
    var isDraggingDown: Bool = false
    var isDisabled: Bool = false

    init(userInput: Binding<String>, onSend: @escaping () -> Void, isSendDisabled: Bool = false, isDragging: Bool = false, isDisabled: Bool = false) {
        self._userInput = userInput
        self.onSend = onSend
        self.isSendDisabled = isSendDisabled
        self.isDraggingDown = isDragging
        self.isDisabled = isDisabled
    }
    
    private var hasText: Bool {
        !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var shouldShowMic: Bool {
        !hasText && !viewModel.isRecording
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Message Alfred...", text: $userInput, axis: .vertical)
                .lineLimit(1...10)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                )
                .cornerRadius(16)
                .contentShape(Rectangle())
                .focused($isTextFieldFocused)
                .disabled(viewModel.isRecording || isDisabled)
                .opacity(viewModel.isRecording || isDisabled ? 0.6 : 1)
                .onChange(of: isTextFieldFocused) { oldValue, newValue in
                    if newValue {
                        focusManager.requestFocus(for: .chat)
                    }
                }
                .padding(.leading, 6)
                .padding(.vertical, 2)
            
            Button(action: {
                if shouldShowMic || viewModel.isRecording {
                    if viewModel.isRecording {
                        // Stopping recording - the transcription will be finalized by the service
                        viewModel.toggleRecording(directUpdateHandler: { transcription in
                            // This will continue to receive updates until finalization is complete
                            userInput = transcription
                        })
                        
                        // Don't automatically send - let user verify the transcription first
                        // This provides better user experience by allowing them to see the final result
                    } else {
                        // Starting recording - normal behavior
                        viewModel.toggleRecording(directUpdateHandler: { transcription in
                            userInput = transcription
                        })
                    }
                } else if hasText {
                    // Normal text sending
                    let textToSend = userInput
                    onSend()
                    
                    // Safety check to ensure the text field is cleared
                    DispatchQueue.main.async {
                        if userInput == textToSend {
                            userInput = ""
                        }
                    }
                }
            }) {
                Image(systemName: buttonImageName)
                    .font(.system(size: 28))
                    .foregroundColor(buttonColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(buttonDisabled || isDisabled)
            .opacity(isDisabled ? 0.6 : 1)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                if value.translation.height > 20 {
                                    isTextFieldFocused = false
                                }
                            }
                    )
            }
        )
        .onAppear {
            if !viewModel.isSpeechSetup {
                viewModel.setupSpeechRecognition(directUpdateHandler: { transcription in
                    userInput = transcription
                })
            }
        }
        .onChange(of: viewModel.isRecording) { oldValue, newValue in
            if newValue {
                isTextFieldFocused = false
            }
        }
        .onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
            if oldValue == .chat && newValue != .chat {
                isTextFieldFocused = false
            }
        }
        .alert("Speech Recognition Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .manageFocus(using: focusManager, for: .chat)
    }
    
    private var buttonImageName: String {
        if viewModel.isRecording {
            return "stop.circle.fill"
        } else if shouldShowMic {
            return "mic.circle.fill"
        } else {
            return "arrow.up.circle.fill"
        }
    }
    
    private var buttonColor: Color {
        if viewModel.isRecording {
            return .red
        } else if shouldShowMic {
            return viewModel.isSpeechSetup ? .blue : .gray
        } else {
            return .blue
        }
    }
    
    private var buttonDisabled: Bool {
        if shouldShowMic {
            return !viewModel.isSpeechSetup
        } else if viewModel.isRecording {
            return false
        } else {
            return isSendDisabled || !hasText
        }
    }
}
