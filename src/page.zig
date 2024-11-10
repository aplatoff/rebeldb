//
// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//

const std = @import("std");

const testing = std.testing;
const assert = std.debug.assert;

pub fn Fixed(comptime offset: type, comptime capacity: usize) type {
    comptime if (capacity % @sizeOf(offset) != 0)
        @compileError("Page size must be a multiple of the offset type size");

    return packed struct {
        const Self = @This();
        const Ofs = offset;
        const Index = packed struct { begin: Ofs, index: Ofs };
        const Slice = packed struct {
            begin: Ofs,
            end: Ofs,
            fn len(self: Slice) usize {
                return @intCast(self.end - self.begin);
            }
        };

        fn init(_: *Self, _: usize) void {}

        fn cap(_: *const Self) usize {
            return capacity;
        }
    };
}

pub fn Variable(comptime offset: type) type {
    return packed struct {
        const Self = @This();
        const Ofs = offset;

        last_byte: Ofs,

        fn init(self: *Self, size: usize) void {
            assert(size % @sizeOf(Ofs) == 0);
            self.last_byte = size - 1;
        }

        fn cap(self: *const Self) usize {
            return self.last_byte + 1;
        }
    };
}

pub const ControlNone = packed struct {
    const Self = @This();
    fn init(_: *Self) void {}
    fn released(_: *Self, _: usize) void {}
};

pub fn Mutable(comptime Layout: type, comptime Control: type) type {
    return packed struct {
        const Self = @This();
        const Ofs = Layout.Ofs;
        const Index = Layout.Index;
        const Slice = Layout.Slice;

        const HeaderSize = @sizeOf(Self) - @sizeOf(Layout);
        const HeaderSizeOfs = HeaderSize / @sizeOf(Ofs);

        comptime {
            assert(HeaderSize % @sizeOf(Ofs) == 0);
        }

        layout: Layout,
        value_pos: Layout.Ofs,
        offset_pos: Layout.Ofs,
        control: Control,

        fn init(self: *Self, page_size: usize) usize {
            self.layout.init(page_size);
            self.control.init();
            self.value_pos = 0;
            const data_end = self.last_offset();
            self.offset_pos = @intCast(data_end / @sizeOf(Ofs));
            return data_end;
        }

        fn last_offset(self: *const Self) usize {
            return self.layout.cap() - HeaderSize - @sizeOf(Ofs);
        }

        fn bytes(self: *Self) []u8 {
            const ptr: [*]u8 = @ptrCast(self);
            return ptr[HeaderSize..self.layout.cap()];
        }

        fn offsets(self: *Self) []Ofs {
            const ptr: [*]Ofs = @ptrCast(self);
            return ptr[HeaderSizeOfs .. self.layout.cap() / @sizeOf(Ofs)];
        }

        fn const_bytes(self: *const Self) []const u8 {
            const ptr: [*]const u8 = @ptrCast(self);
            return ptr[HeaderSize..self.layout.cap()];
        }

        fn const_offsets(self: *const Self) []const Ofs {
            const ptr: [*]align(1) const Ofs = @ptrCast(self);
            return ptr[HeaderSizeOfs .. self.layout.cap() / @sizeOf(Ofs)];
        }

        fn len(self: *const Self) usize {
            return self.last_offset() / @sizeOf(Ofs) - self.offset_pos;
        }

        fn available(self: *const Self) usize {
            return self.offset_pos * @sizeOf(Ofs) - self.value_pos;
        }

        fn allocSlice(self: *Self, size: usize) !Self.Slice {
            if (size > self.available()) return error.OutOfMemory;
            const end: Ofs = self.value_pos + size;
            const result = Self.Slice{ .begin = self.value_pos, .end = end };
            self.offsets()[self.offset_pos] = self.value_pos;
            self.value_pos = end;
            self.offset_pos -= 1;
            return result;
        }

        fn allocIndex(self: *Self, size: usize) !Self.Index {
            if (size > self.available()) return error.OutOfMemory;
            const result = Self.Index{ .begin = self.value_pos, .index = @intCast(self.len()) };
            self.offsets()[self.offset_pos] = self.value_pos;
            self.value_pos += @intCast(size);
            self.offset_pos -= 1;
            return result;
        }
    };
}

