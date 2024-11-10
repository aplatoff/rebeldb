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

pub fn Variable(comptime offset: type) type {
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

const ControlNone = packed struct {
    const Self = @This();
    fn initialized(_: *Self, _: usize) void {}
    fn allocated(_: *Self, _: usize) void {}
    fn deallocated(_: *Self, _: usize) void {}
};

pub fn Mutable(comptime Layout: type, comptime Ctrl: type) type {
    return packed struct {
        const Self = @This();
        const Ofs = Layout.Ofs;
        const Control = Ctrl;

        const HeaderSize = @sizeOf(Self) - @sizeOf(Layout);
        const SizeOfs = HeaderSize / @sizeOf(Ofs);

        comptime {
            assert(HeaderSize % @sizeOf(Ofs) == 0);
        }

        layout: Layout,
        offset_pos: Layout.Ofs,
        value_pos: Layout.Ofs,
        control: Control,

        fn init(self: *Self, page_size: usize, control: Control) void {
            self.layout.init(page_size);
            self.offset_pos = @intCast(self.const_offsets().len - 1);
            self.value_pos = 0;
            self.control = control;
            self.control.initialized(self.offset_pos);
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
            self.control.allocated(size);
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
        const Ofs = Layout.Ofs;
        const HeaderSize = @sizeOf(Self) - @sizeOf(Layout);
        const SizeOfs = HeaderSize / @sizeOf(Ofs);

        comptime {
            assert(HeaderSize % @sizeOf(Ofs) == 0);
        }

        layout: Layout,
        len: Layout.Ofs,

        fn const_bytes(self: *const Self) []const u8 {
            return self.layout.const_bytes()[HeaderSize..];
        }

        fn const_offsets(self: *const Self) []const Ofs {
            return self.layout.const_offsets()[SizeOfs..];
        }

        // since we can't add data here: we only can copy data at creation time
        fn init(_: *Self, _: usize, _: usize, _: ControlNone) void {
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
        const Control = Header.Control;

        header: Header,

        fn init(self: *Self, size: usize, control: Control) void {
            self.header.init(size, control);
        }

        fn get(self: *const Self, index: usize) [*]const u8 {
            const offsets = self.header.const_offsets();
            const offset = offsets[offsets.len - 1 - index];
            const bytes = self.header.const_bytes();
            return @ptrCast(&bytes[offset]);
        }
    };
}

test "Fixed u8" {
    const Layout = Page(Fixed(u8, 8));
    const data = [_]u8{ 0, 7, 6, 0, 0, 0, 2, 1 };
    const page: *const Layout = @ptrCast(&data);
    try testing.expectEqual(7, page.get(0)[0]);
    try testing.expectEqual(6, page.get(1)[0]);
}

test "Fixed u12" {
    const Layout = Page(Fixed(u12, 8));
    const data = [_]u8{ 0, 7, 6, 0, 1, 0, 2, 0 };
    const page: *const Layout = @ptrCast(&data);
    try testing.expectEqual(6, page.get(0)[0]);
    try testing.expectEqual(7, page.get(1)[0]);
}

test "Fixed u12 unaligned" {
    const Layout = Page(Fixed(u12, 8));
    const data = [_]u8{ 255, 0, 7, 6, 0, 1, 0, 2, 0 };
    const page: *const Layout = @ptrCast(&data[1]);
    try testing.expectEqual(6, page.get(0)[0]);
    try testing.expectEqual(7, page.get(1)[0]);
}

test "Variable u8" {
    const Layout = Page(Variable(u8));
    const data = [8]u8{ 8, 7, 6, 0, 0, 0, 1, 0 };
    const page: *const Layout = @alignCast(@ptrCast(&data));
    try testing.expectEqual(7, page.get(0)[0]);
    try testing.expectEqual(6, page.get(1)[0]);

    const data2 = [_]u8{ 255, 5, 7, 6, 0, 1, 255, 255, 255 };
    const page2: *const Layout = @alignCast(@ptrCast(&data2[1]));
    try testing.expectEqual(6, page2.get(0)[0]);
    try testing.expectEqual(7, page2.get(1)[0]);
}

test "Fixed + Mutable u8" {
    const Layout = Page(Mutable(Fixed(u8, 8), ControlNone));
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
    page.init(8, ControlNone{});
    try testing.expectEqual(5, data[0]);
    try testing.expectEqual(0, data[1]);
    try testing.expectEqual(11, page.get(0)[0]);
    try testing.expectEqual(10, page.get(1)[0]);
}
