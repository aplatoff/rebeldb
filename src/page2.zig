//
// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//

//! This is RebelDB modular page structure. Designed to be highly configurable
//! so users can configure byte or bit-level addressing and indexing,
//! optionally supporting write and delete operations.
//!
//! Page is basically an array of variable length values.

const std = @import("std");

const testing = std.testing;
const assert = std.debug.assert;

//
// Layouts. User can choose from byte-level or bit-level addressing and indexing.
//

fn createUnsigned(bitCount: u16) type {
    return @Type(.{
        .Int = .{ .signedness = .unsigned, .bits = bitCount },
    });
}

/// Byte-level addressing and indexing support.
fn ByteAligned(comptime capacity: comptime_int) type {
    const cap: usize = if (capacity == 0) 0 else capacity - 1;
    const bits_needed = @bitSizeOf(usize) - @clz(cap);
    assert(bits_needed <= 64);

    const OffsetType = createUnsigned((bits_needed + 7) / 8 * 8);
    assert(capacity % @sizeOf(OffsetType) == 0);

    return packed struct {
        const Capacity = capacity;
        const Offset = OffsetType; // used to index any byte in the capacity space
        const Index = OffsetType; // used to index any index in the capacity space

        fn constIndexes(buffer: []const u8) []const Offset {
            assert(buffer.len % @sizeOf(Index) == 0);
            const idx: [*]const Index align(1) = @alignCast(@ptrCast(&buffer[0]));
            return idx[0 .. buffer.len / @sizeOf(Index)];
        }

        fn indexes(buffer: []u8) []Offset {
            assert(buffer.len % @sizeOf(Index) == 0);
            const idx: [*]Index = @ptrCast(&buffer[0]);
            return idx[0 .. buffer.len / @sizeOf(Index)];
        }

        fn sizeOfIndexes(len: usize) Offset {
            return @intCast(@sizeOf(Index) * len);
        }

        fn setIndex(buffer: []u8, index: Index, offset: Offset) void {
            const idx = indexes(buffer);
            idx[idx.len - 1 - index] = offset;
        }

        fn getIndex(buffer: []const u8, index: Index) Offset {
            const idx = constIndexes(buffer);
            return idx[idx.len - 1 - index];
        }
    };
}

//
//  Page sizes. Fixed to capacity or variable length.
//

// Page can grow to the capacity of the alignment type.
fn Fixed(comptime AlignmentType: type) type {
    return packed struct {
        const Self = @This();
        const Align = AlignmentType;
        const Offset = Align.Offset;

        fn init(_: usize) Self {
            return Self{};
        }

        fn cap(_: Self) usize {
            return AlignmentType.Capacity;
        }
    };
}

// Page can grow to the size provided.
fn Variable(comptime AlignmentType: type) type {
    return packed struct {
        const Self = @This();
        const Align = AlignmentType;

        last_byte: AlignmentType.Offset,

        fn init(size: usize) Self {
            assert(size <= AlignmentType.Capacity);
            return Self{ .last_byte = @intCast(size - 1) };
        }

        fn cap(self: Self) usize {
            return self.last_byte + 1;
        }
    };
}

//
//  Mutability.
//

// Immutable size. No append operations allowed.
fn Const(comptime Offset: type) type {
    return packed struct {
        const Self = @This();
        fn init(_: Offset) Self {
            return Self{};
        }
        fn position(_: Self) Offset {
            return 0;
        }
        fn advance(_: Self, _: usize) Self {
            unreachable;
        }
    };
}

fn Mutable(comptime Offset: type) type {
    return packed struct {
        const Self = @This();
        write: Offset,
        fn init() Self {
            return Self{ .write = 0 };
        }
        fn position(self: Self) Offset {
            return self.write;
        }
        fn advance(self: Self, size: Offset) Self {
            return Self{ .write = self.write + size };
        }
    };
}

//
//  Delete support.
//

fn NoDelete(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        fn init(_: usize) Self {
            return Self{};
        }

        fn delete(_: Offset) Self {
            unreachable;
        }

        fn reclaimable(_: Self) Offset {
            return 0;
        }
    };
}

fn Delete(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        fn init(_: usize) Self {
            return Self{};
        }

        fn delete(_: Offset) Self {
            unreachable;
        }

        fn reclaimable(_: Self) Offset {
            return 0;
        }
    };
}

//
//
//

