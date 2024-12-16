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
pub fn ByteAligned(comptime OffsetType: type, comptime IndexType: type) type {
    return struct {
        const Offset = OffsetType;
        const Index = IndexType;

        inline fn getIndicesOffset(capacity: usize, len: Index) usize {
            return capacity - len * @sizeOf(Offset);
        }

        inline fn getOffset(page: []const u8, index: Index) Offset {
            const ofs = page.len - (index + 1) * @sizeOf(Offset);
            const ptr: *const Offset = @alignCast(@ptrCast(&page[ofs]));
            return ptr.*;
        }

        inline fn setOffset(page: []u8, index: Index, offset: Offset) void {
            const ofs = page.len - (index + 1) * @sizeOf(Offset);
            const ptr: *Offset = @alignCast(@ptrCast(&page[ofs]));
            ptr.* = offset;
        }
    };
}

/// NibbleAligned indices -- for Offset values aligned to four bits
pub fn NibbleAligned(comptime OffsetType: type, comptime IndexType: type) type {
    return struct {
        const Offset = OffsetType;
        const Index = IndexType;

        comptime {
            if (@bitSizeOf(Offset) % 4 != 0) {
                @compileError("Offset bit-size must be a multiple of 4 for NibbleAligned indexing");
            }
        }

        const offset_nibbles = @bitSizeOf(Offset) / 4;

        /// Compute the byte offset where the indexing region starts.
        inline fn getIndicesOffset(capacity: usize, len: Index) usize {
            const total_nibbles = @as(usize, @intCast(len)) * offset_nibbles;
            const index_bytes = (total_nibbles + 1) / 2;
            return capacity - index_bytes;
        }

        /// Get a nibble (4 bits) from the page given a nibble index (0-based from the front).
        inline fn getNibble(page: []const u8, nib_idx: usize) u4 {
            const byte_idx = nib_idx / 2;
            const in_byte_pos = nib_idx % 2; // 0 = high nibble, 1 = low nibble
            const byte_val = page[byte_idx];
            return @intCast(if (in_byte_pos == 0) (byte_val >> 4) & 0xF else byte_val & 0xF);
        }

        /// Set a nibble (4 bits) in the page at a given nibble index.
        inline fn setNibble(page: []u8, nib_idx: usize, nib: u4) void {
            const byte_idx = nib_idx / 2;
            const in_byte_pos = nib_idx % 2;

            const old_byte = page[byte_idx];
            const mask = if (in_byte_pos == 0) u8(0x0F) else u8(0xF0);
            const shifted_nib = if (in_byte_pos == 0) @as(u8, nib << 4) else @as(u8, nib);

            page[byte_idx] = (old_byte & mask) | shifted_nib;
        }

        /// Get the Offset stored at a given index.
        inline fn getOffset(page: []const u8, index: Index) Offset {
            const total_nibbles = page.len * 2;
            const start_nibble = total_nibbles - (index + 1) * offset_nibbles;

            var offset: usize = 0;
            inline for (0..offset_nibbles) |i| {
                offset = (offset << 4) | getNibble(page, start_nibble + i);
            }
            return @intCast(offset);
        }

        /// Set the Offset at a given index.
        inline fn setOffset(page: []u8, index: Index, offset: Offset) void {
            const total_nibbles = page.len * 2;
            const start_nibble = total_nibbles - (index + 1) * offset_nibbles;

            for (offset_nibbles) |i| {
                const shift_bits = (@as(u32, offset_nibbles - 1 - i)) * 4;
                const nib = @as(u4, (offset >> shift_bits) & 0xF);
                setNibble(page, start_nibble + i, nib);
            }
        }
    };
}

// Capacity is a type that defines the maximum number of values that can be stored in the page.

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

// Mutability

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

