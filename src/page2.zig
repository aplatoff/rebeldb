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
pub fn ByteAligned(comptime capacity: comptime_int, OffsetType: type) type {
    const cap: usize = if (capacity == 0) 0 else capacity - 1;
    const bits_needed = @bitSizeOf(usize) - @clz(cap);
    assert(bits_needed <= 64);

    // const OffsetType = createUnsigned((bits_needed + 7) / 8 * 8);
    // assert(capacity % @sizeOf(OffsetType) == 0);

    return struct {
        const Capacity = capacity;
        pub const Offset = OffsetType; // used to index any byte in the capacity space
        const Index = OffsetType; // used to index any index in the capacity space

        fn sizeOfIndexes(len: Offset) Offset {
            return @sizeOf(Index) * (len + 1);
        }

        fn setIndex(buf: []u8, index: Index, offset: Offset) void {
            const idx: [*]Index = @alignCast(@ptrCast(buf));
            // const last_index = last_byte / @sizeOf(Index);
            idx[buf.len / @sizeOf(Index) - 1 - index] = offset;
        }

        fn getIndex(buf: *u8, last_byte: Offset, index: Index) Offset {
            const idx: [*]const Index = @alignCast(@ptrCast(buf));
            const last_index = last_byte / @sizeOf(Index);
            return idx[last_index - index];
        }
    };
}

//
//  Page sizes. Fixed to capacity or variable length.
//

