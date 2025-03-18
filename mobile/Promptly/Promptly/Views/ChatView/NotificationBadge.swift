import SwiftUI

struct NotificationBadge: View {
    let count: Int
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
            Text("\(min(count, 99))")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
        }
        .frame(width: 18, height: 18)
        .opacity(count > 0 ? 1 : 0)
    }
} 
