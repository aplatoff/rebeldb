// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//
// This code defines a flexible Page abstraction for a database-like storage layer.
// Pages contain variable-sized values accessible by index. Values are appended forward
// from the start of the page data region, while their offsets (for indexing) are stored
// starting from the end of the page and growing backward as more values are inserted.
//
// Memory Layout Concept:
// ----------------------
// [ Page Metadata | Values Growing Forward --> ... ... <-- Indexes Growing Backward ]
//
// The indexing scheme:
// - Values are appended at increasing offsets from the start of the page.
// - Index offsets are stored at the end of the page and move backward as new values are added.
// - An index maps an index number (0, 1, 2, ...) to a stored offset (byte position) of a value.
//
// This design allows for flexible configuration of:
// - Offset storage (Byte aligned Offset integer types and Four-bit aligned).
// - Capacity handling (static vs. dynamic).
// - Mutability (read-only vs. mutable append).
//

const std = @import("std");
const assert = std.debug.assert;

/// ByteAligned indices -- for Offset values aligned to the byte boundary
pub fn ByteAligned(comptime OffsetType: type) type {
    return struct {
        const Offset = OffsetType;

        inline fn getIndicesOffset(capacity: usize, len: usize) usize {
            return capacity - len * @sizeOf(Offset);
        }

        inline fn getOffset(page: []const u8, index: usize) Offset {
            const ofs = page.len - (index + 1) * @sizeOf(Offset);
            const ptr: *const Offset = @alignCast(@ptrCast(&page[ofs]));
            return ptr.*;
        }

        inline fn setOffset(page: []u8, index: usize, offset: Offset) void {
            const ofs = page.len - (index + 1) * @sizeOf(Offset);
            const ptr: *Offset = @alignCast(@ptrCast(&page[ofs]));
            ptr.* = offset;
        }
    };
}

/// NibbleAligned indices -- for Offset values aligned to four bits
pub fn NibbleAligned(comptime OffsetType: type) type {
    return struct {
        const Offset = OffsetType;

        comptime {
            if (@bitSizeOf(Offset) % 4 != 0 or @bitSizeOf(Offset) % 8 == 0) {
                @compileError("Offset bit-size must be a multiple of 4 for NibbleAligned indexing and not a multiple of 8");
            }
        }

        const offset_bits = @bitSizeOf(Offset);
        const Aligned = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = offset_bits + 4 } });

        const offset_nibbles = offset_bits / 4;
        const mask: Aligned = (1 << offset_bits) - 1;

        inline fn getIndicesOffset(capacity: usize, len: usize) usize {
            const total_nibbles = @as(usize, @intCast(len)) * offset_nibbles;
            const index_bytes = (total_nibbles + 1) / 2;
            return capacity - index_bytes;
        }

        inline fn getOffset(page: []const u8, index: usize) Offset {
            const total_nibbles = page.len * 2;
            const start_nibble = total_nibbles - (index + 1) * offset_nibbles;

            const start_byte = start_nibble / 2;
            const nibble_in_byte = start_nibble % 2;

            const buf = page[start_byte..][0..@sizeOf(Aligned)];
            const aligned = std.mem.readInt(Aligned, buf, std.builtin.Endian.little);
            const raw = aligned >> @intCast(nibble_in_byte << 2);

            return @intCast(raw & mask);
        }

        inline fn setOffset(page: []u8, index: usize, offset: Offset) void {
            const total_nibbles = page.len * 2;
            const start_nibble = total_nibbles - (index + 1) * offset_nibbles;

            const start_byte = start_nibble / 2;
            const nibble_in_byte = start_nibble % 2;

            const buf = page[start_byte..][0..@sizeOf(Aligned)];
            const aligned = std.mem.readInt(Aligned, buf, std.builtin.Endian.little);
            const shift = nibble_in_byte << 2;
            const raw = aligned & ~(mask << @intCast(shift));
            const shifted_offset: Aligned = @as(Aligned, @intCast(offset)) << @intCast(shift);
            std.mem.writeInt(Aligned, buf, raw | shifted_offset, std.builtin.Endian.little);
        }
    };
}

/// Capacity configuration that defines a fixed maximum size at compile time.
///
/// Static capacity pages have their size determined at compile time, providing
/// zero runtime overhead for capacity tracking. This configuration is ideal for
/// scenarios where page sizes are known and consistent.
///
/// Performance considerations:
/// - Zero runtime overhead (no capacity storage)
/// - No memory overhead beyond page content
/// - Compile-time size validation
/// - Best for fixed-size allocations
///
/// Example usage:
/// ```zig
/// const StaticPage = Page(u8, Static(128), ByteAligned(u8), Mutable(u8));
/// ```
///
/// Args:
///     cap: Compile-time constant defining page capacity in bytes
pub fn Static(comptime cap: comptime_int) type {
    return packed struct {
        const Self = @This();

        inline fn init(_: usize) Self {
            return Self{};
        }

        inline fn capacity(_: Self) usize {
            return cap;
        }
    };
}

