import XCTest
import UIKit
@testable import AkiChat

final class ComposerPerformanceTests: XCTestCase {
    private func editor(_ text: String, width: CGFloat = 300) -> ComposerTextView {
        let view = ComposerTextView(frame: CGRect(x: 0, y: 0, width: width, height: 140))
        view.font = .systemFont(ofSize: 16)
        view.textContainerInset = UIEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        view.text = text
        return view
    }
    private func legacyHeight(_ view: UITextView) -> CGFloat {
        min(140, max(42, ceil(view.sizeThatFits(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)).height)))
    }
    func testBoundedHeightMatchesNativeAcrossScriptsAndWidths() {
        let values = ["", "hello", "输入与中文候选", "مرحبا بالعالم", "👩🏽‍💻👨‍👩‍👧‍👦", "\n", "a\n\n",
                      String(repeating: "行\n", count: 300), String(repeating: "unbroken", count: 400),
                      String(repeating: "中英 emoji 👩🏽‍💻 text ", count: 200)]
        for width: CGFloat in [180, 280, 370] {
            for value in values {
                let view = editor(value, width: width)
                let expected = legacyHeight(view)
                XCTAssertEqual(view.fittingComposerHeight(), expected, accuracy: 1, "width=\(width), length=\(value.utf16.count)")
                XCTAssertEqual(view.text, value)
            }
        }
        // Exercise the clamp boundary and trailing empty lines, including >512 chars.
        for lines in 4...9 {
            let value = String(repeating: "\u{200B}", count: 520) + String(repeating: "\n", count: lines)
            let view = editor(value)
            XCTAssertEqual(view.fittingComposerHeight(), legacyHeight(view), accuracy: 1)
        }
    }
    func testHeightShrinksAfterDeletionAndResizePreservesSelection() {
        let view = editor(String(repeating: "长草稿\n", count: 500))
        view.selectedRange = NSRange(location: 3, length: 2)
        let selection = view.selectedRange
        XCTAssertEqual(view.fittingComposerHeight(), 140)
        XCTAssertEqual(view.selectedRange, selection)
        view.text = "short"
        XCTAssertEqual(view.fittingComposerHeight(), 42)
        view.text = String(repeating: "wrapping words ", count: 50)
        for width: CGFloat in [190, 370, 260] {
            view.bounds.size.width = width
            XCTAssertEqual(view.fittingComposerHeight(), legacyHeight(view), accuracy: 1)
        }
    }
    /// Paired main-thread measurements, same UIKit editor, different instances so
    /// the baseline's unlimited layout cannot warm the optimized editor's layout.
    func testCompareNativeAndBoundedInputHeightAfterEdits() throws {
        let fixtures = [("short", "draft"), ("wrapped-8k", String(repeating: "中英 text 👩🏽‍💻 ", count: 400)),
                        ("multiline-2k", String(repeating: "行 text\n", count: 2000))]
        for (name, text) in fixtures {
            for trial in 0..<4 {
                let before = editor(text), after = editor(text)
                _ = legacyHeight(before); _ = after.fittingComposerHeight()
                var oldMS = 0.0, newMS = 0.0
                for tick in 0..<12 {
                    var expected: CGFloat = 0, actual: CGFloat = 0
                    let append = NSAttributedString(string: "x", attributes: [.font: UIFont.systemFont(ofSize: 16)])
                    // Editing cost is included; both paths must invalidate layout.
                    func old() {
                        let start = CFAbsoluteTimeGetCurrent()
                        before.textStorage.append(append); expected = legacyHeight(before)
                        oldMS += (CFAbsoluteTimeGetCurrent() - start) * 1000
                    }
                    func new() {
                        let start = CFAbsoluteTimeGetCurrent()
                        after.textStorage.append(append); actual = after.fittingComposerHeight()
                        newMS += (CFAbsoluteTimeGetCurrent() - start) * 1000
                    }
                    if (trial + tick).isMultiple(of: 2) { old(); new() } else { new(); old() }
                    XCTAssertEqual(actual, expected, accuracy: 1)
                }
                XCTAssertEqual(before.text, after.text)
                let record: [String: Any] = ["fixture": name, "trial": trial, "edits": 12,
                    "utf16Length": (text as NSString).length, "legacyMS": oldMS, "boundedMS": newMS,
                    "system": UIDevice.current.systemVersion, "fpsMeasured": false]
                print("COMPOSER_HEIGHT_BENCHMARK " + String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
            }
        }
    }
}
