import SwiftUI

struct ItemDetailsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel: ItemDetailsViewModel
    @State private var newSubitemText = ""
    
    init(item: Models.ChecklistItem, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: ItemDetailsViewModel(item: item))
    }
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header with title and close button
                HStack {
                    // Item title
                    Text(viewModel.item.title)
                        .font(.title3)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .strikethrough(viewModel.item.isCompleted, color: .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 18, weight: .medium))
                            .padding(8)
                    }
                }
                .padding()
                
                // Divider between header and content
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal)
                
                // Main item details
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Subitems section - only show if there are subitems or we want to add one
                        VStack(alignment: .leading, spacing: 16) {
                            if !viewModel.item.subItems.isEmpty {
                                // List of subitems
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(viewModel.item.subItems) { subitem in
                                        HStack(alignment: .top, spacing: 12) {
                                            // Subitem status indicator
                                            Image(systemName: subitem.isCompleted ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(subitem.isCompleted ? .green : .gray)
                                                .font(.system(size: 20))
                                            
                                            // Subitem title
                                            Text(subitem.title)
                                                .font(.body)
                                                .foregroundColor(.white)
                                                .lineLimit(3)
                                                .strikethrough(subitem.isCompleted, color: .gray)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                            
                            // Add subitem field
                            HStack(alignment: .top, spacing: 12) {
                                // Empty circle for new subitem
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 20))
                                
                                // Text field for new subitem
                                TextField("Add subitem...", text: $newSubitemText)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        if !newSubitemText.isEmpty {
                                            viewModel.addSubitem(newSubitemText)
                                            newSubitemText = ""
                                        }
                                    }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                        
                        // Metadata section - notifications & group
                        if viewModel.item.notification != nil || viewModel.item.group != nil || viewModel.item.groupId != nil {
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                // Group information
                                if let group = viewModel.item.group {
                                    HStack {
                                        Image(systemName: "tag.fill")
                                            .foregroundColor(.white.opacity(0.6))
                                            .font(.system(size: 16))
                                        Text(group.title)
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                } else if let groupId = viewModel.item.groupId, 
                                          let group = viewModel.groupStore.getGroup(by: groupId) {
                                    HStack {
                                        Image(systemName: "tag.fill")
                                            .foregroundColor(.white.opacity(0.6))
                                            .font(.system(size: 16))
                                        Text(group.title)
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                
                                // Notification information
                                if let notification = viewModel.item.notification {
                                    HStack {
                                        Image(systemName: "bell.fill")
                                            .foregroundColor(.white.opacity(0.6))
                                            .font(.system(size: 16))
                                        Text(viewModel.formatNotificationTime(notification))
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 20)
                }
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
            .padding()
        }
        .onAppear {
            viewModel.loadDetails()
        }
    }
} 