/// Page
pub fn Page(comptime Capacity: type, comptime Indices: type, comptime Mutability: type) type {
    return packed struct {
        const Self = @This();

        pub const Offset = Indices.Offset;
        pub const Index = Indices.Index;

        len: Index,
        cap: Capacity,
        mut: Mutability,
        // del: Delete,

        // returns bytes available for writing
        pub fn init(self: *Self, capacity: usize) Offset {
            self.len = 0;
            self.mut = Mutability.init(0);
            self.cap = Capacity.init(capacity);
            return self.available();
        }

        pub inline fn count(self: Self) Index {
            return self.len;
        }

        inline fn indices(self: *const Self, index: Index) usize {
            return Indices.getIndicesOffset(self.cap.capacity(), index);
        }

        pub inline fn available(self: *Self) Offset {
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

        pub inline fn alloc(self: *Self, size: Offset) []u8 {
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

const testing = std.testing;

test "get readonly static nibble u4 u4" {
    const data = [16]u8{ 0x20, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 5, 0x50 };
    const StaticPage = Page(Static(16), NibbleAligned(u4, u4), Readonly(u4));
    const static_page: *const StaticPage = @ptrCast(&data);

    try testing.expectEqual(1, @sizeOf(StaticPage));
    try testing.expectEqual(@as(u8, 1), static_page.get(0)[0]);
    try testing.expectEqual(@as(u8, 6), static_page.get(1)[0]);
}

test "get readonly static bytes u8 u8" {
    const data = [16]u8{ 2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 5, 0 };
    const StaticPage = Page(Static(16), ByteAligned(u8, u8), Readonly(u8));
    const static_page: *const StaticPage = @ptrCast(&data);

    try testing.expectEqual(1, @sizeOf(StaticPage));
    try testing.expectEqual(@as(u8, 1), static_page.get(0)[0]);
    try testing.expectEqual(@as(u8, 6), static_page.get(1)[0]);
}

test "get and push mutable static bytes u8 u8" {
    var data = [16]u8{ 2, 6, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 5, 0 };
    const StaticPage = Page(Static(16), ByteAligned(u8, u8), Mutable(u8));
    const static_page: *StaticPage = @alignCast(@ptrCast(&data));

    try testing.expectEqual(2, @sizeOf(StaticPage));
    try testing.expectEqual(@as(u8, 2), static_page.get(0)[0]);
    try testing.expectEqual(@as(u8, 7), static_page.get(1)[0]);

    const value = static_page.alloc(1);
    value[0] = 100;

    try testing.expectEqual(@as(u8, 3), data[0]);
    try testing.expectEqual(@as(u8, 7), data[1]);
    try testing.expectEqual(@as(u8, 100), static_page.get(2)[0]);
}

test "mutable static bytes u16 u16" {
    var data = [16]u16{ 0, 0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 5, 0 };
    const StaticPage = Page(Static(0x10000), ByteAligned(u16, u16), Mutable(u16));
    const static_page: *StaticPage = @alignCast(@ptrCast(&data));

    try testing.expectEqual(@as(u16, 65530), static_page.available());
}

// for assemly generation
// zig build-lib -O ReleaseSmall -femit-asm=page.asm src/page.zig

const PageSize = 0x10000;
const PageIndex = u16;
const PageOffset = u16;

const HeapPage = Page(Static(PageSize), ByteAligned(PageOffset, PageIndex), Mutable(PageOffset));

export fn get(page: *const HeapPage, index: PageIndex) [*]const u8 {
    return page.get(index);
}

// export fn push(page: *HeapPage, value: [*]const u8, size: PageOffset) void {
//     _ = page.push(value[0..size]);
// }

export fn alloc(page: *HeapPage, size: PageOffset) [*]const u8 {
    return @ptrCast(&page.alloc(size));
}

export fn available(page: *HeapPage) PageOffset {
    return page.available();
}

const NibblePage = Page(Static(4096), NibbleAligned(u12, u12), Readonly(u12));

export fn nibbleGet(page: *const NibblePage, index: usize) [*]const u8 {
    return page.get(@intCast(index));
}