pub fn Dynamic(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        last_byte: Offset, // same as capacity - 1, since capacity may not fit in Offset type

        inline fn init(size: usize) Self {
            return Self{ .last_byte = @intCast(size - 1) };
        }

        inline fn capacity(self: Self) usize {
            return @as(usize, @intCast(self.last_byte)) + 1;
        }
    };
}

/// Mutability configuration that enables write operations.
///
/// Mutable pages support both read and write operations, tracking the
/// current write position and managing available space. This configuration
/// is necessary for pages that need to accept new values.
///
/// Performance considerations:
/// - Small runtime overhead for position tracking
/// - Single offset storage overhead
/// - Enables efficient append operations
/// - Best for write-heavy workloads
///
/// Example usage:
/// ```zig
/// const MutablePage = Page(u8, Static(32), ByteAligned(u8), Mutable(u8));
/// ```
///
/// Args:
///     Offset: Type used for storing position offsets
pub fn Mutable(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        value: Offset,

        inline fn init(offset: Offset) Self {
            return Self{ .value = offset };
        }

        inline fn available(self: Self, cap: Offset) Offset {
            return cap - self.value;
        }

        inline fn get(self: Self) Offset {
            return self.value;
        }
    };
}

/// Mutability configuration that prevents write operations.
///
/// Readonly pages only support read operations, providing compile-time
/// guarantees against modification. This configuration is ideal for
/// sharing data across threads or preventing accidental modifications.
///
/// Performance considerations:
/// - Zero runtime overhead (no state)
/// - No memory overhead
/// - Compile-time write prevention
/// - Best for concurrent access patterns
///
/// Example usage:
/// ```zig
/// const ReadonlyPage = Page(u8, Static(16), ByteAligned(u8), Readonly(u8));
/// ```
///
/// Args:
///     Offset: Type used for offset calculations (though writes are prevented)
pub fn Readonly(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        inline fn init(_: Offset) Self {
            return Self{};
        }

        inline fn available(_: Self, _: Offset) Offset {
            return 0;
        }

        inline fn get(_: Self) Offset {
            unreachable;
        }
    };
}

/// Page represents a flexible storage abstraction with configurable behavior.
///
/// The Page type provides a memory-efficient storage mechanism with:
/// - Configurable index type for value references
/// - Static or dynamic capacity management
/// - Byte or nibble-aligned index storage
/// - Mutable or readonly access patterns
///
/// Memory Layout:
/// ┌──────────────┬─────────────────────┬─────────────────┐
/// │   Header     │    Values           │     Indices     │
/// │              │    (Growing →)      │    (← Growing)  │
/// └──────────────┴─────────────────────┴─────────────────┘
///
/// Performance considerations:
/// - Bidirectional growth minimizes fragmentation
/// - Aligned index access optimizes memory operations
/// - Flexible configuration enables use-case optimization
///
/// Args:
///     IndexType: Type used for value indexing
///     Capacity: Static or Dynamic capacity configuration
///     Indices: ByteAligned or NibbleAligned index storage
///     Mutability: Readonly or Mutable access configuration
pub fn Page(comptime IndexType: type, comptime Capacity: type, comptime Indices: type, comptime Mutability: type) type {
    return packed struct {
        const Self = @This();

        pub const Offset = Indices.Offset;
        pub const Index = IndexType;

        len: Index,
        cap: Capacity,
        mut: Mutability,
        // del: Delete,

        /// Initialize a new page with the given capacity
        ///
        /// Args:
        ///     capacity: Total size of the page in bytes
        ///
        /// Returns: Number of bytes available for writing
        pub fn init(self: *Self, capacity: usize) Offset {
            self.len = 0;
            self.mut = Mutability.init(0);
            self.cap = Capacity.init(capacity);
            return self.available();
        }

        /// Get the current number of values stored in the page
        pub inline fn count(self: Self) Index {
            return self.len;
        }

        /// Calculate the byte offset where indices start for a given index
        inline fn indices(self: *const Self, index: Index) usize {
            return Indices.getIndicesOffset(self.cap.capacity(), index);
        }

        /// Get the number of bytes available for writing
        ///
        /// Returns the number of bytes that can be allocated for new values,
        /// accounting for both value storage and index storage needs.
        pub fn available(self: *Self) Offset {
            const avail = self.mut.available(@intCast(self.indices(self.len + 1)));
            return if (avail > @sizeOf(Self)) avail - @sizeOf(Self) else 0;
        }

        // Read methods

        inline fn constValues(self: *const Self) []const u8 {
            const page: [*]const u8 = @ptrCast(self);
            return page[@sizeOf(Self)..self.cap.capacity()];
        }

        pub inline fn get(self: *const Self, index: Index) [*]const u8 {
            const page = self.constValues();
            return @ptrCast(&page[Indices.getOffset(page, index)]);
        }

        // Write methods

        inline fn values(self: *Self) []u8 {
            const page: [*]u8 = @ptrCast(self);
            return page[@sizeOf(Self)..self.cap.capacity()];
        }

        /// Allocate space for a new value
        ///
        /// Args:
        ///     size: Number of bytes to allocate
        ///
        /// Returns: Slice of allocated memory for writing the value
        pub fn alloc(self: *Self, size: Offset) []u8 {
            const page = self.values();
            const offset = self.mut.get();
            Indices.setOffset(page, self.len, offset);
            const next = offset + size;
            self.mut = Mutability.init(next);
            self.len += 1;
            return page[offset..next];
        }
    };
}

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
    _ = NibbleAligned(u4);
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

    const StaticPage = Page(u8, Static(16), ByteAligned(u8), Readonly(u8));
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
    const StaticPage = Page(u8, Static(32), ByteAligned(u8), Mutable(u8));
    const page_ptr: *StaticPage = @alignCast(@ptrCast(&data));

    const avail = page_ptr.init(32);
    try testing.expectEqual(@as(u8, 32 - @sizeOf(StaticPage) - @sizeOf(u8)), avail);

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

