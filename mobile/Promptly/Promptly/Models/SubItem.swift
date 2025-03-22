//
//  SubItem.swift
//  Promptly
//
//  Created by Yuta Belmont on 3/19/25.
//

import Foundation

extension Models {
    struct SubItem: Identifiable, Codable, Equatable, Hashable {
        let id: UUID
        var title: String
        var isCompleted: Bool
        
        init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
            self.id = id
            self.title = title
            self.isCompleted = isCompleted
        }
        
        static func == (lhs: SubItem, rhs: SubItem) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
} 