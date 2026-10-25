import XCTest
import SwiftUI
import UIKit
import Combine
@testable import AkiChat

final class MarkdownTablePerformanceTests: XCTestCase {
    private func fixture(_ rows: Int) -> String {
        (["| Name | Value | Detail |", "| --- | ---: | --- |"] + (0..<rows).map {
            "| 项目 \($0) | **\($0)** | [链接](https://example.com/\($0)) |"
        }).joined(separator: "\n")
    }

    func testPreparedRowsPreserveTableContentAndStreamingSuffix() throws {
        for source in ["| A | B |\n|---|---|\n| 1 | 2 |", "A | B\n---|---\nx | y\nz", fixture(100)] {
            let probe = LegacyTableProbe()
            let block = try XCTUnwrap(MarkdownParser.blocks(source).first)
            XCTAssertEqual(block.kind, .table)
            XCTAssertEqual(block.text, source)
            XCTAssertEqual(block.tableRows, probe.parse(source))
            let next = try XCTUnwrap(MarkdownParser.blocks(source + "\n| next | `code` | 最终单元格").first)
            XCTAssertEqual(next.tableRows.last, ["next", "`code`", "最终单元格"])
            XCTAssertEqual(block.tableRows, probe.parse(source)) // prior snapshot is immutable
        }
        XCTAssertTrue(MarkdownParser.blocks("plain paragraph")[0].tableRows.isEmpty)
    }

    func testTablePreparationFinishesOnDocumentWorker() {
        let document = MarkdownDocument(parser: { source in
            XCTAssertFalse(Thread.isMainThread)
            let blocks = MarkdownParser.blocks(source)
            XCTAssertEqual(blocks.first?.tableRows.count, 101)
            return blocks
        })
        let done = expectation(description: "prepared table delivered to main")
        let sink = document.$blocks.dropFirst().sink { blocks in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(blocks.first?.tableRows.last?.first, "项目 99")
            done.fulfill()
        }
        document.load(fixture(100), cacheResult: false)
        wait(for: [done], timeout: 3)
        withExtendedLifetime(sink) {}
    }

    /// Same process, same native cells, alternating order. Not a scroll/FPS benchmark.
    func testCompareLegacyAndPreparedTableFirstLayout() throws {
        for count in [20, 100] {
            let source = fixture(count)
            let started = CFAbsoluteTimeGetCurrent()
            let block = try XCTUnwrap(MarkdownParser.blocks(source).first)
            let preparation = CFAbsoluteTimeGetCurrent() - started
            // Warm UIKit/font/link caches equally before recording samples.
            _ = layout(MarkdownTable(rows: block.tableRows, size: 16))
            _ = layout(LegacyMarkdownTable(text: source, size: 16, probe: LegacyTableProbe()))
            for trial in 0..<4 {
                let probe = LegacyTableProbe()
                var before: LayoutSample!, after: LayoutSample!
                if trial.isMultiple(of: 2) {
                    before = layout(LegacyMarkdownTable(text: source, size: 16, probe: probe))
                    after = layout(MarkdownTable(rows: block.tableRows, size: 16))
                } else {
                    after = layout(MarkdownTable(rows: block.tableRows, size: 16))
                    before = layout(LegacyMarkdownTable(text: source, size: 16, probe: probe))
                }
                XCTAssertEqual(before.cells, after.cells)
                XCTAssertEqual(after.cells.count, (count + 1) * 3)
                XCTAssertGreaterThan(probe.calls, count)
                let report: [String: Any] = ["rows": count, "columns": 3, "trial": trial,
                    "legacyFullParsesOnMain": probe.calls, "legacyParseMS": probe.seconds * 1000,
                    "preparedFullParsesOnMain": 0, "preparationMS": preparation * 1000,
                    "legacyLayoutMS": before.seconds * 1000, "preparedLayoutMS": after.seconds * 1000,
                    "equalNativeCells": before.cells == after.cells,
                    "system": UIDevice.current.systemVersion, "fpsMeasured": false]
                let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                print("TABLE_LAYOUT_BENCHMARK " + String(decoding: data, as: UTF8.self))
            }
        }
    }

    private struct LayoutSample { var seconds: Double; var cells: [String] }
    private func layout<Content: View>(_ content: Content) -> LayoutSample {
        precondition(Thread.isMainThread)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        let start = CFAbsoluteTimeGetCurrent()
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        // Drain the existing NativeRichText async height feedback on both paths.
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        host.view.layoutIfNeeded()
        let seconds = CFAbsoluteTimeGetCurrent() - start
        func cells(_ view: UIView) -> [String] {
            if let text = view as? UITextView { return [text.text ?? ""] }
            return view.subviews.flatMap(cells)
        }
        let result = LayoutSample(seconds: seconds, cells: cells(host.view).sorted())
        window.isHidden = true; window.rootViewController = nil
        return result
    }
}

/// Exact pre-change computed getter and table body from 433e9b3; test-only baseline.
private final class LegacyTableProbe {
    var calls = 0
    var seconds = 0.0
    func parse(_ text: String) -> [[String]] {
        precondition(Thread.isMainThread)
        calls += 1
        let start = CFAbsoluteTimeGetCurrent()
        defer { seconds += CFAbsoluteTimeGetCurrent() - start }
        return text.components(separatedBy: "\n").enumerated().filter { $0.offset != 1 }.map {
            var cells = $0.element.components(separatedBy: "|")
            if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
            if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
            return cells.map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
}

private struct LegacyMarkdownTable: View {
    let text: String
    let size: Double
    let probe: LegacyTableProbe
    var rows: [[String]] { probe.parse(text) }
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
