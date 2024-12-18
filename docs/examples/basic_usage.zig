//! Basic usage examples for RebelDB™
//! This file demonstrates fundamental operations like initializing pages,
//! storing values, and retrieving data.

const std = @import("std");
const Page = @import("page.zig").Page;
const ByteAligned = @import("page.zig").ByteAligned;
const Static = @import("page.zig").Static;
const Mutable = @import("page.zig").Mutable;

pub fn main() !void {
    // Create a simple page with 128 bytes capacity
    var data: [128]u8 = undefined;
    const BasicPage = Page(u8, Static(128), ByteAligned(u8), Mutable(u8));
    var page: *BasicPage = @ptrCast(&data);

    // Initialize the page
    _ = page.init(128);

    // Store some values
    const val1 = page.alloc(16);  // Allocate 16 bytes
    @memcpy(val1, "Hello, RebelDB!");

    const val2 = page.alloc(8);   // Allocate 8 bytes
    @memcpy(val2, "World!");

    // Retrieve stored values
    const stored1 = page.get(0);  // Get first value
    const stored2 = page.get(1);  // Get second value

    // Check available space
    const remaining = page.available();
    _ = remaining;

    // Print values (in real code)
    std.debug.print("Value 1: {s}\n", .{stored1[0..16]});
    std.debug.print("Value 2: {s}\n", .{stored2[0..6]});
}
