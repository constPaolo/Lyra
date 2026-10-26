import SwiftUI

/// The onboarding's ASCII wave, driven by the audio spectrum: stepped
/// gradient bands that rise with the music and dissolve into characters.
struct VisualizerView: View {
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 6) {
            if let track = vm.currentTrack {
                Text(track.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            AsciiWaveField(lift: 0, spectrum: vm.visualizerLevels)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)))
                .allowsHitTesting(false)
        }
        .padding(.top, 8)
        .padding(.bottom, 130)
    }
}
