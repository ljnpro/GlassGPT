import Foundation
import UIKit

@MainActor
func makeSnapshotImageFile() throws -> URL {
    let size = CGSize(width: 1200, height: 900)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
        UIColor.systemIndigo.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor.white.setFill()
        context.fill(
            CGRect(x: 80, y: 120, width: 1040, height: 620)
        )
        let title = "Generated Chart" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        title.draw(
            at: CGPoint(x: 120, y: 180),
            withAttributes: attributes
        )
    }

    guard let data = image.pngData() else {
        throw NativeChatTestError.saveFailed
    }

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-preview-image.png")
    try data.write(to: url, options: .atomic)
    return url
}

@MainActor
func makeSnapshotPDFFile() throws -> URL {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: bounds)
    let data = renderer.pdfData { context in
        context.beginPage()
        let title = "Quarterly Report" as NSString
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(
                ofSize: 28,
                weight: .bold
            ),
            .foregroundColor: UIColor.black
        ]
        title.draw(
            at: CGPoint(x: 48, y: 52),
            withAttributes: titleAttributes
        )
        let body = "The release completed successfully." as NSString
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(
                ofSize: 18,
                weight: .regular
            ),
            .foregroundColor: UIColor.darkGray
        ]
        body.draw(
            in: CGRect(x: 48, y: 120, width: 516, height: 200),
            withAttributes: bodyAttributes
        )
    }

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-preview-document.pdf")
    try data.write(to: url, options: .atomic)
    return url
}
