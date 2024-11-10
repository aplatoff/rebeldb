const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const ArrayList = std.ArrayList;

pub fn PairingHeap(comptime T: type, comptime compareFn: fn (a: T, b: T) Order) type {
    // Special index values
    const NULL_INDEX = std.math.maxInt(u32);

    const Node = struct {
        value: T,
        child: u32, // Index of first child
        sibling: u32, // Index of next sibling
        is_active: bool, // Whether this node is in use
    };

    return struct {
        const Self = @This();

        nodes: ArrayList(Node),
        root: u32, // Index of root node
        free_list: u32, // Head of free list
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .nodes = ArrayList(Node).init(allocator),
                .root = NULL_INDEX,
                .free_list = NULL_INDEX,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit();
        }

        fn allocNode(self: *Self, value: T) !u32 {
            // First try to reuse a node from the free list
            if (self.free_list != NULL_INDEX) {
                const index = self.free_list;
                const node = &self.nodes.items[index];
                self.free_list = node.sibling;
                node.* = Node{
                    .value = value,
                    .child = NULL_INDEX,
                    .sibling = NULL_INDEX,
                    .is_active = true,
                };
                return index;
            }

            // If no free nodes, append a new one
            const index = @as(u32, @intCast(self.nodes.items.len));
            try self.nodes.append(Node{
                .value = value,
                .child = NULL_INDEX,
                .sibling = NULL_INDEX,
                .is_active = true,
            });
            return index;
        }

        fn freeNode(self: *Self, index: u32) void {
            if (index == NULL_INDEX) return;

            var node = &self.nodes.items[index];
            node.is_active = false;
            node.sibling = self.free_list;
            self.free_list = index;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.root == NULL_INDEX;
        }

        pub fn insert(self: *Self, value: T) !void {
            const new_index = try self.allocNode(value);
            if (self.root == NULL_INDEX) {
                self.root = new_index;
            } else {
                self.root = self.mergeNodes(self.root, new_index);
            }
        }

        pub fn findMin(self: *const Self) ?T {
            return if (self.root != NULL_INDEX)
                self.nodes.items[self.root].value
            else
                null;
        }

        pub fn deleteMin(self: *Self) void {
            if (self.root == NULL_INDEX) return;

            const old_root = self.root;
            const root_node = &self.nodes.items[old_root];
            const children = root_node.child;

            // Clear the old root's pointers before freeing
            root_node.child = NULL_INDEX;
            root_node.sibling = NULL_INDEX;

            self.root = self.mergePairs(children);
            self.freeNode(old_root);
        }

        pub fn merge(self: *Self, other: *Self) void {
            if (other.root == NULL_INDEX) return;
            if (self.root == NULL_INDEX) {
                // If self is empty, just take other's nodes
                self.nodes.clearAndFree();
                self.nodes = other.nodes;
                self.root = other.root;
                self.free_list = other.free_list;

                other.nodes = ArrayList(Node).init(other.allocator);
                other.root = NULL_INDEX;
                other.free_list = NULL_INDEX;
                return;
            }

            // Move all nodes from other to self
            const old_len = self.nodes.items.len;

            // Append other's nodes to self
            self.nodes.appendSlice(other.nodes.items) catch return;

            // Update indices in moved nodes
            var i: u32 = 0;
            while (i < other.nodes.items.len) : (i += 1) {
                const idx = @as(u32, @intCast(old_len + i));
                var node = &self.nodes.items[idx];
                if (node.child != NULL_INDEX) {
                    node.child += @as(u32, @intCast(old_len));
                }
                if (node.sibling != NULL_INDEX) {
                    node.sibling += @as(u32, @intCast(old_len));
                }
            }

            // Update other's root index and merge roots
            const other_root = other.root + @as(u32, @intCast(old_len));
            self.root = self.mergeNodes(self.root, other_root);

            // Clear other heap
            other.nodes.clearAndFree();
            other.root = NULL_INDEX;
            other.free_list = NULL_INDEX;
        }

        fn mergeNodes(self: *Self, a: u32, b: u32) u32 {
            if (a == NULL_INDEX) return b;
            if (b == NULL_INDEX) return a;

            var node_a = &self.nodes.items[a];
            var node_b = &self.nodes.items[b];

            if (compareFn(node_a.value, node_b.value) == Order.lt) {
                // a becomes the root
                node_b.sibling = node_a.child;
                node_a.child = b;
                return a;
            } else {
                // b becomes the root
                node_a.sibling = node_b.child;
                node_b.child = a;
                return b;
            }
        }

        fn mergePairs(self: *Self, first: u32) u32 {
            if (first == NULL_INDEX) return NULL_INDEX;

            const first_node = &self.nodes.items[first];
            const second = first_node.sibling;
            if (second == NULL_INDEX) return first;

            const second_node = &self.nodes.items[second];
            const remaining = second_node.sibling;

            // Clear sibling pointers
            first_node.sibling = NULL_INDEX;
            second_node.sibling = NULL_INDEX;

            // Merge this pair and the result of merging remaining pairs
            const merged_pair = self.mergeNodes(first, second);
            const merged_remaining = self.mergePairs(remaining);
            return self.mergeNodes(merged_pair, merged_remaining);
        }
    };
}

