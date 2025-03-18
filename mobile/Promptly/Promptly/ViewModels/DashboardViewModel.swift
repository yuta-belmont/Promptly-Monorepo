import Foundation

struct DailyStats: Identifiable {
    let id = UUID()
    let date: Date
    let completed: Int
    let total: Int
    
    var completionRate: Double {
        return total > 0 ? Double(completed) / Double(total) : 0
    }
    
    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

struct MonthlyStats: Identifiable {
    let id = UUID()
    let date: Date
    let completed: Int
    let total: Int
    
    var completionRate: Double {
        return total > 0 ? Double(completed) / Double(total) : 0
    }
    
    var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var weeklyStats: (completed: Int, total: Int) = (0, 0)
    @Published private(set) var monthlyStats: (completed: Int, total: Int) = (0, 0)
    @Published private(set) var yearlyStats: (completed: Int, total: Int) = (0, 0)
    @Published private(set) var isLoading: Bool = false
    
    // Detailed stats for charts
    @Published private(set) var dailyStatsForWeek: [DailyStats] = []
    @Published private(set) var dailyStatsForMonth: [DailyStats] = []
    @Published private(set) var monthlyStatsForYear: [MonthlyStats] = []
    
    private let persistence = ChecklistPersistence.shared
    
    init() {
        Task {
            await loadStats()
        }
    }
    
    func loadStats() async {
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        let today = Date()
        
        // Calculate weekly stats (previous 7 days)
        var weeklyCompleted = 0
        var weeklyTotal = 0
        var dailyStatsWeek: [DailyStats] = []
        
        // Calculate monthly stats (previous 30 days)
        var monthlyCompleted = 0
        var monthlyTotal = 0
        var dailyStatsMonth: [DailyStats] = []
        
        // Calculate yearly stats (previous 365 days)
        var yearlyCompleted = 0
        var yearlyTotal = 0
        
        // Initialize monthly stats for the year
        var monthlyStatsYear: [MonthlyStats] = []
        var monthlyData: [Int: (completed: Int, total: Int)] = [:]
        
        // Process the last 365 days
        for dayOffset in 0...365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            let monthKey = year * 100 + month // Unique key for each month
            
            if let checklist = persistence.loadChecklist(for: date) {
                let completed = checklist.items.filter { $0.isCompleted }.count
                let total = checklist.items.count
                
                // Add to yearly stats
                yearlyCompleted += completed
                yearlyTotal += total
                
                // Aggregate monthly data for yearly chart
                if monthlyData[monthKey] == nil {
                    monthlyData[monthKey] = (completed, total)
                } else {
                    monthlyData[monthKey]!.completed += completed
                    monthlyData[monthKey]!.total += total
                }
                
                // Add to monthly stats if within the last 30 days
                if dayOffset <= 30 {
                    monthlyCompleted += completed
                    monthlyTotal += total
                    
                    // Add daily stats for monthly chart
                    dailyStatsMonth.append(DailyStats(date: date, completed: completed, total: total))
                    
                    // Add to weekly stats if within the last 7 days
                    if dayOffset <= 7 {
                        weeklyCompleted += completed
                        weeklyTotal += total
                        
                        // Add daily stats for weekly chart
                        dailyStatsWeek.append(DailyStats(date: date, completed: completed, total: total))
                    }
                }
            } else if dayOffset <= 30 {
                // Add empty stats for days without data
                dailyStatsMonth.append(DailyStats(date: date, completed: 0, total: 0))
                
                if dayOffset <= 7 {
                    dailyStatsWeek.append(DailyStats(date: date, completed: 0, total: 0))
                }
            }
        }
        
        // Convert monthly data to array of MonthlyStats
        let currentYear = calendar.component(.year, from: today)
        let currentMonth = calendar.component(.month, from: today)
        
        for month in 1...12 {
            let year = month > currentMonth ? currentYear - 1 : currentYear
            let monthKey = year * 100 + month
            
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            
            if let date = calendar.date(from: components) {
                let stats = monthlyData[monthKey] ?? (0, 0)
                monthlyStatsYear.append(MonthlyStats(
                    date: date,
                    completed: stats.completed,
                    total: stats.total
                ))
            }
        }
        
        // Sort the arrays by date
        dailyStatsWeek.sort { $0.date < $1.date }
        dailyStatsMonth.sort { $0.date < $1.date }
        monthlyStatsYear.sort { $0.date < $1.date }
        
        // Update the published properties on the main thread
        await MainActor.run {
            self.weeklyStats = (weeklyCompleted, weeklyTotal)
            self.monthlyStats = (monthlyCompleted, monthlyTotal)
            self.yearlyStats = (yearlyCompleted, yearlyTotal)
            
            self.dailyStatsForWeek = dailyStatsWeek
            self.dailyStatsForMonth = dailyStatsMonth
            self.monthlyStatsForYear = monthlyStatsYear
        }
    }
} 
