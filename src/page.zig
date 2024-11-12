//
// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//

const std = @import("std");

const testing = std.testing;
const assert = std.debug.assert;

fn createUnsigned(bitCount: u16) type {
    return @Type(.{
        .Int = .{ .signedness = .unsigned, .bits = bitCount },
    });
}

fn Capacity(comptime capacity: comptime_int) type {
    const cap: usize = capacity - 1;
    const bits_needed = @bitSizeOf(usize) - @clz(cap);
    assert(bits_needed <= 16);

    const OffsetType = createUnsigned(bits_needed);
    assert(capacity % @sizeOf(OffsetType) == 0);

    return packed struct {
        const Offset = OffsetType; // used to index any byte in the capacity space
        const Index = OffsetType; // used to index any index in the capacity space

        fn constIndexes(buffer: []const u8) []const Offset {
            assert(buffer.len % @sizeOf(Index) == 0);
            const idx: [*]const Index = @ptrCast(&buffer[0]);
            return idx[0 .. buffer.len / 2];
        }

        fn indexes(buffer: []u8) []Offset {
            assert(buffer.len % @sizeOf(Index) == 0);
            const idx: [*]Index = @ptrCast(&buffer[0]);
            return idx[0 .. buffer.len / 2];
        }

        fn sizeOfIndexes(len: usize) Offset {
            return @sizeOf(Index) * len;
        }

        fn setIndex(buffer: []u8, index: Index, offset: Offset) void {
            const idx = indexes(buffer);
            idx[idx.len - 1 - index] = offset;
        }

        fn getIndex(buffer: []const u8, index: Index) Offset {
            const idx = constIndexes(buffer);
            return idx[idx.len - 1 - index];
        }
    };
}

pub fn Fixed(comptime capacity: type) type {
    return packed struct {
        const Self = @This();
        const Cap = capacity;

        fn init(_: *Self, _: usize) void {}

        fn cap(_: *const Self) Cap.Ofs {
            return capacity.Capacity;
        }
    };
}

pub fn Variable(comptime capacity: type) type {
    return packed struct {
        const Self = @This();
        const Cap = capacity;

        last_byte: Cap.Ofs,

        fn init(self: *Self, size: usize) void {
            self.last_byte = @intCast(size - 1);
        }

        fn cap(self: *const Self) Cap.Ofs {
            return self.last_byte + 1;
        }
    };
}

const WithoutDelete = packed struct {
    const Self = @This();
    fn init(_: *Self) void {}
    fn available(_: *Self) usize {
        return 0;
    }
    fn onDeleted(_: *Self, _: usize) void {}
    fn onCompacted(_: *Self) void {}
};

fn WithDelete(comptime capacity: type) type {
    return packed struct {
        const Self = @This();
        const Ofs = capacity.Ofs;

        deleted: Ofs,

        fn init(self: *Self) void {
            self.deleted = 0;
        }
        fn available(self: *Self) usize {
            return self.deleted;
        }
        fn onDeleted(self: *Self, size: Ofs) void {
            self.deleted += size;
        }
        fn onCompacted(self: *Self) void {
            self.deleted = 0;
        }
    };
}

pub const NoSizeSupport = packed struct {
    const Self = @This();
    fn init(_: *Self) void {}
    fn size(_: *Self, _: [*]const u8) usize {
        unreachable;
    }
};

