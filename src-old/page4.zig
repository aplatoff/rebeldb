//
// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//

const std = @import("std");
const assert = std.debug.assert;

// Alignment is a type that defines the alignment of the index values on the page.

pub fn ByteAligned(comptime OffsetType: type, comptime IndexType: type) type {
    return struct {
        const Offset = OffsetType;
        const Index = IndexType;

        // fn sizeOfIndices(len: Index) usize {
        //     return @sizeOf(Index) * len;
        // }

        // fn setIndex(buf: []u8, index: Index, offset: Offset) void {
        //     const idx: [*]Index = @alignCast(@ptrCast(buf));
        //     // const last_index = last_byte / @sizeOf(Index);
        //     idx[buf.len / @sizeOf(Index) - 1 - index] = offset;
        // }

        inline fn getOffsetRuntime(page: [*]const u8, index: Index, last_byte: Offset) Offset {
            const pos = last_byte - (index + 1) * @sizeOf(Index) + 1;
            const ptr: *const Offset = @alignCast(@ptrCast(&page[pos]));
            return ptr.*;
        }

        inline fn getOffsetComptime(page: [*]const u8, index: Index, comptime capacity: comptime_int) Offset {
            const pos = capacity - (index + 1) * @sizeOf(Index);
            const ptr: *const Offset = @alignCast(@ptrCast(&page[pos]));
            return ptr.*;
        }

        inline fn setOffsetRuntime(page: [*]u8, index: Index, offset: Offset, last_byte: Offset) void {
            const pos = last_byte - (index + 1) * @sizeOf(Index) + 1;
            const ptr: *Offset = @alignCast(@ptrCast(&page[pos]));
            ptr.* = offset;
        }

        inline fn setOffsetComptime(page: [*]u8, index: Index, offset: Offset, comptime capacity: comptime_int) void {
            const pos = capacity - (index + 1) * @sizeOf(Index);
            const ptr: *Offset = @alignCast(@ptrCast(&page[pos]));
            ptr.* = offset;
        }
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

        inline fn getOffset(_: Self, page: [*]const u8, index: Index) Offset {
            return Align.getOffsetComptime(page, index, capacity);
        }

        inline fn setOffset(_: Self, page: [*]u8, index: Index, offset: Offset) void {
            return Align.setOffsetRuntime(page, index, offset, capacity);
        }
    };
}

pub fn DynamicCapacity(comptime _: comptime_int, comptime Align: type) type {
    return packed struct {
        const Self = @This();
        const Offset = Align.Offset;
        const Index = Align.Index;

        last_byte: Offset,

        inline fn init(size: usize) Self {
            return Self{ .last_byte = @intCast(size - 1) };
        }

        inline fn getOffset(self: Self, page: [*]const u8, index: Index) Offset {
            return Align.getOffsetRuntime(page, index, self.last_byte);
        }

        inline fn setOffset(self: Self, page: [*]u8, index: Index, offset: Offset) void {
            return Align.setOffsetRuntime(page, index, offset, self.last_byte);
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

        inline fn position(self: Self) Offset {
            return self.value;
        }

        inline fn advance(self: Self, size: Offset) Self {
            return Self{ .value = self.value + size };
        }
    };
}

pub fn Readonly(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        inline fn init() Self {
            return Self{};
        }

        inline fn position(_: Self) Offset {
            unreachable;
        }

        inline fn advance(_: Self, _: Offset) Self {
            unreachable;
        }
    };
}

/// Page
pub fn Page(comptime Capacity: type, comptime Append: type) type {
    return packed struct {
        const Self = @This();
        const Offset = Capacity.Offset;
        const Index = Capacity.Index;

        len: Offset,
        cap: Capacity,
        append: Append,
        // delete: Delete,

        // returns bytes available for writing
        pub fn init(self: *Self, capacity: usize) Offset {
            self.len = 0;
            self.cap = Capacity.init(capacity);
            self.append = Append.init();
            return 0;
        }

        // Read methods

        inline fn constValues(self: *const Self) [*]const u8 {
            const val: [*]const u8 = @ptrCast(self);
            return @ptrCast(&val[@sizeOf(Self)]);
        }

        pub fn get(self: *const Self, index: Index) [*]const u8 {
            const page: [*]const u8 = @ptrCast(self);
            return @ptrCast(&self.constValues()[self.cap.getOffset(page, index)]);
        }

        // Write methods

        inline fn values(self: *Self) [*]u8 {
            const val: [*]u8 = @ptrCast(self);
            return @ptrCast(&val[@sizeOf(Self)]);
        }

        pub fn push(self: *Self, value: [*]const u8, size: Offset) void {
            self.len += 1;
            const pos = self.append.position();
            self.cap.setOffset(@ptrCast(self), self.len, pos);

            const buf = self.values();
            for (0..size) |i| buf[pos + i] = value[i];

            self.append = self.append.advance(size);
        }
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

    const value = [1]u8{100};
    static_page.push(&value, 1);

    try testing.expectEqual(@as(u8, 3), data[0]);
    try testing.expectEqual(@as(u8, 7), data[1]);
    try testing.expectEqual(@as(u8, 100), static_page.get(2)[0]);
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

const SPage = Page(StaticCapacity(16, ByteAligned(u8, u8)), Mutable(u8));

export fn get(page: *const SPage, pos: u8) [*]const u8 {
    return page.get(pos);
}

export fn push(page: *SPage, value: [*]const u8, size: u8) void {
    return page.push(value, size);
}
