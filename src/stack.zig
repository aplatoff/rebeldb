// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT

const std = @import("std");
const rebel = @import("rebel.zig");

const Allocator = std.mem.Allocator;

const Value = rebel.Value;

const Stack = struct {
    buf: []Value,
    len: usize,

    pub fn init(allocator: Allocator, size: usize) Stack {
        return Stack{ .buf = allocator.alloc(u32, size), .len = 0 };
    }

    pub fn deinit(self: Stack, allocator: Allocator) void {
        allocator.free(self.buf);
    }

    pub fn push(self: *Stack, value: Value) void {
        const len = self.len;
        self.buf[len] = value;
        self.len = len + 1;
    }

    pub fn pop(self: *Stack) Value {
        self.len -= 1;
        return self.buf[self.len];
    }

    pub fn peek(self: *Stack) Value {
        return self.buf[self.len - 1];
    }

    pub fn poke(self: *Stack, value: Value) void {
        self.buf[self.len - 1] = value;
    }
};

export fn add(stack: *Stack) void {
    const b = stack.pop();
    stack.poke(b + stack.peek());
}

export fn ops(stack: *Stack, a: Value, b: Value) void {
    stack.push(a);
    stack.push(b);
}
