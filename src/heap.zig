//
// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT
//

const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Order = std.math.Order;

pub fn PairingHeap(comptime T: type, comptime compareFn: fn (a: T, b: T) Order) type {
    const Node = struct {
        const Self = @This();
        value: T,
        child: ?*Self,
        sibling: ?*Self,

        pub fn init(allocator: Allocator, value: T) !*Self {
            const self = try allocator.create(Self);
            self.value = value;
            self.child = null;
            self.sibling = null;
            return self;
        }
    };

    return struct {
        const Self = @This();

        root: ?*Node,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .root = null,
                .allocator = allocator,
            };
        }

        pub fn isEmpty(self: *Self) bool {
            return self.root == null;
        }

        pub fn insert(self: *Self, value: T) !void {
            const newNode = try Node.init(self.allocator, value);
            self.root = mergeNodes(self.root, newNode);
        }

        pub fn findMin(self: *Self) ?T {
            return if (self.root) |root| root.value else null;
        }

        pub fn deleteMin(self: *Self) void {
            if (self.root) |root| {
                const oldRoot = root;
                self.root = self.mergePairs(root.child);
                self.allocator.destroy(oldRoot);
            }
        }

        pub fn merge(self: *Self, other: *Self) void {
            self.root = mergeNodes(self.root, other.root);
            other.root = null;
        }

        pub fn deinit(self: *Self) void {
            self.destroyNode(self.root);
            self.root = null;
        }

        fn destroyNode(self: *Self, node: ?*Node) void {
            if (node) |n| {
                self.destroyNode(n.child);
                self.destroyNode(n.sibling);
                self.allocator.destroy(n);
            }
        }

        fn mergeNodes(a: ?*Node, b: ?*Node) ?*Node {
            if (a) |aa|
                if (b) |bb|
                    if (compareFn(bb.value, aa.value) == Order.gt) {
                        bb.sibling = aa.child;
                        aa.child = bb;
                        return a;
                    } else {
                        aa.sibling = bb.child;
                        bb.child = aa;
                        return b;
                    }
                else
                    return a
            else
                return b;
        }

        fn mergePairs(self: *Self, node: ?*Node) ?*Node {
            if (node) |first|
                if (first.sibling) |second| {
                    const remaining = second.sibling;
                    first.sibling = null;
                    second.sibling = null;
                    const merged = mergeNodes(first, second);
                    return mergeNodes(merged, self.mergePairs(remaining));
                } else return first
            else
                return null;
        }
    };
}

fn cmp(a: i32, b: i32) Order {
    return std.math.order(a, b);
}

const expect = testing.expect;
const expectEqual = testing.expectEqual;

test "PairingHeap" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try heap.insert(10);
    try heap.insert(5);
    try heap.insert(20);
    try heap.insert(3);

    heap.deleteMin();

    // Merging example
    var heap1 = Heap.init(testing.allocator);
    defer heap1.deinit();

    try heap1.insert(15);
    try heap1.insert(2);

    heap.merge(&heap1);
}

test "PairingHeap - Empty Heap Operations" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Test empty heap properties
    try expect(heap.isEmpty());
    try expect(heap.findMin() == null);

    // DeleteMin on empty heap should not crash
    heap.deleteMin();
    try expect(heap.isEmpty());
}

test "PairingHeap - Single Element Operations" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try heap.insert(42);
    try expect(!heap.isEmpty());
    try expectEqual(heap.findMin(), 42);

    heap.deleteMin();
    try expect(heap.isEmpty());
    try expect(heap.findMin() == null);
}

test "PairingHeap - Multiple Elements Order" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Insert in random order
    try heap.insert(5);
    try heap.insert(3);
    try heap.insert(7);
    try heap.insert(1);
    try heap.insert(4);

    // Verify extraction order
    try expectEqual(heap.findMin(), 1);
    heap.deleteMin();
    try expectEqual(heap.findMin(), 3);
    heap.deleteMin();
    try expectEqual(heap.findMin(), 4);
    heap.deleteMin();
    try expectEqual(heap.findMin(), 5);
    heap.deleteMin();
    try expectEqual(heap.findMin(), 7);
    heap.deleteMin();
    try expect(heap.isEmpty());
}

test "PairingHeap - Duplicate Values" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try heap.insert(5);
    try heap.insert(5);
    try heap.insert(5);

    try expectEqual(heap.findMin(), 5);
    heap.deleteMin();
    try expectEqual(heap.findMin(), 5);
    heap.deleteMin();
    try expectEqual(heap.findMin(), 5);
    heap.deleteMin();
    try expect(heap.isEmpty());
}

test "PairingHeap - Merge Operations" {
    const Heap = PairingHeap(i32, cmp);
    var heap1 = Heap.init(testing.allocator);
    defer heap1.deinit();
    var heap2 = Heap.init(testing.allocator);
    defer heap2.deinit();

    // Fill first heap
    try heap1.insert(5);
    try heap1.insert(3);
    try heap1.insert(7);

    // Fill second heap
    try heap2.insert(4);
    try heap2.insert(2);
    try heap2.insert(6);

    // Merge heaps
    heap1.merge(&heap2);

    // Verify merged heap contains all elements in correct order
    const expected = [_]i32{ 2, 3, 4, 5, 6, 7 };
    for (expected) |exp| {
        try expectEqual(heap1.findMin(), exp);
        heap1.deleteMin();
    }
    try expect(heap1.isEmpty());
    try expect(heap2.isEmpty());
}

test "PairingHeap - Stress Test" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Insert many elements in reverse order
    var i: i32 = 1000;
    while (i > 0) : (i -= 1) {
        try heap.insert(i);
        try expectEqual(heap.findMin(), @min(i, 1000));
    }

    // Verify they come out in sorted order
    i = 1;
    while (!heap.isEmpty()) : (i += 1) {
        try expectEqual(heap.findMin(), i);
        heap.deleteMin();
    }
}

test "PairingHeap - Mixed Operations" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Insert some elements
    try heap.insert(10);
    try heap.insert(5);
    try expectEqual(heap.findMin(), 5);

    // Delete min
    heap.deleteMin();
    try expectEqual(heap.findMin(), 10);

    // Insert more elements
    try heap.insert(3);
    try heap.insert(7);
    try expectEqual(heap.findMin(), 3);

    // Create and merge another heap
    var other = Heap.init(testing.allocator);
    defer other.deinit();
    try other.insert(4);
    try other.insert(2);

    heap.merge(&other);
    try expectEqual(heap.findMin(), 2);

    // Verify final order
    const expected = [_]i32{ 2, 3, 4, 7, 10 };
    for (expected) |exp| {
        try expectEqual(heap.findMin(), exp);
        heap.deleteMin();
    }
    try expect(heap.isEmpty());
}
