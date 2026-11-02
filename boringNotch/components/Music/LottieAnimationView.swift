//
//  LottieAnimationContainer.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 29..
//

import SwiftUI
import Defaults

struct LottieAnimationContainer: View {
    @Default(.selectedVisualizer) var selectedVisualizer
    var body: some View {
        if selectedVisualizer == nil {
            // Animation « Ondes » embarquée : aucun téléchargement.
            LottieView(url: Bundle.main.url(forResource: "ondes", withExtension: "json")!, speed: 1.0, loopMode: .loop)
        } else {
            LottieView(url: selectedVisualizer!.url, speed: selectedVisualizer!.speed, loopMode: .loop)
        }
    }
}

#Preview {
    LottieAnimationContainer()
}
