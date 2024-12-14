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
const PageSize = 0x10000;

pub const Address = packed struct { page: PageId, index: Index };

// We're managing pages externally, they can be loaded from disk, etc.
// This is just a simple example of how to manage pages in memory.
pub const PageManager = struct {
    const Self = @This();

    const Header = pg.Page(StaticCapacity(PageSize - @sizeOf(PageId), ByteAligned(Offset, Index)), Mutable(Offset));

    const Page = struct {
        id: PageId,
        data: Header,
        buf: [PageSize - @sizeOf(PageId) - @sizeOf(Header)]u8,
    };

    fn cmpFree(_: void, a: *Page, b: *Page) Order {
        return std.math.order(a.data.available(), b.data.available());
    }

    const Pages = std.ArrayList(*Page);
    const Heap = std.PriorityQueue(*Page, void, cmpFree);

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

    fn freeMem(self: *Self) usize {
        var free: usize = 0;
        var it = self.heap.iterator();
        while (it.next()) |page| free += page.data.available();
        return free;
    }

    fn allocNewPage(self: *Self) !*Page {
        const page = try self.page_allocator.create(Page);
        page.id = @intCast(self.pages.items.len);
        _ = page.data.init(PageSize - @sizeOf(PageId));
        try self.pages.append(page);
        return page;
    }

    fn getOrAllocPage(self: *Self, size: Offset) !*Page {
        return if (self.heap.peek()) |page|
            if (page.data.available() < size)
                self.allocNewPage()
            else
                self.heap.remove()
        else
            self.allocNewPage();
    }

    // pub fn allocEmpty(self: *Self, size: Offset) !Address {
    //     const page = try self.getOrAllocPage(size);
    //     const address = Address{ .page = page.id, .index = page.data.alloc(size) };
    //     try self.heap.add(page);
    //     return address;
    // }

    pub fn alloc(self: *Self, buf: [*]const u8, size: Offset) !Address {
        const page = try self.getOrAllocPage(size);
        const address = Address{ .page = page.id, .index = page.data.push(buf, size) };
        try self.heap.add(page);
        return address;
    }
};

const testing = std.testing;

test "init" {
    var data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var manager = PageManager.init(testing.allocator, testing.allocator);
    defer manager.deinit();
    const addr1 = try manager.alloc(&data, 10);
    std.debug.print("allocated address: {d}:{d}, free: {d}\n", .{ addr1.page, addr1.index, manager.freeMem() });
    const addr2 = try manager.alloc(&data, 20);
    std.debug.print("allocated address: {d}:{d}, free: {d}\n", .{ addr2.page, addr2.index, manager.freeMem() });
}

// for assemly generation
// zig build-lib -O ReleaseSmall -femit-asm=page.asm src/mem.zig
export fn heapAlloc(heap: *PageManager, buf: [*]const u8, size: Offset) void {
    _ = heap.alloc(buf, size) catch unreachable;
}
