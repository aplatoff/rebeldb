// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT

const std = @import("std");
const page = @import("page.zig");

const Page = page.Page;
const StaticCapacity = page.StaticCapacity;
const ByteAligned = page.ByteAligned;
const Mutable = page.Mutable;

const Format = enum {
    u32_le,
};

pub fn Values(Storage: type) type {

    // const Index = Storage.Index;
    const Offset = Storage.Offset;

    return struct {
        inline fn alloc(storage: *Storage, fmt: Format, size: Offset) []u8 {
            const buf = storage.alloc(size + 1);
            buf[0] = @intFromEnum(fmt);
            return buf[1..];
        }

        pub fn writeUint(storage: *Storage, value: u32) void {
            std.mem.writeInt(u32, alloc(storage, Format.u32_le, 4)[0..4], value, std.builtin.Endian.little);
        }
    };
}

//

const testing = std.testing;

const PageSize = 0x10000;
const StaticPage = Page(StaticCapacity(PageSize, ByteAligned(u16, u16)), Mutable(u16));
const Typed = Values(StaticPage);

test "mutable static bytes u16 u16" {
    var data: [PageSize]u8 = undefined;
    const static_page: *StaticPage = @alignCast(@ptrCast(&data));

    try testing.expectEqual(@as(u16, 65530), static_page.init(PageSize));
    Typed.writeUint(static_page, 42);
    try testing.expectEqualDeep(&[_]u8{ 1, 0, 5, 0, 0, 42, 0, 0, 0 }, data[0..9]);
    std.debug.print("{any}\n", .{data[0..100]});
}

export fn writeUint(storage: *StaticPage, value: u32) void {
    Typed.writeUint(storage, value);
}
