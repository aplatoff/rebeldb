//! This module implements a variable-length integer encoding scheme optimized for
//! lexicographical ordering and performance. The encoding ensures that comparing
//! encoded bytes lexicographically produces the same ordering as comparing the
//! original integers.
//!
//! Encoding ranges:
//! - 0x00-0xF0:     1 byte  (0-240)
//! - 0xF1-0xF8:     2 bytes (241-2287)
//! - 0xF9:          3 bytes (2288-67823)
//! - 0xFA:          4 bytes (up to 16777215)
//! - 0xFB:          5 bytes (up to 4294967295)
//! - 0xFC:          6 bytes (up to 1099511627775)
//! - 0xFD:          7 bytes (up to 281474976710655)
//! - 0xFE:          8 bytes (up to 72057594037927935)
//! - 0xFF:          9 bytes (up to 18446744073709551615)

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

/// Maximum number of bytes needed to encode a u64
pub const max_encoded_length = 9;

/// Encodes a u64 value into a variable-length byte sequence that preserves
/// lexicographical ordering.
///
/// Args:
///     value: The unsigned 64-bit integer to encode
///     buffer: Destination buffer for encoded bytes (must be at least 9 bytes)
///
/// Returns: Number of bytes written to the buffer
pub fn encodeUint64(buffer: []u8, value: u64) usize {
    if (value <= 0xF0) {
        buffer[0] = @intCast(value);
        return 1;
    }

    if (value <= 0x8EF) {
        buffer[0] = @intCast(((value - 0xF0) >> 8) + 0xF1);
        buffer[1] = @intCast((value - 0xF0) & 0xFF);
        return 2;
    }

    if (value <= 0x108EF) {
        buffer[0] = 0xF9;
        buffer[1] = @intCast((value - 0x8F0) >> 8);
        buffer[2] = @intCast((value - 0x8F0) & 0xFF);
        return 3;
    }

    if (value <= 0xFFFFFF) {
        buffer[0] = 0xFA;
        buffer[1] = @intCast((value >> 16) & 0xFF);
        buffer[2] = @intCast((value >> 8) & 0xFF);
        buffer[3] = @intCast(value & 0xFF);
        return 4;
    }

    if (value <= 0xFFFFFFFF) {
        buffer[0] = 0xFB;
        buffer[1] = @intCast((value >> 24) & 0xFF);
        buffer[2] = @intCast((value >> 16) & 0xFF);
        buffer[3] = @intCast((value >> 8) & 0xFF);
        buffer[4] = @intCast(value & 0xFF);
        return 5;
    }

    if (value <= 0xFFFFFFFFFF) {
        buffer[0] = 0xFC;
        buffer[1] = @intCast((value >> 32) & 0xFF);
        buffer[2] = @intCast((value >> 24) & 0xFF);
        buffer[3] = @intCast((value >> 16) & 0xFF);
        buffer[4] = @intCast((value >> 8) & 0xFF);
        buffer[5] = @intCast(value & 0xFF);
        return 6;
    }

    if (value <= 0xFFFFFFFFFFFF) {
        buffer[0] = 0xFD;
        buffer[1] = @intCast((value >> 40) & 0xFF);
        buffer[2] = @intCast((value >> 32) & 0xFF);
        buffer[3] = @intCast((value >> 24) & 0xFF);
        buffer[4] = @intCast((value >> 16) & 0xFF);
        buffer[5] = @intCast((value >> 8) & 0xFF);
        buffer[6] = @intCast(value & 0xFF);
        return 7;
    }

    if (value <= 0xFFFFFFFFFFFFFF) {
        buffer[0] = 0xFE;
        buffer[1] = @intCast((value >> 48) & 0xFF);
        buffer[2] = @intCast((value >> 40) & 0xFF);
        buffer[3] = @intCast((value >> 32) & 0xFF);
        buffer[4] = @intCast((value >> 24) & 0xFF);
        buffer[5] = @intCast((value >> 16) & 0xFF);
        buffer[6] = @intCast((value >> 8) & 0xFF);
        buffer[7] = @intCast(value & 0xFF);
        return 8;
    }

    buffer[0] = 0xFF;
    buffer[1] = @intCast((value >> 56) & 0xFF);
    buffer[2] = @intCast((value >> 48) & 0xFF);
    buffer[3] = @intCast((value >> 40) & 0xFF);
    buffer[4] = @intCast((value >> 32) & 0xFF);
    buffer[5] = @intCast((value >> 24) & 0xFF);
    buffer[6] = @intCast((value >> 16) & 0xFF);
    buffer[7] = @intCast((value >> 8) & 0xFF);
    buffer[8] = @intCast(value & 0xFF);
    return 9;
}

