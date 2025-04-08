import Foundation

class UserSettings: ObservableObject {
    static let shared = UserSettings()
    
    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current
    
    // MARK: - Check-in Settings
    @Published var isCheckInNotificationEnabled: Bool {
        didSet {
            defaults.set(isCheckInNotificationEnabled, forKey: "isCheckInNotificationEnabled")
        }
    }
    
    @Published var checkInTime: Date {
        didSet {
            // Save the full date object to preserve timezone information
            defaults.set(checkInTime, forKey: "checkInTime")
        }
    }
    
    @Published var alfredPersonality: Int {
        didSet {
            defaults.set(alfredPersonality, forKey: "alfredPersonality")
        }
    }
    
    @Published var objectives: String {
        didSet {
            defaults.set(objectives, forKey: "objectives")
        }
    }
    
    // MARK: - Chat Settings
    @Published var isChatEnabled: Bool {
        didSet {
            defaults.set(isChatEnabled, forKey: "isChatEnabled")
        }
    }
    
    // MARK: - Check-in Stats
    @Published var checkinPoints: Int {
        didSet {
            defaults.set(checkinPoints, forKey: "checkinPoints")
        }
    }
    
    @Published var lastCheckin: Date {
        didSet {
            defaults.set(lastCheckin, forKey: "lastCheckin")
        }
    }
    
    @Published var streak: Int {
        didSet {
            defaults.set(streak, forKey: "streak")
        }
    }
    
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    // Dictionary to track when each day's check-in button expires
    @Published var checkInButtonExpiryTimes: [String: Date] = [:]
    
    private func saveExpiryTimes(_ times: [String: Date]) {
        defaults.set(times, forKey: "checkInButtonExpiryTimes")
    }
    
    private init() {
        // Initialize with defaults
        self.isCheckInNotificationEnabled = defaults.bool(forKey: "isCheckInNotificationEnabled", defaultValue: true)
        
        // Default to 8 PM in local timezone if not set
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 20 // 8 PM
        components.minute = 0
        components.second = 0
        let defaultTime = calendar.date(from: components) ?? Date()
        
        // Load the saved check-in time or use default
        if let savedTime = defaults.object(forKey: "checkInTime") as? Date {
            self.checkInTime = savedTime
        } else {
            self.checkInTime = defaultTime
        }
        
        // Default to minimalist (2) if not set
        self.alfredPersonality = defaults.integer(forKey: "alfredPersonality", defaultValue: 2)
        
        // Default to empty string if not set
        self.objectives = defaults.string(forKey: "objectives") ?? ""
        
        // Default to true if not set
        self.isChatEnabled = defaults.bool(forKey: "isChatEnabled", defaultValue: true)
        
        // Initialize check-in stats
        self.checkinPoints = defaults.integer(forKey: "checkinPoints", defaultValue: 0)
        self.streak = defaults.integer(forKey: "streak", defaultValue: 0)
        
        // Load last check-in date or set to distant past if not set
        if let lastCheckin = defaults.object(forKey: "lastCheckin") as? Date {
            self.lastCheckin = lastCheckin
        } else {
            self.lastCheckin = Date.distantPast
        }
        
        // Load check-in button expiry times
        if let savedExpiryTimes = defaults.object(forKey: "checkInButtonExpiryTimes") as? [String: Date] {
            self.checkInButtonExpiryTimes = savedExpiryTimes
        } else {
            self.checkInButtonExpiryTimes = [:]
        }
        
        // Now that all properties are initialized, we can set up the didSet observer
        self.checkInButtonExpiryTimes = self.checkInButtonExpiryTimes
    }
    
    // Add this method to update expiry times
    func updateExpiryTimes(_ times: [String: Date]) {
        self.checkInButtonExpiryTimes = times
        saveExpiryTimes(times)
    }
}

// MARK: - Helper Extensions
extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
    
    func integer(forKey key: String, defaultValue: Int) -> Int {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return integer(forKey: key)
    }
}

// Add Dictionary extension for mapKeys
extension Dictionary {
    func mapKeys<T>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[try transform(key)] = value
        }
        return result
    }
}

// MARK: - Personality Enum
enum AlfredPersonality: Int, CaseIterable {
    case cheerleader = 1
    case minimalist = 2
    case disciplinarian = 3
    
    var title: String {
        switch self {
        case .cheerleader: return "Cheerleader"
        case .minimalist: return "Minimalist"
        case .disciplinarian: return "Disciplinarian"
        }
    }
    
    var description: String {
        switch self {
        case .cheerleader:
            return "Positive, encouraging and celebrates your achievements."
        case .minimalist:
            return "Direct and concise with minimal interaction."
        case .disciplinarian:
            return "Strict and focused on accountability and results."
        }
    }
} 
