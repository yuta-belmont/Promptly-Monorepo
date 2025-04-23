import Foundation

// MARK: - Data Structures
struct CheckInStats {
    struct VolumeStats {
        let today: Int
        let sevenDayAvg: Double
        let thirtyDayAvg: Double
    }
    
    struct CompletionStats {
        let today: Double
        let sevenDayAvg: Double
        let thirtyDayAvg: Double
    }
    
    let itemVolume: VolumeStats
    let subitemVolume: VolumeStats
    let itemCompletionRates: CompletionStats
    let subitemCompletionRates: CompletionStats
}

// MARK: - Formatting Extension
extension CheckInStats {
    var formattedString: String {
        """
        ITEM VOLUME
        Today: \(itemVolume.today) items
        7-Day Average: \(String(format: "%.1f", itemVolume.sevenDayAvg)) items/day
        30-Day Average: \(String(format: "%.1f", itemVolume.thirtyDayAvg)) items/day

        ITEM COMPLETION RATES
        Today: \(String(format: "%.0f%%", itemCompletionRates.today * 100))
        7-Day Average: \(String(format: "%.0f%%", itemCompletionRates.sevenDayAvg * 100))
        30-Day Average: \(String(format: "%.0f%%", itemCompletionRates.thirtyDayAvg * 100))
        """
    }
}

// MARK: - Analytics Service
final class CheckInAnalytics {
    // MARK: - Singleton
    static let shared = CheckInAnalytics()
    
    // MARK: - Dependencies
    private let persistence = ChecklistPersistence.shared
    private let calendar = Calendar.current
    
    private init() {}
    
    // MARK: - Public API
    
    /// Calculates check-in statistics for the specified date
    /// - Parameter date: The date to calculate statistics for (defaults to today)
    /// - Returns: CheckInStats containing all calculated metrics
    @MainActor func calculateStats(forDate date: Date = Date()) -> CheckInStats {
        // Get today's checklist
        let todayChecklist = persistence.loadChecklist(for: date)
        
        // Calculate today's stats
        let todayItemVolume = calculateItemVolume(from: todayChecklist)
        let todaySubitemVolume = calculateSubitemVolume(from: todayChecklist)
        let todayItemCompletion = calculateItemCompletionRate(from: todayChecklist)
        let todaySubitemCompletion = calculateSubitemCompletionRate(from: todayChecklist)
        
        // Calculate historical averages - use volume average for counts
        let sevenDayItemVolume = calculateVolumeAverage(days: 7, before: date) { Double(self.calculateItemVolume(from: $0)) }
        let thirtyDayItemVolume = calculateVolumeAverage(days: 30, before: date) { Double(self.calculateItemVolume(from: $0)) }
        
        let sevenDaySubitemVolume = calculateVolumeAverage(days: 7, before: date) { Double(self.calculateSubitemVolume(from: $0)) }
        let thirtyDaySubitemVolume = calculateVolumeAverage(days: 30, before: date) { Double(self.calculateSubitemVolume(from: $0)) }
        
        // Use original average calculation for completion rates
        let sevenDayItemCompletion = calculateHistoricalAverage(days: 7, before: date) { self.calculateItemCompletionRate(from: $0) }
        let thirtyDayItemCompletion = calculateHistoricalAverage(days: 30, before: date) { self.calculateItemCompletionRate(from: $0) }
        
        let sevenDaySubitemCompletion = calculateHistoricalAverage(days: 7, before: date) { self.calculateSubitemCompletionRate(from: $0) }
        let thirtyDaySubitemCompletion = calculateHistoricalAverage(days: 30, before: date) { self.calculateSubitemCompletionRate(from: $0) }
        
        return CheckInStats(
            itemVolume: .init(
                today: todayItemVolume,
                sevenDayAvg: sevenDayItemVolume,
                thirtyDayAvg: thirtyDayItemVolume
            ),
            subitemVolume: .init(
                today: todaySubitemVolume,
                sevenDayAvg: sevenDaySubitemVolume,
                thirtyDayAvg: thirtyDaySubitemVolume
            ),
            itemCompletionRates: .init(
                today: todayItemCompletion,
                sevenDayAvg: sevenDayItemCompletion,
                thirtyDayAvg: thirtyDayItemCompletion
            ),
            subitemCompletionRates: .init(
                today: todaySubitemCompletion,
                sevenDayAvg: sevenDaySubitemCompletion,
                thirtyDayAvg: thirtyDaySubitemCompletion
            )
        )
    }
    
