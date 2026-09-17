/// Union-find with union-by-size and path halving.
///
/// This replaces the original's `ConnectionCreator` / `Connection` pair, which
/// rebuilt and merged explicit lists of connected points on every move.
public struct DisjointSet: Sendable, Hashable, Codable {
    private var parent: [Int32]
    private var size: [Int32]

    public init(count: Int) {
        parent = (0..<count).map(Int32.init)
        size = [Int32](repeating: 1, count: count)
    }

    public var count: Int { parent.count }

    public mutating func find(_ element: Int) -> Int {
        var x = Int32(element)
        while parent[Int(x)] != x {
            parent[Int(x)] = parent[Int(parent[Int(x)])]  // path halving
            x = parent[Int(x)]
        }
        return Int(x)
    }

    /// Merges two sets. Returns `false` if they were already the same set.
    @discardableResult
    public mutating func union(_ a: Int, _ b: Int) -> Bool {
        var rootA = find(a)
        var rootB = find(b)
        guard rootA != rootB else { return false }
        if size[rootA] < size[rootB] { swap(&rootA, &rootB) }
        parent[rootB] = Int32(rootA)
        size[rootA] += size[rootB]
        return true
    }

    public mutating func connected(_ a: Int, _ b: Int) -> Bool {
        find(a) == find(b)
    }

    /// Non-compressing lookup, for read-only queries on a `let` binding.
    public func root(_ element: Int) -> Int {
        var x = Int32(element)
        while parent[Int(x)] != x { x = parent[Int(x)] }
        return Int(x)
    }

    public func areConnected(_ a: Int, _ b: Int) -> Bool { root(a) == root(b) }
}