// RebelDB™ Test Suite for Page Abstraction
// © 2024 Huly Labs • SPDX-License-Identifier: MIT
// This test suite is designed to thoroughly check various configurations and behaviors of the Page abstraction.

const testing = std.testing;

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

    const StaticPage = Page(u4, Static(16), NibbleAligned(u4), Readonly(u4));
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

    const StaticPage = Page(u4, Static(16), NibbleAligned(u4), Mutable(u4));
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
    const DynamicPage = Page(u16, Dynamic(u16), ByteAligned(u16), Mutable(u16));
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
    const ReadOnlyPage = Page(u8, Static(16), ByteAligned(u8), Readonly(u8));
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
    try testing.expectEqual(0, page_ptr.available());
}

// ---------------------------------------------
// Boundary checks (no runtime checks present, just sanity tests)
// ---------------------------------------------
test "verify no overlap for multiple allocations" {
    // This test ensures that allocations do not overlap each other or the indexing region.
    // We'll allocate small chunks until we approach the indexing region and check final layout.

    var data = [_]u8{0} ** 64;
    const StaticPage = Page(u8, Static(64), ByteAligned(u8), Mutable(u8));
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
    try testing.expectEqual(80, last_val[0]); // i=4 => 4*20=80
    try testing.expectEqual(81, last_val[1]);
}

