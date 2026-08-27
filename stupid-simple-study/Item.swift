//
//  Item.swift
//  stupid-simple-study
//
//  Created by Elliot on 2026-08-27.
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
