//
// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//

const std = @import("std");

const testing = std.testing;
const assert = std.debug.assert;

pub fn FLayout(comptime offset: type, comptime capacity: usize) type {
    comptime if (capacity % @sizeOf(offset) != 0)
        @compileError("Page size must be a multiple of the offset type size");

    return packed struct {
        const Self = @This();
        const Ofs = offset;

        fn init(_: *Self, _: usize) void {}

        fn bytes(self: *Self) []u8 {
            const ptr: [*]u8 = @ptrCast(self);
            return ptr[0..capacity];
        }

        fn offsets(self: *Self) []Ofs {
            const ptr: [*]Ofs = @ptrCast(self);
            return ptr[0 .. capacity / @sizeOf(offset)];
        }

        fn const_bytes(self: *const Self) []const u8 {
            const ptr: [*]const u8 = @ptrCast(self);
            return ptr[0..capacity];
        }

        fn const_offsets(self: *const Self) []const Ofs {
            const ptr: [*]const Ofs = @alignCast(@ptrCast(self));
            return ptr[0 .. capacity / @sizeOf(offset)];
        }
    };
}

pub fn VLayout(comptime offset: type) type {
    return packed struct {
        const Self = @This();
        const Ofs = offset;

        page_size: Ofs,

        fn init(self: *Self, size: usize) void {
            assert(size % @sizeOf(Ofs) == 0);
            self.page_size = size;
        }

        fn bytes(self: *Self) []u8 {
            const ptr: [*]u8 = @ptrCast(self);
            return ptr[@sizeOf(Self)..self.page_size];
        }

        fn offsets(self: *Self) []Ofs {
            const ptr: [*]Ofs = @ptrCast(self);
            return ptr[@sizeOf(Self) .. self.page_size / @sizeOf(offset)];
        }

        fn const_bytes(self: *const Self) []const u8 {
            const ptr: [*]const u8 = @ptrCast(self);
            return ptr[@sizeOf(Self)..self.page_size];
        }

        fn const_offsets(self: *const Self) []const Ofs {
            const ptr: [*]const Ofs = @alignCast(@ptrCast(self));
            return ptr[@sizeOf(Self) .. self.page_size / @sizeOf(offset)];
        }
    };
}

pub fn Grow(comptime Layout: type, comptime Delete: type) type {
    return packed struct {
        const Self = @This();
        const Ofs = Layout.Ofs;
        const HeaderSize = @sizeOf(Self) - @sizeOf(Layout);
        const SizeOfs = HeaderSize / @sizeOf(Ofs);

        comptime {
            assert(HeaderSize % @sizeOf(Ofs) == 0);
        }

        layout: Layout,
        offset_pos: Layout.Ofs,
        value_pos: Layout.Ofs,
        delete: Delete,

        fn init(self: *Self, page_size: usize) void {
            self.layout.init(page_size);
            self.offset_pos = @intCast(self.layout.const_offsets().len - 1);
            self.value_pos = HeaderSize;
        }

        fn bytes(self: *Self) []u8 {
            return self.layout.bytes()[HeaderSize..];
        }

        fn offsets(self: *Self) []Ofs {
            return self.layout.offsets()[SizeOfs..];
        }

        fn const_bytes(self: *const Self) []const u8 {
            return self.layout.const_bytes()[HeaderSize..];
        }

        fn const_offsets(self: *const Self) []const Ofs {
            return self.layout.const_offsets()[SizeOfs..];
        }

        fn available(self: *const Self) usize {
            return self.offset_pos - self.value_pos;
        }

        fn alloc(self: *Self, size: usize) []u8 {
            const result = self.bytes()[self.value_pos .. self.value_pos + size];
            self.bytes()[self.offset_pos] = self.value_pos;
            self.value_pos += @intCast(size);
            self.offset_pos -= 1;
            return result;
        }

        fn len(self: *const Self) usize {
            return self.const_offsets().len - 1 - self.offset_pos;
        }
    };
}

pub fn Const(comptime Layout: type) type {
    return packed struct {
        const Self = @This();

        layout: Layout,
        len: Layout.Ofs,

        fn layout(self: *Self) *Layout {
            return self.layout;
        }

        // since we can't add data here: we only can copy data at creation time
        fn init(_: *Self, _: usize, _: usize) void {
            unreachable;
        }

        fn available(_: *const Self) usize {
            return 0;
        }

        fn alloc(_: *Self, _: usize) []u8 {
            unreachable;
        }

        fn len(self: *const Self) usize {
            return self.len;
        }
    };
}

pub fn Page(comptime Header: type) type {
    return packed struct {
        const Self = @This();

        header: Header,

        fn init(self: *Self, size: usize) void {
            self.header.init(size);
        }

        fn get(self: *const Self, index: usize) [*]const u8 {
            const offsets = self.header.const_offsets();
            const offset = offsets[offsets.len - 1 - index];
            const bytes = self.header.const_bytes();
            return @ptrCast(&bytes[offset]);
        }
    };
}

test "FLayout u8" {
    const Layout = Page(FLayout(u8, 8));
    const data = [_]u8{ 0, 7, 6, 0, 0, 0, 2, 1 };
    const page: *const Layout = @ptrCast(&data);
    try testing.expectEqual(7, page.get(0)[0]);
    try testing.expectEqual(6, page.get(1)[0]);
}

test "FLayout u12" {
    const Layout = Page(FLayout(u12, 8));
    const data = [_]u8{ 0, 7, 6, 0, 1, 0, 2, 0 };
    const page: *const Layout = @ptrCast(&data);
    try testing.expectEqual(6, page.get(0)[0]);
    try testing.expectEqual(7, page.get(1)[0]);
}

test "FLayout u12 unaligned" {
    const Layout = Page(FLayout(u12, 8));
    const data = [_]u8{ 255, 0, 7, 6, 0, 1, 0, 2, 0 };
    const page: *const Layout = @ptrCast(&data[1]);
    try testing.expectEqual(6, page.get(0)[0]);
    try testing.expectEqual(7, page.get(1)[0]);
}

test "VLayout u8" {
    const Layout = Page(VLayout(u8));
    const data = [8]u8{ 8, 7, 6, 0, 0, 0, 1, 0 };
    const page: *const Layout = @alignCast(@ptrCast(&data));
    try testing.expectEqual(7, page.get(0)[0]);
    try testing.expectEqual(6, page.get(1)[0]);

    const data2 = [_]u8{ 255, 5, 7, 6, 0, 1, 255, 255, 255 };
    const page2: *const Layout = @alignCast(@ptrCast(&data2[1]));
    try testing.expectEqual(6, page2.get(0)[0]);
    try testing.expectEqual(7, page2.get(1)[0]);
}

test "FLayout + Grow" {
    const Layout = Page(Grow(FLayout(u8, 8), void));
    var data = [_]u8{
        255, // offset
        255, // value
        10,
        11,
        255,
        255,
        0,
        1,
    };
    var page: *Layout = @alignCast(@ptrCast(&data));
    page.init(8);
    try testing.expectEqual(7, data[0]);
    try testing.expectEqual(2, data[1]);
    try testing.expectEqual(11, page.get(0)[0]);
    try testing.expectEqual(10, page.get(1)[0]);
}
