import ChatDomain
import SwiftUI

package extension FileAttachment {
    /// Returns a color representing the file type for use in attachment chips.
    var iconColor: Color {
        switch fileType.lowercased() {
        case "pdf": .red
        case "docx", "doc": .blue
        case "pptx", "ppt": .orange
        case "csv": .green
        case "xlsx", "xls": .green
        default: .secondary
        }
    }
}
