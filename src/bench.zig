//
// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT
//

const std = @import("std");
const zbench = @import("zbench");

const PairingHeap = @import("heap.zig").PairingHeap;
const Allocator = std.mem.Allocator;

fn cmp(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

// Benchmark configurations
const SMALL_SIZE = 100;
const MEDIUM_SIZE = 10_000;
const LARGE_SIZE = 100_000;

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create benchmark suite
    var suite = zbench.Benchmark.init(allocator, .{});
    defer suite.deinit();

    try suite.add("Insert Small", benchInsertSmall, .{});
    try suite.add("Insert Medium", benchInsertMedium, .{});
    try suite.add("Insert Large", benchInsertLarge, .{});
    try suite.add("DeleteMin Small", benchDeleteMinSmall, .{});
    try suite.add("DeleteMin Medium", benchDeleteMinMedium, .{});
    try suite.add("Merge Small", benchMergeSmall, .{});
    try suite.add("Mixed Operations", benchMixedOperations, .{});
    try suite.add("Sorted Insert", benchSortedInsert, .{});
    try suite.add("Reverse Sorted Insert", benchReverseSortedInsert, .{});
    try suite.add("Random Access Pattern", benchRandomAccess, .{});
    try suite.add("Random Access Zig PQ", benchRandomAccessPQ, .{});

    const stdout = std.io.getStdOut().writer();
    try suite.run(stdout);
}

// Benchmark functions
fn benchInsertSmall(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var i: i32 = 0;
    while (i < SMALL_SIZE) : (i += 1) {
        heap.insert(i) catch unreachable;
    }
}

fn benchInsertMedium(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var i: i32 = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        heap.insert(i) catch unreachable;
    }
}

fn benchInsertLarge(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var i: i32 = 0;
    while (i < LARGE_SIZE) : (i += 1) {
        heap.insert(i) catch unreachable;
    }
}

fn benchDeleteMinSmall(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    // Setup: Insert elements first
    var i: i32 = 0;
    while (i < SMALL_SIZE) : (i += 1) {
        heap.insert(i) catch unreachable;
    }

    i = 0;
    while (i < SMALL_SIZE) : (i += 1) {
        heap.deleteMin();
    }
}

fn benchDeleteMinMedium(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var i: i32 = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        heap.insert(i) catch unreachable;
    }

    i = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        heap.deleteMin();
    }
}

fn benchMergeSmall(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);

    var i: usize = 0;
    while (i < SMALL_SIZE) : (i += 1) {
        var heap1 = Heap.init(allocator);
        var heap2 = Heap.init(allocator);

        heap1.insert(@intCast(i)) catch unreachable;
        heap2.insert(@intCast(i + 1)) catch unreachable;

        heap1.merge(&heap2);
        heap1.deinit();
    }
}

fn benchMixedOperations(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    var i: usize = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        const op = random.intRangeAtMost(u8, 0, 2);
        switch (op) {
            0 => heap.insert(random.int(i32)) catch unreachable,
            1 => if (!heap.isEmpty()) heap.deleteMin(),
            2 => {
                var other = Heap.init(allocator);
                other.insert(random.int(i32)) catch unreachable;
                heap.merge(&other);
            },
            else => unreachable,
        }
    }
}

fn benchSortedInsert(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var i: i32 = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        heap.insert(i) catch unreachable;
    }
}

fn benchReverseSortedInsert(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var i: i32 = MEDIUM_SIZE;
    while (i > 0) : (i -= 1) {
        heap.insert(i) catch unreachable;
    }
}

fn benchRandomAccess(allocator: std.mem.Allocator) void {
    const Heap = PairingHeap(i32, cmp);
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    // First, insert random values
    var i: usize = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        heap.insert(random.int(i32)) catch unreachable;
    }

    i = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        if (random.boolean()) {
            heap.insert(random.int(i32)) catch unreachable;
        } else if (!heap.isEmpty()) {
            heap.deleteMin();
        }
    }
}

fn cmpPQ(_: void, a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

fn benchRandomAccessPQ(allocator: Allocator) void {
    var heap = std.PriorityQueue(i32, void, cmpPQ).init(allocator, {});
    defer heap.deinit();

    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    // First, insert random values
    var i: usize = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        heap.add(random.int(i32)) catch unreachable;
    }

    i = 0;
    while (i < MEDIUM_SIZE) : (i += 1) {
        if (random.boolean()) {
            heap.add(random.int(i32)) catch unreachable;
        } else _ = heap.removeOrNull();
    }
}
