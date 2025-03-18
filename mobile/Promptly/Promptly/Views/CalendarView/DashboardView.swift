import SwiftUI
import Foundation

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    var onTodayButtonTapped: () -> Void
    
    // Standardize to use a single green color for all charts
    private let standardGreen = Color(red: 0.2, green: 0.7, blue: 0.2).opacity(0.9) // Medium forest green
    private let incompleteGray = Color.white.opacity(0.3) // Gray for incomplete items
    
    // State for page control
    @State private var currentPage = 0
    private let pageCount = 4
    
    var body: some View {
        VStack(spacing: 10) {
            // Go to Today button moved outside the dashboard background
            Button(action: onTodayButtonTapped) {
                HStack(spacing: 4) {
                    Text("Go to Today")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.bottom, 0)
            
            // Dashboard content with background
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.2))
                
                // Swipeable dashboard content
                TabView(selection: $currentPage) {
                    // Page 1: Summary metrics
                    SummaryMetricsView(viewModel: viewModel, standardGreen: standardGreen)
                        .tag(0)
                    
                    // Page 2: Weekly bar chart
                    WeeklyBarChartView(viewModel: viewModel, standardGreen: standardGreen, incompleteGray: incompleteGray)
                        .tag(1)
                    
                    // Page 3: Monthly bar chart
                    MonthlyBarChartView(viewModel: viewModel, standardGreen: standardGreen, incompleteGray: incompleteGray)
                        .tag(2)
                    
                    // Page 4: Yearly bar chart
                    YearlyBarChartView(viewModel: viewModel, standardGreen: standardGreen, incompleteGray: incompleteGray)
                        .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Hide default indicators
            }
            .padding(.horizontal)
            
            // Custom page indicators below the background
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            
            Spacer()
        }
        .padding(.top, 15)
        .padding(.bottom, 20)
        .onAppear {
            Task {
                await viewModel.loadStats()
            }
        }
    }
}

// MARK: - Summary Metrics View
struct SummaryMetricsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var standardGreen: Color
    
    // Define varying green colors for the summary view only
    private let weeklyGreen = Color(red: 0.6, green: 0.9, blue: 0.6).opacity(0.9) // Light mint green
    private let monthlyGreen = Color(red: 0.2, green: 0.7, blue: 0.2).opacity(0.9) // Medium forest green
    private let yearlyGreen = Color(red: 0.0, green: 0.5, blue: 0.0).opacity(0.9) // Deep emerald green
    
    var body: some View {
        VStack(spacing: 12) {
            // Title
            Text("Metrics Dashboard")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, -15)
                .padding(.bottom, 5)
            
            // Weekly stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last 7 Days")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    } else {
                        Text("\(viewModel.weeklyStats.completed)/\(viewModel.weeklyStats.total)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                // Progress bar - lightest green
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 10)
                        
                        // Progress - lightest green
                        RoundedRectangle(cornerRadius: 5)
                            .fill(weeklyGreen)
                            .frame(width: calculateProgressWidth(
                                completed: viewModel.weeklyStats.completed,
                                total: viewModel.weeklyStats.total,
                                availableWidth: geometry.size.width
                            ), height: 10)
                    }
                }
                .frame(height: 10)
            }
            .padding(.horizontal)
            
            // Monthly stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last 30 Days")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    } else {
                        Text("\(viewModel.monthlyStats.completed)/\(viewModel.monthlyStats.total)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                // Progress bar - medium green
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 10)
                        
                        // Progress - medium green
                        RoundedRectangle(cornerRadius: 5)
                            .fill(monthlyGreen)
                            .frame(width: calculateProgressWidth(
                                completed: viewModel.monthlyStats.completed,
                                total: viewModel.monthlyStats.total,
                                availableWidth: geometry.size.width
                            ), height: 10)
                    }
                }
                .frame(height: 10)
            }
            .padding(.horizontal)
            
            // Yearly stats (365 days)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last 365 Days")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    } else {
                        Text("\(viewModel.yearlyStats.completed)/\(viewModel.yearlyStats.total)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                // Progress bar - darkest green
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 10)
                        
                        // Progress - darkest green
                        RoundedRectangle(cornerRadius: 5)
                            .fill(yearlyGreen)
                            .frame(width: calculateProgressWidth(
                                completed: viewModel.yearlyStats.completed,
                                total: viewModel.yearlyStats.total,
                                availableWidth: geometry.size.width
                            ), height: 10)
                    }
                }
                .frame(height: 10)
            }
            .padding(.horizontal)
        }
        .padding(.top, 5)
        .padding(.bottom, 10)
    }
    
    private func calculateProgressWidth(completed: Int, total: Int, availableWidth: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let progress = CGFloat(completed) / Double(total)
        return min(progress * availableWidth, availableWidth)
    }
}

