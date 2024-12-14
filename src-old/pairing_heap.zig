const std = @import("std");
const Allocator = std.mem.Allocator;
const Order = std.math.Order;

/// PairingHeap implementation as a drop-in replacement for std.priority_queue.
/// Initialize with `init`.
/// Provide `compareFn` that returns `Order.lt` when its second argument
/// should get popped before its third argument,
/// `Order.eq` if the arguments are of equal priority, or `Order.gt`
/// if the third argument should be popped first.
pub fn PairingHeap(comptime T: type, comptime Context: type, comptime compareFn: fn (context: Context, a: T, b: T) Order) type {
    // Special index value for null references
    const NULL_INDEX = std.math.maxInt(usize);

    // Define Node as a union of ActiveNode and FreeNode
    const Node = union(enum) {
        ActiveNode: struct {
            value: T,
            child: usize, // Index of first child
            sibling: usize, // Index of next sibling
        },
        FreeNode: struct {
            next_free: usize, // Index of next free node
        },
    };

    return struct {
        const Self = @This();

        nodes: []Node,
        cap: usize,
        root: usize, // Index of root node
        free_list: usize, // Head of free list
        allocator: Allocator,
        context: Context,

        /// Initialize and return a pairing heap.
        pub fn init(allocator: Allocator, context: Context) Self {
            return Self{
                .nodes = &[_]Node{},
                .cap = 0,
                .root = NULL_INDEX,
                .free_list = NULL_INDEX,
                .allocator = allocator,
                .context = context,
            };
        }

        /// Free memory used by the heap.
        pub fn deinit(self: Self) void {
            self.allocator.free(self.allocatedSlice());
        }

        /// Ensure that the heap can fit at least `new_capacity` items.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) !void {
            var better_capacity = self.cap;
            if (better_capacity >= new_capacity) return;
            while (true) {
                better_capacity = better_capacity + better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }
            const old_memory = self.allocatedSlice();
            const new_memory = try self.allocator.realloc(old_memory, better_capacity);
            self.nodes.ptr = new_memory.ptr;
            self.cap = new_memory.len;
        }

        fn allocatedSlice(self: *const Self) []Node {
            return self.nodes.ptr[0..self.cap];
        }

        fn allocNode(self: *Self, value: T) !usize {
            // First try to reuse a node from the free list
            if (self.free_list != NULL_INDEX) {
                const index = self.free_list;
                const free_node = &self.nodes[index].FreeNode;
                self.free_list = free_node.next_free;
                self.nodes[index] = Node{
                    .ActiveNode = .{
                        .value = value,
                        .child = NULL_INDEX,
                        .sibling = NULL_INDEX,
                    },
                };
                return index;
            }

            // If no free nodes, append a new one
            const index = self.nodes.len;
            try self.ensureTotalCapacity(index + 1);
            self.nodes.len += 1;
            self.nodes[index] = Node{
                .ActiveNode = .{
                    .value = value,
                    .child = NULL_INDEX,
                    .sibling = NULL_INDEX,
                },
            };
            return index;
        }

        fn freeNode(self: *Self, index: usize) void {
            if (index == NULL_INDEX) return;

            // Overwrite the node with a FreeNode
            self.nodes[index] = Node{
                .FreeNode = .{
                    .next_free = self.free_list,
                },
            };
            self.free_list = index;
        }

        /// Insert a new element, maintaining priority.
        pub fn add(self: *Self, value: T) !void {
            const new_index = try self.allocNode(value);
            if (self.root == NULL_INDEX) {
                self.root = new_index;
            } else {
                self.root = self.mergeNodes(self.root, new_index);
            }
        }

        /// Look at the highest priority element in the heap. Returns null if empty.
        pub fn peek(self: *const Self) ?T {
            return if (self.root != NULL_INDEX)
                self.nodes[self.root].ActiveNode.value
            else
                null;
        }

        /// Remove and return the highest priority element from the heap.
        pub fn removeOrNull(self: *Self) ?T {
            if (self.root == NULL_INDEX) return null;

            const old_root = self.root;
            const root_node = &self.nodes[old_root].ActiveNode;
            const result = root_node.value;
            const children = root_node.child;

            self.root = self.mergePairs(children);

            // Free the old root node
            self.freeNode(old_root);

            return result;
        }

        pub fn count(self: Self) usize {
            // Return the number of active nodes
            return self.nodes.len - self.countFreeNodes();
        }

        fn countFreeNodes(self: Self) usize {
            var free_count: usize = 0;
            var index = self.free_list;
            while (index != NULL_INDEX) {
                free_count += 1;
                index = self.nodes[index].FreeNode.next_free;
            }
            return free_count;
        }

        pub fn capacity(self: Self) usize {
            return self.cap;
        }

        fn mergeNodes(self: *Self, a: usize, b: usize) usize {
            if (a == NULL_INDEX) return b;
            if (b == NULL_INDEX) return a;

            var node_a = &self.nodes[a].ActiveNode;
            var node_b = &self.nodes[b].ActiveNode;

            if (compareFn(self.context, node_a.value, node_b.value) == Order.lt) {
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

        fn mergePairs(self: *Self, first: usize) usize {
            if (first == NULL_INDEX) return NULL_INDEX;

            const first_node = &self.nodes[first].ActiveNode;
            const second = first_node.sibling;
            if (second == NULL_INDEX) return first;

            const second_node = &self.nodes[second].ActiveNode;
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

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;

fn lessThan(context: void, a: u32, b: u32) Order {
    _ = context;
    return std.math.order(a, b);
}

fn greaterThan(context: void, a: u32, b: u32) Order {
    return lessThan(context, a, b).invert();
}

const PHlt = PairingHeap(u32, void, lessThan);
const PHgt = PairingHeap(u32, void, greaterThan);

test "PairingHeap - add and remove min heap" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.add(54);
    try heap.add(12);
    try heap.add(7);
    try heap.add(23);
    try heap.add(25);
    try heap.add(13);
    try expectEqual(@as(u32, 7), heap.removeOrNull().?);
    try expectEqual(@as(u32, 12), heap.removeOrNull().?);
    try expectEqual(@as(u32, 13), heap.removeOrNull().?);
    try expectEqual(@as(u32, 23), heap.removeOrNull().?);
    try expectEqual(@as(u32, 25), heap.removeOrNull().?);
    try expectEqual(@as(u32, 54), heap.removeOrNull().?);
}

test "PairingHeap - add and remove same min heap" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.add(1);
    try heap.add(1);
    try heap.add(2);
    try heap.add(2);
    try heap.add(1);
    try heap.add(1);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
    try expectEqual(@as(u32, 2), heap.removeOrNull().?);
    try expectEqual(@as(u32, 2), heap.removeOrNull().?);
}

test "PairingHeap - removeOrNull on empty" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try expect(heap.removeOrNull() == null);
}

test "PairingHeap - edge case 3 elements" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.add(9);
    try heap.add(3);
    try heap.add(2);
    try expectEqual(@as(u32, 2), heap.removeOrNull().?);
    try expectEqual(@as(u32, 3), heap.removeOrNull().?);
    try expectEqual(@as(u32, 9), heap.removeOrNull().?);
}

