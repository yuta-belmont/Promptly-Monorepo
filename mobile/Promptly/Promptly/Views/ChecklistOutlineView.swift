import SwiftUI
import CoreData

struct ChecklistOutlineView: View {
    let outline: ChecklistOutline
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Summary section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(outline.summary ?? "")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal)
                    
                    // Timeline section
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Start")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(dateFormatter.string(from: outline.startDate ?? Date()))
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("End")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(dateFormatter.string(from: outline.endDate ?? Date()))
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Line items section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        ForEach(outline.lineItem as? [String] ?? [], id: \.self) { item in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text(item)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                        .frame(height: 100) // Add extra padding at the bottom
                }
                .padding(.vertical)
            }
            
            // Bottom overlay with buttons
            VStack(spacing: 8) {
                Text("Create plan?")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)
                
                HStack(spacing: 12) {
                    Button(action: onAccept) {
                        Text("Accept")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button(action: onDecline) {
                        Text("Decline")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
            .padding(.horizontal, 8)
        }
    }
}
