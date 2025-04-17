import SwiftUI
import CoreData

struct ReportsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = ReportsViewModel()
    @State private var showingInfoPopover = false
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Reports")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Button(action: {
                        showingInfoPopover = true
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 14))
                    }
                    .popover(isPresented: $showingInfoPopover) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("View and analyze your task completion history.")
                        }
                        .padding()
                        .frame(width: 250)
                        .background(.ultraThinMaterial)
                        .presentationCompactAdaptation(.none)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // List content
                List {
                    ForEach(viewModel.reports) { report in
                        ReportRow(report: report)
                            .contentShape(Rectangle())
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                    }
                    
                    // Add spacer at bottom of list for better scrolling
                    Color.clear.frame(height: 250)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.black.opacity(0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
            .offset(x: dragOffset.width)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.startLocation.x < 66 && value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        if value.startLocation.x < 66 && value.translation.width > 50 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                isPresented = false
                            }
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            dragOffset = .zero
                        }
                    }
            )
            .transition(.opacity)
            .zIndex(999)
        }
        .onAppear {
            viewModel.loadReports()
        }
    }
}

struct ReportRow: View {
    let report: Report
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.trailing, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.summary ?? "")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    if let date = report.date {
                        Text(date, style: .date)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.3))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: -1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var reports: [Report] = []
    private let persistenceController = PersistenceController.shared
    
    func loadReports() {
        // TODO: Implement report loading from persistence
        // For now, we'll just show a placeholder
        let report = Report(context: persistenceController.container.viewContext)
        report.date = Date()
        report.summary = "Weekly Task Completion"
        report.analysis = "You completed 80% of your tasks this week"
        report.response = "Great job! Keep up the good work."
        reports = [report]
    }
} 
