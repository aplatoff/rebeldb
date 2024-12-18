//! Page configuration examples for RebelDB™
//! This file demonstrates different page configurations and their use cases.

const std = @import("std");
const rebeldb = @import("rebeldb");
const Page = rebeldb.Page;
const ByteAligned = rebeldb.ByteAligned;
const NibbleAligned = rebeldb.NibbleAligned;
const Static = rebeldb.Static;
const Dynamic = rebeldb.Dynamic;
const Mutable = rebeldb.Mutable;
const Readonly = rebeldb.Readonly;

// 1. Static page with byte-aligned indices
const StaticBytePage = Page(
    u8,                    // Index type
    Static(4096),         // Fixed 4KB capacity
    ByteAligned(u16),     // Byte-aligned u16 offsets
    Mutable(u16)          // Mutable access
);

// 2. Dynamic page with nibble-aligned indices
const DynamicNibblePage = Page(
    u16,                  // Index type (more values)
    Dynamic(u12),         // Runtime-sized
    NibbleAligned(u12),   // Nibble-aligned u12 offsets
    Mutable(u12)          // Mutable access
);

// 3. Readonly page for shared access
const ReadonlyPage = Page(
    u8,                   // Index type
    Static(1024),        // Fixed 1KB capacity
    ByteAligned(u8),     // Byte-aligned u8 offsets
    Readonly(u8)         // Readonly access
);

pub fn main() !void {
    // Example 1: Static byte-aligned page
    var static_data: [4096]u8 = undefined;
    var static_page: *StaticBytePage = @ptrCast(@alignCast(&static_data));
    _ = static_page.init(4096);

    // Example 2: Dynamic nibble-aligned page
    var dynamic_data: [8192]u8 = undefined;
    var dynamic_page: *DynamicNibblePage = @ptrCast(@alignCast(&dynamic_data));
    _ = dynamic_page.init(8192);

    // Example 3: Readonly page
    var readonly_data: [1024]u8 = undefined;
    var readonly_page: *ReadonlyPage = @ptrCast(@alignCast(&readonly_data));
    _ = readonly_page.init(1024);
}
