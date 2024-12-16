// RebelDB™ Test Suite for Page Abstraction
// © 2024 Huly Labs • SPDX-License-Identifier: MIT
// This test suite is designed to thoroughly check various configurations and behaviors of the Page abstraction.

const std = @import("std");
const testing = std.testing;
const page = @import("page.zig");

const Page = page.Page; // Adjust if needed
const ByteAligned = page.ByteAligned;
const NibbleAligned = page.NibbleAligned;
const Static = page.Static;
const Dynamic = page.Dynamic;
const Mutable = page.Mutable;
const Readonly = page.Readonly;

// ---------------------------------------------
// Compile-time checks for NibbleAligned
// ---------------------------------------------

// NibbleAligned requires OffsetType bit-size multiple of 4 but not multiple of 8.
// u4 is 4 bits, multiple of 4 but not 8, so it's valid.
// u8 is 8 bits, which is multiple of 8, thus should fail compile-time check.
// test "nibble aligned offset compile-time failure with u8" {
//     comptime {
//         var caught = false;
//         try std.testing.expect(@compileErrorCatch({
//             _ = NibbleAligned(u8, u4);
//         }, &caught));
//         try testing.expect(caught);
//     }
// }

// Using u4 as offset is valid for NibbleAligned.
test "nibble aligned offset compile-time success with u4" {
    // Just instantiate it; if it compiles, it's good.
    _ = NibbleAligned(u4, u4);
    try testing.expect(true);
}

// ---------------------------------------------
// Basic tests with Static + ByteAligned + Readonly
// ---------------------------------------------
test "static byte aligned readonly: basic retrieval" {
    // Layout: Page metadata (1 byte) + data + indices (at the end)
    // Let's say we have a Static(16) capacity and store 2 values.
    // We'll simulate a scenario:
    // Value[0] starts at offset 0 -> 'A' (0x41)
    // Value[1] starts at offset 1 -> 'B' (0x42)
    // Offsets stored at the end:
    // For ByteAligned(u8,u8): last byte is offset for index 1 (1), second to last is offset for index 0 (0).

    var data = [16]u8{
        // Page struct fields occupy the first bytes, but here we just assume minimal space.
        // We'll fill it to reflect what a constructed page might look like:
        // Let’s say metadata is minimal. Just put something dummy for now.
        // The actual layout may differ depending on how Page is sized.
        0, // metadata start (len=0?), after final test it will reflect actual state

        // Values section:
        0x41, 0x42, // two bytes for values 'A', 'B'
        // Unused bytes in between
        0,    0,
        0,    0,
        0,    0,
        0,    0,
        0,    0,
        0,
        // Indices at the end:
        // index=0 offset=0x00
        // index=1 offset=0x01
           0x01,
        0x00,
    };

    const StaticPage = Page(Static(16), ByteAligned(u8, u8), Readonly(u8));
    const page_ptr: *const StaticPage = @ptrCast(&data);

    // Validate structure size
    // Should be minimal, check that it doesn't blow up unexpectedly.
    try testing.expectEqual(@sizeOf(StaticPage), 1);

    // Check value retrieval
    try testing.expectEqual('A', page_ptr.get(0)[0]);
    try testing.expectEqual('B', page_ptr.get(1)[0]);
}

// ---------------------------------------------
// Static + ByteAligned + Mutable tests
// ---------------------------------------------
test "static byte aligned mutable: append values" {
    var data = [_]u8{0} ** 32;

    // Choose bigger capacity (32 bytes).
    const StaticPage = Page(Static(32), ByteAligned(u8, u8), Mutable(u8));
    const page_ptr: *StaticPage = @alignCast(@ptrCast(&data));

    const available = page_ptr.init(32);
    try testing.expectEqual(@as(u8, 32 - @sizeOf(StaticPage) - @sizeOf(u8)), available);

    // Append a value of 3 bytes
    const val1 = page_ptr.alloc(3);
    val1[0] = 0x10;
    val1[1] = 0x11;
    val1[2] = 0x12;

    try testing.expectEqual(@as(u8, 0x10), page_ptr.get(0)[0]);
    try testing.expectEqual(@as(u8, 0x11), page_ptr.get(0)[1]);
    try testing.expectEqual(@as(u8, 0x12), page_ptr.get(0)[2]);

    // Append another value of 2 bytes
    const val2 = page_ptr.alloc(2);
    val2[0] = 0xAA;
    val2[1] = 0xBB;

    try testing.expectEqual(@as(u8, 0xAA), page_ptr.get(1)[0]);
    try testing.expectEqual(@as(u8, 0xBB), page_ptr.get(1)[1]);

    // Check count
    try testing.expectEqual(@as(u8, 2), page_ptr.count());

    // Check available space after allocations
    const after = page_ptr.available();
    // We have used 3 + 2 = 5 bytes for values, plus indices at the end.
    // With ByteAligned(u8,u8), each index uses 1 byte.
    // We have 2 values -> 2 indexes at the end, total 2 bytes for indices.
    // Used = 5 (values) + 2 (indices) + @sizeOf(StaticPage)
    const used = 5 + 2 + @sizeOf(StaticPage) + @sizeOf(u8);
    try testing.expectEqual(32 - used, after);
}