pub fn bytesNeeded(value: u64) usize {
    if (value <= 0xF0) return 1;
    if (value <= 0x8EF) return 2;
    if (value <= 0x108EF) return 3;
    if (value <= 0xFFFFFF) return 4;
    if (value <= 0xFFFFFFFF) return 5;
    if (value <= 0xFFFFFFFFFF) return 6;
    if (value <= 0xFFFFFFFFFFFF) return 7;
    if (value <= 0xFFFFFFFFFFFFFF) return 8;
    return 9;
}

pub fn encodedSize(first_byte: u8) usize {
    if (first_byte <= 0xF0) return 1;
    if (first_byte <= 0xF8) return 2;

    return switch (first_byte) {
        0xF9 => 3,
        0xFA => 4,
        0xFB => 5,
        0xFC => 6,
        0xFD => 7,
        0xFE => 8,
        0xFF => 9,
        _ => 0,
    };
}

/// Decodes encoded value from a byte buffer. This is an unchecked version that assumes
/// the buffer contains valid encoded data with sufficient length.
///
/// Args:
///     buffer: Source buffer containing encoded bytes
///
/// Returns: A struct containing the decoded value and number of bytes read
pub fn decodeUint64(buffer: [*]const u8) struct { value: u64, size: usize } {
    const first = buffer[0];

    // Single byte values
    if (first <= 0xF0) {
        return .{ .value = first, .size = 1 };
    }

    // Two byte values
    if (first <= 0xF8) {
        const value = 0xF0 + (@as(u64, first - 0xF1) * 0x100) + buffer[1];
        return .{ .value = value, .size = 2 };
    }

    // Three byte values
    if (first == 0xF9) {
        const value = 0x8F0 + (@as(u64, buffer[1]) * 0x100) + buffer[2];
        return .{ .value = value, .size = 3 };
    }

    // Multi-byte values with fixed sizes
    const size: usize = switch (first) {
        0xFA => 4,
        0xFB => 5,
        0xFC => 6,
        0xFD => 7,
        0xFE => 8,
        0xFF => 9,
        else => unreachable,
    };

    var value: u64 = 0;
    var i: usize = 1;
    while (i < size) : (i += 1) {
        value = (value << 8) | buffer[i];
    }
    return .{ .value = value, .size = size };
}

test "encoding single byte values - comprehensive" {
    var buffer: [max_encoded_length]u8 = undefined;

    // Test all single-byte values
    var i: u64 = 0;
    while (i <= 0xF0) : (i += 1) {
        const size = encodeUint64(&buffer, i);
        try testing.expectEqual(@as(usize, 1), size);
        try testing.expectEqual(i, buffer[0]);

        const decoded = decodeUint64(&buffer);
        try testing.expectEqual(i, decoded.value);
        try testing.expectEqual(@as(usize, 1), decoded.size);
    }
}

test "encoding two byte values - comprehensive" {
    var buffer: [max_encoded_length]u8 = undefined;

    // Test range boundaries and some values in between
    const cases = [_]u64{
        0xF1, 0xF2, // Start of range
        500, 1000, 1500, // Middle values
        2286, 2287, // End of range
        // Edge cases
        241, 242, 243, // First few two-byte values
        0x8EE, 0x8EF, // Last two-byte values
    };

    for (cases) |value| {
        const size = encodeUint64(&buffer, value);
        try testing.expectEqual(@as(usize, 2), size);

        const decoded = decodeUint64(&buffer);
        try testing.expectEqual(value, decoded.value);
        try testing.expectEqual(@as(usize, 2), decoded.size);
    }
}

test "encoding three byte values - comprehensive" {
    var buffer: [max_encoded_length]u8 = undefined;

    const cases = [_]u64{
        2288, 2289, 2290, // Start of range
        10000, 30000, 50000, // Middle values
        67821, 67822, 67823, // End of range
        // Edge cases
        0x108EE, 0x108EF, // Maximum three-byte values
    };

    for (cases) |value| {
        const size = encodeUint64(&buffer, value);
        try testing.expectEqual(@as(usize, 3), size);

        const decoded = decodeUint64(&buffer);
        try testing.expectEqual(value, decoded.value);
        try testing.expectEqual(@as(usize, 3), decoded.size);
    }
}

