import SwiftUI
import UIKit

struct MessageInputBar: View {
    let resetToken: UUID
    let isStreaming: Bool
    @Binding var selectedImageData: Data?
    @Binding var pendingAttachments: [FileAttachment]
    let onSend: (String) -> Bool
    let onStop: () -> Void
    let onPickImage: () -> Void
    let onPickDocument: () -> Void
    let onRemoveAttachment: (FileAttachment) -> Void

    @State private var text = ""
    @State private var composerHeight = Self.minimumComposerHeight

    private static let horizontalTextInset: CGFloat = 12
    private static let verticalTextInset: CGFloat = 8
    private static let composerFont = UIFont.preferredFont(forTextStyle: .body)
    private static let minimumComposerHeight = ceil(composerFont.lineHeight + (verticalTextInset * 2))
    private static let maximumComposerHeight = ceil((composerFont.lineHeight * 6) + (verticalTextInset * 2))

    var body: some View {
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

                    Button {
                        withAnimation { selectedImageData = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }

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

                    Button {
                        onPickDocument()
                    } label: {
                        Label("Document", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.glass)

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
                } else {
                    Button(action: handleSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canSend ? .blue : .secondary)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canSend)
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
