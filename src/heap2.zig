const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Order = std.math.Order;

fn PairingHeap(comptime T: type, comptime compareFn: fn (a: T, b: T) Order) type {
    const Node = struct {
        const Self = @This();
        value: T,
        child: ?*Self,
        sibling: ?*Self,
        parent: ?*Self,

        pub fn init(allocator: Allocator, value: T) !*Self {
            const self = try allocator.create(Self);
            self.value = value;
            self.child = null;
            self.sibling = null;
            self.parent = null;
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
            if (self.root) |r| r.parent = null;
        }

        pub fn findMin(self: *Self) ?T {
            return if (self.root) |root| root.value else null;
        }

        pub fn deleteMin(self: *Self) void {
            if (self.root) |root| {
                const oldRoot = root;
                self.root = self.mergePairs(root.child);
                if (self.root) |r| r.parent = null;
                self.allocator.destroy(oldRoot);
            }
        }

        pub fn merge(self: *Self, other: *Self) void {
            self.root = mergeNodes(self.root, other.root);
            if (self.root) |r| r.parent = null;
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
            if (a) |aa| {
                if (b) |bb| {
                    if (compareFn(bb.value, aa.value) == Order.gt) {
                        bb.sibling = aa.child;
                        if (bb.sibling) |s| s.parent = bb;
                        aa.child = bb;
                        bb.parent = aa;
                        return a;
                    } else {
                        aa.sibling = bb.child;
                        if (aa.sibling) |s| s.parent = aa;
                        bb.child = aa;
                        aa.parent = bb;
                        return b;
                    }
                } else {
                    return a;
                }
            } else {
                return b;
            }
        }

        fn mergePairs(self: *Self, node: ?*Node) ?*Node {
            if (node) |first| {
                if (first.sibling) |second| {
                    const remaining = second.sibling;
                    first.sibling = null;
                    second.sibling = null;
                    const merged = mergeNodes(first, second);
                    return mergeNodes(merged, self.mergePairs(remaining));
                } else {
                    return first;
                }
            } else {
                return null;
            }
        }

        pub fn replace(self: *Self, old_value: T, new_value: T) !void {
            const node = self.findNode(self.root, old_value);
            if (node) |n| {
                const order = compareFn(new_value, n.value);
                n.value = new_value;

                if (order == Order.lt) {
                    // New value is smaller, percolate up
                    self.percolateUp(n);
                } else if (order == Order.gt) {
                    // New value is larger, percolate down
                    percolateDown(n);
                }
            } else return error.ValueNotFound;
        }

        fn percolateUp(self: *Self, node: *Node) void {
            var current = node;
            while (current.parent) |parent| {
                if (compareFn(current.value, parent.value) == Order.lt) {
                    // Swap values
                    const temp = current.value;
                    current.value = parent.value;
                    parent.value = temp;

                    current = parent;
                } else {
                    break;
                }
            }
            if (current.parent == null) {
                self.root = current;
            }
        }

        fn percolateDown(node: *Node) void {
            var current = node;
            while (true) {
                var smallest = current;
                if (current.child != null) {
                    var c = current.child;
                    while (c) |sibling| {
                        if (compareFn(sibling.value, smallest.value) == Order.lt) {
                            smallest = sibling;
                        }
                        c = sibling.sibling;
                    }
                }

                if (smallest != current) {
                    const temp = current.value;
                    current.value = smallest.value;
                    smallest.value = temp;

                    current = smallest;
                } else {
                    break;
                }
            }
        }

        fn findNode(self: *Self, node: ?*Node, value: T) ?*Node {
            if (node) |n| {
                if (compareFn(n.value, value) == Order.eq) {
                    return n;
                } else {
                    const foundInChild = self.findNode(n.child, value);
                    if (foundInChild) |found| {
                        return found;
                    } else {
                        return self.findNode(n.sibling, value);
                    }
                }
            } else return null;
        }
    };
}

fn cmp(a: i32, b: i32) Order {
    if (a < b) {
        return Order.lt;
    } else if (a > b) {
        return Order.gt;
    } else {
        return Order.eq;
    }
}

test "PairingHeap" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try heap.insert(10);
    try heap.insert(5);
    try heap.insert(20);
    try heap.insert(3);
    std.debug.print("Min value: {any}\n", .{heap.findMin()});

    heap.deleteMin();
    std.debug.print("Min value after deleteMin: {any}\n", .{heap.findMin()});

    // Update value
    try heap.replace(5, 8);
    std.debug.print("Min value after replacing 5 with 8: {any}\n", .{heap.findMin()});

    // Merging example
    var heap1 = Heap.init(testing.allocator);
    defer heap1.deinit();

    try heap1.insert(15);
    try heap1.insert(7);

    heap.merge(&heap1);

    std.debug.print("Min value after merging: {any}\n", .{heap.findMin()});
}