// Page can grow to the capacity of the alignment type.
pub fn Fixed(comptime AlignmentType: type) type {
    return packed struct {
        const Self = @This();
        const Offset = AlignmentType.Offset;
        const Index = AlignmentType.Index;
        const last_byte: Offset = AlignmentType.Capacity - 1;
        const last_index: Index = AlignmentType.Capacity / @sizeOf(Index) - 1;

        fn init(_: usize) Self {
            return Self{};
        }

        fn setIndex(self: *Self, index: Index, offset: Offset) void {
            const buf: [*]u8 = @ptrCast(self);
            const idx: [*]Index = @alignCast(@ptrCast(buf));
            idx[last_index - index] = offset;

            // AlignmentType.setIndex(buf[0..AlignmentType.Capacity], index, offset);
        }

        fn getIndex(self: *const Self, index: Index) Offset {
            const buf: *u8 = @ptrCast(self);
            return AlignmentType.getIndex(buf, last_byte, index);
        }

        fn space(_: *const Self, len: Index) Offset {
            return last_byte - AlignmentType.sizeOfIndexes(len) + 1;
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

pub fn Mutable(comptime Offset: type) type {
    return packed struct {
        const Self = @This();
        write: Offset,
        fn init(pos: Offset) Self {
            return Self{ .write = pos };
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

pub fn WithoutDelete(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        fn init() Self {
            return Self{};
        }

        fn deleted(_: [*]const u8) Self {
            unreachable;
        }

        fn reclaimable(_: Self) Offset {
            return 0;
        }

        fn size(_: [*]const u8) Offset {
            unreachable;
        }
    };
}

fn WithDelete(comptime Offset: type, comptime size_fn: fn (value: [*]const u8) Offset) type {
    return packed struct {
        const Self = @This();
        deleted_bytes: Offset,

        fn init() Self {
            return Self{ .deleted_bytes = 0 };
        }

        fn deleted(self: Self, value: [*]const u8) Self {
            return Self{ .deleted_bytes = self.deleted_bytes + size_fn(value) };
        }

        fn reclaimable(self: Self) Offset {
            return self.deleted_bytes;
        }

        fn size(value: [*]const u8) Offset {
            return size_fn(value);
        }
    };
}

//
//  Page implementation.
//

/// Page
pub fn Page(comptime LayoutType: type, comptime Write: type, comptime Delete: type) type {
    return packed struct {
        const Self = @This();

        const Layout = LayoutType;
        const Offset = LayoutType.Offset;
        const Index = LayoutType.Index;

        const header = @sizeOf(Self);

        len: Offset, // it's important to keep `len` and `write` at zero offset -- improves performance 4 times on M1!
        write: Write, // order of `len` and `write` can be swapped -- no changes on M1
        delete_support: Delete,
        layout: Layout,

        pub fn init(self: *Self, size: usize) usize {
            self.len = 0;
            self.layout = Layout.init(size);
            self.write = Write.init(0);
            self.delete_support = Delete.init();
            return self.layout.space(0) - header;
        }

        // Read methods

        fn constBytes(self: *const Self) []const u8 {
            const values: [*]const u8 = @ptrCast(self);
            return values[header..self.layout.space(self.len)];
        }

        fn get(self: *const Self, index: Index) [*]const u8 {
            return @ptrCast(&self.constBytes()[self.layout.getIndex(index)]);
        }

        fn immediatelyAvailable(self: *const Self, size: usize) bool {
            const new_value = header + self.write.position() + size;
            const new_index = self.layout.space(self.len + 1);
            return new_value <= new_index;
        }

        // Write methods

        fn bytes(self: *Self) []u8 {
            const values: [*]u8 = @ptrCast(self);
            return values[header..self.layout.space(self.len)];
        }

        pub fn available(self: *const Self, size: usize) bool {
            const new_value = header + self.write.position() + size - self.delete_support.reclaimable();
            const new_index = self.layout.space(self.len + 1);
            return new_value <= new_index;
        }

        fn ensureAvailable(self: *Self, size: usize) !void {
            if (self.immediatelyAvailable(size)) return;
            if (self.available(size)) {
                self.compact();
                assert(self.immediatelyAvailable(size));
            } else return error.OutOfMemory;
        }

        pub fn add(self: *Self, value: [*]const u8, size: Offset) void {
            // try self.ensureAvailable(size);
            const buf = self.bytes();
            const pos = self.write.position();
            self.layout.setIndex(self.len, pos);
            //
            for (0..size) |i| buf[pos + i] = value[i];
            self.write = self.write.advance(size);
            self.len += 1;
        }

        fn compact(self: *Self) void {
            const buf = self.bytes();
            var new_offset: Offset = 0;
            var i: Index = 0;
            while (i < self.len) : (i += 1) {
                const cur_offset = Layout.Align.getIndex(self.constBytes(), i);
                const cur_value = &self.constBytes()[cur_offset];
                const size = Delete.size(@ptrCast(cur_value));
                if (new_offset <= cur_offset) {
                    for (0..size) |j| buf[new_offset + j] = buf[cur_offset + j];
                    Layout.Align.setIndex(buf, i, new_offset);
                } else assert(new_offset == cur_offset);
                new_offset += size;
            }
            assert(new_offset <= self.write.position());
            self.write = Write.init(new_offset);
        }

        fn delete(self: *Self, index: Index) void {
            self.delete_support = self.delete_support.deleted(self.get(index));
            const buf = self.bytes();
            var i = index;
            self.len -= 1;
            while (i < self.len) : (i += 1)
                Layout.Align.setIndex(buf, i, Layout.Align.getIndex(buf, i + 1));
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
    const page: *const Page(Fixed(Cap8), Const(Cap8.Offset), WithoutDelete(Cap8.Offset)) = @ptrCast(&data);
    try testing.expectEqual(@as(u8, 6), page.get(0)[0]);
    try testing.expectEqual(@as(u8, 42), page.get(1)[0]);
}

test "Write and Read Data" {
    const Cap16 = ByteAligned(16);
    const LayoutType = Fixed(Cap16);
    const WriteType = Mutable(Cap16.Offset);

    const PageType = Page(LayoutType, WriteType, WithoutDelete(Cap16.Offset));

    var page_data = [_]u8{0} ** 256;
    var page: *PageType = @alignCast(@ptrCast(&page_data));

    // Data to write to the page
    const data1 = [_]u8{ 0x11, 0x22, 0x33 };
    const data2 = [_]u8{ 0xAA, 0xBB };

    // Write data1 to the page
    try page.add(@ptrCast(&data1[0]), data1.len);

    // Write data2 to the page
    try page.add(@ptrCast(&data2[0]), data2.len);

    // Read data back from the page
    const read_data1 = page.get(0)[0..data1.len];
    const read_data2 = page.get(1)[0..data2.len];

    // Verify that the read data matches the written data
    try testing.expect(std.mem.eql(u8, read_data1, &data1));
    try testing.expect(std.mem.eql(u8, read_data2, &data2));
}

fn constValue(comptime T: type, result: T) type {
    return struct {
        fn size(_: [*]const u8) T {
            return result;
        }
    };
}

test "Delete and Compact Functionality" {
    const Cap16 = ByteAligned(16);
    const LayoutType = Fixed(Cap16);
    const WriteType = Mutable(Cap16.Offset);
    const DeleteType = WithDelete(Cap16.Offset, constValue(Cap16.Offset, 2).size);

    const PageType = Page(LayoutType, WriteType, DeleteType);

    var page_data = [_]u8{0} ** 256;
    var page: *PageType = @alignCast(@ptrCast(&page_data));

    _ = page.init(256);

    // Data to write to the page
    const data1 = [_]u8{ 0x1, 0x2 };
    const data2 = [_]u8{ 0x3, 0x4 };
    const data3 = [_]u8{ 0x5, 0x6 };
    const data4 = [_]u8{ 0x7, 0x8 };

    // Write data to the page
    try page.add(@ptrCast(&data1), data1.len);
    try page.add(@ptrCast(&data2), data2.len);
    try page.add(@ptrCast(&data3), data3.len);
    try page.add(@ptrCast(&data4), data4.len);
    try testing.expectEqual(4, page.len);

    page.delete(1);
    try testing.expectEqual(3, page.len);

    // Read data back from the page
    const read_data1 = page.get(0)[0..data1.len];
    const read_data2 = page.get(1)[0..data3.len];
    const read_data3 = page.get(2)[0..data4.len];

    // Verify that the read data matches the expected data
    try testing.expect(std.mem.eql(u8, read_data1, &data1));
    try testing.expect(std.mem.eql(u8, read_data2, &data3));
    try testing.expect(std.mem.eql(u8, read_data3, &data4));

    page.compact();

    // Read data back from the page
    const c_data1 = page.get(0)[0..data1.len];
    std.debug.print("read_data1: {any}\n", .{c_data1});
    const c_data2 = page.get(1)[0..data3.len];
    std.debug.print("read_data2: {any}\n", .{c_data2});
    const c_data3 = page.get(2)[0..data4.len];
    std.debug.print("read_data3: {any}\n", .{c_data3});

    // Verify that the read data matches the expected data
    try testing.expect(std.mem.eql(u8, c_data1, &data1));
    try testing.expect(std.mem.eql(u8, c_data2, &data3));
    try testing.expect(std.mem.eql(u8, c_data3, &data4));
}