pub fn Mutable(comptime layout: type, comptime Delete: type, comptime Size: type) type {
    return packed struct {
        const Self = @This();
        const Layout = layout;
        const Offset = Layout.Cap.Offset;
        const Index = Layout.Cap.Index;

        const HeaderSize = @sizeOf(Self);

        layout: Layout,
        offset: Offset,
        len: Index,
        delete_support: Delete,
        size_support: Size,

        fn init(self: *Self, page_size: usize) usize {
            self.layout.init(page_size);
            self.delete_control.init();
            self.offset = 0;
            self.len = 0;
            return self.index_pos;
        }

        fn constBytes(self: *const Self) []u8 {
            const ptr: [*]u8 = @ptrCast(self);
            return ptr[HeaderSize..self.layout.cap()];
        }

        fn bytes(self: *Self) []u8 {
            const ptr: [*]u8 = @ptrCast(self);
            return ptr[HeaderSize..self.layout.cap()];
        }

        // fn const_indexes(self: *const Self) []const Index {
        //     return self.layout.const_indexes(self.const_bytes());
        // }

        // fn indexes(self: *const Self) []const Index {
        //     return self.layout.indexes(self.bytes());
        // }

        fn len(self: *const Self) usize {
            return self.len;
        }

        fn available(self: *const Self) usize {
            return self.layout.cap() - HeaderSize - self.offset - Layout.Cap.sizeOfIndexes(self.len);
        }

        fn ensureAvailable(self: *Self, size: usize) !void {
            if (size > self.available())
                if (size > self.available() + self.delete_control.available())
                    return error.OutOfMemory;
            self.compact();
            assert(size <= self.available());
        }

        // fn allocSlice(self: *Self, size: usize) !Self.Slice {
        //     try self.ensureAvailable(size);
        //     const end: Ofs = self.value_pos + size;
        //     const result = Self.Slice{ .begin = self.value_pos, .end = end };
        //     self.offsets()[self.offset_pos] = self.value_pos;
        //     self.value_pos = end;
        //     self.offset_pos -= 1;
        //     return result;
        // }

        // fn allocIndex(self: *Self, size: usize) !Self.Index {
        //     try self.ensureAvailable(size);
        //     const result = Self.Index{ .begin = self.value_pos, .index = @intCast(self.len()) };
        //     self.offsets()[self.offset_pos] = self.value_pos;
        //     self.value_pos += @intCast(size);
        //     self.offset_pos -= 1;
        //     return result;
        // }

        // fn get(self: *Self, index: usize) [*]const u8 {
        //     const buf = self.constBytes();
        //     const offset = Layout.Cap.getIndex(buf, index);
        //     return @ptrCast(&buf[offset]);
        // }

        fn add(self: *Self, value: [*]const u8, size: usize) !void {
            try self.ensureAvailable(size);
            const buf = self.bytes();
            Layout.Cap.setIndex(buf, self.len, self.offset);
            for (0..size) |i| buf[self.offset + i] = value[i];
            self.offset += @intCast(size);
            self.len += 1;
        }

        // const Iterator = struct {
        //     index: usize,
        //     page: *Self,

        //     fn next(self: *const Iterator) ?[*]const u8 {
        //         if (self.index >= self.page.len()) return null;
        //         const value = self.page.getValue(self.index);
        //         self.index += 1;
        //         return value;
        //     }
        // };

        // fn iterator(self: *const Self) Iterator {
        //     return Iterator{ .page = self, .index = 0 };
        // }

        fn compact(self: *Self) void {
            const buf = &self.bytes();
            var new_offset = 0;
            for (0..self.len) |i| {
                const cur_offset = Layout.Cap.getIndex(self.constBytes(), i);
                const cur_value = &self.constBytes()[cur_offset];
                const size = self.control.size(cur_value);
                if (new_offset == cur_offset) {
                    new_offset += size;
                } else {
                    assert(new_offset < cur_offset);
                    for (0..size) |j| buf[new_offset + j] = buf[cur_offset + j];
                    Layout.Cap.setIndex(buf, i, new_offset);
                }
            }
            assert(new_offset <= self.offset);
            self.offset = new_offset;
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

        fn init(self: *Self, page_size: usize) usize {
            self.layout.init(page_size);
            self.len = 0;
            return 0; // no free space available
        }

        fn len(self: *const Self) usize {
            return self.len;
        }

        fn available(_: *const Self) usize {
            return 0;
        }

        fn allocSlice(_: *Self, _: usize) !Self.Slice {
            return error.ImmutableValue;
        }

        fn allocIndex(_: *Self, _: usize) !Self.Index {
            return error.ImmutableValue;
        }
    };
}

pub fn Page(comptime Header: type) type {
    return packed struct {
        const Self = @This();

        header: Header,

        pub fn init(self: *Self, size: usize) usize {
            return self.header.init(size);
        }

        fn len(self: *const Self) usize {
            return self.header.len();
        }

        fn get(self: *const Self, index: usize) [*]const u8 {
            const offset = Header.Layout.Cap.getIndex(self.header.constBytes(), index);
            return @ptrCast(&self.header.constBytes()[offset]);
        }

        // fn allocSlice(self: *Self, size: usize) !Header.Slice {
        //     return self.header.allocSlice(size);
        // }

        // pub fn allocIndex(self: *Self, size: usize) !Header.Index {
        //     return self.header.allocIndex(size);
        // }

        // fn getSlice(self: *const Self, slice: Self.Slice) []u8 {
        //     return self.header.const_bytes()[slice.begin..slice.end];
        // }

        // fn delete(self: *Self, index: usize) void {
        //     assert(index < self.len());
        //     const offsets = self.header.offsets();
        //     self.offset_pos += 1;
        //     var offset = offsets.len - 1 - index;
        //     while (offset > self.offset_pos) : (offset -= 1) {
        //         offsets[offset] = offsets[offset - 1];
        //     }
        //     self.header.control.deleted(self.get(index));
        // }
    };
}

test "Fixed + Mutable u8" {
    const Layout = Page(Mutable(Fixed(Capacity(8)), WithoutDelete, NoSizeSupport));
    var data = [_]u8{
        255, // offset
        255, // len
        10,
        11,
        255,
        255,
        0,
        1,
    };
    var page: *Layout = @alignCast(@ptrCast(&data));
    try testing.expectEqual(5, page.init(8));
    try testing.expectEqual(0, data[0]);
    try testing.expectEqual(5, data[1]);
    try testing.expectEqual(11, page.get(0)[0]);
    try testing.expectEqual(10, page.get(1)[0]);
}