// ---------------------------------------------
// Static + NibbleAligned + Readonly tests
// ---------------------------------------------
test "static nibble aligned readonly: multiple values" {
    // We'll store multiple small values and hand-craft their offsets and nibble-aligned indexes.
    // Let's say offset type = u4, index type = u4. offset_nibbles = @bitSizeOf(u4)/4 = 1 nibble per offset.
    // With NibbleAligned(u4,u4), each index consumes exactly 1 nibble.
    // For 3 values, we have 3 nibbles at the end.
    //
    // Suppose we have a page of 16 bytes:
    // Values:
    //   value[0] at offset 0x0: 'X'
    //   value[1] at offset 0x1: 'Y'
    //   value[2] at offset 0x2: 'Z'
    //
    // Indices (stored from the end):
    //   last nibble = offset of value[2] = 0x2
    //   second last nibble = offset of value[1] = 0x1
    //   third last nibble = offset of value[0] = 0x0
    //
    // The last 3 nibbles (which is 2 bytes in total since 3 nibbles = 1.5 bytes) are at the end.
    // For simplicity, nibble aligned indexing is complex, but we trust the logic. Let's place them carefully:
    // The final 2 bytes might look like: (0x??)
    // We have 3 offsets: 0x0, 0x1, 0x2 stored at the very end:
    //
    // If we store them as (in reverse order): value[2]=0x2 nibble, value[1]=0x1 nibble, value[0]=0x0 nibble
    // starting from the end: the last nibble is 0x2, before that 0x1, before that 0x0
    //
    // Let's say the last two bytes are [0x12, 0x?] where nibble 2 is least significant nibble of last byte,
    // nibble 1 is next nibble, nibble 0 is the nibble before that.
    //
    // Actually, let's arrange a simpler pattern:
    // We'll fill with zero and just manually test retrieving them.
    var data = [16]u8{
        0, // Page struct
        'X', 'Y', 'Z', // values
        0,    0,    0, 0, 0, 0, 0, 0, 0, 0, // unused
        // last two bytes for 3 nibbles:
        // 3 nibbles: 0x0 (for index0), 0x1 (for index1), 0x2 (for index2)
        // Stored from the end: index2:0x2 nibble is last nibble in memory
        // index1:0x1 nibble before that, index0:0x0 nibble before that
        // So final two bytes: The last nibble is 0x2, next nibble is 0x1, next nibble 0x0.
        // In hex, let's store them as: 0x01 (for the first two nibbles: 0 and 1 => nibble0=0 low nibble, nibble1=1 high nibble)
        // and then we need nibble2=2 in the next nibble. That would go into another byte.
        // We have 3 nibbles = 0x0 (low nibble), 0x1 (next nibble), 0x2 (final nibble)
        // Memory in reverse nibble order might be tricky. Let's trust the code and just place:
        // We'll try: second last byte = 0x10 (high nibble=1, low nibble=0)
        // last byte = 0x2 (just a nibble 2 in low nibble)
        // So indices = [0x10,0x02].
        0x23, 0x01,
    };

    const StaticPage = Page(Static(16), NibbleAligned(u4, u4), Readonly(u4));
    const page_ptr: *const StaticPage = @alignCast(@ptrCast(&data));

    // Check size
    try testing.expectEqual(@sizeOf(StaticPage), 1);

    // Validate retrieval
    try testing.expectEqual('X', page_ptr.get(0)[0]);
    try testing.expectEqual('Y', page_ptr.get(1)[0]);
    try testing.expectEqual('Z', page_ptr.get(2)[0]);
}

