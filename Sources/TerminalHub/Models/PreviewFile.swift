import Foundation

/// A file currently open in the preview panel.
struct PreviewFile: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }

    /// Icon name based on file extension.
    var iconName: String {
        switch url.pathExtension.lowercased() {
        case "pdf":                             return "doc.richtext"
        case "png", "jpg", "jpeg", "gif",
             "webp", "heic", "tiff", "bmp":    return "photo"
        case "md", "markdown", "txt":           return "doc.plaintext"
        case "docx", "doc":                     return "doc.fill"
        case "pptx", "ppt":                     return "rectangle.stack"
        case "xlsx", "xls", "csv":              return "tablecells"
        case "swift", "py", "js", "ts",
             "html", "css", "json", "yaml":     return "chevron.left.forwardslash.chevron.right"
        default:                                return "doc"
        }
    }
}
