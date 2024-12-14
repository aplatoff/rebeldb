const std = @import("std");
const encoding = @import("encoding.zig");
const assert = std.debug.assert;

const NintBase = 0x10;
const UintBase = 0x20;
const String = 0x30;
const Binary = 0x31;

inline fn encodeUint(buffer: []u8, comptime T: type, value: T, comptime base: u8) usize {
    var little: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &little, value, .little);
    var i: usize = @sizeOf(T);
    while (little[i - 1] == 0 and i > 0) : (i -= 1) {}
    for (1..i + 1) |j| buffer[j] = little[i - j];
    buffer[0] = base + @as(u8, @intCast(i));
    return i + 1;
}

inline fn decodeUint(buffer: [*]const u8, comptime T: type, comptime base: u8) T {
    const bytes = buffer[0] - base;
    assert(bytes < @sizeOf(T));
    var result: T = 0;
    for (1..bytes + 1) |i| result = (result << 8) | buffer[i];
    return result;
}

inline fn encodeBlob(buffer: []u8, value: []const u8, base: u8) usize {
    buffer[0] = base;
    const header_len = encoding.encodeUint64(buffer[1..], value.len) + 1;
    @memcpy(buffer[header_len .. header_len + value.len], value);
    return header_len + value.len;
}

inline fn decodeBlob(buffer: [*]const u8) []const u8 {
    const len = encoding.decodeUint64(@ptrCast(&buffer[1]));
    const header_len = 1 + len.size;
    return buffer[header_len .. header_len + len.value];
}

inline fn bytesNeededBlob(value: []const u8) usize {
    return encoding.bytesNeeded(value.len) + value.len + 1;
}

pub const Int = struct {
    pub const Type = isize;
    const Unsigned = usize;

    fn abs(value: Type) Unsigned {
        const mask = value >> (@bitSizeOf(Type) - 1);
        return @intCast((value + mask) ^ mask);
    }

    pub fn bytesNeeded(value: Type) usize {
        return (@bitSizeOf(Type) + 7 - @clz(abs(value))) / 8 + 1;
    }

    pub fn encode(buffer: []u8, value: Type) usize {
        return if (value < 0)
            encodeUint(buffer, Type, -value, NintBase)
        else
            encodeUint(buffer, Type, value, UintBase);
    }

    pub fn decode(buffer: [*]const u8) Type {
        return if (buffer[0] & UintBase == 0)
            -decodeUint(buffer, Type, NintBase)
        else
            decodeUint(buffer, Type, UintBase);
    }
};

pub const Str = struct {
    pub const Type = []const u8;

    pub fn bytesNeeded(value: Type) usize {
        return bytesNeededBlob(value);
    }

    pub fn encode(buffer: []u8, value: Type) usize {
        return encodeBlob(buffer, value, String);
    }

    pub fn decode(buffer: [*]const u8) Type {
        return decodeBlob(buffer);
    }
};

pub const Blob = struct {
    pub const Type = []const u8;

    pub fn bytesNeeded(value: Type) usize {
        return bytesNeededBlob(value);
    }

    pub fn encode(buffer: []u8, value: Type) usize {
        return encodeBlob(buffer, value, Binary);
    }

    pub fn decode(buffer: [*]const u8) Type {
        return decodeBlob(buffer);
    }
};

pub const Block = struct {
    pub const Type = []const u8;

    pub fn bytesNeeded(value: Type) usize {
        return bytesNeededBlob(value);
    }

    pub fn encode(buffer: []u8, value: Type) usize {
        return encodeBlob(buffer, value, Binary);
    }

    pub fn decode(buffer: [*]const u8) Type {
        return decodeBlob(buffer);
    }
};
