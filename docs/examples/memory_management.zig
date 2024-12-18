//! Memory management examples for RebelDB™
//! This file demonstrates efficient memory usage patterns and techniques.

const std = @import("std");
const rebeldb = @import("rebeldb");
const Page = rebeldb.Page;
const ByteAligned = rebeldb.ByteAligned;
const Static = rebeldb.Static;
const Mutable = rebeldb.Mutable;

// Define a page optimized for memory efficiency
const MemoryEfficientPage = Page(
    u16,                  // Support up to 65535 values
    Static(65536),       // 64KB fixed size
    ByteAligned(u16),    // Byte-aligned for better performance
    Mutable(u16)         // Mutable for updates
);

pub fn main() !void {
    // Allocate page memory
    var data: [65536]u8 = undefined;
    var page: *MemoryEfficientPage = @ptrCast(@alignCast(&data));

    // Initialize with full capacity
    const initial_space = page.init(65536);

    // Demonstrate efficient space usage

    // 1. Pre-calculate space requirements
    const value_size = 32;
    const max_values = initial_space / (value_size + @sizeOf(u16));

    // 2. Batch allocations for better efficiency
    var values = std.ArrayList([]u8).init(std.heap.page_allocator);
    defer values.deinit();

    var i: usize = 0;
    while (i < max_values) : (i += 1) {
        if (page.available() < value_size) break;
        const val = page.alloc(value_size);
        try values.append(val);
    }

    // 3. Demonstrate memory reclamation
    const remaining_space = page.available();
    _ = remaining_space;
}
