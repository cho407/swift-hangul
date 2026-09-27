struct BoundedTopK<Element> {
    private var heap: [Element] = []
    private let capacity: Int
    private let isBetter: (Element, Element) -> Bool

    init(capacity: Int, isBetter: @escaping (Element, Element) -> Bool) {
        self.capacity = max(1, capacity)
        self.isBetter = isBetter
        heap.reserveCapacity(self.capacity)
    }

    mutating func insert(_ value: Element) {
        // The root is the worst retained result; replacements cost O(log K).
        if heap.count < capacity {
            heap.append(value)
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard isBetter(heap[parent], heap[child]) else { break }
                heap.swapAt(parent, child)
                child = parent
            }
        } else if isBetter(value, heap[0]) {
            heap[0] = value
            var parent = 0
            while parent * 2 + 1 < heap.count {
                var child = parent * 2 + 1
                if child + 1 < heap.count, isBetter(heap[child], heap[child + 1]) { child += 1 }
                guard isBetter(heap[parent], heap[child]) else { break }
                heap.swapAt(parent, child)
                parent = child
            }
        }
    }

    func sorted() -> [Element] { heap.sorted(by: isBetter) }
}
