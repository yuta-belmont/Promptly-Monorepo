import SwiftUI
import CoreData

struct ReportsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = ReportsViewModel()
    @State private var showingInfoPopover = false
    @State private var dragOffset = CGSize.zero
    @State private var selectedReport: Report? = nil
    
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
                        ReportRow(report: report, 
                                 viewModel: viewModel,
                                 selectedReport: $selectedReport)
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
        .sheet(item: $selectedReport) { report in
            ReportDetailView(report: report)
        }
        .alert("Delete Report", isPresented: $viewModel.showingDeleteReportAlert) {
            Button("Cancel", role: .cancel) { 
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteReport()
            }
        } message: {
            if let report = viewModel.reportToDelete {
                Text("Are you sure you want to delete the report from \(report.date?.formatted(date: .long, time: .omitted) ?? "this date")?")
            } else {
                Text("Are you sure you want to delete this report?")
            }
        }
    }
}

struct ReportDetailView: View {
    let report: Report
    @Environment(\.dismiss) private var dismiss
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: report.date ?? Date())
    }
    
    private struct AnalyticsDetailView: View {
        let report: Report
        
        private struct StatRow: View {
            let title: String
            let day: String
            let week: String
            let month: String
            
            var body: some View {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 24) {
                        StatColumn(title: "30-Day Avg", value: month)
                        StatColumn(title: "7-Day Avg", value: week)
                        StatColumn(title: "Today", value: day)
                    }
                    .padding(.leading, 8)
                }
            }
        }
        
        private struct StatColumn: View {
            let title: String
            let value: String
            
            var body: some View {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
            }
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                // Item Statistics
                Text("Item Statistics")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                StatRow(
                    title: "Item Count",
                    day: report.itemCountDay ?? "0",
                    week: report.itemCountWeek ?? "0",
                    month: report.itemCountMonth ?? "0"
                )
                
                StatRow(
                    title: "Item Completion Rate",
                    day: report.itemCompletionDay ?? "0%",
                    week: report.itemCompletionWeek ?? "0%",
                    month: report.itemCompletionMonth ?? "0%"
                )
                
                Divider()
                    .background(Color.white.opacity(0.05))
                
                // Subitem Statistics
                Text("Subitem Statistics")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                StatRow(
                    title: "Subitem Count",
                    day: report.subitemCountDay ?? "0",
                    week: report.subitemCountWeek ?? "0",
                    month: report.subitemCountMonth ?? "0"
                )
                
                StatRow(
                    title: "Subitem Completion Rate",
                    day: report.subitemCompletionDay ?? "0%",
                    week: report.subitemCompletionWeek ?? "0%",
                    month: report.subitemCompletionMonth ?? "0%"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // Add back the snapshot-related views
    private struct SnapshotItemsView: View {
        let items: NSSet
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.allObjects as! [SnapshotItem]) { item in
                    SnapshotItemView(item: item)
                }
            }
            .padding(.top, 8)
        }
    }
    
    private struct SnapshotItemView: View {
        let item: SnapshotItem
        
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(item.isCompleted ? .green : .white.opacity(0.6))
                        .padding(.top, 3)
                        .frame(maxHeight: .infinity, alignment: .top)
                    let _ = print(item.title ?? "")
                    Text(item.title ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // Properly fetch and display subitems
                if let subitems = item.subitems {
                    SnapshotSubItemsView(subitems: subitems)
                }
            }
        }
    }
    
    private struct SnapshotSubItemsView: View {
        let subitems: NSSet
        
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(subitems.allObjects as! [SnapshotSubItem]) { subitem in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.6))
                            .padding(.top, 2)
                            .frame(maxHeight: .infinity, alignment: .top)
                        
                        Text(subitem.title ?? "")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Report for \(formattedDate)")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding()
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Summary Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(report.summary ?? "")
                            .font(.body)
                            .foregroundColor(.white)
                        
                        if let snapshotItems = report.snapshotItems {
                            if snapshotItems.count > 0 {
                                Divider()
                                    .background(Color.white.opacity(0.05))
                                SnapshotItemsView(items: snapshotItems)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    
                    // Analysis Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Analysis")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                         
                        AnalyticsDetailView(report: report)
                        
                        if let analysis = report.analysis, !analysis.isEmpty {
                            Divider()
                                .background(Color.white.opacity(0.05))
                            
                        }
                        
                        Text(report.analysis ?? "")
                            .font(.body)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    
                    // Response Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Response")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(report.response ?? "")
                            .font(.body)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
    }
}

struct ReportRow: View {
    let report: Report
    @ObservedObject private var viewModel: ReportsViewModel
    @State private var isGlowing: Bool = false
    @Binding var selectedReport: Report?

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    init(report: Report, viewModel: ReportsViewModel, selectedReport: Binding<Report?>) {
        self.report = report
        self.viewModel = viewModel
        self._selectedReport = selectedReport
    }
    
    // Extract the first sentence from either response or summary
    private var firstSentence: String {
        
        guard let summary = report.summary, !summary.isEmpty else {
            return "No summary available"
        }
        
        // Process summary - split by newline first to handle multi-line summaries
        let lines = summary.components(separatedBy: "\n")
        let firstLine = lines[0]
        
        // Find the first period that's not part of a number (e.g., 3.5)
        let components = firstLine.components(separatedBy: ". ")
        if components.count > 0 {
            // Return first sentence with trailing period removed
            var sentence = components[0]
            if sentence.hasSuffix(".") {
                sentence = String(sentence.dropLast())
            }
            return sentence
        }
        
        // If no period found, return the whole first line (with trailing period removed if present)
        var result = firstLine
        if result.hasSuffix(".") {
            result = String(result.dropLast())
        }
        return result
    }
    
    var body: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.trailing, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(firstSentence)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    if let date = report.date {
                        Text(date, style: .date)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Add trash icon button
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    // Start the glow animation
                    isGlowing = true
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isGlowing = false
                        }
                    }
                    viewModel.confirmDeleteReport(report)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundColor(.gray.opacity(0.3))
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: -1, y: 1)
                
                // Glow effect
                if isGlowing {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .blur(radius: 8)
                        .opacity(0.15)
                }
            }
        )
        .overlay(
            Group {
                // Default outline
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                
                // Animated outline that appears with the glow
                if isGlowing {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                }
            }
        )
        .onTapGesture {
            selectedReport = report
            // Start the glow animation
            isGlowing = true
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isGlowing = false
                }
            }
        }
    }
}

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var reports: [Report] = []
    @Published var showingDeleteReportAlert = false
    @Published var reportToDelete: Report? = nil
    private let persistenceController = PersistenceController.shared
    
    func loadReports() {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<Report> = Report.fetchRequest()
        
        // Sort by date, most recent first
        let sortDescriptor = NSSortDescriptor(key: "date", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        do {
            let results = try context.fetch(fetchRequest)
            reports = results
        } catch {
            print("Error loading reports: \(error)")
            reports = []
        }
    }
    
    func confirmDeleteReport(_ report: Report) {
        reportToDelete = report
        showingDeleteReportAlert = true
    }
    
    func deleteReport() {
        guard let report = reportToDelete else { return }
        
        let context = persistenceController.container.viewContext
        context.delete(report)
        
        do {
            try context.save()
            // Reload reports after deletion
            loadReports()
        } catch {
            print("Error deleting report: \(error)")
        }
        
        // Reset state
        reportToDelete = nil
        showingDeleteReportAlert = false
    }
    
    func cancelDelete() {
        reportToDelete = nil
        showingDeleteReportAlert = false
    }
} 
