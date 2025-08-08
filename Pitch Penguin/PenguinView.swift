//
//  PenguinView.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct PenguinView: View {
    let state: PenguinState
    
    private var imageName: String {
        switch state {
        case .waiting:
            return "pp_ok"
        case .tooLow:
            return "pp_up"
        case .correct:
            return "pp_ok"
        case .tooHigh:
            return "pp_down"
        }
    }
    
    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.none)
            .aspectRatio(contentMode: .fit)
            .animation(.easeInOut(duration: 0.3), value: state)
    }
}