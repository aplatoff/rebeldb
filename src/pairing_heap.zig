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

fn cmp(context: void, a: i32, b: i32) Order {
    _ = context;
    return std.math.order(a, b);
}

test "PairingHeap - Basic Operations" {
    const Heap = PairingHeap(i32, void, cmp);
    var heap = Heap.init(testing.allocator, {});
    defer heap.deinit();

    try expect(heap.peek() == null);

    try heap.add(10);
    try expectEqual(heap.peek().?, 10);

    try heap.add(5);
    try expectEqual(heap.peek().?, 5);

    try heap.add(15);
    try expectEqual(heap.peek().?, 5);

    try expectEqual(heap.removeOrNull().?, 5);
    try expectEqual(heap.peek().?, 10);

    try expectEqual(heap.removeOrNull().?, 10);
    try expectEqual(heap.peek().?, 15);

    try expectEqual(heap.removeOrNull().?, 15);
    try expect(heap.peek() == null);
}