test "PairingHeap - peek" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try expect(heap.peek() == null);
    try heap.add(9);
    try heap.add(3);
    try heap.add(2);
    try expectEqual(@as(u32, 2), heap.peek().?);
    try expectEqual(@as(u32, 2), heap.peek().?);
}

test "PairingHeap - addSlice" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();
    const items = [_]u32{ 15, 7, 21, 14, 13, 22, 12, 6, 7, 25, 5, 24, 11, 16, 15, 24, 2, 1 };

    // Since PairingHeap doesn't have addSlice, we need to add items individually
    for (items) |item| {
        try heap.add(item);
    }

    const sorted_items = [_]u32{ 1, 2, 5, 6, 7, 7, 11, 12, 13, 14, 15, 15, 16, 21, 22, 24, 24, 25 };
    for (sorted_items) |expected| {
        try expectEqual(expected, heap.removeOrNull().?);
    }
}

test "PairingHeap - add and remove max heap" {
    var heap = PHgt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.add(54);
    try heap.add(12);
    try heap.add(7);
    try heap.add(23);
    try heap.add(25);
    try heap.add(13);
    try expectEqual(@as(u32, 54), heap.removeOrNull().?);
    try expectEqual(@as(u32, 25), heap.removeOrNull().?);
    try expectEqual(@as(u32, 23), heap.removeOrNull().?);
    try expectEqual(@as(u32, 13), heap.removeOrNull().?);
    try expectEqual(@as(u32, 12), heap.removeOrNull().?);
    try expectEqual(@as(u32, 7), heap.removeOrNull().?);
}

test "PairingHeap - add and remove same max heap" {
    var heap = PHgt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.add(1);
    try heap.add(1);
    try heap.add(2);
    try heap.add(2);
    try heap.add(1);
    try heap.add(1);
    try expectEqual(@as(u32, 2), heap.removeOrNull().?);
    try expectEqual(@as(u32, 2), heap.removeOrNull().?);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
}

test "PairingHeap - remove all elements and check empty" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.add(10);
    try heap.add(20);
    try heap.add(30);

    try expectEqual(@as(u32, 10), heap.removeOrNull().?);
    try expectEqual(@as(u32, 20), heap.removeOrNull().?);
    try expectEqual(@as(u32, 30), heap.removeOrNull().?);
    try expect(heap.removeOrNull() == null);
}

test "PairingHeap - ensureTotalCapacity" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.ensureTotalCapacity(100);
    try expect(heap.capacity() >= 100);
}

