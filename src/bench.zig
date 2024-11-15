// bench.zig
//
// RebelDB™ © 2024 Huly Labs • https://rebeldb.com • SPDX-License-Identifier: MIT
//

const std = @import("std");
const zbench = @import("zbench");
const page = @import("page4.zig");

const Allocator = std.mem.Allocator;

const StaticCapacity = page.StaticCapacity;
const DynamicCapacity = page.DynamicCapacity;
const ByteAligned = page.ByteAligned;
const Page = page.Page;

const LARGE_SIZE = 1_000_000;

fn getStaticByte_16_u8_u8() usize {
    const data = [16]u8{ 2, 1, 2, 3, 4, 5, 6, 7, 0, 6, 5, 4, 3, 2, 1, 0 };
    const StaticBytes = StaticCapacity(16, ByteAligned(u8, u8));
    const StaticPage = Page(StaticBytes);
    const p: *const StaticPage = @alignCast(@ptrCast(&data));

    var i: usize = 0;
    for (0..LARGE_SIZE) |_| {
        if (p.get(@intCast(i % 7))[0] == 123) return 0;
        i += 3;
    }
    return i;
}

fn benchGetStaticByte_16_u8_u8(_: Allocator) void {
    std.mem.doNotOptimizeAway(getStaticByte_16_u8_u8());
}

fn getDynamicByte_16_u8_u8() usize {
    const data = [16]u8{ 2, 15, 1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2, 1, 0 };
    const DynamicBytes = DynamicCapacity(16, ByteAligned(u8, u8));
    const DynamicPage = Page(DynamicBytes);
    const p: *const DynamicPage = @alignCast(@ptrCast(&data));

    var i: usize = 0;
    for (0..LARGE_SIZE) |_| {
        if (p.get(@intCast(i % 7))[0] == 123) return 0;
        i += 3;
    }
    return i;
}

fn benchGetDynamicByte_16_u8_u8(_: Allocator) void {
    std.mem.doNotOptimizeAway(getDynamicByte_16_u8_u8());
}

// Now set up the benchmarks using zbench
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var suite = zbench.Benchmark.init(allocator, .{});
    defer suite.deinit();

    try suite.add("Get Static Byte 16 u8 u8", benchGetStaticByte_16_u8_u8, .{});
    try suite.add("Get Dynamic Byte 16 u8 u8", benchGetDynamicByte_16_u8_u8, .{});

    const stdout = std.io.getStdOut().writer();
    try suite.run(stdout);
}
