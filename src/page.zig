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

        inline fn getIndex(capacity: usize, index: Index) usize {
            return capacity - (index + 1) * @sizeOf(Offset);
        }

        inline fn getIndicesOffset(capacity: usize, len: Index) usize {
            return capacity - len * @sizeOf(Offset);
        }

        inline fn getOffset(page: []const u8, index: Index) Offset {
            const ptr: *const Offset = @alignCast(@ptrCast(&page[getIndex(page.len, index)]));
            return ptr.*;
        }

        inline fn setOffset(page: []u8, index: Index, offset: Offset) void {
            const ptr: *Offset = @alignCast(@ptrCast(&page[getIndex(page.len, index)]));
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

        // TODO: Implement NibbleAligned indexing

        // inline fn getIndicesStart(index0: Offset, len: Index) Offset {
        // }

        // inline fn getOffset(page: [*]const u8, index: Index, index0: Offset) Offset {
        // }

        // inline fn setOffset(page: [*]u8, index: Index, offset: Offset, index0: Offset) void {
        // }
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

        // inline fn getConstData(_: Self, page: [*]const u8, header_size: comptime_int) []const u8 {
        //     return page[header_size..capacity];
        // }

        // inline fn getData(_: Self, page: [*]u8, header_size: comptime_int) []u8 {
        //     return page[header_size..capacity];
        // }
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

        // inline fn getConstData(self: Self, page: [*]const u8, header_size: comptime_int) []const u8 {
        //     // const capacity = @as(usize, @intCast(self.last_byte)) + 1;
        //     return page[header_size .. self.last_byte + 1];
        // }

        // inline fn getData(self: Self, page: [*]u8, header_size: comptime_int) []u8 {
        //     // const capacity = @as(usize, @intCast(self.last_byte)) + 1;
        //     return page[header_size .. self.last_byte + 1];
        // }
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

        // pub fn push(self: *Self, value: []const u8) Index {
        //     const index = self.len;
        //     const buf = self.alloc(@intCast(value.len));
        //     for (0..value.len) |i| buf[i] = value[i];
        //     return index;
        // }

        // pub fn push(self: *Self, value: [*]const u8, size: Offset) Index {
        //     const index = self.len;
        //     const pos = self.append.push(size);
        //     self.cap.setOffset(@ptrCast(self), index, pos);

        //     const buf = self.values();
        //     for (0..size) |i| buf[pos + i] = value[i];

        //     self.len += 1;
        //     return index;
        // }
    };
}

const testing = std.testing;

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
