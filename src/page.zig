// RebelDB™ • https://rebeldb.com • © 2024 Huly Labs • SPDX-License-Identifier: MIT
//
// This code defines a flexible Page abstraction for a database-like storage layer.
// Pages contain variable-sized values accessible by index. Values are appended forward
// from the start of the page data region, while their offsets (for indexing) are stored
// starting from the end of the page and growing backward as more values are inserted.
//
// Memory Layout Concept:
// ----------------------
// [ Page Metadata | Values Growing Forward --> ... ... <-- Indexes Growing Backward ]
//
// The indexing scheme:
// - Values are appended at increasing offsets from the start of the page.
// - Index offsets are stored at the end of the page and move backward as new values are added.
// - An index maps an index number (0, 1, 2, ...) to a stored offset (byte position) of a value.
//
// This design allows for flexible configuration of:
// - Offset storage (Byte aligned Offset integer types and Four-bit aligned).
// - Capacity handling (static vs. dynamic).
// - Mutability (read-only vs. mutable append).
//

const std = @import("std");
const assert = std.debug.assert;

/// ByteAligned indices -- for Offset values aligned to the byte boundary
pub fn ByteAligned(comptime OffsetType: type, comptime IndexType: type) type {
    return struct {
        const Offset = OffsetType;
        const Index = IndexType;

        inline fn getIndicesOffset(capacity: usize, len: Index) usize {
            return capacity - len * @sizeOf(Offset);
        }

        inline fn getOffset(page: []const u8, index: Index) Offset {
            const ofs = page.len - (index + 1) * @sizeOf(Offset);
            const ptr: *const Offset = @alignCast(@ptrCast(&page[ofs]));
            return ptr.*;
        }

        inline fn setOffset(page: []u8, index: Index, offset: Offset) void {
            const ofs = page.len - (index + 1) * @sizeOf(Offset);
            const ptr: *Offset = @alignCast(@ptrCast(&page[ofs]));
            ptr.* = offset;
        }
    };
}

/// NibbleAligned indices -- for Offset values aligned to four bits
pub fn NibbleAligned(comptime OffsetType: type, comptime IndexType: type) type {
    return struct {
        const Offset = OffsetType;
        const Index = IndexType;

        comptime {
            if (@bitSizeOf(Offset) % 4 != 0 or @bitSizeOf(Offset) % 8 == 0) {
                @compileError("Offset bit-size must be a multiple of 4 for NibbleAligned indexing and not a multiple of 8");
            }
        }

        const offset_bits = @bitSizeOf(Offset);
        const Aligned = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = offset_bits + 4 } });

        const offset_nibbles = offset_bits / 4;
        const mask: Aligned = (1 << offset_bits) - 1;

        /// Compute the byte offset where the indexing region starts.
        inline fn getIndicesOffset(capacity: usize, len: Index) usize {
            const total_nibbles = @as(usize, @intCast(len)) * offset_nibbles;
            const index_bytes = (total_nibbles + 1) / 2;
            return capacity - index_bytes;
        }

        /// Get the Offset stored at a given index.
        inline fn getOffset(page: []const u8, index: Index) Offset {
            const total_nibbles = page.len * 2;
            const start_nibble = total_nibbles - (index + 1) * offset_nibbles;

            const start_byte = start_nibble / 2;
            const nibble_in_byte = start_nibble % 2;

            //const aligned: *const Aligned = @alignCast(@ptrCast(&page[start_byte]));
            const buf = page[start_byte..][0..@sizeOf(Aligned)];
            const aligned = std.mem.readInt(Aligned, buf, std.builtin.Endian.little);
            const raw = aligned >> @intCast(nibble_in_byte << 2);

            // std.debug.print("get index: {d}, aligned: {x}, raw: {x}, mask: {d}, nib {d}, res: {d}\n", .{ index, aligned.*, raw, mask, nibble_in_byte, res });

            return @intCast(raw & mask);
        }

        // 8 - 4 3 - 0 .. 8 - 4 3 - 0

        /// Set the Offset at a given index.
        inline fn setOffset(page: []u8, index: Index, offset: Offset) void {
            const total_nibbles = page.len * 2;
            const start_nibble = total_nibbles - (index + 1) * offset_nibbles;

            const start_byte = start_nibble / 2;
            const nibble_in_byte = start_nibble % 2;

            //const aligned: *Aligned = @alignCast(@ptrCast(&page[start_byte]));
            const buf = page[start_byte..][0..@sizeOf(Aligned)];
            const aligned = std.mem.readInt(Aligned, buf, std.builtin.Endian.little);
            const shift = nibble_in_byte << 2;
            const raw = aligned & ~(mask << @intCast(shift));
            const shifted_offset: Aligned = @as(Aligned, @intCast(offset)) << @intCast(shift);
            //aligned.* = raw | shifted_offset;
            std.mem.writeInt(Aligned, buf, raw | shifted_offset, std.builtin.Endian.little);
        }
    };
}