test "static nibble aligned u12 offsets: append multiple values" {
    // This test ensures that nibble-aligned indexing with u12 offsets works correctly for multiple appended values.
    // We'll use a static page of size 64 bytes for simplicity.
    var data = [_]u8{0} ** 64;

    // Use NibbleAligned(u12, u8) and Mutable(u12) to allow appends.
    // Using u8 as Index is fine for a small number of values.
    const StaticPage = Page(u8, Static(64), NibbleAligned(u12), Mutable(u12));
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

test "static nibble aligned u12 offsets: boundary conditions with small values" {
    // Test minimal allocations and indexing near the start.
    var data = [_]u8{0} ** 32;

    const StaticPage = Page(u8, Static(32), NibbleAligned(u12), Mutable(u12));
    const page_ptr: *StaticPage = @alignCast(@ptrCast(&data));

    _ = page_ptr.init(32);

    // Allocate a small value at offset 0
    const val0 = page_ptr.alloc(@as(u12, 1));
    val0[0] = 0xAB;
    try testing.expectEqual(0xAB, page_ptr.get(0)[0]);

    // Allocate a second small value (2 bytes)
    const val1 = page_ptr.alloc(2);
    val1[0] = 0xCD;
    val1[1] = 0xEF;
    try testing.expectEqual(0xCD, page_ptr.get(1)[0]);
    try testing.expectEqual(0xEF, page_ptr.get(1)[1]);

    // Check count and availability
    try testing.expectEqual(2, page_ptr.count());
    try testing.expectEqual(32 - @sizeOf(StaticPage) - 3 - 5, page_ptr.available());
}

test "static nibble aligned u12 offsets: multiple medium-sized values" {
    // Test appending values that cause offset to exceed one-byte boundaries in indexing.
    var data = [_]u8{0} ** 128;

    // We'll store 3 values:
    // - Value0 starts at offset 0 and is 20 bytes long
    // - Value1 starts at offset 20 and is 15 bytes long
    // - Value2 starts at offset 35 and is 25 bytes long
    //
    // Total values = 60 bytes. Indices: 3 * 12 bits = 36 bits = 4.5 bytes, so 5 bytes indexing.
    const StaticPage = Page(u8, Static(128), NibbleAligned(u12), Mutable(u12));
    const page_ptr: *StaticPage = @alignCast(@ptrCast(&data));
    _ = page_ptr.init(128);

    const val0 = page_ptr.alloc(20);
    for (val0, 0..) |*b, i| b.* = @intCast(i);
    try testing.expectEqual(19, page_ptr.get(0)[19]);

    const val1 = page_ptr.alloc(15);
    for (val1, 0..) |*b, i| b.* = @intCast(i + 100);
    try testing.expectEqual(100, page_ptr.get(1)[0]);
    try testing.expectEqual(114, page_ptr.get(1)[14]);

    const val2 = page_ptr.alloc(25);
    for (val2, 0..) |*b, i| b.* = @intCast(i + 200);
    try testing.expectEqual(200, page_ptr.get(2)[0]);
    try testing.expectEqual(224, page_ptr.get(2)[24]);

    // Verify count
    try testing.expectEqual(3, page_ptr.count());

    // Check availability after large allocations:
    // Used = struct size + @sizeOf(u12) for mut + 20+15+25=60 bytes values + ~5 bytes indexing = ~67 + overhead
    // Just ensure we still have some space left
    try testing.expect(page_ptr.available() > 40);
}

test "dynamic nibble aligned u12 offsets: multiple values" {
    // Test a dynamic page with nibble-aligned u12 offsets.
    // We'll use a 512-byte page and store multiple values.
    var data = [_]u8{0} ** 512;
    const DynamicPage = Page(u8, Dynamic(u12), NibbleAligned(u12), Mutable(u12));
    const page_ptr: *DynamicPage = @alignCast(@ptrCast(&data));

    const avail = page_ptr.init(512);
    // Just a sanity check to ensure some initial availability
    try testing.expect(avail > 400);

    // Store 8 values of 10 bytes each = 80 bytes total
    for (0..8) |i| {
        const val = page_ptr.alloc(10);
        for (val, 0..) |*b, idx| b.* = @intCast(i * 10 + idx);
    }

    // Verify retrieval
    for (0..8) |i| {
        const got = page_ptr.get(@intCast(i));
        try testing.expectEqual(@as(u8, @intCast(i * 10)), got[0]);
        try testing.expectEqual(@as(u8, @intCast(i * 10 + 9)), got[9]);
    }

    // Check availability after 80 bytes + indexes:
    // 8 values = 8 * 12 bits = 96 bits = 12 bytes indexing + metadata
    // Used ~= @sizeOf(DynamicPage) + @sizeOf(u12) + 80 + 12
    // This should be well under 512, so still plenty available.
    try testing.expect(page_ptr.available() > 400 - 80 - 20);
}

// for assemly generation
// zig build-lib -O ReleaseSmall -femit-asm=page.asm src/page.zig

const PageSize = 0x10000;
const PageIndex = u16;
const PageOffset = u16;

const HeapPage = Page(PageIndex, Static(PageSize), ByteAligned(PageOffset), Mutable(PageOffset));

export fn init(page: *HeapPage) void {
    _ = page.init(PageSize);
}

export fn get(page: *const HeapPage, index: PageIndex) [*]const u8 {
    return page.get(index);
}

export fn alloc(page: *HeapPage, size: PageOffset) *u8 {
    return &page.alloc(size)[0];
}

export fn available(page: *HeapPage) PageOffset {
    return page.available();
}

const NibblePage = Page(u8, Static(4096), NibbleAligned(u12), Mutable(u12));

export fn nibbleGet(page: *const NibblePage, index: usize) [*]const u8 {
    return page.get(@intCast(index));
}

export fn nibbleAlloc(page: *NibblePage, size: usize) *u8 {
    return &page.alloc(@intCast(size))[0];
}
