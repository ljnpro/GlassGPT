import SwiftUI
import ChatDomain

package extension FileAttachment {
    /// Returns a color representing the file type for use in attachment chips.
    var iconColor: Color {
        switch fileType.lowercased() {
        case "pdf": return .red
        case "docx", "doc": return .blue
        case "pptx", "ppt": return .orange
        case "csv": return .green
        case "xlsx", "xls": return .green
        default: return .secondary
        }
    }
}
