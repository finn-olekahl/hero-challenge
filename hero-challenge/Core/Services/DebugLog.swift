import Foundation

// MARK: - Debug Logging

/// Debug-only logging function. Compiles to nothing in release builds.
/// Replaces raw `print()` calls to prevent sensitive data leakage in production.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
