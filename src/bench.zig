// RebelDB™ © 2024 Huly Labs • https://rebeldb.com • SPDX-License-Identifier: MIT

const std = @import("std");
const zbench = @import("zbench");
const page = @import("page.zig");
const mem = @import("mem.zig");
const heap = @import("heap.zig");

const Allocator = std.mem.Allocator;

const Static = page.Static;
const Dynamic = page.Dynamic;
const ByteAligned = page.ByteAligned;
const NibbleAligned = page.NibbleAligned;
const Readonly = page.Readonly;
const Mutable = page.Mutable;
const Page = page.Page;

const MemoryFile = mem.MemoryFile;
const Heap = heap.Heap;

const LARGE_SIZE = 1_000_000;

fn benchGetStaticByte_16_u8_u8(_: Allocator) void {
    const data = [16]u8{ 2, 1, 2, 3, 4, 5, 6, 7, 0, 6, 5, 4, 3, 2, 1, 0 };
    const StaticPage = Page(u8, Static(16), ByteAligned(u8), Readonly(u8));
    const p: *const StaticPage = @alignCast(@ptrCast(&data));

    var sum: usize = 0;
    for (0..LARGE_SIZE) |i|
        sum += p.get(@intCast(i % 3))[0];

    std.mem.doNotOptimizeAway(sum);
}

fn benchGetDynamicByte_16_u8_u8(_: Allocator) void {
    const data = [16]u8{ 2, 15, 1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2, 1, 0 };
    const DynamicPage = Page(u8, Dynamic(u8), ByteAligned(u8), Readonly(u8));
    const p: *const DynamicPage = @alignCast(@ptrCast(&data));

    var sum: usize = 0;
    for (0..LARGE_SIZE) |i|
        sum += p.get(@intCast(i % 3))[0];

    std.mem.doNotOptimizeAway(sum);
}

// Existing heap allocation benchmarks
fn benchHeapAllocation64K(allocator: Allocator) void {
    const Mem64K = MemoryFile(0x10000);
    var mem_file = Mem64K.init(allocator);
    defer mem_file.deinit();
    var hp = Heap(Mem64K, u16, u16).init(allocator, &mem_file);
    defer hp.deinit();

    var data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (0..LARGE_SIZE) |_| _ = hp.push(&data) catch unreachable;
}

fn benchHeapAllocation4096(allocator: Allocator) void {
    const Mem = MemoryFile(4096);
    var mem_file = Mem.init(allocator);
    defer mem_file.deinit();
    var hp = Heap(Mem, u16, u16).init(allocator, &mem_file);
    defer hp.deinit();

    var data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (0..LARGE_SIZE) |_| _ = hp.push(&data) catch unreachable;
}

fn benchGetStaticNibble_16_u4_u4(_: Allocator) void {
    var data = [16]u8{
        0, // Page struct minimal (len=0?), simplified
        'X',
        'Y',
        'Z',
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        // Nibble indexes:
        0x23,
        0x01,
    };

    const StaticPage = Page(u8, Static(16), NibbleAligned(u4), Readonly(u4));
    const p: *const StaticPage = @alignCast(@ptrCast(&data));

    var sum: usize = 0;
    for (0..LARGE_SIZE) |i|
        sum += p.get(@intCast(i % 3))[0];

    std.mem.doNotOptimizeAway(sum);
}

fn benchGetDynamicNibble_16_u4_u8(_: Allocator) void {
    var data = [16]u8{
        3, 15, // len=3, dynamic last_byte=15 => capacity=16
        'A', 'B', 'C', // values at offset0='A', offset1='B'
        0, 0, 0, 0, 0, 0, 0, 0, 0, // pad
        0x23, 0x01, // nibble indexes: value1 offset=1 nib high, value0 offset=0 nib low
    };

    const DynamicPage = Page(u8, Dynamic(u4), NibbleAligned(u4), Readonly(u4));
    const p: *const DynamicPage = @alignCast(@ptrCast(&data));

    var sum: usize = 0;
    for (0..LARGE_SIZE) |i|
        sum += p.get(@intCast(i % 3))[0];

    std.mem.doNotOptimizeAway(sum);
}

// ------------------------------------------------------------
// Mutable Benchmarks: Appending Values
// Here we benchmark writing/appending values to pages.
// We'll do two scenarios:
// 1) ByteAligned + Static large page
// 2) NibbleAligned + Static large page
//
// Both will simulate appending many small values and measure the overhead.

fn benchAppendValuesByteAligned(_: Allocator) void {
    const PageSize = 4096;
    var data = [_]u8{0} ** PageSize;
    const PageType = Page(u16, Static(PageSize), ByteAligned(u16), Mutable(u16));
    var p: *PageType = @alignCast(@ptrCast(&data));
    _ = p.init(PageSize); // Initialize page

    var sum: usize = 0;
    for (0..LARGE_SIZE) |i| {
        if (p.available() < 10) _ = p.init(PageSize);
        const val = p.alloc(10);
        val[0] = @intCast(i & 0xFF);
        sum += val[0];
    }
    std.mem.doNotOptimizeAway(sum);
}

fn benchAppendValuesNibbleAligned(_: Allocator) void {
    const PageSize = 4096;
    var data = [_]u8{0} ** PageSize;
    const PageType = Page(u12, Static(PageSize), NibbleAligned(u12), Mutable(u12));
    var p: *PageType = @alignCast(@ptrCast(&data));
    _ = p.init(PageSize); // Initialize page

    var sum: usize = 0;
    for (0..LARGE_SIZE) |i| {
        if (p.available() < 10) _ = p.init(PageSize);
        const val = p.alloc(10);
        val[0] = @intCast(i & 0xFF);
        sum += val[0];
    }
    std.mem.doNotOptimizeAway(sum);
}

// ------------------------------------------------------------
// Main function sets up and runs all benchmarks
// ------------------------------------------------------------
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var suite = zbench.Benchmark.init(allocator, .{});
    defer suite.deinit();

    // Existing Byte-Aligned Get Benchmarks
    try suite.add("Get Static Byte 16 u8 u8", benchGetStaticByte_16_u8_u8, .{});
    try suite.add("Get Dynamic Byte 16 u8 u8", benchGetDynamicByte_16_u8_u8, .{});

    // Existing Heap Allocation Benchmarks
    try suite.add("Heap Allocation 64K", benchHeapAllocation64K, .{});
    try suite.add("Heap Allocation 4096", benchHeapAllocation4096, .{});

    // New Nibble-Aligned Get Benchmarks
    try suite.add("Get Static Nibble 16 u4 u4", benchGetStaticNibble_16_u4_u4, .{});
    try suite.add("Get Dynamic Nibble 16 u4 u8", benchGetDynamicNibble_16_u4_u8, .{});

    // New Mutable Append Benchmarks
    try suite.add("apnd stat byte u16 4K", benchAppendValuesByteAligned, .{});
    try suite.add("apnd stat nibble u12 4K", benchAppendValuesNibbleAligned, .{});

    const stdout = std.io.getStdOut().writer();
    try suite.run(stdout);
}