pub fn Const(comptime Layout: type) type {
    return packed struct {
        const Self = @This();
        const Ofs = Layout.Ofs;
        const HeaderSize = @sizeOf(Self) - @sizeOf(Layout);
        const SizeOfs = HeaderSize / @sizeOf(Ofs);

        comptime {
            assert(HeaderSize % @sizeOf(Ofs) == 0);
        }

        layout: Layout,
        len: Layout.Ofs,

        fn init(self: *Self, page_size: usize) usize {
            self.layout.init(page_size);
            self.len = 0;
            return 0; // no free space available
        }

        fn len(self: *const Self) usize {
            return self.len;
        }

        fn available(_: *const Self) usize {
            return 0;
        }

        fn allocSlice(_: *Self, _: usize) !Self.Slice {
            return error.ImmutableValue;
        }

        fn allocIndex(_: *Self, _: usize) !Self.Index {
            return error.ImmutableValue;
        }
    };
}

pub fn Page(comptime Header: type) type {
    return packed struct {
        const Self = @This();

        header: Header,

        pub fn init(self: *Self, size: usize) usize {
            return self.header.init(size);
        }

        fn allocSlice(self: *Self, size: usize) !Header.Slice {
            return self.header.allocSlice(size);
        }

        pub fn allocIndex(self: *Self, size: usize) !Header.Index {
            return self.header.allocIndex(size);
        }

        fn get(self: *const Self, index: usize) [*]const u8 {
            const offsets = self.header.const_offsets();
            const offset = offsets[offsets.len - 1 - index];
            const bytes = self.header.const_bytes();
            return @ptrCast(&bytes[offset]);
        }

        fn getSlice(self: *const Self, slice: Self.Slice) []u8 {
            return self.header.const_bytes()[slice.begin..slice.end];
        }
    };
}

// test "Fixed u8" {
//     const Layout = Page(Mutable(Fixed(u8, 8), ControlNone));
//     const data = [_]u8{ 0, 7, 6, 0, 0, 0, 2, 1 };
//     const page: *const Layout = @ptrCast(&data);
//     try testing.expectEqual(7, page.get(0)[0]);
//     try testing.expectEqual(6, page.get(1)[0]);
// }

// test "Fixed u12" {
//     const Layout = Page(Mutable(Fixed(u12, 8), ControlNone));
//     const data = [_]u8{ 0, 7, 6, 0, 1, 0, 2, 0 };
//     const page: *const Layout = @ptrCast(&data);
//     try testing.expectEqual(6, page.get(0)[0]);
//     try testing.expectEqual(7, page.get(1)[0]);
// }

// test "Fixed u12 unaligned" {
//     const Layout = Page(Mutable(Fixed(u12, 8), ControlNone));
//     const data = [_]u8{ 255, 0, 7, 6, 0, 1, 0, 2, 0 };
//     const page: *const Layout = @ptrCast(&data[1]);
//     try testing.expectEqual(6, page.get(0)[0]);
//     try testing.expectEqual(7, page.get(1)[0]);
// }

// test "Variable u8" {
//     const Layout = Page(Mutable(Variable(u12), ControlNone));
//     const data = [8]u8{ 8, 7, 6, 0, 0, 0, 1, 0 };
//     const page: *const Layout = @alignCast(@ptrCast(&data));
//     try testing.expectEqual(7, page.get(0)[0]);
//     try testing.expectEqual(6, page.get(1)[0]);

//     const data2 = [_]u8{ 255, 5, 7, 6, 0, 1, 255, 255, 255 };
//     const page2: *const Layout = @alignCast(@ptrCast(&data2[1]));
//     try testing.expectEqual(6, page2.get(0)[0]);
//     try testing.expectEqual(7, page2.get(1)[0]);
// }

test "Fixed + Mutable u8" {
    const Layout = Page(Mutable(Fixed(u8, 8), ControlNone));
    var data = [_]u8{
        255, // value
        255, // offset
        10,
        11,
        255,
        255,
        0,
        1,
    };
    var page: *Layout = @alignCast(@ptrCast(&data));
    try testing.expectEqual(5, page.init(8));
    try testing.expectEqual(0, data[0]);
    try testing.expectEqual(5, data[1]);
    try testing.expectEqual(11, page.get(0)[0]);
    try testing.expectEqual(10, page.get(1)[0]);
}
