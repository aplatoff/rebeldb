// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT

const std = @import("std");
const pg = @import("page.zig");
const mem = @import("mem.zig");

const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const assert = std.debug.assert;

const StaticCapacity = pg.StaticCapacity;
const DynamicCapacity = pg.DynamicCapacity;
const ByteAligned = pg.ByteAligned;
const Mutable = pg.Mutable;

const MemoryFile = mem.MemoryFile;

const Offset = u16; // 64KB max page size
const Index = u16;

const PageId = u32;
const PageSize = 0x10000;

pub const Address = packed struct { page: PageId, index: Index };

pub const Heap = struct {
    const Self = @This();

    const Page = pg.Page(StaticCapacity(PageSize, ByteAligned(Offset, Index)), Mutable(Offset));
    const PageDescriptor = struct { id: PageId, available: Offset };

    fn cmpFree(_: void, a: PageDescriptor, b: PageDescriptor) Order {
        return std.math.order(b.available, a.available);
    }

    const PQueue = std.PriorityQueue(PageDescriptor, void, cmpFree);

    heap: PQueue,
    pages: MemoryFile,

    pub fn init(allocator: Allocator, memory_file: MemoryFile) Heap {
        return Heap{
            .heap = PQueue.init(allocator, {}),
            .pages = memory_file,
        };
    }

    pub fn deinit(self: Self) void {
        self.pages.deinit();
        self.heap.deinit();
    }

    fn freeMem(self: *Self) usize {
        var free: usize = 0;
        var iter = self.heap.iterator();
        while (iter.next()) |page| free += page.available;
        return free;
    }

    fn allocNewPage(self: *Self) !PageDescriptor {
        const raw = try self.pages.alloc();
        const page: *Page = @alignCast(@ptrCast(raw.data));
        return PageDescriptor{ .id = @intCast(raw.id), .available = page.init(PageSize) };
    }

    fn getOrAllocPage(self: *Self, size: Offset) !PageDescriptor {
        return if (self.heap.peek()) |page|
            if (page.available < size)
                self.allocNewPage()
            else
                self.heap.remove()
        else
            self.allocNewPage();
    }

    pub fn alloc(self: *Self, buf: [*]const u8, size: Offset) !Address {
        var desc = try self.getOrAllocPage(size);
        const page: *Page = @alignCast(@ptrCast(self.pages.get(desc.id)));
        const address = Address{ .page = desc.id, .index = page.length() };
        page.push(buf, size);
        desc.available = page.available();
        try self.heap.add(desc);
        return address;
    }
};

const testing = std.testing;

test "init" {
    const mem_file = MemoryFile.init(testing.allocator, PageSize);
    var data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var manager = Heap.init(testing.allocator, mem_file);
    defer manager.deinit();
    const addr1 = try manager.alloc(&data, 10);
    std.debug.print("allocated address: {d}:{d}, free: {d}\n", .{ addr1.page, addr1.index, manager.freeMem() });
    const addr2 = try manager.alloc(&data, 2);
    std.debug.print("allocated address: {d}:{d}, free: {d}\n", .{ addr2.page, addr2.index, manager.freeMem() });
    for (0..1_000_000) |_| {
        _ = try manager.alloc(&data, 10);
        // std.debug.print("allocated address: {d}:{d}, free: {d}\n", .{ a.page, a.index, manager.freeMem() });
    }
    std.debug.print("free: {d}\n", .{manager.freeMem()});
}

// for assemly generation
// zig build-lib -O ReleaseSmall -femit-asm=page.asm src/mem.zig
export fn heapAlloc(heap: *Heap, buf: [*]const u8, size: Offset) void {
    _ = heap.alloc(buf, size) catch unreachable;
}
