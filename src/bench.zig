// bench.zig
//
// RebelDB™ © 2024 Huly Labs • https://rebeldb.com • SPDX-License-Identifier: MIT
//

const std = @import("std");
const zbench = @import("zbench");
const PageModule = @import("page2.zig");

// Benchmark configurations
const SMALL_SIZE = 100;
const MEDIUM_SIZE = 10_000;
const LARGE_SIZE = 1_000_000;

const PageSize = 4096 * 1;
const Cap = PageModule.ByteAligned(PageSize);
const LayoutType = PageModule.Fixed(Cap);
const WriteType = PageModule.Mutable(Cap.Offset);
const DeleteType = PageModule.WithoutDelete(Cap.Offset);

const PageType = PageModule.Page(LayoutType, WriteType, DeleteType);

fn benchAddEntries(allocator: std.mem.Allocator, iterations: usize) !void {
    const entry = [_]u8{ 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 7, 8 }; // Example entry data
    const entry_size = entry.len;

    var page_data = try allocator.alloc(u8, PageSize);
    defer allocator.free(page_data);

    var page: *PageType = @alignCast(@ptrCast(&page_data[0]));

    for (0..iterations) |_| {
        _ = page.init(PageSize);
        while (page.available(entry_size)) {
            try page.add(@ptrCast(&entry), entry_size);
        }
    }
}

fn benchAddEntriesMedium(allocator: std.mem.Allocator) void {
    benchAddEntries(allocator, LARGE_SIZE) catch unreachable;
}

// // Benchmark function for reading entries from the Page
// fn benchReadEntries(allocator: std.mem.Allocator) !void {
//     const size = MEDIUM_SIZE;
//     const entry = [_]u8{ 0x1, 0x2 }; // Example entry data
//     const entry_size = entry.len;

//     var page = try initPage(allocator, size * entry_size * 2);
//     defer allocator.free(@ptrCast(@as([*]u8, page)));

//     // Add entries to the page
//     var i: Cap16.Index = 0;
//     while (i < size) : (i += 1) {
//         try page.add(@ptrCast(&entry), entry_size);
//     }

//     // Read entries from the page
//     i = 0;
//     while (i < size) : (i += 1) {
//         const read_entry = page.get(i);
//         // Do something with read_entry if needed
//         _ = read_entry;
//     }
// }

// // Benchmark function for deleting entries from the Page
// fn benchDeleteEntries(allocator: std.mem.Allocator) !void {
//     const size = MEDIUM_SIZE;
//     const entry = [_]u8{ 0x1, 0x2 }; // Example entry data
//     const entry_size = entry.len;

//     var page = try initPage(allocator, size * entry_size * 2);
//     defer allocator.free(@ptrCast(@as([*]u8, page)));

//     // Add entries to the page
//     var i: Cap16.Index = 0;
//     while (i < size) : (i += 1) {
//         try page.add(@ptrCast(&entry), entry_size);
//     }

//     // Delete entries from the page
//     i = 0;
//     while (i < size) : (i += 1) {
//         page.delete(i);
//     }
// }

// // Benchmark function for compacting the Page
// fn benchCompactPage(allocator: std.mem.Allocator) !void {
//     const size = MEDIUM_SIZE;
//     const entry = [_]u8{ 0x1, 0x2 }; // Example entry data
//     const entry_size = entry.len;

//     var page = try initPage(allocator, size * entry_size * 2);
//     defer allocator.free(@ptrCast(@as([*]u8, page)));

//     // Add entries to the page
//     var i: Cap16.Index = 0;
//     while (i < size) : (i += 1) {
//         try page.add(@ptrCast(&entry), entry_size);
//     }

//     // Delete half of the entries
//     i = 0;
//     while (i < size / 2) : (i += 1) {
//         page.delete(i);
//     }

//     // Compact the page
//     page.compact();
// }

// Now set up the benchmarks using zbench
pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create benchmark suite
    var suite = zbench.Benchmark.init(allocator, .{});
    defer suite.deinit();

    // Add benchmarks for adding entries
    // try suite.add("Add Entries Small", benchAddEntries, &small_size);
    try suite.add("Add Entries Medium", benchAddEntriesMedium, .{});
    // try suite.add("Add Entries Large", benchAddEntries, &large_size);

    // Add benchmarks for reading entries
    // try suite.add("Read Entries Small", benchReadEntries, &small_size);
    // try suite.add("Read Entries Medium", benchReadEntries, .{});
    // try suite.add("Read Entries Large", benchReadEntries, &large_size);

    // Add benchmarks for deleting entries
    // try suite.add("Delete Entries Small", benchDeleteEntries, &small_size);
    // try suite.add("Delete Entries Medium", benchDeleteEntries, .{});
    // try suite.add("Delete Entries Large", benchDeleteEntries, &large_size);

    // Add benchmarks for compacting the page
    // try suite.add("Compact Page Small", benchCompactPage, &small_size);
    // try suite.add("Compact Page Medium", benchCompactPage, .{});
    // try suite.add("Compact Page Large", benchCompactPage, &large_size);

    const stdout = std.io.getStdOut().writer();
    try suite.run(stdout);
}
