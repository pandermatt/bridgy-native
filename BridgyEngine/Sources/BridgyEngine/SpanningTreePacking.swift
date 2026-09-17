/// Splits a graph's edges into two edge-disjoint spanning trees.
///
/// This is the matroid-union augmenting algorithm. Placing an edge is easy when
/// it closes no cycle in one of the two forests; when it closes a cycle in both,
/// we look for a chain of displacements — this edge can go into a forest if that
/// edge moves out of it, and that edge can move if another moves, and so on —
/// and apply the whole chain at once.
///
/// It is used for the Perfect engine's pairing strategy, which needs the two
/// trees rather than just the knowledge that they exist.
public enum SpanningTreePacking {

    public struct Edge: Sendable {
        /// Caller's identifier, carried through untouched.
        public let id: Int
        public let u: Int
        public let v: Int

        public init(id: Int, u: Int, v: Int) {
            self.id = id
            self.u = u
            self.v = v
        }
    }

    /// A forest under construction: its edges plus adjacency for path queries.
    private struct Forest {
        var edges: Set<Int> = []
        var adjacency: [[Int]]  // node -> edge ids

        init(nodeCount: Int) {
            adjacency = [[Int]](repeating: [], count: nodeCount)
        }

        mutating func insert(_ edge: Edge) {
            edges.insert(edge.id)
            adjacency[edge.u].append(edge.id)
            adjacency[edge.v].append(edge.id)
        }

        mutating func remove(_ edge: Edge) {
            edges.remove(edge.id)
            adjacency[edge.u].removeAll { $0 == edge.id }
            adjacency[edge.v].removeAll { $0 == edge.id }
        }

        /// Edges on the unique path between `from` and `to`, or `nil` if the two
        /// are in different components — which means an edge joining them is
        /// safe to add.
        func path(from: Int, to: Int, edges edgeTable: [Int: Edge]) -> [Int]? {
            if from == to { return [] }
            var cameFromNode = [Int: Int]()
            var cameFromEdge = [Int: Int]()
            var queue = [from]
            cameFromNode[from] = from
            var head = 0
            while head < queue.count {
                let node = queue[head]
                head += 1
                for edgeID in adjacency[node] {
                    guard let edge = edgeTable[edgeID] else { continue }
                    let next = edge.u == node ? edge.v : edge.u
                    if cameFromNode[next] != nil { continue }
                    cameFromNode[next] = node
                    cameFromEdge[next] = edgeID
                    if next == to {
                        var result: [Int] = []
                        var cursor = to
                        while cursor != from, let previous = cameFromNode[cursor] {
                            if let used = cameFromEdge[cursor] { result.append(used) }
                            cursor = previous
                        }
                        return result
                    }
                    queue.append(next)
                }
            }
            return nil
        }
    }

    /// Partitions `edges` into two spanning trees, or returns `nil` if the graph
    /// does not admit such a split.
    ///
    /// A necessary condition is `edges.count == 2 * (nodeCount - 1)`; it is not
    /// sufficient, which is why this searches rather than merely counting.
    public static func packTwoSpanningTrees(
        nodeCount: Int,
        edges: [Edge]
    ) -> (first: Set<Int>, second: Set<Int>)? {
        guard nodeCount > 0 else { return nil }
        guard edges.count == 2 * (nodeCount - 1) else { return nil }

        var table = [Int: Edge]()
        for edge in edges { table[edge.id] = edge }

        var forests = [Forest(nodeCount: nodeCount), Forest(nodeCount: nodeCount)]
        var home = [Int: Int]()  // edge id -> forest index

        for edge in edges {
            guard place(edge, into: &forests, home: &home, table: table) else { return nil }
        }

        guard forests[0].edges.count == nodeCount - 1,
              forests[1].edges.count == nodeCount - 1 else { return nil }
        return (forests[0].edges, forests[1].edges)
    }

    /// Finds and applies a chain of displacements that makes room for `newEdge`.
    private static func place(
        _ newEdge: Edge,
        into forests: inout [Forest],
        home: inout [Int: Int],
        table: [Int: Edge]
    ) -> Bool {
        var displacedBy = [Int: Int]()   // edge -> the edge that would push it out
        var queue = [newEdge.id]
        displacedBy[newEdge.id] = -1
        var head = 0

        while head < queue.count {
            let currentID = queue[head]
            head += 1
            guard let current = table[currentID] else { continue }

            for forestIndex in 0..<2 {
                guard let cycle = forests[forestIndex].path(from: current.u, to: current.v, edges: table) else {
                    // No path, so no cycle: `current` fits here. Walk the chain back
                    // to the original edge, moving each one into the slot freed by
                    // the edge ahead of it.
                    var chain: [Int] = []
                    var cursor = currentID
                    while cursor != -1 {
                        chain.append(cursor)
                        cursor = displacedBy[cursor] ?? -1
                    }

                    var target = forestIndex
                    for (position, edgeID) in chain.enumerated() {
                        guard let edge = table[edgeID] else { return false }
                        if position == chain.count - 1 {
                            forests[target].insert(edge)      // the new edge, never placed before
                            home[edgeID] = target
                        } else {
                            guard let source = home[edgeID] else { return false }
                            forests[source].remove(edge)
                            forests[target].insert(edge)
                            home[edgeID] = target
                            target = source                   // the slot just vacated
                        }
                    }
                    return true
                }

                for candidate in cycle where displacedBy[candidate] == nil {
                    displacedBy[candidate] = currentID
                    queue.append(candidate)
                }
            }
        }
        return false
    }
}
