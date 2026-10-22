import SwiftUI
import UIKit

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable { case paragraph, heading(Int), quote, code(String), table }
    var id: Int
    var kind: Kind
    var text: String
}
enum MarkdownParser {
    static func blocks(_ source: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = [], lines: [String] = []
        var codeLanguage: String?
        func append(_ kind: MarkdownBlock.Kind, _ text: String) {
            guard !text.isEmpty else { return }
            result.append(MarkdownBlock(id: result.count, kind: kind, text: text))
        }
        func flush() {
            let text = lines.joined(separator: "\n")
            if text.contains("|"), lines.count >= 2,
               lines[1].replacingOccurrences(of: " ", with: "").range(of: "^\\|?:?-+:?\\|", options: .regularExpression) != nil {
                append(.table, text)
            } else { append(.paragraph, text) }
            lines = []
        }
        for line in source.components(separatedBy: .newlines) {
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if let language = codeLanguage { append(.code(language), lines.joined(separator: "\n")); lines = []; codeLanguage = nil }
                else { flush(); codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                continue
            }
            if codeLanguage != nil { lines.append(line); continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }
            let level = line.prefix(while: { $0 == "#" }).count
            if level > 0 && level <= 6 && line.dropFirst(level).hasPrefix(" ") {
                flush(); append(.heading(level), String(line.dropFirst(level + 1)))
            } else if line.hasPrefix("> ") { flush(); append(.quote, String(line.dropFirst(2))) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush(); append(.paragraph, "• " + String(line.dropFirst(2)))
            } else { lines.append(line) }
        }
        if let language = codeLanguage { append(.code(language), lines.joined(separator: "\n")) } else { flush() }
        return result
    }
}

struct MarkdownView: View {
    let source: String
    let size: Double
    @State private var blocks: [MarkdownBlock] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block.kind {
                case .code(let language):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(language.isEmpty ? "代码" : language).font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Button { UIPasteboard.general.string = block.text } label: { Label("复制", systemImage: "doc.on.doc").font(.caption) }
                        }
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(block.text).font(.system(size: CGFloat(max(12, size - 2)), design: .monospaced))
                                .fixedSize(horizontal: true, vertical: true).padding(.bottom, 4)
                        }
                    }.padding(14).background(Theme.card).cornerRadius(12)
                case .heading(let level): NativeRichText(text: block.text, size: size + Double(max(0, 4 - level)) * 2, bold: true, markdown: true)
                case .quote:
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.5)).frame(width: 3)
                        NativeRichText(text: block.text, size: size, color: .secondaryLabel, markdown: true)
                    }
                case .table: MarkdownTable(text: block.text, size: size)
                case .paragraph: NativeRichText(text: block.text, size: size, markdown: true)
                }
            }
        }.onAppear { blocks = MarkdownParser.blocks(source) }
            .onChange(of: source) { blocks = MarkdownParser.blocks($0) }
    }
}
struct MarkdownTable: View {
    let text: String
    let size: Double
    var rows: [[String]] {
        text.components(separatedBy: "\n").enumerated().filter { $0.offset != 1 }.map {
            var cells = $0.element.components(separatedBy: "|")
            if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
            if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
            return cells.map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(rows[row].indices, id: \.self) { column in
                            NativeRichText(text: rows[row][column], size: max(12, size - 2), bold: row == 0, markdown: true)
                                .frame(width: 144, alignment: .leading).padding(10)
                        }
                    }.background(row == 0 ? Theme.accent.opacity(0.08) : Theme.card)
                    Divider()
                }
            }
        }.cornerRadius(10)
    }
}

/// iOS 14 UITextView supplies text selection, accessible native text, and tappable links.
struct NativeRichText: View {
    var text: String
    var size: Double
    var color: UIColor = .label
    var bold = false
    var markdown = false
    @State private var height: CGFloat = 24
    var body: some View {
        GeometryReader { geometry in
            MeasuredText(text: text, size: size, color: color, bold: bold, markdown: markdown,
                         width: geometry.size.width, height: $height)
        }.frame(height: height)
    }
}
private struct MeasuredText: UIViewRepresentable {
    let text: String
    let size: Double
    let color: UIColor
    let bold: Bool
    let markdown: Bool
    let width: CGFloat
    @Binding var height: CGFloat
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isScrollEnabled = false; view.backgroundColor = .clear
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let stamp = "\(size)-\(bold)-\(markdown)-\(view.traitCollection.userInterfaceStyle.rawValue)-\(text)"
        if view.accessibilityIdentifier != stamp {
            view.attributedText = InlineMarkdown.render(text, size: CGFloat(size), color: color, bold: bold, enabled: markdown)
            view.accessibilityIdentifier = stamp
        }
        let measured = ceil(view.sizeThatFits(CGSize(width: max(1, width), height: .greatestFiniteMagnitude)).height)
        if abs(height - measured) > 0.5 { DispatchQueue.main.async { height = measured } }
    }
}
enum InlineMarkdown {
    static func render(_ source: String, size: CGFloat, color: UIColor, bold: Bool, enabled: Bool) -> NSAttributedString {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let result = NSMutableAttributedString(string: source, attributes: [.font: base, .foregroundColor: color])
        guard enabled else { return result }
        // A deliberately small native renderer; block parsing is independent for later extensions.
        let patterns = ["`([^`\n]+)`", "\\*\\*(.+?)\\*\\*", "(?<!\\*)\\*([^*\n]+)\\*(?!\\*)", "\\[([^\\]]+)\\]\\((https?://[^\\s)]+|mailto:[^\\s)]+)\\)"]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: result.string, range: NSRange(location: 0, length: result.length))
            for match in matches.reversed() {
                let captured = (result.string as NSString).substring(with: match.range(at: 1))
                var attributes: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: color]
                if index == 0 { attributes[.font] = UIFont.monospacedSystemFont(ofSize: size - 1, weight: .regular); attributes[.backgroundColor] = UIColor.secondarySystemBackground }
                if index == 1 { attributes[.font] = UIFont.systemFont(ofSize: size, weight: .bold) }
                if index == 2 { attributes[.font] = UIFont.italicSystemFont(ofSize: size) }
                if index == 3 { attributes[.link] = (result.string as NSString).substring(with: match.range(at: 2)) }
                result.replaceCharacters(in: match.range, with: NSAttributedString(string: captured, attributes: attributes))
            }
        }
        return result
    }
}