const expect = testing.expect;
const expectEqual = testing.expectEqual;

fn cmp(a: i32, b: i32) Order {
    return std.math.order(a, b);
}

test "ArrayPairingHeap" {
    // All your existing tests should work with this implementation
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try heap.insert(10);
    try heap.insert(5);
    try heap.insert(20);
    try heap.insert(3);

    try testing.expectEqual(heap.findMin(), 3);
    heap.deleteMin();
    try testing.expectEqual(heap.findMin(), 5);
}

test "ArrayPairingHeap - Basic Operations" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try expect(heap.isEmpty());
    try expect(heap.findMin() == null);

    try heap.insert(10);
    try expect(!heap.isEmpty());
    try expectEqual(heap.findMin().?, 10);

    try heap.insert(5);
    try expectEqual(heap.findMin().?, 5);

    try heap.insert(15);
    try expectEqual(heap.findMin().?, 5);

    heap.deleteMin();
    try expectEqual(heap.findMin().?, 10);

    heap.deleteMin();
    try expectEqual(heap.findMin().?, 15);

    heap.deleteMin();
    try expect(heap.isEmpty());
}

test "ArrayPairingHeap - Node Reuse" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Insert and delete to populate free list
    try heap.insert(1);
    try heap.insert(2);
    try heap.insert(3);
    heap.deleteMin();
    heap.deleteMin();
    heap.deleteMin();

    // These insertions should reuse freed nodes
    try heap.insert(4);
    try heap.insert(5);
    try heap.insert(6);

    // Verify the heap still works correctly
    try expectEqual(heap.findMin().?, 4);
    heap.deleteMin();
    try expectEqual(heap.findMin().?, 5);
    heap.deleteMin();
    try expectEqual(heap.findMin().?, 6);
}

test "ArrayPairingHeap - Stress Test with Node Reuse" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const n = 1000;
    var i: i32 = 0;

    // Phase 1: Insert n elements
    while (i < n) : (i += 1) {
        try heap.insert(i);
        try expectEqual(heap.findMin().?, 0);
    }

    // Phase 2: Delete n/2 elements
    i = 0;
    while (i < n / 2) : (i += 1) {
        try expectEqual(heap.findMin().?, i);
        heap.deleteMin();
    }

    // Phase 3: Insert n/2 new elements (should reuse nodes)
    i = 0;
    while (i < n / 2) : (i += 1) {
        try heap.insert(i);
    }

    // Verify final state
    var expected: i32 = 0;
    while (!heap.isEmpty()) : (expected += 1) {
        try expectEqual(heap.findMin().?, expected);
        heap.deleteMin();
    }
}

test "ArrayPairingHeap - Complex Merge Operations" {
    const Heap = PairingHeap(i32, cmp);
    var heap1 = Heap.init(testing.allocator);
    defer heap1.deinit();
    var heap2 = Heap.init(testing.allocator);
    defer heap2.deinit();
    var heap3 = Heap.init(testing.allocator);
    defer heap3.deinit();

    // Fill heaps with interleaving values
    try heap1.insert(1);
    try heap1.insert(4);
    try heap1.insert(7);

    try heap2.insert(2);
    try heap2.insert(5);
    try heap2.insert(8);

    try heap3.insert(3);
    try heap3.insert(6);
    try heap3.insert(9);

    // Merge all heaps
    heap1.merge(&heap2);
    heap1.merge(&heap3);

    // Verify merged result
    var expected: i32 = 1;
    while (!heap1.isEmpty()) : (expected += 1) {
        try expectEqual(heap1.findMin().?, expected);
        heap1.deleteMin();
    }

    // Verify other heaps are empty
    try expect(heap2.isEmpty());
    try expect(heap3.isEmpty());
}

