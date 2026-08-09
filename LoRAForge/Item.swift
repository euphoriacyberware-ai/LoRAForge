//
//  Item.swift
//  LoRAForge
//
//  Created by Brian Cantin on 2026-08-08.
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
