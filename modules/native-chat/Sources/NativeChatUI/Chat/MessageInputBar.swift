import ChatDomain
import ChatUIComponents
import SwiftUI
import UIKit

/// Composable message input bar with text composer, attachment previews, and send/stop controls.
package struct MessageInputBar: View {
    /// Token that resets the composer text when changed.
    let resetToken: UUID
    /// Whether the assistant is currently streaming a response.
    let isStreaming: Bool
    /// Raw data of a selected photo attachment, if any.
    @Binding var selectedImageData: Data?
    /// File attachments pending upload.
    @Binding var pendingAttachments: [FileAttachment]
    /// Callback to send a message; returns `true` if the send was accepted.
    let onSend: (String) -> Bool
    /// Callback to stop the active streaming response.
    let onStop: () -> Void
    /// Callback to present the image picker.
    let onPickImage: () -> Void
    /// Callback to present the document picker.
    let onPickDocument: () -> Void
    /// Callback to remove a pending file attachment.
    let onRemoveAttachment: (FileAttachment) -> Void

    @State private var text = ""
    @State private var composerHeight = Self.minimumComposerHeight

    private static let horizontalTextInset: CGFloat = 12
    private static let verticalTextInset: CGFloat = 8
    private static let composerFont = UIFont.preferredFont(forTextStyle: .body)
    private static let minimumComposerHeight = ceil(composerFont.lineHeight + (verticalTextInset * 2))
    private static let maximumComposerHeight = ceil((composerFont.lineHeight * 6) + (verticalTextInset * 2))

    /// Creates a message input bar with the given bindings and action callbacks.
    package init(
        resetToken: UUID,
        isStreaming: Bool,
        selectedImageData: Binding<Data?>,
        pendingAttachments: Binding<[FileAttachment]>,
        onSend: @escaping (String) -> Bool,
        onStop: @escaping () -> Void,
        onPickImage: @escaping () -> Void,
        onPickDocument: @escaping () -> Void,
        onRemoveAttachment: @escaping (FileAttachment) -> Void
    ) {
        self.resetToken = resetToken
        self.isStreaming = isStreaming
        self._selectedImageData = selectedImageData
        self._pendingAttachments = pendingAttachments
        self.onSend = onSend
        self.onStop = onStop
        self.onPickImage = onPickImage
        self.onPickDocument = onPickDocument
        self.onRemoveAttachment = onRemoveAttachment
    }

    package var body: some View {
        VStack(spacing: 0) {
            // Image preview
            if let imageData = selectedImageData,
               let uiImage = UIImage(data: imageData) {
                HStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Attached image preview")
                        .accessibilityIdentifier("composer.imagePreview")

                    Button {
                        withAnimation { selectedImageData = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Remove image")
                    .accessibilityIdentifier("composer.removeImage")

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Pending file attachments preview
            if !pendingAttachments.isEmpty {
                FileAttachmentsRow(
                    attachments: pendingAttachments,
                    onRemove: { attachment in
                        withAnimation { onRemoveAttachment(attachment) }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                // Attachment menu button (replaces single image picker)
                Menu {
                    Button {
                        onPickImage()
                    } label: {
                        Label("Photo", systemImage: "photo")
                    }
                    .accessibilityLabel("Attach photo")
                    .accessibilityIdentifier("composer.attachPhoto")

                    Button {
                        onPickDocument()
                    } label: {
                        Label("Document", systemImage: "doc")
                    }
                    .accessibilityLabel("Attach document")
                    .accessibilityIdentifier("composer.attachDocument")
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Attach")
                .accessibilityIdentifier("composer.attach")

                messageComposer

                // Send / Stop button
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Stop generating")
                    .accessibilityIdentifier("composer.stop")
                } else {
                    Button(action: handleSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canSend ? .blue : .secondary)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canSend)
                    .accessibilityLabel("Send message")
                    .accessibilityIdentifier("composer.send")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
        .onChange(of: resetToken) { _, _ in
            clearComposer()
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedImageData != nil
            || !pendingAttachments.isEmpty
    }

    private var messageComposer: some View {
        MessageComposerTextView(
            text: $text,
            measuredHeight: $composerHeight,
            placeholder: "Message",
            minHeight: Self.minimumComposerHeight,
            maxHeight: Self.maximumComposerHeight,
            textInsets: UIEdgeInsets(
                top: Self.verticalTextInset,
                left: Self.horizontalTextInset,
                bottom: Self.verticalTextInset,
                right: Self.horizontalTextInset
            )
        )
        .frame(height: composerHeight)
        .frame(maxWidth: .infinity, minHeight: Self.minimumComposerHeight, alignment: .leading)
    }

    private func handleSend() {
        let textToSend = text
        guard onSend(textToSend) else { return }
        clearComposer()
    }

    private func clearComposer() {
        text = ""
        composerHeight = Self.minimumComposerHeight
    }
}
