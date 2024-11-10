//
// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT
//

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

    // Merging example
    var heap1 = Heap.init(testing.allocator);
    defer heap1.deinit();

    try heap1.insert(15);
    try heap1.insert(2);

    heap.merge(&heap1);

    std.debug.print("Min value after merging: {any}\n", .{heap.findMin()});
}