test "PairingHeap - count and capacity" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try expectEqual(@as(usize, 0), heap.count());
    try heap.add(1);
    try heap.add(2);
    try expectEqual(@as(usize, 2), heap.count());

    // The capacity might be greater than or equal to count
    try expect(heap.capacity() >= heap.count());
}

test "PairingHeap - peek after remove" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.add(2);
    try heap.add(1);
    try expectEqual(@as(u32, 1), heap.peek().?);
    try expectEqual(@as(u32, 1), heap.removeOrNull().?);
    try expectEqual(@as(u32, 2), heap.peek().?);
    try expectEqual(@as(u32, 2), heap.removeOrNull().?);
    try expect(heap.peek() == null);
}

fn contextLessThan(context: []const u32, a: usize, b: usize) Order {
    return std.math.order(context[a], context[b]);
}

test "PairingHeap - contextful comparator" {
    const context = [_]u32{ 5, 3, 4, 2, 2, 8, 0 };

    const CPHlt = PairingHeap(usize, []const u32, contextLessThan);

    var heap = CPHlt.init(testing.allocator, context[0..]);
    defer heap.deinit();

    try heap.add(0);
    try heap.add(1);
    try heap.add(2);
    try heap.add(3);
    try heap.add(4);
    try heap.add(5);
    try heap.add(6);
    try expectEqual(@as(usize, 6), heap.removeOrNull().?); // context[6] == 0
    try expectEqual(@as(usize, 4), heap.removeOrNull().?); // context[4] == 2
    try expectEqual(@as(usize, 3), heap.removeOrNull().?); // context[3] == 2
    try expectEqual(@as(usize, 1), heap.removeOrNull().?); // context[1] == 3
    try expectEqual(@as(usize, 2), heap.removeOrNull().?); // context[2] == 4
    try expectEqual(@as(usize, 0), heap.removeOrNull().?); // context[0] == 5
    try expectEqual(@as(usize, 5), heap.removeOrNull().?); // context[5] == 8
}

test "PairingHeap - large number of elements" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    const num_elements = 1000;
    var rand = std.rand.DefaultPrng.init(0);

    var tracker = std.AutoHashMap(u32, void).init(testing.allocator);
    defer tracker.deinit();

    // Add random elements
    for (num_elements) |_| {
        const value = rand.random().uintLessThan(u32, 10000);
        try heap.add(value);
        try tracker.put(value, {});
    }

    var last_value: u32 = 0;
    while (heap.removeOrNull()) |value| {
        // Ensure min-heap property
        try expect(value >= last_value);
        last_value = value;
        _ = tracker.remove(value);
    }

    // Ensure all elements were removed
    try expectEqual(@as(usize, 0), tracker.count());
}

const Item = struct {
    key: u32,
    value: []const u8,
};

fn itemLessThan(context: void, a: Item, b: Item) Order {
    _ = context;
    return std.math.order(a.key, b.key);
}

test "PairingHeap - custom struct elements" {
    const ItemHeap = PairingHeap(Item, void, itemLessThan);

    var heap = ItemHeap.init(testing.allocator, {});
    defer heap.deinit();

    const items = [_]Item{
        .{ .key = 5, .value = "five" },
        .{ .key = 2, .value = "two" },
        .{ .key = 8, .value = "eight" },
        .{ .key = 1, .value = "one" },
        .{ .key = 3, .value = "three" },
    };

    for (items) |item| {
        try heap.add(item);
    }

    const expected_order = [_][]const u8{ "one", "two", "three", "five", "eight" };
    for (expected_order) |expected_value| {
        const item = heap.removeOrNull().?;
        try expectEqualStrings(expected_value, item.value);
    }
}

fn expectEqualStrings(expected: []const u8, actual: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) {
        return error.TestFailure;
    }
}

test "PairingHeap - remove all elements and check count" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    const items = [_]u32{ 10, 20, 30, 40, 50 };
    for (items) |item| {
        try heap.add(item);
    }

    try expectEqual(@as(usize, 5), heap.count());

    while (heap.removeOrNull()) |value| {
        _ = value;
    }

    try expectEqual(@as(usize, 0), heap.count());
}

test "PairingHeap - removeOrNull with manual free" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    const items = [_]u32{ 10, 20, 30 };
    for (items) |item| {
        try heap.add(item);
    }

    try expectEqual(@as(u32, 10), heap.removeOrNull().?);
    try expectEqual(@as(u32, 20), heap.removeOrNull().?);
}

test "PairingHeap - test ensureTotalCapacity and free" {
    var heap = PHlt.init(testing.allocator, {});
    defer heap.deinit();

    try heap.ensureTotalCapacity(64);
    try expect(heap.capacity() >= 64);

    try heap.add(1);
    try heap.add(2);
    try expectEqual(@as(usize, 2), heap.count());

    // Deinit should not crash
}
