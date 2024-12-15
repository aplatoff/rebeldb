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

pub fn Heap(comptime File: type, Offset: type, Index: type) type {
    return struct {
        const Self = @This();

        const PageSize = File.PageSize;
        const PageId = File.PageId;

        pub const Address = packed struct { page: PageId, index: Index };

        const Page = pg.Page(StaticCapacity(PageSize, ByteAligned(Offset, Index)), Mutable(Offset));
        const PageDescriptor = struct { available: Offset, id: PageId };

        fn cmpFree(_: void, a: PageDescriptor, b: PageDescriptor) Order {
            return std.math.order(b.available, a.available);
        }

        const PQueue = std.PriorityQueue(PageDescriptor, void, cmpFree);

        heap: PQueue,
        file: *File,

        pub fn init(allocator: Allocator, pages: *File) Self {
            return Self{
                .heap = PQueue.init(allocator, {}),
                .file = pages,
            };
        }

        pub fn deinit(self: Self) void {
            self.heap.deinit();
        }

        fn freeMem(self: *Self) usize {
            var free: usize = 0;
            var iter = self.heap.iterator();
            while (iter.next()) |page| free += page.available;
            return free;
        }

        fn allocNewPage(self: *Self) !PageDescriptor {
            const raw = try self.file.alloc();
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
            const page: *Page = @alignCast(@ptrCast(self.file.get(desc.id)));
            const address = Address{ .page = desc.id, .index = page.length() };
            page.push(buf, size);
            desc.available = page.available();
            try self.heap.add(desc);
            return address;
        }
    };
}

const testing = std.testing;
const MemoryFile = mem.MemoryFile;
const Mem64K = MemoryFile(0x10000);

test "init" {
    var data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var mem_file = Mem64K.init(testing.allocator);
    defer mem_file.deinit();
    var heap = Heap(Mem64K, u16, u16).init(testing.allocator, &mem_file);
    defer heap.deinit();
    const addr1 = try heap.alloc(&data, 10);
    std.debug.print("allocated address: {d}:{d}, free: {d}\n", .{ addr1.page, addr1.index, heap.freeMem() });
    const addr2 = try heap.alloc(&data, 2);
    std.debug.print("allocated address: {d}:{d}, free: {d}\n", .{ addr2.page, addr2.index, heap.freeMem() });
    for (0..1_000_000) |_| {
        _ = try heap.alloc(&data, 10);
        // std.debug.print("allocated address: {d}:{d}, free: {d}\n", .{ a.page, a.index, manager.freeMem() });
    }
    std.debug.print("free: {d}\n", .{heap.freeMem()});
}

// for assemly generation
// zig build-lib -O ReleaseSmall -femit-asm=page.asm src/mem.zig
export fn heapAlloc(heap: *Heap(Mem64K, u16, u16), buf: [*]const u8, size: u16) void {
    _ = heap.alloc(buf, size) catch unreachable;
}
