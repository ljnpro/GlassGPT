import ChatUIComponents
import SwiftUI

extension View {
    func assistantSingleSurfaceGlass(isLive: Bool) -> some View {
        singleSurfaceGlass(
            cornerRadius: 20,
            stableFillOpacity: isLive ? 0.01 : 0.004,
            tintOpacity: isLive ? 0.03 : 0.024,
            borderWidth: 0.85,
            darkBorderOpacity: 0.16,
            lightBorderOpacity: 0.09
        )
    }
}
