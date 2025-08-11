//
//  Extensions.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import Foundation

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        get {
            return index >= 0 && index < count ? self[index] : nil
        }
        set {
            if let newValue = newValue, index >= 0 && index < count {
                self[index] = newValue
            }
        }
    }
}