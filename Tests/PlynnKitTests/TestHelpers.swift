import Foundation

extension Array {
    /// Split into consecutive slices of at most `size` elements — used to feed
    /// fixture audio to streaming engines the way the mic does.
    func chunks(of size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
