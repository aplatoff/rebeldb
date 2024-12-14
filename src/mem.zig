// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT

const std = @import("std");
const pg = @import("page.zig");

const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const assert = std.debug.assert;

const StaticCapacity = pg.StaticCapacity;
const DynamicCapacity = pg.DynamicCapacity;
const ByteAligned = pg.ByteAligned;
const Mutable = pg.Mutable;

const Offset = u16; // 64KB max page size
const Index = u16;

const PageId = u32;

pub const Address = packed struct { page: PageId, index: Index };

// We're managing pages externally, they can be loaded from disk, etc.
// This is just a simple example of how to manage pages in memory.
pub const PageManager = struct {
    const Self = @This();

    const PageSize = 0x10000;
    const Page = pg.Page(StaticCapacity(PageSize, ByteAligned(Offset, Index)), Mutable(Offset));

    const Pages = std.ArrayList(*Page);

    const FreeSpace = struct { page: PageId, free: Offset };
    fn cmp(_: void, a: FreeSpace, b: FreeSpace) Order {
        if (a.free < b.free) return Order.lt;
        if (a.free > b.free) return Order.gt;
        // if (a.page < b.page) return Order.gt;
        // if (a.page > b.page) return Order.lt;
        return Order.eq;
    }
    const Heap = std.PriorityQueue(FreeSpace, void, cmp);

    pages: Pages,
    heap: Heap,
    page_allocator: Allocator,

    pub fn init(allocator: Allocator, page_allocator: Allocator) PageManager {
        return PageManager{
            .pages = Pages.init(allocator),
            .heap = Heap.init(allocator, {}),
            .page_allocator = page_allocator,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.pages.items) |page| self.page_allocator.destroy(page);
        self.pages.deinit();
        self.heap.deinit();
    }

    fn memUsage(self: *Self) void {
        var it = self.heap.iterator();
        var allocated: usize = 0;
        var free: usize = 0;
        while (it.next()) |space| {
            allocated += PageSize - 3 * @sizeOf(Offset);
            free += space.free;
        }
        std.debug.print("allocated: {d} bytes\nfree: {d} bytes\n", .{ allocated, free });
    }

    fn allocInPage(self: *Self, page: *Page, id: PageId, available: Offset, size: Offset) !Address {
        assert(size <= available);
        try self.heap.add(FreeSpace{ .page = id, .free = available - size });
        return Address{ .page = id, .index = page.alloc(size) };
    }

    fn allocNewPage(self: *Self, size: Offset) !Address {
        const page = try self.page_allocator.create(Page);
        const available = page.init(PageSize);
        const id: PageId = @intCast(self.pages.items.len);
        try self.pages.append(page);
        return self.allocInPage(page, id, available, size);
    }

    pub fn alloc(self: *Self, size: Offset) !Address {
        const free_space = self.heap.removeOrNull();
        return if (free_space) |space|
            if (space.free < size) self.allocNewPage(size) else self.allocInPage(self.pages.items[space.page], space.page, space.free, size)
        else
            self.allocNewPage(size);
    }
};

const testing = std.testing;

test "init" {
    var manager = PageManager.init(testing.allocator, testing.allocator);
    defer manager.deinit();
    const bytes1 = manager.alloc(10);
    std.debug.print("bytes: {any}\n", .{bytes1});
    // const bytes2 = manager.alloc(55);
    // std.debug.print("bytes: {any}\n", .{bytes2});
    manager.memUsage();
}
