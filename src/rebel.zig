// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT

const std = @import("std");

// All RebelDB™ values are 32-bit size. We do not store type of the value.
// RebelDB™ code interpret the value based on the context.

pub const Value = u32;

pub const PageId = u20;
pub const Offset = u12;
pub const Index = u12;

pub const Object = packed union {
    val: Value,
    addr: packed struct { index: Index, page: PageId },

    pub inline fn init(idx: Index, pg: PageId) Object {
        return Object{ .addr = .{ .index = idx, .page = pg } };
    }

    pub inline fn object(v: Value) Object {
        return Object{ .val = v };
    }

    pub inline fn value(self: Object) Value {
        return self.val;
    }

    pub inline fn index(self: Object) Index {
        return self.addr.index;
    }

    pub inline fn page(self: Object) Index {
        return self.addr.page;
    }
};

const testing = std.testing;

test "sizes" {
    try testing.expectEqual(@sizeOf(Value), @sizeOf(Object));
}
