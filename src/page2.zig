//
// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//

const std = @import("std");

const testing = std.testing;
const assert = std.debug.assert;

// We have many layers of abstraction here, but we're trying to keep it simple
// Layers are:
// 1. Capacity -- define types based on the capacity of the page
// 2. Layout -- define the layout of the page (fixed to capacity or variable length)
// 3. Read -- read values from the page
// 4. Write -- write values to the page
// 5. Delete -- delete values from the page

// 1. Capacity

fn createUnsigned(bitCount: u16) type {
    return @Type(.{
        .Int = .{ .signedness = .unsigned, .bits = bitCount },
    });
}

fn Capacity(comptime capacity: comptime_int) type {
    const capu64: usize = if (capacity == 0) 0 else capacity - 1;
    const bits_needed = @bitSizeOf(usize) - @clz(capu64);
    assert(bits_needed <= 16);

    const OffsetType = createUnsigned(bits_needed);
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

// 2. Layout

fn Fixed(comptime CapacityType: type) type {
    return packed struct {
        const Self = @This();
        const Capacity = CapacityType;

        fn init(_: *Self, _: usize) void {}

        fn cap(_: *const Self) usize {
            return CapacityType.Capacity;
        }
    };
}

fn Variable(comptime CapacityType: type) type {
    return packed struct {
        const Self = @This();
        const Capacity = CapacityType;

        last_byte: CapacityType.Offset,

        fn init(self: *Self, size: usize) void {
            self.last_byte = @intCast(size - 1);
        }

        fn cap(self: *const Self) usize {
            return self.last_byte + 1;
        }
    };
}

// 3. Page

fn Const(comptime Offset: type) type {
    return packed struct {
        const Self = @This();
        fn init(_: *Self, _: usize) void {}
        fn position(_: *Self) Offset {
            return 0;
        }
        fn advance(_: *Self, _: usize) Self {
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

fn Page(comptime LayoutType: type, comptime Write: type) type {
    return packed struct {
        const Self = @This();

        const Layout = LayoutType;
        const Offset = LayoutType.Capacity.Offset;
        const Index = LayoutType.Capacity.Index;

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
            return @ptrCast(&data[Layout.Capacity.getIndex(data, index)]);
        }

        fn available(self: *const Self) usize {
            return self.layout.cap() - header - Layout.Capacity.sizeOfIndexes(self.len) - self.write.position();
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
            Layout.Capacity.setIndex(buf, self.len, pos);
            for (0..size) |i| buf[pos + i] = value[i];
            self.write = self.write.advance(size);
            self.len += 1;
        }
    };
}

test "Capacity" {
    const Cap8 = Capacity(8);
    var buf8 = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    try testing.expectEqual(7, Cap8.getIndex(&buf8, 0));
    try testing.expectEqual(@as(usize, 6), Cap8.getIndex(&buf8, 1));
    try testing.expectEqual(@as(usize, 0), Cap8.getIndex(&buf8, 7));

    Cap8.setIndex(&buf8, 0, 2);
    try testing.expectEqual(@as(usize, 2), Cap8.getIndex(&buf8, 0));
    try testing.expectEqual(@as(usize, 6), Cap8.getIndex(&buf8, 1));

    const Cap12 = Capacity(4096);
    var buf12 = [_]u8{ 42, 42 } ++ .{0} ** 4092 ++ [_]u8{ 1, 0 };
    try testing.expectEqual(@as(usize, 1), Cap12.getIndex(&buf12, 0));
}

test "Layout" {
    const data = [_]u8{ 3, 7, 6, 0, 0, 0, 2, 1 };
    const page1: *const Fixed(Capacity(8)) = @ptrCast(&data);
    const page2: *const Variable(Capacity(8)) = @ptrCast(&data);

    try testing.expectEqual(8, page1.cap());
    try testing.expectEqual(4, page2.cap());

    const Zero = Variable(Capacity(0));
    try testing.expectEqual(0, @sizeOf(Zero));
}

test "Read" {
    const data = [_]u8{ 3, 7, 6, 42, 0, 0, 2, 1 };
    const Cap8 = Capacity(8);
    const page: *const Page(Fixed(Cap8), Const(Cap8.Offset)) = @ptrCast(&data);
    try testing.expectEqual(@as(u8, 6), page.get(0)[0]);
    try testing.expectEqual(@as(u8, 42), page.get(1)[0]);
}

test "Write and Read Data" {
    const mem = std.mem;

    const Cap16 = Capacity(256);
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
    try testing.expect(mem.eql(u8, read_data1, &data1));
    try testing.expect(mem.eql(u8, read_data2, &data2));
}
