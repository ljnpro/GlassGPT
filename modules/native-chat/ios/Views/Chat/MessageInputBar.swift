import SwiftUI

struct MessageInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    @Binding var selectedImageData: Data?
    @Binding var pendingAttachments: [FileAttachment]
    let onSend: () -> Void
    let onStop: () -> Void
    let onPickImage: () -> Void
    let onPickDocument: () -> Void
    let onRemoveAttachment: (FileAttachment) -> Void

    @FocusState private var isFocused: Bool
    @State private var showAttachmentMenu = false

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

                // Text field
                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))

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
                    Button(action: onSend) {
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
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedImageData != nil
            || !pendingAttachments.isEmpty
    }
}