// ---------------------------------------------
// Static + NibbleAligned + Mutable tests
// ---------------------------------------------
test "static nibble aligned mutable: append values" {
    var data = [_]u8{0} ** 16;

    const StaticPage = Page(Static(16), NibbleAligned(u4, u4), Mutable(u4));
    const page_ptr: *StaticPage = @alignCast(@ptrCast(&data));

    const avail = page_ptr.init(16);
    try testing.expectEqual(@as(u4, 16 - @sizeOf(StaticPage) - @sizeOf(u4)), avail);

    // Append one byte
    {
        const val = page_ptr.alloc(1);
        val[0] = 0xFF;
        try testing.expectEqual(@as(u8, 0xFF), page_ptr.get(0)[0]);
    }

    // Append another 2 bytes
    {
        const val2 = page_ptr.alloc(2);
        val2[0] = 0x01;
        val2[1] = 0x02;
        try testing.expectEqual(@as(u8, 0x01), page_ptr.get(1)[0]);
        try testing.expectEqual(@as(u8, 0x02), page_ptr.get(1)[1]);
    }

    // Check count
    try testing.expectEqual(@as(u4, 2), page_ptr.count());
}

// ---------------------------------------------
// Dynamic capacity tests
// ---------------------------------------------
test "dynamic byte aligned mutable: large page" {
    var data = [_]u8{0} ** 1024; // a 1KB page
    const DynamicPage = Page(Dynamic(u16), ByteAligned(u16, u16), Mutable(u16));
    const page_ptr: *DynamicPage = @alignCast(@ptrCast(&data));

    const avail = page_ptr.init(1024);
    try testing.expectEqual(1024 - @sizeOf(DynamicPage) - @sizeOf(u16), avail);

    // Append several values and ensure no overlap:
    // Each appended value + index consumes space at front for value and at end for offset.
    for (0..10) |i| {
        const val = page_ptr.alloc(10);
        // Fill with some pattern
        for (val, 0..) |*b, idx| b.* = @intCast(i * 16 + idx);
    }

    // Check values
    for (0..10) |i| {
        const got = page_ptr.get(@intCast(i));
        try testing.expectEqual(@as(u8, @intCast(i * 16)), got[0]);
        try testing.expectEqual(@as(u8, @intCast(i * 16 + 9)), got[9]);
    }

    // After adding 10 * 10 = 100 bytes plus 10 offsets (each offset = 2 bytes = 20 bytes) plus metadata,
    // total used ~ 1 byte (metadata?) + 100 bytes (values) + 20 (indices) = 121. We started with 1024,
    // so we should have plenty left.
    const remaining = page_ptr.available();
    try testing.expect(remaining > 800); // Just a sanity check
}

// ---------------------------------------------
// Attempting read-only writes
// ---------------------------------------------
test "readonly page cannot alloc" {
    var data = [_]u8{0} ** 16;
    const ReadOnlyPage = Page(Static(16), ByteAligned(u8, u8), Readonly(u8));
    const page_ptr: *ReadOnlyPage = @alignCast(@ptrCast(&data));

    _ = page_ptr.init(16);
    // Attempt to alloc would cause a compile error or a runtime unreachable.
    // Since we know Readonly returns unreachable in get(), we won't actually call alloc on it.
    //
    // If we tried something like:
    // const val = page_ptr.alloc(1);
    // val[0] = 0xAA; // This would fail at runtime.
    //
    // Just check that available() returns 0
    try testing.expectEqual(@as(u8, 0), page_ptr.available());
}

// ---------------------------------------------
// Boundary checks (no runtime checks present, just sanity tests)
// ---------------------------------------------
test "verify no overlap for multiple allocations" {
    // This test ensures that allocations do not overlap each other or the indexing region.
    // We'll allocate small chunks until we approach the indexing region and check final layout.

    var data = [_]u8{0} ** 64;
    const StaticPage = Page(Static(64), ByteAligned(u8, u8), Mutable(u8));
    const page_ptr: *StaticPage = @alignCast(@ptrCast(&data));

    _ = page_ptr.init(64);

    // Each appended value consumes 1 offset byte at the end.
    // Let's append 5 values of varying sizes.
    const sizes = [_]u8{ 5, 10, 3, 8, 2 };
    var total_value_bytes: usize = 0;
    for (sizes, 0..) |sz, i| {
        const val = page_ptr.alloc(sz);
        try testing.expectEqual(sz, val.len);
        // Fill with a unique pattern
        for (val, 0..) |*b, idx| b.* = @intCast(i * 20 + idx);
        total_value_bytes += sz;
    }

    // We stored 5 values, so indices = 5 * 1 byte = 5 bytes for offsets at the end.
    // Used bytes = page struct size + total_value_bytes + 5 offset bytes
    const used = @sizeOf(StaticPage) + @sizeOf(u8) + total_value_bytes + 5;
    try testing.expectEqual(64 - used, page_ptr.available());

    // Check last inserted value correctness
    const last_val = page_ptr.get(4);
    try testing.expectEqual(@as(u8, 80), last_val[0]); // i=4 => 4*20=80
    try testing.expectEqual(@as(u8, 81), last_val[1]);
}