test "encoding boundary values for all lengths" {
    var buffer: [max_encoded_length]u8 = undefined;

    const cases = [_]struct { value: u64, expected_size: usize }{
        // Single byte boundaries
        .{ .value = 0, .expected_size = 1 },
        .{ .value = 0xF0, .expected_size = 1 },
        // Two byte boundaries
        .{ .value = 0xF1, .expected_size = 2 },
        .{ .value = 0x8EF, .expected_size = 2 },
        // Three byte boundaries
        .{ .value = 0x8F0, .expected_size = 3 },
        .{ .value = 0x108EF, .expected_size = 3 },
        // Four byte
        .{ .value = 0x108F0, .expected_size = 4 },
        .{ .value = 0xFFFFFF, .expected_size = 4 },
        // Five byte
        .{ .value = 0x1000000, .expected_size = 5 },
        .{ .value = 0xFFFFFFFF, .expected_size = 5 },
        // Six byte
        .{ .value = 0x100000000, .expected_size = 6 },
        .{ .value = 0xFFFFFFFFFF, .expected_size = 6 },
        // Seven byte
        .{ .value = 0x10000000000, .expected_size = 7 },
        .{ .value = 0xFFFFFFFFFFFF, .expected_size = 7 },
        // Eight byte
        .{ .value = 0x1000000000000, .expected_size = 8 },
        .{ .value = 0xFFFFFFFFFFFFFF, .expected_size = 8 },
        // Nine byte
        .{ .value = 0x100000000000000, .expected_size = 9 },
        .{ .value = 0xFFFFFFFFFFFFFFFF, .expected_size = 9 },
    };

    for (cases) |case| {
        const size = encodeUint64(&buffer, case.value);
        try testing.expectEqual(case.expected_size, size);

        const decoded = decodeUint64(&buffer);
        try testing.expectEqual(case.value, decoded.value);
        try testing.expectEqual(case.expected_size, decoded.size);
    }
}

