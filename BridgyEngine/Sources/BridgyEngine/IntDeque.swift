/// Minimal integer deque backed by a growable ring buffer.
///
/// Exists so the 0-1 BFS can push zero-cost relaxations to the front and
/// unit-cost ones to the back without pulling in swift-collections.
struct IntDeque {
    private var storage: ContiguousArray<Int>
    private var head = 0
    private(set) var count = 0

    init(minimumCapacity: Int = 16) {
        var capacity = 16
        while capacity < minimumCapacity { capacity <<= 1 }
        storage = ContiguousArray(repeating: 0, count: capacity)
    }

    var isEmpty: Bool { count == 0 }

    private var mask: Int { storage.count - 1 }

    private mutating func growIfNeeded() {
        guard count == storage.count else { return }
        var larger = ContiguousArray<Int>(repeating: 0, count: storage.count << 1)
        for offset in 0..<count { larger[offset] = storage[(head + offset) & mask] }
        storage = larger
        head = 0
    }

    mutating func pushFront(_ value: Int) {
        growIfNeeded()
        head = (head - 1) & mask
        storage[head] = value
        count += 1
    }

    mutating func pushBack(_ value: Int) {
        growIfNeeded()
        storage[(head + count) & mask] = value
        count += 1
    }

    mutating func popFront() -> Int? {
        guard count > 0 else { return nil }
        let value = storage[head]
        head = (head + 1) & mask
        count -= 1
        return value
    }
}
