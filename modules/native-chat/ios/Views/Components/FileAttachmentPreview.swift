import SwiftUI

/// Displays a compact chip for a file attachment in a message bubble.
/// Used for both user messages (showing what was uploaded) and as a preview before sending.
struct FileAttachmentChip: View {
    let attachment: FileAttachment
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            // File type icon
            Image(systemName: attachment.iconName)
                .font(.body.weight(.medium))
                .foregroundStyle(attachment.iconColor)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(attachment.iconColor.opacity(0.12))
                }

            // File info
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.filename)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(attachment.fileType.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)

                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)

                    Text(attachment.fileSizeString)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    if attachment.uploadStatus == .uploading {
                        ProgressView()
                            .controlSize(.mini)
                    } else if attachment.uploadStatus == .failed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    }
                }
            }

            // Remove button (only in input bar, not in sent messages)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .singleSurfaceGlass(
            cornerRadius: 10,
            stableFillOpacity: 0.01,
            borderWidth: 0.7,
            darkBorderOpacity: 0.14,
            lightBorderOpacity: 0.08
        )
    }
}

/// Horizontal scrollable row of file attachment chips.
struct FileAttachmentsRow: View {
    let attachments: [FileAttachment]
    var onRemove: ((FileAttachment) -> Void)? = nil

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        FileAttachmentChip(
                            attachment: attachment,
                            onRemove: onRemove != nil ? { onRemove?(attachment) } : nil
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