test "lexicographical ordering - comprehensive" {
    var buffer1: [max_encoded_length]u8 = undefined;
    var buffer2: [max_encoded_length]u8 = undefined;

    // Test boundaries between different byte lengths
    const boundary_pairs = [_]struct { a: u64, b: u64 }{
        // Single to two bytes
        .{ .a = 0xF0, .b = 0xF1 },
        // Two to three bytes
        .{ .a = 0x8EF, .b = 0x8F0 },
        // Three to four bytes
        .{ .a = 0x108EF, .b = 0x108F0 },
        // Four to five bytes
        .{ .a = 0xFFFFFF, .b = 0x1000000 },
        // Five to six bytes
        .{ .a = 0xFFFFFFFF, .b = 0x100000000 },
        // Six to seven bytes
        .{ .a = 0xFFFFFFFFFF, .b = 0x10000000000 },
        // Seven to eight bytes
        .{ .a = 0xFFFFFFFFFFFF, .b = 0x1000000000000 },
        // Eight to nine bytes
        .{ .a = 0xFFFFFFFFFFFFFF, .b = 0x100000000000000 },
    };

    // Test each boundary pair
    for (boundary_pairs) |pair| {
        const size1 = encodeUint64(&buffer1, pair.a);
        const size2 = encodeUint64(&buffer2, pair.b);

        // Verify lexicographical ordering
        try testing.expect(std.mem.lessThan(u8, buffer1[0..size1], buffer2[0..size2]));

        // Verify decode roundtrip
        const decoded1 = decodeUint64(@ptrCast(&buffer1[0]));
        const decoded2 = decodeUint64(@ptrCast(&buffer2[0]));
        try testing.expectEqual(pair.a, decoded1.value);
        try testing.expectEqual(pair.b, decoded2.value);
    }

    // Test sequential values within each encoding length
    const sequential_ranges = [_]struct { start: u64, count: u16 }{
        // Single byte ranges
        .{ .start = 0, .count = 10 }, // Start of range
        .{ .start = 0xE8, .count = 10 }, // End of single byte

        // Two byte ranges
        .{ .start = 0xF0, .count = 10 }, // Start of two bytes
        .{ .start = 0x8E8, .count = 10 }, // End of two bytes

        // Three byte ranges
        .{ .start = 0x8F0, .count = 10 }, // Start of three bytes
        .{ .start = 0x108E8, .count = 10 }, // End of three bytes

        // Four byte ranges
        .{ .start = 0x108F0, .count = 10 }, // Start of four bytes
        .{ .start = 0xFFFFF0, .count = 10 }, // End of four bytes

        // Five byte ranges
        .{ .start = 0x1000000, .count = 10 }, // Start of five bytes
        .{ .start = 0xFFFFFFF0, .count = 10 }, // End of five bytes

        // Six byte ranges
        .{ .start = 0x100000000, .count = 10 }, // Start of six bytes
        .{ .start = 0xFFFFFFFFF0, .count = 10 }, // End of six bytes

        // Seven byte ranges
        .{ .start = 0x10000000000, .count = 10 }, // Start of seven bytes
        .{ .start = 0xFFFFFFFFFFF0, .count = 10 }, // End of seven bytes

        // Eight byte ranges
        .{ .start = 0x1000000000000, .count = 10 }, // Start of eight bytes
        .{ .start = 0xFFFFFFFFFFFFF0, .count = 10 }, // End of eight bytes

        // Nine byte ranges
        .{ .start = 0x100000000000000, .count = 10 }, // Start of nine bytes
        .{ .start = 0xFFFFFFFFFFFFFFF0, .count = 10 }, // Near max value
    };

    // Test each sequential range
    for (sequential_ranges) |range| {
        var prev_value = range.start;
        var prev_size = encodeUint64(&buffer1, prev_value);

        var i: u16 = 1;
        while (i < range.count) : (i += 1) {
            const curr_value = range.start + i;
            const curr_size = encodeUint64(&buffer2, curr_value);

            // Verify lexicographical ordering
            try testing.expect(std.mem.lessThan(u8, buffer1[0..prev_size], buffer2[0..curr_size]));

            // Verify values are actually increasing
            try testing.expect(curr_value > prev_value);

            // Verify decode roundtrip
            const decoded1 = decodeUint64(@ptrCast(&buffer1[0]));
            const decoded2 = decodeUint64(@ptrCast(&buffer2[0]));
            try testing.expectEqual(prev_value, decoded1.value);
            try testing.expectEqual(curr_value, decoded2.value);

            // Move to next pair
            @memcpy(buffer1[0..curr_size], buffer2[0..curr_size]);
            prev_size = curr_size;
            prev_value = curr_value;
        }
    }

    // Test random jumps within and across encoding lengths
    const random_pairs = [_]struct { a: u64, b: u64 }{
        // Within single byte
        .{ .a = 0x00, .b = 0x01 },
        .{ .a = 0x7F, .b = 0x80 },

        // Within two bytes
        .{ .a = 0xF1, .b = 0xF2 },
        .{ .a = 0x8E0, .b = 0x8E1 },

        // Within three bytes
        .{ .a = 0x8F1, .b = 0x8F2 },
        .{ .a = 0x108E0, .b = 0x108E1 },

        // Across encoding lengths with gaps
        .{ .a = 0xE0, .b = 0x100 }, // Single to two bytes
        .{ .a = 0x8E0, .b = 0x9000 }, // Two to three bytes
        .{ .a = 0x108E0, .b = 0x200000 }, // Three to four bytes

        // Large value jumps
        .{ .a = 0x1000, .b = 0x1000000 },
        .{ .a = 0x1000000, .b = 0x100000000 },
        .{ .a = 0x100000000, .b = 0x10000000000 },
    };

    // Test each random pair
    for (random_pairs) |pair| {
        const size1 = encodeUint64(&buffer1, pair.a);
        const size2 = encodeUint64(&buffer2, pair.b);

        // Verify lexicographical ordering
        try testing.expect(std.mem.lessThan(u8, buffer1[0..size1], buffer2[0..size2]));

        // Verify decode roundtrip
        const decoded1 = decodeUint64(@ptrCast(&buffer1[0]));
        const decoded2 = decodeUint64(@ptrCast(&buffer2[0]));
        try testing.expectEqual(pair.a, decoded1.value);
        try testing.expectEqual(pair.b, decoded2.value);
    }
}
