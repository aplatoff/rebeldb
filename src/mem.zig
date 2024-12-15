// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn MemoryFile(Size: comptime_int) type {
    return struct {
        pub const PageSize = Size;
        pub const PageId = u32;

        const Self = @This();
        const Pages = std.ArrayList([*]u8);

        pages: Pages,

        pub fn init(allocator: Allocator) Self {
            return Self{ .pages = Pages.init(allocator) };
        }

        pub fn deinit(self: Self) void {
            for (self.pages.items) |page| std.heap.page_allocator.free(page[0..PageSize]);
            self.pages.deinit();
        }

        pub fn alloc(self: *Self) !struct { data: [*]u8, id: PageId } {
            const page = try std.heap.page_allocator.alloc(u8, PageSize);
            const data: [*]u8 = @ptrCast(page);
            const id = self.pages.items.len;
            try self.pages.append(data);
            return .{ .data = data, .id = @intCast(id) };
        }

        pub fn get(self: Self, id: PageId) [*]u8 {
            return self.pages.items[id];
        }
    };
}
