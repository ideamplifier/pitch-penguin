//
//  PenguinView.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct PenguinView: View {
    let state: PenguinState
    @State private var guitarFrame = 0
    @State private var animationTimer: Timer?
    
    private var imageName: String {
        switch state {
        case .waiting:
            return guitarFrame == 0 ? "g1" : "g2"
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
            .scaleEffect(state == .waiting ? 1.05 : 1.0)
            .onAppear {
                startAnimation()
            }
            .onChange(of: state) { _, newState in
                if newState == .waiting {
                    startAnimation()
                } else {
                    stopAnimation()
                }
            }
    }
    
    private func startAnimation() {
        stopAnimation()
        if state == .waiting {
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
                guitarFrame = guitarFrame == 0 ? 1 : 0
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}