fn noSizeSupport(comptime Offset: type, _: [*]const u8) Offset {
    unreachable;
}

//
//  Page implementation.
//

/// Page
fn Page(comptime LayoutType: type, comptime Write: type) type {
    return packed struct {
        const Self = @This();

        const Layout = LayoutType;
        const Offset = LayoutType.Align.Offset;
        const Index = LayoutType.Align.Index;

        const header = @sizeOf(Self);

        layout: Layout,
        len: Offset,
        write: Write,

        // Read methods

        fn constBytes(self: *const Self) []const u8 {
            const ptr: [*]const u8 = @ptrCast(self);
            return ptr[header..self.layout.cap()];
        }

        fn get(self: *const Self, index: Index) [*]const u8 {
            const data = self.constBytes();
            return @ptrCast(&data[Layout.Align.getIndex(data, index)]);
        }

        fn available(self: *const Self) usize {
            return self.layout.cap() - header - Layout.Align.sizeOfIndexes(self.len) - self.write.position();
        }

        // Write methods

        fn bytes(self: *Self) []u8 {
            const ptr: [*]u8 = @ptrCast(self);
            return ptr[header..self.layout.cap()];
        }

        fn add(self: *Self, value: [*]const u8, size: Offset) void {
            assert(size <= self.available());
            const buf = self.bytes();
            const pos = self.write.position();
            Layout.Align.setIndex(buf, self.len, pos);
            for (0..size) |i| buf[pos + i] = value[i];
            self.write = self.write.advance(size);
            self.len += 1;
        }
    };
}

test "Capacity" {
    const Cap8 = ByteAligned(8);
    var buf8 = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    try testing.expectEqual(7, Cap8.getIndex(&buf8, 0));
    try testing.expectEqual(@as(usize, 6), Cap8.getIndex(&buf8, 1));
    try testing.expectEqual(@as(usize, 0), Cap8.getIndex(&buf8, 7));

    Cap8.setIndex(&buf8, 0, 2);
    try testing.expectEqual(@as(usize, 2), Cap8.getIndex(&buf8, 0));
    try testing.expectEqual(@as(usize, 6), Cap8.getIndex(&buf8, 1));

    const Cap12 = ByteAligned(4096);
    var buf12 = [_]u8{ 42, 42 } ++ .{0} ** 4092 ++ [_]u8{ 1, 0 };
    try testing.expectEqual(@as(usize, 1), Cap12.getIndex(&buf12, 0));
}

test "Layout" {
    const data = [_]u8{ 3, 7, 6, 0, 0, 0, 2, 1 };
    const page1: *const Fixed(ByteAligned(8)) = @ptrCast(&data);
    const page2: *const Variable(ByteAligned(8)) = @ptrCast(&data);

    try testing.expectEqual(8, page1.cap());
    try testing.expectEqual(4, page2.cap());

    const Zero = Variable(ByteAligned(0));
    try testing.expectEqual(0, @sizeOf(Zero));
}

test "Read" {
    const data = [_]u8{ 3, 7, 6, 42, 0, 0, 2, 1 };
    const Cap8 = ByteAligned(8);
    const page: *const Page(Fixed(Cap8), Const(Cap8.Offset)) = @ptrCast(&data);
    try testing.expectEqual(@as(u8, 6), page.get(0)[0]);
    try testing.expectEqual(@as(u8, 42), page.get(1)[0]);
}

test "Write and Read Data" {
    const Cap16 = ByteAligned(16);
    const LayoutType = Fixed(Cap16);
    const WriteType = Mutable(Cap16.Offset);

    const PageType = Page(LayoutType, WriteType);

    var page_data = [_]u8{0} ** 256;
    var page: *PageType = @alignCast(@ptrCast(&page_data));

    // Data to write to the page
    const data1 = [_]u8{ 0x11, 0x22, 0x33 };
    const data2 = [_]u8{ 0xAA, 0xBB };

    // Write data1 to the page
    page.add(@ptrCast(&data1[0]), data1.len);

    // Write data2 to the page
    page.add(@ptrCast(&data2[0]), data2.len);

    // Read data back from the page
    const read_data1 = page.get(0)[0..data1.len];
    const read_data2 = page.get(1)[0..data2.len];

    // Verify that the read data matches the written data
    try testing.expect(std.mem.eql(u8, read_data1, &data1));
    try testing.expect(std.mem.eql(u8, read_data2, &data2));
}