// Capacity is a type that defines the maximum number of values that can be stored in the page.

pub fn Static(comptime cap: comptime_int) type {
    return packed struct {
        const Self = @This();

        inline fn init(_: usize) Self {
            return Self{};
        }

        inline fn capacity(_: Self) usize {
            return cap;
        }
    };
}

pub fn Dynamic(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        last_byte: Offset, // same as capacity - 1, since capacity may not fit in Offset type

        inline fn init(size: usize) Self {
            return Self{ .last_byte = @intCast(size - 1) };
        }

        inline fn capacity(self: Self) usize {
            return @as(usize, @intCast(self.last_byte)) + 1;
        }
    };
}

// Mutability

pub fn Mutable(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        value: Offset,

        inline fn init(offset: Offset) Self {
            return Self{ .value = offset };
        }

        inline fn available(self: Self, cap: Offset) Offset {
            return cap - self.value;
        }

        inline fn get(self: Self) Offset {
            return self.value;
        }
    };
}

pub fn Readonly(comptime Offset: type) type {
    return packed struct {
        const Self = @This();

        inline fn init(_: Offset) Self {
            return Self{};
        }

        inline fn available(_: Self, _: Offset) Offset {
            return 0;
        }

        inline fn get(_: Self) Offset {
            unreachable;
        }
    };
}

/// Page
pub fn Page(comptime Capacity: type, comptime Indices: type, comptime Mutability: type) type {
    return packed struct {
        const Self = @This();

        pub const Offset = Indices.Offset;
        pub const Index = Indices.Index;

        len: Index,
        cap: Capacity,
        mut: Mutability,
        // del: Delete,

        // returns bytes available for writing
        pub fn init(self: *Self, capacity: usize) Offset {
            self.len = 0;
            self.mut = Mutability.init(0);
            self.cap = Capacity.init(capacity);
            return self.available();
        }

        pub inline fn count(self: Self) Index {
            return self.len;
        }

        inline fn indices(self: *const Self, index: Index) usize {
            return Indices.getIndicesOffset(self.cap.capacity(), index);
        }

        pub inline fn available(self: *Self) Offset {
            const avail = self.mut.available(@intCast(self.indices(self.len + 1)));
            return if (avail > @sizeOf(Self)) avail - @sizeOf(Self) else 0;
        }

        // Read methods

        inline fn constValues(self: *const Self) []const u8 {
            const page: [*]const u8 = @ptrCast(self);
            return page[@sizeOf(Self)..self.cap.capacity()];
        }

        pub inline fn get(self: *const Self, index: Index) [*]const u8 {
            const page = self.constValues();
            return @ptrCast(&page[Indices.getOffset(page, index)]);
        }

        // Write methods

        inline fn values(self: *Self) []u8 {
            const page: [*]u8 = @ptrCast(self);
            return page[@sizeOf(Self)..self.cap.capacity()];
        }

        pub inline fn alloc(self: *Self, size: Offset) []u8 {
            const page = self.values();
            const offset = self.mut.get();
            Indices.setOffset(page, self.len, offset);
            const next = offset + size;
            self.mut = Mutability.init(next);
            self.len += 1;
            return page[offset..next];
        }
    };
}
