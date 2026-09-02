import CoreGraphics
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum FrontmatterBlockLayout {
    static let collapsedHeight: CGFloat = 40
    static let gapBelowCollapsedBlock: CGFloat = 12
    static let cornerRadius: CGFloat = 8
    static let horizontalPadding: CGFloat = 12
    static let chevronWidth: CGFloat = 16
    static let iconTextGap: CGFloat = 8
    static let countWidth: CGFloat = 36
    static let rowHeight: CGFloat = 36
    static let deleteControlSize: CGFloat = 22
    static let deleteControlGap: CGFloat = 6
    static let editControlSize: CGFloat = 22
    static let editControlGap: CGFloat = 4
    static let fieldGap: CGFloat = 8

    #if os(iOS)
    static let uiSurfaceColor = UIColor(hex: 0x1C1C1E)
    static let uiFieldBackgroundColor = UIColor(hex: 0x2C2C2E)
    #elseif os(macOS)
    static let nsSurfaceColor = NSColor(hex: 0x1C1C1E)
    static let nsFieldBackgroundColor = NSColor(hex: 0x2C2C2E)
    #endif

    static var reservedTopInset: CGFloat {
        collapsedHeight + gapBelowCollapsedBlock
    }

    static func blockHeight(for document: EditableFrontmatterDocument) -> CGFloat {
        blockHeight(for: document, isExpanded: true)
    }

    static func blockHeight(for document: EditableFrontmatterDocument, isExpanded: Bool) -> CGFloat {
        guard isExpanded else { return collapsedHeight }
        return collapsedHeight + CGFloat(rowCount(for: document)) * rowHeight
    }

    static func reservedHeight(for document: EditableFrontmatterDocument) -> CGFloat {
        reservedHeight(for: document, isExpanded: true)
    }

    static func reservedHeight(for document: EditableFrontmatterDocument, isExpanded: Bool) -> CGFloat {
        reservedTopInset
    }

    static func rowCount(for document: EditableFrontmatterDocument) -> Int {
        document.fields.count + 1
    }

    static func newFieldRowIndex(for document: EditableFrontmatterDocument) -> Int {
        document.fields.count
    }

    static func blockRect(point: CGPoint, contentWidth: CGFloat, document: EditableFrontmatterDocument) -> CGRect {
        blockRect(point: point, contentWidth: contentWidth, document: document, isExpanded: true)
    }

    static func blockRect(
        point: CGPoint,
        contentWidth: CGFloat,
        document: EditableFrontmatterDocument,
        isExpanded: Bool
    ) -> CGRect {
        CGRect(
            x: point.x,
            y: point.y,
            width: max(0, contentWidth),
            height: blockHeight(for: document, isExpanded: isExpanded)
        ).integral
    }

    static func headerRect(in blockRect: CGRect) -> CGRect {
        CGRect(
            x: blockRect.minX,
            y: blockRect.minY,
            width: blockRect.width,
            height: collapsedHeight
        )
    }

    static func rowRect(at index: Int, in blockRect: CGRect) -> CGRect {
        CGRect(
            x: blockRect.minX + horizontalPadding,
            y: blockRect.minY + collapsedHeight + CGFloat(index) * rowHeight,
            width: max(0, blockRect.width - horizontalPadding * 2),
            height: rowHeight
        )
    }

    static func keyRect(for rowRect: CGRect, blockWidth: CGFloat) -> CGRect {
        let keyWidth = min(118, blockWidth * 0.34)
        return CGRect(
            x: rowRect.minX,
            y: rowRect.minY,
            width: keyWidth,
            height: rowRect.height
        )
    }

    static func valueRect(
        for rowRect: CGRect,
        blockWidth: CGFloat,
        hasEditControl: Bool = false
    ) -> CGRect {
        let keyWidth = min(118, blockWidth * 0.34)
        let valueLeading = rowRect.minX + keyWidth + fieldGap
        var valueTrailing = rowRect.maxX - deleteControlSize - deleteControlGap
        if hasEditControl {
            valueTrailing -= editControlSize + editControlGap
        }
        return CGRect(
            x: valueLeading,
            y: rowRect.minY,
            width: max(0, valueTrailing - valueLeading),
            height: rowRect.height
        )
    }

    static func deleteRect(for rowRect: CGRect) -> CGRect {
        CGRect(
            x: rowRect.maxX - deleteControlSize,
            y: rowRect.midY - deleteControlSize / 2,
            width: deleteControlSize,
            height: deleteControlSize
        )
    }

    static func editRect(for rowRect: CGRect) -> CGRect {
        CGRect(
            x: rowRect.maxX - deleteControlSize - deleteControlGap - editControlSize,
            y: rowRect.midY - editControlSize / 2,
            width: editControlSize,
            height: editControlSize
        )
    }

    static func fieldIndex(at point: CGPoint, in blockRect: CGRect, document: EditableFrontmatterDocument, isExpanded: Bool) -> Int? {
        guard let rowIndex = rowIndex(at: point, in: blockRect, document: document, isExpanded: isExpanded),
              rowIndex < document.fields.count else {
            return nil
        }
        return rowIndex
    }

    static func rowIndex(at point: CGPoint, in blockRect: CGRect, document: EditableFrontmatterDocument, isExpanded: Bool) -> Int? {
        guard isExpanded else { return nil }
        let visibleCount = rowCount(for: document)

        for index in 0..<visibleCount where rowRect(at: index, in: blockRect).contains(point) {
            return index
        }
        return nil
    }
}