// MARK: - Weekly Bar Chart View
struct WeeklyBarChartView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var standardGreen: Color
    var incompleteGray: Color
    
    var body: some View {
        VStack(spacing: 15) {
            Text("This Week")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 10)
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.0)
                    .padding(.vertical, 50)
            } else if viewModel.dailyStatsForWeek.isEmpty {
                Text("No data available")
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 50)
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(viewModel.dailyStatsForWeek) { dayStat in
                            VStack {
                                // Two-part bar with rounded corners
                                VStack(spacing: 0) {
                                    // Calculate total bar height
                                    let totalBarHeight = calculateTotalBarHeight(
                                        total: dayStat.total,
                                        maxHeight: geometry.size.height - 40
                                    )
                                    
                                    // Calculate completed bar height
                                    let completedBarHeight = calculateCompletedBarHeight(
                                        completed: dayStat.completed,
                                        total: dayStat.total,
                                        totalBarHeight: totalBarHeight
                                    )
                                    
                                    // Incomplete part (gray) - rounded only at top
                                    if dayStat.completed < dayStat.total {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(incompleteGray)
                                            .frame(width: 12, height: totalBarHeight - completedBarHeight)
                                            .cornerRadius(1, corners: [.topLeft, .topRight])
                                    }
                                    
                                    // Completed part (green) - rounded only at bottom if there's incomplete part
                                    if completedBarHeight > 0 {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(standardGreen)
                                            .frame(width: 12, height: completedBarHeight)
                                            .cornerRadius(1, corners: dayStat.completed < dayStat.total ? 
                                                [.bottomLeft, .bottomRight] : [.topLeft, .topRight, .bottomLeft, .bottomRight])
                                    }
                                }
                                
                                // Day label
                                Text(dayStat.dayName)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                                
                                // Completion count
                                Text("\(dayStat.completed)/\(dayStat.total)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(.vertical, 10)
    }
    
    private func calculateTotalBarHeight(total: Int, maxHeight: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        
        // Find the maximum total value to scale bars
        let maxTotal = viewModel.dailyStatsForWeek.map { $0.total }.max() ?? 1
        
        // Scale the bar height based on the maximum value
        let height = (CGFloat(total) / CGFloat(maxTotal)) * maxHeight
        return max(height, 5) // Minimum height of 5 for visibility
    }
    
    private func calculateCompletedBarHeight(completed: Int, total: Int, totalBarHeight: CGFloat) -> CGFloat {
        guard total > 0 && completed > 0 else { return 0 }
        
        // Calculate the proportion of the total bar that should be filled
        let proportion = CGFloat(completed) / CGFloat(total)
        return proportion * totalBarHeight
    }
}

// MARK: - Monthly Bar Chart View
struct MonthlyBarChartView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var standardGreen: Color
    var incompleteGray: Color
    
    var body: some View {
        VStack(spacing: 15) {
            Text("This Month")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 10)
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.0)
                    .padding(.vertical, 50)
            } else if viewModel.dailyStatsForMonth.isEmpty {
                Text("No data available")
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 50)
            } else {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 5) {
                        // Find the maximum total value for scaling
                        let maxTotal = viewModel.dailyStatsForMonth.map { $0.total }.max() ?? 1
                        let maxHeight = geometry.size.height - 50
                        
                        // Calculate available width for all bars
                        let availableWidth = geometry.size.width - 20 // Accounting for horizontal padding
                        let numberOfDays = 30 // Ensure we always show 30 days
                        
                        // Calculate spacing and bar width to fill the entire width
                        let totalSpacing = CGFloat(numberOfDays - 1) // Total spacing between bars
                        let barWidth = (availableWidth - totalSpacing) / CGFloat(numberOfDays)
                        
                        // Compact bar chart that fills the entire width
                        HStack(alignment: .bottom, spacing: 1) {
                            // Ensure we display all 30 days, including today
                            ForEach(0..<numberOfDays, id: \.self) { index in
                                // Adjust index to show most recent 30 days including today
                                // If we have more than 30 days of data, start from (count-30)
                                // This ensures we show the most recent 30 days
                                let adjustedIndex = viewModel.dailyStatsForMonth.count > numberOfDays ?
                                    (viewModel.dailyStatsForMonth.count - numberOfDays) + index :
                                    index
                                
                                // Get the day stat if available, otherwise use a placeholder
                                let dayStat = adjustedIndex < viewModel.dailyStatsForMonth.count ? 
                                    viewModel.dailyStatsForMonth[adjustedIndex] : 
                                    DailyStats(date: Date(), completed: 0, total: 0)
                                
                                VStack(spacing: 0) {
                                    // Calculate heights directly here for clarity
                                    let totalHeight = dayStat.total > 0 ? 
                                        (CGFloat(dayStat.total) / CGFloat(maxTotal)) * maxHeight : 0
                                    let completedHeight = dayStat.total > 0 && dayStat.completed > 0 ? 
                                        (CGFloat(dayStat.completed) / CGFloat(dayStat.total)) * totalHeight : 0
                                    
                                    // Container to ensure proper alignment
                                    VStack(spacing: 0) {
                                        // Check if this is today's bar
                                        let isToday = Calendar.current.isDateInToday(dayStat.date)
                                        
                                        // Always show at least a minimal bar for each day
                                        if totalHeight <= 0 {
                                            // Empty day - show a minimal indicator
                                            RoundedRectangle(cornerRadius: 1)
                                                .fill(isToday ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                                                .frame(width: barWidth, height: 2)
                                        } else {
                                            // Incomplete part (gray) - rounded only at top
                                            if dayStat.completed < dayStat.total && totalHeight > 0 {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(isToday ? incompleteGray.opacity(1.2) : incompleteGray)
                                                    .frame(width: barWidth, height: max(totalHeight - completedHeight, 0))
                                                    .cornerRadius(1, corners: [.topLeft, .topRight])
                                            }
                                            
                                            // Completed part (green) - rounded only at bottom if there's incomplete part
                                            if completedHeight > 0 {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(isToday ? standardGreen.opacity(1.2) : standardGreen)
                                                    .frame(width: barWidth, height: completedHeight)
                                                    .cornerRadius(1, corners: dayStat.completed < dayStat.total ? 
                                                        [.bottomLeft, .bottomRight] : [.topLeft, .topRight, .bottomLeft, .bottomRight])
                                            }
                                        }
                                    }
                                    .frame(height: max(totalHeight, 3)) // Minimum height for visibility
                                    
                                    // No day labels as requested
                                    Spacer()
                                        .frame(height: 15)
                                }
                            }
                        }
                        .frame(width: availableWidth) // Ensure the HStack fills the available width
                        .padding(.horizontal, 10)
                        .padding(.bottom, 5)
                        
                        // Date range labels
                        if let firstDate = viewModel.dailyStatsForMonth.count > numberOfDays ?
                            viewModel.dailyStatsForMonth[viewModel.dailyStatsForMonth.count - numberOfDays].date :
                            viewModel.dailyStatsForMonth.first?.date,
                           let lastDate = viewModel.dailyStatsForMonth.last?.date {
                            HStack {
                                Text(formatStartDate(firstDate))
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Spacer()
                                
                                Text(formatEndDate(lastDate))
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
    
    private func formatStartDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "From: \(formatter.string(from: date))"
    }
    
    private func formatEndDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "To: \(formatter.string(from: date))"
    }
}

// MARK: - Yearly Bar Chart View
struct YearlyBarChartView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var standardGreen: Color
    var incompleteGray: Color
    
    var body: some View {
        VStack(spacing: 15) {
            Text("This Year")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 10)
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.0)
                    .padding(.vertical, 50)
            } else if viewModel.monthlyStatsForYear.isEmpty {
                Text("No data available")
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 50)
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(viewModel.monthlyStatsForYear) { monthStat in
                            VStack {
                                // Two-part bar with rounded corners
                                VStack(spacing: 0) {
                                    // Calculate total bar height
                                    let totalBarHeight = calculateTotalBarHeight(
                                        total: monthStat.total,
                                        maxHeight: geometry.size.height - 40
                                    )
                                    
                                    // Calculate completed bar height
                                    let completedBarHeight = calculateCompletedBarHeight(
                                        completed: monthStat.completed,
                                        total: monthStat.total,
                                        totalBarHeight: totalBarHeight
                                    )
                                    
                                    // Incomplete part (gray) - rounded only at top
                                    if monthStat.completed < monthStat.total {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(incompleteGray)
                                            .frame(width: 12, height: totalBarHeight - completedBarHeight)
                                            .cornerRadius(1, corners: [.topLeft, .topRight])
                                    }
                                    
                                    // Completed part (green) - rounded only at bottom if there's incomplete part
                                    if completedBarHeight > 0 {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(standardGreen)
                                            .frame(width: 12, height: completedBarHeight)
                                            .cornerRadius(1, corners: monthStat.completed < monthStat.total ? 
                                                [.bottomLeft, .bottomRight] : [.topLeft, .topRight, .bottomLeft, .bottomRight])
                                    }
                                }
                                
                                // Month label
                                Text(monthStat.monthName)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                                
                                // Completion count
                                Text("\(monthStat.completed)/\(monthStat.total)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(.vertical, 10)
    }
    
    private func calculateTotalBarHeight(total: Int, maxHeight: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        
        // Find the maximum total value to scale bars
        let maxTotal = viewModel.monthlyStatsForYear.map { $0.total }.max() ?? 1
        
        // Scale the bar height based on the maximum value
        let height = (CGFloat(total) / CGFloat(maxTotal)) * maxHeight
        return max(height, 5) // Minimum height of 5 for visibility
    }
    
    private func calculateCompletedBarHeight(completed: Int, total: Int, totalBarHeight: CGFloat) -> CGFloat {
        guard total > 0 && completed > 0 else { return 0 }
        
        // Calculate the proportion of the total bar that should be filled
        let proportion = CGFloat(completed) / CGFloat(total)
        return proportion * totalBarHeight
    }
}
