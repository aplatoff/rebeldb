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

        inline fn getIndex(index0: Offset, index: Index) Offset {
            return index0 - index * @sizeOf(Offset);
        }

        inline fn getIndicesStart(index0: Offset, len: Index) Offset {
            return getIndex(index0, len);
        }

        inline fn getOffset(page: [*]const u8, index: Index, index0: Offset) Offset {
            const ptr: *const Offset = @alignCast(@ptrCast(&page[getIndex(index0, index)]));
            return ptr.*;
        }

        inline fn setOffset(page: [*]u8, index: Index, offset: Offset, index0: Offset) void {
            const ptr: *Offset = @alignCast(@ptrCast(&page[getIndex(index0, index)]));
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

pub fn StaticCapacity(comptime capacity: comptime_int, comptime Align: type) type {
    return packed struct {
        const Self = @This();
        const Offset = Align.Offset;
        const Index = Align.Index;

        inline fn init(_: usize) Self {
            return Self{};
        }

        inline fn indicesStart(_: Self, len: Index) Offset {
            return Align.getIndicesStart(capacity - @sizeOf(Offset), len);
        }

        inline fn getOffset(_: Self, page: [*]const u8, index: Index) Offset {
            return Align.getOffset(page, index, capacity - @sizeOf(Offset));
        }

        inline fn setOffset(_: Self, page: [*]u8, index: Index, offset: Offset) void {
            return Align.setOffset(page, index, offset, capacity - @sizeOf(Offset));
        }
    };
}

pub fn DynamicCapacity(comptime _: comptime_int, comptime Align: type) type {
    return packed struct {
        const Self = @This();
        const Offset = Align.Offset;
        const Index = Align.Index;

        index0: Offset,

        inline fn init(size: usize) Self {
            return Self{ .index0 = @intCast(size - @sizeOf(Offset)) };
        }

        inline fn indicesStart(self: Self, len: Index) Offset {
            return Align.getIndicesStart(self.index0, len);
        }

        inline fn getOffset(self: Self, page: [*]const u8, index: Index) Offset {
            return Align.getOffset(page, index, self.index0);
        }

        inline fn setOffset(self: Self, page: [*]u8, index: Index, offset: Offset) void {
            return Align.setOffset(page, index, offset, self.index0);
        }
    };
}

// Mutability

pub fn Mutable(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        value: Offset,

        inline fn init() Self {
            return Self{ .value = 0 };
        }

        inline fn available(self: Self, free: Offset) Offset {
            return free - self.value;
        }

        inline fn push(self: *Self, size: Offset) Offset {
            const pos = self.value;
            self.value += size;
            return pos;
        }
    };
}

pub fn Readonly(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        inline fn init() Self {
            return Self{};
        }

        inline fn available(_: Self, _: Offset) Offset {
            return 0;
        }

        inline fn push(_: *Self, _: Offset) Offset {
            unreachable;
        }
    };
}

/// Page
pub fn Page(comptime Capacity: type, comptime Append: type) type {
    return packed struct {
        const Self = @This();

        pub const Offset = Capacity.Offset;
        pub const Index = Capacity.Index;

        len: Index,
        cap: Capacity,
        append: Append,
        // delete: Delete,

        // returns bytes available for writing
        pub fn init(self: *Self, capacity: usize) Offset {
            self.len = 0;
            self.cap = Capacity.init(capacity);
            self.append = Append.init();
            return self.available();
        }

        pub inline fn count(self: Self) Index {
            return self.len;
        }

        pub fn available(self: *Self) Offset {
            const avail = self.append.available(self.cap.indicesStart(self.len));
            // available can be negative if the page is full and it requires some space for the index
            return @max(avail, @sizeOf(Self)) - @sizeOf(Self);
        }

        // Read methods

        inline fn constValues(self: *const Self) [*]const u8 {
            const val: [*]const u8 = @ptrCast(self);
            return @ptrCast(&val[@sizeOf(Self)]);
        }

        pub inline fn get(self: *const Self, index: Index) [*]const u8 {
            const page: [*]const u8 = @ptrCast(self);
            return @ptrCast(&self.constValues()[self.cap.getOffset(page, index)]);
        }

        // Write methods

        inline fn values(self: *Self) [*]u8 {
            const val: [*]u8 = @ptrCast(self);
            return @ptrCast(&val[@sizeOf(Self)]);
        }

        pub inline fn alloc(self: *Self, size: Offset) []u8 {
            const pos = self.append.push(size);
            self.cap.setOffset(@ptrCast(self), self.len, pos);
            self.len += 1;
            return self.values()[pos .. pos + size];
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
    const StaticPage = Page(StaticCapacity(16, ByteAligned(u8, u8)), Readonly(u8));
    const static_page: *const StaticPage = @ptrCast(&data);

    try testing.expectEqual(1, @sizeOf(StaticPage));
    try testing.expectEqual(@as(u8, 1), static_page.get(0)[0]);
    try testing.expectEqual(@as(u8, 6), static_page.get(1)[0]);
}

test "get and push mutable static bytes u8 u8" {
    var data = [16]u8{ 2, 6, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 5, 0 };
    const StaticPage = Page(StaticCapacity(16, ByteAligned(u8, u8)), Mutable(u8));
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
    const StaticPage = Page(StaticCapacity(0x10000, ByteAligned(u16, u16)), Mutable(u16));
    const static_page: *StaticPage = @alignCast(@ptrCast(&data));

    try testing.expectEqual(@as(u16, 65530), static_page.available());
}

// test "get static bytes u8 u16" {
//     const data = [16]u8{ 2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 5, 0, 0, 0 };
//     const StaticBytes = StaticCapacity(16, ByteAligned(u8, u16));
//     const StaticPage = Page(StaticBytes);
//     const static_page: *const StaticPage = @ptrCast(&data);

//     try testing.expectEqual(@as(u8, 1), static_page.get(0)[0]);
//     try testing.expectEqual(@as(u8, 6), static_page.get(1)[0]);
// }

// test "get dynamic bytes u8 u8" {
//     const data = [16]u8{ 2, 15, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 5, 0 };
//     const DynamicBytes = DynamicCapacity(16, ByteAligned(u8, u8));
//     const DynamicPage = Page(DynamicBytes);
//     const page: *const DynamicPage = @alignCast(@ptrCast(&data));

//     try testing.expectEqual(@as(u8, 1), page.get(0)[0]);
//     try testing.expectEqual(@as(u8, 6), page.get(1)[0]);
// }

// test "get dynamic bytes u8 u16" {
//     const data = [16]u8{ 2, 15, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 5, 0, 0, 0 };
//     const DynamicBytes = DynamicCapacity(16, ByteAligned(u8, u16));
//     const DynamicPage = Page(DynamicBytes);
//     const page: *const DynamicPage = @alignCast(@ptrCast(&data));

//     try testing.expectEqual(@as(u8, 1), page.get(0)[0]);
//     try testing.expectEqual(@as(u8, 6), page.get(1)[0]);
// }

// for assemly generation
// zig build-lib -O ReleaseSmall -femit-asm=page.asm src/page.zig

const PageSize = 0x10000;
const PageIndex = u16;
const PageOffset = u16;

const HeapPage = Page(StaticCapacity(PageSize, ByteAligned(PageOffset, PageIndex)), Mutable(PageOffset));

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
