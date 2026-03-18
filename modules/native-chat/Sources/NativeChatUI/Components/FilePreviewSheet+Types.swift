import GeneratedFilesCore
import PDFKit
import SwiftUI
import UIKit

extension FilePreviewSheet {
    struct ImagePreviewPayload {
        let image: UIImage
        let data: Data
    }

    enum ImagePreviewState {
        case loading
        case image(ImagePreviewPayload)
        case error(String)
    }

    enum ImagePreviewLoadResult {
        case image(ImagePreviewPayload)
        case error(String)
        case unavailable
    }

    enum PDFPreviewState {
        case loading
        case document(PDFDocument)
        case error(String)
    }

    enum PDFPreviewLoadResult {
        case document(PDFDocument)
        case error(String)
        case unavailable
    }

    enum SaveState: Equatable {
        case idle
        case saving
    }

    struct PreviewActionButton<Label: View>: View {
        let diameter: CGFloat
        let isEnabled: Bool
        let accessibilityLabel: String
        var accessibilityIdentifier: String?
        var onTriggerStart: () -> Void = {}
        let action: () -> Void
        @ViewBuilder let label: () -> Label

        @State private var isPressed = false

        private var hitBounds: CGRect {
            CGRect(x: 0, y: 0, width: diameter, height: diameter)
        }

        var body: some View {
            label()
                .frame(width: diameter, height: diameter)
                .singleFrameGlassCircleControl(
                    tintOpacity: 0.015,
                    borderWidth: 0.78,
                    darkBorderOpacity: 0.14,
                    lightBorderOpacity: 0.08
                )
                .scaleEffect(isPressed ? 0.9 : 1)
                .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.62)
                .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isPressed)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled else { return }
                            isPressed = hitBounds.contains(value.location)
                        }
                        .onEnded { value in
                            let shouldTrigger = isEnabled && hitBounds.contains(value.location)
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                                isPressed = false
                            }

                            guard shouldTrigger else { return }
                            onTriggerStart()
                            Task { @MainActor in
                                do {
                                    try await Task.sleep(nanoseconds: 55_000_000)
                                } catch {
                                    return
                                }
                                action()
                            }
                        }
                )
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
                .accessibilityAction {
                    guard isEnabled else { return }
                    action()
                }
        }
    }
}
