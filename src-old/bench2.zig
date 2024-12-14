// bench.zig
//
// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT
//

const std = @import("std");
const zbench = @import("zbench");

const PairingHeap = @import("pairing_heap.zig").PairingHeap;
const PriorityQueue = std.PriorityQueue;
const Allocator = std.mem.Allocator;

// Benchmark configurations
const SMALL_SIZE = 100;
const MEDIUM_SIZE = 10_000;
const LARGE_SIZE = 1_000_000;

// Comparison function for the heaps
fn cmp(context: void, a: i32, b: i32) std.math.Order {
    _ = context;
    return std.math.order(a, b);
}

// Generic benchmark function for insertion
fn genBenchInsert(comptime HeapType: type, allocator: Allocator, size: usize) void {
    var heap = HeapType.init(allocator, {});
    defer heap.deinit();

    for (0..size) |i| {
        heap.add(@intCast(i)) catch unreachable;
    }
}

// Define heap types
const PH = PairingHeap(i32, void, cmp);
const PQ = std.PriorityQueue(i32, void, cmp);

fn benchInsertPHSmall(allocator: Allocator) void {
    genBenchInsert(PH, allocator, SMALL_SIZE);
}

fn benchInsertPQSmall(allocator: Allocator) void {
    genBenchInsert(PQ, allocator, SMALL_SIZE);
}

fn benchInsertPHMedium(allocator: Allocator) void {
    genBenchInsert(PH, allocator, MEDIUM_SIZE);
}

fn benchInsertPQMedium(allocator: Allocator) void {
    genBenchInsert(PQ, allocator, MEDIUM_SIZE);
}

fn benchInsertPHLarge(allocator: Allocator) void {
    genBenchInsert(PH, allocator, LARGE_SIZE);
}

fn benchInsertPQLarge(allocator: Allocator) void {
    genBenchInsert(PQ, allocator, LARGE_SIZE);
}

// Generic benchmark function for deleteMin
fn genBenchDeleteMin(comptime HeapType: type, allocator: Allocator, size: usize) void {
    var heap = HeapType.init(allocator, {});
    defer heap.deinit();

    for (0..size) |i|
        heap.add(@intCast(i)) catch unreachable;

    while (heap.removeOrNull() != null) {}
}

fn benchDeletePHSmall(allocator: Allocator) void {
    genBenchDeleteMin(PH, allocator, SMALL_SIZE);
}

fn benchDeletePQSmall(allocator: Allocator) void {
    genBenchDeleteMin(PQ, allocator, SMALL_SIZE);
}

fn benchDeletePHMedium(allocator: Allocator) void {
    genBenchDeleteMin(PH, allocator, MEDIUM_SIZE);
}

fn benchDeletePQMedium(allocator: Allocator) void {
    genBenchDeleteMin(PQ, allocator, MEDIUM_SIZE);
}

fn benchDeletePHLarge(allocator: Allocator) void {
    genBenchDeleteMin(PH, allocator, LARGE_SIZE);
}

fn benchDeletePQLarge(allocator: Allocator) void {
    genBenchDeleteMin(PQ, allocator, LARGE_SIZE);
}

// Generic benchmark function for mixed operations
fn genBenchMixedOperations(comptime HeapType: type, allocator: Allocator, size: usize) void {
    var heap = HeapType.init(allocator, {});
    defer heap.deinit();

    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    var i: usize = 0;
    while (i < size) : (i += 1) {
        const op = random.intRangeAtMost(u32, 0, 2);
        switch (op) {
            0 => heap.add(random.int(i32)) catch unreachable,
            1 => if (heap.removeOrNull()) |_| {},
            2 => {}, // No-op to match distribution
            else => unreachable,
        }
    }
}

fn benchMixedOperationsPHSmall(allocator: Allocator) void {
    genBenchMixedOperations(PH, allocator, SMALL_SIZE);
}

fn benchMixedOperationsPQSmall(allocator: Allocator) void {
    genBenchMixedOperations(PQ, allocator, SMALL_SIZE);
}

fn benchMixedOperationsPHMedium(allocator: Allocator) void {
    genBenchMixedOperations(PH, allocator, MEDIUM_SIZE);
}

fn benchMixedOperationsPQMedium(allocator: Allocator) void {
    genBenchMixedOperations(PQ, allocator, MEDIUM_SIZE);
}

fn benchMixedOperationsPHLarge(allocator: Allocator) void {
    genBenchMixedOperations(PH, allocator, LARGE_SIZE);
}

fn benchMixedOperationsPQLarge(allocator: Allocator) void {
    genBenchMixedOperations(PQ, allocator, LARGE_SIZE);
}

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create benchmark suite
    var suite = zbench.Benchmark.init(allocator, .{});
    defer suite.deinit();

    try suite.add("Insert Small (PH)", benchInsertPHSmall, .{});
    try suite.add("Insert Small (PQ)", benchInsertPQSmall, .{});
    try suite.add("Insert Medium (PH)", benchInsertPHMedium, .{});
    try suite.add("Insert Medium (PQ)", benchInsertPQMedium, .{});
    try suite.add("Insert Large (PH)", benchInsertPHLarge, .{});
    try suite.add("Insert Large (PQ)", benchInsertPQLarge, .{});

    try suite.add("Delete Small (PH)", benchDeletePHSmall, .{});
    try suite.add("Delete Small (PQ)", benchDeletePQSmall, .{});
    try suite.add("Delete Medium (PH)", benchDeletePHMedium, .{});
    try suite.add("Delete Medium (PQ)", benchDeletePQMedium, .{});
    try suite.add("Delete Large (PH)", benchDeletePHLarge, .{});
    try suite.add("Delete Large (PQ)", benchDeletePQLarge, .{});

    try suite.add("Mixed Small (PH)", benchMixedOperationsPHSmall, .{});
    try suite.add("Mixed Small (PQ)", benchMixedOperationsPQSmall, .{});
    try suite.add("Mixed Medium (PH)", benchMixedOperationsPHMedium, .{});
    try suite.add("Mixed Medium (PQ)", benchMixedOperationsPQMedium, .{});
    try suite.add("Mixed Large (PH)", benchMixedOperationsPHLarge, .{});
    try suite.add("Mixed Large (PQ)", benchMixedOperationsPQLarge, .{});

    const stdout = std.io.getStdOut().writer();
    try suite.run(stdout);
}