    /// Populates a Report's analytics fields with current statistics
    /// - Parameters:
    ///   - report: The report to populate
    ///   - date: The date to calculate statistics for (defaults to the report's date)
    @MainActor func populateReportAnalytics(report: Report, forDate date: Date? = nil) {
        let statsDate = date ?? report.date ?? Date()
        let stats = calculateStats(forDate: statsDate)
        
        // Format item counts
        report.itemCountDay = String(stats.itemVolume.today)
        report.itemCountWeek = String(format: "%.1f", stats.itemVolume.sevenDayAvg)
        report.itemCountMonth = String(format: "%.1f", stats.itemVolume.thirtyDayAvg)
        
        // Format item completion rates (as percentages)
        report.itemCompletionDay = String(format: "%.0f%%", stats.itemCompletionRates.today * 100)
        report.itemCompletionWeek = String(format: "%.0f%%", stats.itemCompletionRates.sevenDayAvg * 100)
        report.itemCompletionMonth = String(format: "%.0f%%", stats.itemCompletionRates.thirtyDayAvg * 100)
        
        // Format subitem counts
        report.subitemCountDay = String(stats.subitemVolume.today)
        report.subitemCountWeek = String(format: "%.1f", stats.subitemVolume.sevenDayAvg)
        report.subitemCountMonth = String(format: "%.1f", stats.subitemVolume.thirtyDayAvg)
        
        // Format subitem completion rates (as percentages)
        report.subitemCompletionDay = String(format: "%.0f%%", stats.subitemCompletionRates.today * 100)
        report.subitemCompletionWeek = String(format: "%.0f%%", stats.subitemCompletionRates.sevenDayAvg * 100)
        report.subitemCompletionMonth = String(format: "%.0f%%", stats.subitemCompletionRates.thirtyDayAvg * 100)
    }
    
    // MARK: - Private Calculation Methods
    
    /// Calculates the average of a volume metric over a specified number of days, including days with no checklists as zero
    @MainActor private func calculateVolumeAverage(days: Int, before date: Date, calculator: (Models.Checklist?) -> Double) -> Double {
        var sum = 0.0
        
        for dayOffset in 1...days {
            if let previousDate = calendar.date(byAdding: .day, value: -dayOffset, to: date) {
                let checklist = persistence.loadChecklist(for: previousDate)
                sum += calculator(checklist) // Will add 0 if checklist is nil
            }
        }
        
        return sum / Double(days)
    }
    
    /// Calculates the average of a metric over a specified number of days, only including days with checklists
    @MainActor private func calculateHistoricalAverage(days: Int, before date: Date, calculator: (Models.Checklist?) -> Double) -> Double {
        var sum = 0.0
        var count = 0
        
        for dayOffset in 1...days {
            if let previousDate = calendar.date(byAdding: .day, value: -dayOffset, to: date) {
                let checklist = persistence.loadChecklist(for: previousDate)
                // Only count days that had checklists
                if checklist != nil {
                    sum += calculator(checklist)
                    count += 1
                }
            }
        }
        
        return count > 0 ? sum / Double(count) : 0
    }
    
    /// Calculates the total number of items in a checklist
    private func calculateItemVolume(from checklist: Models.Checklist?) -> Int {
        checklist?.items.count ?? 0
    }
    
    /// Calculates the total number of subitems across all items
    private func calculateSubitemVolume(from checklist: Models.Checklist?) -> Int {
        checklist?.items.reduce(0) { total, item in
            total + (item.subItems.count)
        } ?? 0
    }
    
    /// Calculates the completion rate of main items (0.0 to 1.0)
    private func calculateItemCompletionRate(from checklist: Models.Checklist?) -> Double {
        guard let checklist = checklist, !checklist.items.isEmpty else { return 0 }
        let completed = Double(checklist.items.filter { $0.isCompleted }.count)
        return completed / Double(checklist.items.count)
    }
    
    /// Calculates the completion rate of subitems (0.0 to 1.0)
    private func calculateSubitemCompletionRate(from checklist: Models.Checklist?) -> Double {
        guard let checklist = checklist else { return 0 }
        let allSubitems = checklist.items.flatMap { $0.subItems ?? [] }
        guard !allSubitems.isEmpty else { return 0 }
        let completed = Double(allSubitems.filter { $0.isCompleted }.count)
        return completed / Double(allSubitems.count)
    }
} 
