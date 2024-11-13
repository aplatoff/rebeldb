//
// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//

const std = @import("std");

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

        fn getOffsetRT(page: [*]const u8, index: Index, last_byte: Offset) Offset {
            const pos = last_byte - (index + 1) * @sizeOf(Index) + 1;
            const ptr: *const Offset = @alignCast(@ptrCast(&page[pos]));
            return ptr.*;
        }

        inline fn getOffsetCT(page: [*]const u8, index: Index, comptime capacity: comptime_int) Offset {
            const pos = capacity - (index + 1) * @sizeOf(Index);
            const ptr: *const Offset = @alignCast(@ptrCast(&page[pos]));
            return ptr.*;
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

        // inline fn startOfIndices(_: Self, len: Index) usize {
        //     return capacity - Align.sizeOfIndices(len);
        // }

        inline fn getOffset(_: Self, page: [*]const u8, index: Index) Offset {
            return Align.getOffsetCT(page, index, capacity);
        }
    };
}

pub fn DynamicCapacity(comptime _: comptime_int, comptime Align: type) type {
    return packed struct {
        const Self = @This();
        const Offset = Align.Offset;
        const Index = Align.Index;

        last_byte: Offset,

        fn init(size: usize) Self {
            return Self{ .last_byte = @intCast(size - 1) };
        }

        // fn startOfIndices(self: Self, len: Index) usize {
        //     return @as(usize, self.last_byte) + 1 - Align.sizeOfIndices(len);
        // }

        fn getOffset(self: Self, page: [*]const u8, index: Index) Offset {
            return Align.getOffsetRT(page, index, self.last_byte);
        }
    };
}

/// Page
pub fn Page(comptime Capacity: type) type {
    return packed struct {
        const Self = @This();
        const Offset = Capacity.Offset;
        const Index = Capacity.Index;

        len: Offset,
        cap: Capacity,
        // append: Append,
        // delete: Delete,

        // returns bytes available for writing
        pub fn init(self: *Self, capacity: usize) Offset {
            self.len = 0;
            self.cap = Capacity.init(capacity);
            return 0;
        }

        // Read methods

        fn constValues(self: *const Self) [*]const u8 {
            const values: [*]const u8 = @ptrCast(self);
            return @ptrCast(&values[@sizeOf(Self)]);
        }

        pub fn get(self: *const Self, index: Index) [*]const u8 {
            const page: [*]const u8 = @ptrCast(self);
            return @ptrCast(&self.constValues()[self.cap.getOffset(page, index)]);
        }
    };
}

const testing = std.testing;

test "get static bytes u8 u8" {
    const data = [16]u8{ 2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 5, 0 };
    const StaticBytes = StaticCapacity(16, ByteAligned(u8, u8));
    const StaticPage = Page(StaticBytes);
    const static_page: *const StaticPage = @ptrCast(&data);

    try testing.expectEqual(@as(u8, 1), static_page.get(0)[0]);
    try testing.expectEqual(@as(u8, 6), static_page.get(1)[0]);
}

test "get static bytes u8 u16" {
    const data = [16]u8{ 2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 5, 0, 0, 0 };
    const StaticBytes = StaticCapacity(16, ByteAligned(u8, u16));
    const StaticPage = Page(StaticBytes);
    const static_page: *const StaticPage = @ptrCast(&data);

    try testing.expectEqual(@as(u8, 1), static_page.get(0)[0]);
    try testing.expectEqual(@as(u8, 6), static_page.get(1)[0]);
}

test "get dynamic bytes u8 u8" {
    const data = [16]u8{ 2, 15, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 5, 0 };
    const DynamicBytes = DynamicCapacity(16, ByteAligned(u8, u8));
    const DynamicPage = Page(DynamicBytes);
    const page: *const DynamicPage = @alignCast(@ptrCast(&data));

    try testing.expectEqual(@as(u8, 1), page.get(0)[0]);
    try testing.expectEqual(@as(u8, 6), page.get(1)[0]);
}

test "get dynamic bytes u8 u16" {
    const data = [16]u8{ 2, 15, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 5, 0, 0, 0 };
    const DynamicBytes = DynamicCapacity(16, ByteAligned(u8, u16));
    const DynamicPage = Page(DynamicBytes);
    const page: *const DynamicPage = @alignCast(@ptrCast(&data));

    try testing.expectEqual(@as(u8, 1), page.get(0)[0]);
    try testing.expectEqual(@as(u8, 6), page.get(1)[0]);
}
