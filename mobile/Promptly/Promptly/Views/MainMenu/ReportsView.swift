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
    
    // Add a subview for snapshot items
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
    
    // Add a subview for individual snapshot items
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
    
    // Add a subview for subitems
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
                        

                        
                        // Properly fetch and display snapshot items
                        if let snapshotItems = report.snapshotItems {
                            if snapshotItems.count > 0 {
                                
                                Divider()
                                    .frame(height: 2)
                                    .background(Color.white.opacity(0.05))
                                SnapshotItemsView(items: snapshotItems)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    
                    // Analysis Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Analysis")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(report.analysis ?? "")
                            .font(.body)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    
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
