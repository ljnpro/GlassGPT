import ChatUIComponents
import SwiftUI

extension View {
    func assistantSingleSurfaceGlass(isLive: Bool) -> some View {
        singleSurfaceGlass(
            cornerRadius: 20,
            stableFillOpacity: isLive
                ? GlassStyleMetrics.AssistantSurface.liveStableFillOpacity
                : GlassStyleMetrics.AssistantSurface.idleStableFillOpacity,
            tintOpacity: isLive
                ? GlassStyleMetrics.AssistantSurface.liveTintOpacity
                : GlassStyleMetrics.AssistantSurface.idleTintOpacity,
            borderWidth: GlassStyleMetrics.AssistantSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.AssistantSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.AssistantSurface.lightBorderOpacity
        )
    }
}
