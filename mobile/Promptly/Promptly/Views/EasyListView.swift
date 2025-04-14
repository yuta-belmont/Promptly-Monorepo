struct EasyListHeader: View {
    @ObservedObject var viewModel: EasyListViewModel
    @Binding var isEditing: Bool
    var onEditTap: () -> Void
    var onAddTap: () -> Void
    
    var body: some View {
        HStack {
            Text("Easy List")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Add expand/collapse button
            Button(action: {
                viewModel.toggleAllItemsExpanded()
            }) {
                Image(systemName: viewModel.expandedItemIds.isEmpty ? "chevron.down" : "chevron.up")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            
            Button(action: onAddTap) {
                Image(systemName: "plus")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            
            Button(action: onEditTap) {
                Text(isEditing ? "Done" : "Edit")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }
} 