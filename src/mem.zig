//
// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT
//

const std = @import("std");
const pg = @import("page.zig");
const heap = @import("heap2.zig");

const Allocator = std.mem.Allocator;
const Order = std.math.Order;

pub const PageId = u32;
pub const Offset = u16; // 64KB max page size
pub const Address = packed struct { offset: Offset, page: PageId };

// We're managing pages externally, they can be loaded from disk, etc.
// This is just a simple example of how to manage pages in memory.
pub const PageManager = struct {
    const Self = @This();

    const FreeSpace = struct { free: Offset, page: PageId };

    fn cmp(a: FreeSpace, b: FreeSpace) Order {
        if (a.free < b.free) return Order.lt;
        if (a.free > b.free) return Order.gt;
        if (a.page < b.page) return Order.gt;
        if (a.page > b.page) return Order.lt;
        return Order.eq;
    }

    const Heap = heap.PairingHeap(FreeSpace, cmp);
    heap: Heap,

    const Control = packed struct {
        heap: *Heap,
        page: PageId,

        fn initialized(self: *Self, size: usize) void {
            self.heap.insert(FreeSpace{ .free = size, .page = self.page });
        }
        fn allocated(self: *Self, size: usize) void {
            self.heap.update()
        }
        fn deallocated(_: *Self, _: usize) void {}
    };

    const PageSize = 0x10000;
    const Header = pg.Mutable(pg.Fixed(u16, PageSize), Control);
    const Page = pg.Page(Header);

    pub fn init(allocator: Allocator, pages: usize) !PageManager {
        std.debug.print("initializing heap: {d} bytes...\n", .{@sizeOf(Page) * pages});
        const heap = try allocator.alloc(Page, pages);
        for (0..pages) |i| {
            const ptr: *PageId = @ptrCast(&heap[i]);
            ptr.* = @intCast(i + 1);
        }
        return PageManager{ .heap = heap, .next = 0 };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.heap);
    }

    pub fn createAllocator(self: *Self) PageAllocator {
        return PageAllocator.init(self);
    }

    inline fn alloc(self: *Self) !PageId {
        const id = self.next;
        if (id == self.heap.len) return error.OutOfMemory;
        const ptr: *PageId = @ptrCast(&self.heap[id]);
        self.next = ptr.*;
        return @intCast(id);
    }

    inline fn free(self: *Self, page: PageId) void {
        const ptr: *PageId = @ptrCast(&self.heap[page]);
        ptr.* = self.next;
        self.next = page;
    }

    inline fn get(self: *const Self, page: PageId) *Page {
        return @ptrCast(&self.heap[page]);
    }
};

const testing = std.testing;

test "init" {
    var manager = try PageManager.init(testing.allocator, 4096);
    defer manager.deinit(testing.allocator);
    var allocator = &manager.createAllocator();
    const page = try allocator.alloc();
    try testing.expectEqual(0, page);
    allocator.free(page);
}
