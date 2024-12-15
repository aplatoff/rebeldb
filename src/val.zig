// RebelDB™ © 2024 Huly Labs • https://hulylabs.com • SPDX-License-Identifier: MIT

const std = @import("std");
const heap = @import("heap.zig");

pub fn Typed(Storage: type) type {
    return struct {
        storage: *Storage,

        pub fn writeUint() void {}
    };
}
