//
//  Item.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
