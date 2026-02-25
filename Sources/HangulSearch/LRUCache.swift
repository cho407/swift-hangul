import Foundation

final class LRUCache<Key: Hashable, Value>: @unchecked Sendable {
    private final class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private let capacity: Int
    private var storage: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard let node = storage[key] else { return nil }
        moveToTail(node)
        return node.value
    }

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }

        if let existing = storage[key] {
            existing.value = value
            moveToTail(existing)
            return
        }

        let node = Node(key: key, value: value)
        storage[key] = node
        appendToTail(node)

        if storage.count > capacity {
            evictHead()
        }
    }

    private func appendToTail(_ node: Node) {
        if let tail {
            tail.next = node
            node.prev = tail
            self.tail = node
        } else {
            head = node
            tail = node
        }
    }

    private func moveToTail(_ node: Node) {
        guard tail !== node else { return }

        let prev = node.prev
        let next = node.next

        if let prev {
            prev.next = next
        } else {
            head = next
        }

        if let next {
            next.prev = prev
        } else {
            tail = prev
        }

        node.prev = nil
        node.next = nil
        appendToTail(node)
    }

    private func evictHead() {
        guard let head else { return }

        let next = head.next
        if let next {
            next.prev = nil
        }

        self.head = next
        if tail === head {
            tail = nil
        }

        storage.removeValue(forKey: head.key)
    }
}