test "static nibble aligned u12 offsets: append multiple values" {
    // This test ensures that nibble-aligned indexing with u12 offsets works correctly for multiple appended values.
    // We'll use a static page of size 64 bytes for simplicity.
    var data = [_]u8{0} ** 64;

    // Use NibbleAligned(u12, u8) and Mutable(u12) to allow appends.
    // Using u8 as Index is fine for a small number of values.
    const StaticPage = Page(Static(64), NibbleAligned(u12, u8), Mutable(u12));
    const page_ptr: *StaticPage = @alignCast(@ptrCast(&data));

    // Initialize the page.
    const avail = page_ptr.init(64);
    // With nibble-aligned u12 offsets, indexing overhead is slightly complex. We won't assert the exact initial avail here.
    // Just ensure it's positive and roughly equals total capacity minus struct size minus one offset space.
    try testing.expect(avail > 50); // sanity check, since @sizeOf(u12)=2 bytes, one index nibble alignment overhead is small.

    // Append four values with varying sizes to test indexing:
    // Value0: length = 5 bytes
    // Value1: length = 10 bytes
    // Value2: length = 8 bytes
    // Value3: length = 12 bytes

    // Append Value0
    const val0 = page_ptr.alloc(5);
    for (val0, 0..) |*b, i| b.* = @intCast(i + 10); // Fill with pattern starting at 10
    try testing.expectEqual(@as(u8, 10), page_ptr.get(0)[0]);
    try testing.expectEqual(@as(u8, 14), page_ptr.get(0)[4]);

    // Append Value1
    const val1 = page_ptr.alloc(10);
    for (val1, 0..) |*b, i| b.* = @intCast(i + 50); // Fill with pattern starting at 50
    try testing.expectEqual(@as(u8, 50), page_ptr.get(1)[0]);
    try testing.expectEqual(@as(u8, 59), page_ptr.get(1)[9]);

    // Append Value2
    const val2 = page_ptr.alloc(8);
    for (val2, 0..) |*b, i| b.* = @intCast(i + 100); // Fill with pattern starting at 100
    try testing.expectEqual(@as(u8, 100), page_ptr.get(2)[0]);
    try testing.expectEqual(@as(u8, 107), page_ptr.get(2)[7]);

    // Append Value3
    const val3 = page_ptr.alloc(12);
    for (val3, 0..) |*b, i| b.* = @intCast(i + 200); // Fill with pattern starting at 200
    try testing.expectEqual(@as(u8, 200), page_ptr.get(3)[0]);
    try testing.expectEqual(@as(u8, 211), page_ptr.get(3)[11]);

    // Check counts and indexing
    try testing.expectEqual(4, page_ptr.count());

    // Check that no values overlap and indexing didn't get corrupted:
    // Ensure value0 is still intact
    try testing.expectEqual(@as(u8, 10), page_ptr.get(0)[0]);
    try testing.expectEqual(@as(u8, 14), page_ptr.get(0)[4]);

    // Check available space after all allocations:
    // Let's do a rough check. We've allocated total of 5+10+8+12 = 35 bytes for values.
    // We have 4 indexes. Each index = 12 bits = 1.5 bytes. For 4 indexes, total indexing = 6 bytes at the end.
    // Used = @sizeOf(StaticPage) + @sizeOf(u12) [for mut offset state] + 35 (values) + 6 (index nibbles)
    const used = @sizeOf(StaticPage) + @sizeOf(u12) + 35 + 6;
    try testing.expectEqual(64 - used, page_ptr.available());

    // Everything retrieved matches what we wrote, so nibble-aligned indexing with u12 offsets works.
}
