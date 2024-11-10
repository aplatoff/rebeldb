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

        // Modified insert function to return node reference
        pub fn insert(self: *Self, value: T) !*Node {
            const newNode = try Node.init(self.allocator, value);
            self.root = mergeNodes(self.root, newNode);
            if (self.root) |r| r.parent = null;
            return newNode;
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
                        // Make bb a child of aa
                        bb.sibling = aa.child;
                        if (bb.sibling) |s| s.parent = aa;
                        bb.parent = aa;
                        aa.child = bb;
                        return a;
                    } else {
                        // Make aa a child of bb
                        aa.sibling = bb.child;
                        if (aa.sibling) |s| s.parent = bb;
                        aa.parent = bb;
                        bb.child = aa;
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
                    const mergedWithRemaining = mergeNodes(merged, self.mergePairs(remaining));
                    return mergedWithRemaining;
                } else {
                    return first;
                }
            } else {
                return null;
            }
        }

        // Decrease the value of a node and adjust the heap
        pub fn decreaseKey(self: *Self, node: *Node, new_value: T) !void {
            if (compareFn(new_value, node.value) == Order.gt) {
                return error.NewValueGreaterThanCurrent;
            }
            node.value = new_value;

            if (node.parent != null) {
                // Cut the node from its current position and merge with root
                cutNode(node);
                self.root = mergeNodes(self.root, node);
                if (self.root) |r| r.parent = null;
            }
        }

        // Increase the value of a node and adjust the heap
        pub fn increaseKey(self: *Self, node: *Node, new_value: T) !void {
            if (compareFn(new_value, node.value) == Order.lt) {
                return error.NewValueLessThanCurrent;
            }
            node.value = new_value;
            // Percolate down the node to restore heap property
            self.percolateDown(node);
        }

        // Delete a specific node from the heap
        pub fn deleteNode(self: *Self, node: *Node) !void {
            try self.decreaseKey(node, node.value); // Ensure node is at the root
            self.deleteMin();
        }

        fn cutNode(node: *Node) void {
            // Remove node from its parent's child list
            const parent = node.parent.?;
            if (parent.child == node) {
                parent.child = node.sibling;
            } else {
                var sibling = parent.child;
                while (sibling) |sib| {
                    if (sib.sibling == node) {
                        sib.sibling = node.sibling;
                        break;
                    }
                    sibling = sib.sibling;
                }
            }
            if (node.sibling) |s| s.parent = node.parent;
            node.parent = null;
            node.sibling = null;
        }

        fn percolateDown(self: *Self, node: *Node) void {
            var current = node;
            while (current.child) |child| {
                // Find the child with the smallest value
                var minChild = child;
                var nextSibling = child.sibling;
                while (nextSibling) |sibling| {
                    if (compareFn(sibling.value, minChild.value) == Order.lt) {
                        minChild = sibling;
                    }
                    nextSibling = sibling.sibling;
                }
                if (compareFn(minChild.value, current.value) == Order.lt) {
                    // Swap current node with minChild
                    swapNodes(current, minChild);
                    current = minChild;
                } else {
                    break;
                }
            }
            // Update root if necessary
            if (current.parent == null) {
                self.root = current;
            }
        }

        fn swapNodes(node1: *Node, node2: *Node) void {
            // Swap the positions of node1 and node2 in the heap
            // Adjust parent, child, and sibling pointers
            // Note: This is more complex due to the tree structure

            // Swap parents
            const tempParent = node1.parent;
            node1.parent = node2.parent;
            node2.parent = tempParent;

            // Swap children
            const tempChild = node1.child;
            node1.child = node2.child;
            node2.child = tempChild;

            // Swap siblings
            const tempSibling = node1.sibling;
            node1.sibling = node2.sibling;
            node2.sibling = tempSibling;

            // Update parents' child pointers
            if (node1.parent) |parent| {
                if (parent.child == node2) {
                    parent.child = node1;
                } else {
                    var sibling = parent.child;
                    while (sibling) |sib| {
                        if (sib.sibling == node2) {
                            sib.sibling = node1;
                            break;
                        }
                        sibling = sib.sibling;
                    }
                }
            }
            if (node2.parent) |parent| {
                if (parent.child == node1) {
                    parent.child = node2;
                } else {
                    var sibling = parent.child;
                    while (sibling) |sib| {
                        if (sib.sibling == node1) {
                            sib.sibling = node2;
                            break;
                        }
                        sibling = sib.sibling;
                    }
                }
            }

            // Update children's parent pointers
            if (node1.child != null) {
                var c = node1.child;
                while (c) |childNode| {
                    childNode.parent = node1;
                    c = childNode.sibling;
                }
            }
            if (node2.child != null) {
                var c = node2.child;
                while (c) |childNode| {
                    childNode.parent = node2;
                    c = childNode.sibling;
                }
            }

            // Update siblings' sibling pointers
            if (node1.sibling) |sib| {
                sib.parent = node1.parent;
            }
            if (node2.sibling) |sib| {
                sib.parent = node2.parent;
            }
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

test "PairingHeap with decreaseKey, increaseKey, and deleteNode" {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    // Insert values and keep node references
    const node10 = try heap.insert(10);
    const node5 = try heap.insert(5);
    const node20 = try heap.insert(20);
    _ = try heap.insert(3);
    _ = try heap.insert(15);
    std.debug.print("Min value: {}\n", .{heap.findMin().?});

    heap.deleteMin();
    std.debug.print("Min value after deleteMin: {}\n", .{heap.findMin().?});

    // Decrease key of node20 from 20 to 2
    try heap.decreaseKey(node20, 2);
    std.debug.print("Min value after decreasing key of 20 to 2: {}\n", .{heap.findMin().?});

    // Increase key of node5 from 5 to 25
    try heap.increaseKey(node5, 25);
    std.debug.print("Min value after increasing key of 5 to 25: {}\n", .{heap.findMin().?});

    // Delete node10
    try heap.deleteNode(node10);
    std.debug.print("Min value after deleting node with value 10: {}\n", .{heap.findMin().?});

    // Merging example
    var heap1 = Heap.init(testing.allocator);
    defer heap1.deinit();

    _ = try heap1.insert(7);
    _ = try heap1.insert(1);

    heap.merge(&heap1);

    std.debug.print("Min value after merging: {}\n", .{heap.findMin().?});
}