test "ArrayPairingHeap - Random Operations" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    // Track elements in a separate array for validation
    var elements = std.ArrayList(i32).init(testing.allocator);
    defer elements.deinit();

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const op = random.intRangeLessThan(u8, 0, 3);
        switch (op) {
            0 => { // Insert
                const value = random.intRangeLessThan(i32, -100, 100);
                try heap.insert(value);
                try elements.append(value);
                if (elements.items.len > 0) {
                    var min_val = elements.items[0];
                    for (elements.items) |val| {
                        if (val < min_val) min_val = val;
                    }
                    try expectEqual(heap.findMin().?, min_val);
                }
            },
            1 => { // DeleteMin
                if (!heap.isEmpty()) {
                    heap.deleteMin();

                    // Remove min value from elements
                    if (elements.items.len > 0) {
                        var min_idx: usize = 0;
                        var j: usize = 1;
                        while (j < elements.items.len) : (j += 1) {
                            if (elements.items[j] < elements.items[min_idx]) {
                                min_idx = j;
                            }
                        }
                        _ = elements.orderedRemove(min_idx);
                    }
                }
            },
            2 => { // Merge with new heap
                var other = Heap.init(testing.allocator);
                defer other.deinit();
                const num_elements = random.intRangeLessThan(usize, 1, 10);
                var j: usize = 0;
                while (j < num_elements) : (j += 1) {
                    const value = random.intRangeLessThan(i32, -100, 100);
                    try other.insert(value);
                    try elements.append(value);
                }
                heap.merge(&other);
            },
            else => unreachable,
        }

        if (!heap.isEmpty()) {
            var min_val = elements.items[0];
            for (elements.items) |val| {
                if (val < min_val) min_val = val;
            }
            try expectEqual(heap.findMin().?, min_val);
        }
    }
}

test "ArrayPairingHeap - Edge Cases" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Edge case 1: Delete from empty heap
    heap.deleteMin();
    try expect(heap.isEmpty());

    // Edge case 2: Insert same value multiple times
    try heap.insert(1);
    try heap.insert(1);
    try heap.insert(1);
    try expectEqual(heap.findMin().?, 1);
    heap.deleteMin();
    try expectEqual(heap.findMin().?, 1);
    heap.deleteMin();
    try expectEqual(heap.findMin().?, 1);
    heap.deleteMin();
    try expect(heap.isEmpty());

    // Edge case 3: Merge with empty heap
    var empty_heap = Heap.init(testing.allocator);
    defer empty_heap.deinit();
    try heap.insert(1);
    heap.merge(&empty_heap);
    try expectEqual(heap.findMin().?, 1);

    // Edge case 4: Merge empty heap with non-empty heap
    var another_heap = Heap.init(testing.allocator);
    defer another_heap.deinit();
    try another_heap.insert(2);
    empty_heap.merge(&another_heap);
    try expectEqual(empty_heap.findMin().?, 2);

    // Edge case 5: Insert min/max values
    try heap.insert(std.math.minInt(i32));
    try heap.insert(std.math.maxInt(i32));
    try expectEqual(heap.findMin().?, std.math.minInt(i32));
}

test "ArrayPairingHeap - Monotonic Sequences" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Test increasing sequence
    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        try heap.insert(i);
        try expectEqual(heap.findMin().?, 0);
    }

    // Test decreasing sequence
    var heap2 = Heap.init(testing.allocator);
    defer heap2.deinit();

    i = 100;
    while (i >= 0) : (i -= 1) {
        try heap2.insert(i);
        try expectEqual(heap2.findMin().?, i);
    }

    // Merge increasing and decreasing sequences
    heap.merge(&heap2);

    // Verify merged heap
    i = 0;
    var prev_min: ?i32 = null;
    while (!heap.isEmpty()) {
        const current_min = heap.findMin().?;
        if (prev_min) |p| {
            try testing.expect(current_min >= p);
        }
        heap.deleteMin();
        prev_min = current_min;
    }
}

test "ArrayPairingHeap - Memory Management" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Fill and empty the heap multiple times to test memory management
    var outer: usize = 0;
    while (outer < 5) : (outer += 1) {
        // Fill heap
        var i: i32 = 0;
        while (i < 100) : (i += 1) {
            try heap.insert(i);
        }

        // Empty half the heap
        i = 0;
        while (i < 50) : (i += 1) {
            heap.deleteMin();
        }

        // Fill again
        i = 0;
        while (i < 50) : (i += 1) {
            try heap.insert(i);
        }

        // Empty completely
        while (!heap.isEmpty()) {
            heap.deleteMin();
        }
    }
}
