import Foundation

enum SVGIcon {
    /// 根元素的 width/height 换成 viewBox 的像素尺寸。很多图标库导出的是 width="1em"，
    /// 系统会把它当成 1×1 点，排版时缩成一个点。
    static func normalized(_ text: String) -> String {
        guard let range = text.range(of: "<svg[^>]*>", options: .regularExpression) else { return text }
        var tag = String(text[range])
        var size = (width: "64", height: "64")
        if let box = tag.range(of: #"viewBox="[^"]*""#, options: .regularExpression) {
            let numbers = tag[box].dropFirst(9).dropLast()
                .split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { Double($0) }
            if numbers.count == 4, numbers[2] > 0, numbers[3] > 0 {
                size = (format(numbers[2]), format(numbers[3]))
            }
        }
        tag = tag.replacingOccurrences(of: #"\s(width|height)="[^"]*""#, with: "", options: .regularExpression)
        tag = tag.replacingOccurrences(of: "<svg", with: "<svg width=\"\(size.width)\" height=\"\(size.height)\"")
        var result = text
        result.replaceSubrange(range, with: tag)
        return result
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
