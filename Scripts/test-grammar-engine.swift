#!/usr/bin/env swift

// Quick test of the grammar engine
import Foundation

// Import the grammar bridge
@_cdecl("analyze_text")
func analyze_text(_ text: UnsafePointer<CChar>, _ dialect: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

let testText = "This are a test."
let dialect = "American"

print("Testing grammar engine with: '\(testText)'")
print("Dialect: \(dialect)")

// Call the C function
if let resultPtr = analyze_text(testText, dialect) {
    let resultString = String(cString: resultPtr)
    print("\nResult:")
    print(resultString)

    // Parse JSON to check if errors were found
    if let jsonData = resultString.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
       let errors = json["errors"] as? [[String: Any]]
    {
        print("\n✅ Found \(errors.count) error(s)")
        for error in errors {
            if let message = error["message"] as? String {
                print("  - \(message)")
            }
        }
    }
} else {
    print("❌ analyze_text returned null")
}
