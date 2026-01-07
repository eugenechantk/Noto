//
//  Item.swift
//  PersonalNotetaking
//
//  Created by Eugene Chan on 1/8/26.
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
