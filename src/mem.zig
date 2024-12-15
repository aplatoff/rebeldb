// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MemoryFile = struct {
    const Self = @This();
    const Pages = std.ArrayList([*]u8);

    pages: Pages,
    page_size: usize,

    pub fn init(allocator: Allocator, page_size: usize) MemoryFile {
        return MemoryFile{
            .pages = Pages.init(allocator),
            .page_size = page_size,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.pages.items) |page| std.heap.page_allocator.free(page[0..self.page_size]);
        self.pages.deinit();
    }

    pub fn alloc(self: *Self) !struct { data: [*]u8, id: usize } {
        const page = try std.heap.page_allocator.alloc(u8, self.page_size);
        const data: [*]u8 = @ptrCast(page);
        const id = self.pages.items.len;
        try self.pages.append(data);
        return .{ .data = data, .id = id };
    }

    pub fn get(self: Self, id: usize) [*]u8 {
        return self.pages.items[id];
    }
};
