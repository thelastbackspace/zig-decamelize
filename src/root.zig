//! Convert camelCase identifiers to separator-separated identifiers:
//! `unicornRainbow` → `unicorn_rainbow`, with configurable separator.
//!
//! A behavior-faithful Zig port of the npm package
//! [`decamelize`](https://github.com/sindresorhus/decamelize) (v6.0.1).
//! The upstream test suite is ported in `tests.zig`; see README.md for
//! API notes and the intentional divergences from upstream.

const std = @import("std");
const uni = @import("unicode_data.zig");

/// Options mirroring the upstream package.
pub const Options = struct {
    /// Inserted between words. Defaults to `_`.
    separator: []const u8 = "_",
    /// Keep runs of uppercase letters intact:
    /// `myURLString` → `my_URL_string` instead of `my_ur_lstring`.
    preserve_consecutive_uppercase: bool = false,
};

pub const Error = std.mem.Allocator.Error;

/// Convert a camelCase string to a separated string. Caller owns the
/// returned memory.
///
/// A separator is inserted at each lowercase-letter-or-digit →
/// uppercase-letter transition, and before the last uppercase letter of
/// an acronym that is followed by lowercase letters. By default the
/// result is lowercased (`URLString` → `url_string`); with
/// `preserve_consecutive_uppercase` acronym runs are kept
/// (`URLString` → `URL_string`).
pub fn decamelize(allocator: std.mem.Allocator, text: []const u8, options: Options) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const input = try decode(a, text);

    if (input.len < 2) {
        if (options.preserve_consecutive_uppercase) return allocator.dupe(u8, text);
        var single = std.ArrayList(u21).empty;
        defer single.deinit(a);
        for (input) |c| try single.append(a, uni.toLower(c));
        return encode(allocator, single.items, &.{});
    }

    // Pass 1: insert a separator between every
    // (lowercase letter | digit) → uppercase letter transition.
    const sep = try decode(a, options.separator);

    var work = std.ArrayList(u21).empty;
    defer work.deinit(a);
    try work.append(a, input[0]);
    for (input[1..], 1..) |c, i| {
        const prev = input[i - 1];
        if ((uni.isLowercaseLetter(prev) or isAsciiDigit(prev)) and uni.isUppercaseLetter(c)) {
            try work.appendSlice(a, sep);
        }
        try work.append(a, c);
    }

    if (options.preserve_consecutive_uppercase) {
        return encode(allocator, try preserveUppercase(a, work.items, sep), &.{});
    }

    // Split the last uppercase letter of an acronym away from a
    // following lowercase sequence: `my_URLstring` → `my_UR_Lstring`.
    var split = std.ArrayList(u21).empty;
    defer split.deinit(a);
    const items = work.items;
    var i: usize = 0;
    while (i < items.len) {
        if (i + 2 < items.len and
            uni.isUppercaseLetter(items[i]) and
            uni.isUppercaseLetter(items[i + 1]) and
            uni.isLowercaseLetter(items[i + 2]))
        {
            try split.append(a, items[i]);
            try split.appendSlice(a, sep);
            var k = i + 1;
            try split.append(a, items[k]);
            k += 1;
            while (k < items.len and uni.isLowercaseLetter(items[k])) : (k += 1) {
                try split.append(a, items[k]);
            }
            i = k;
        } else {
            try split.append(a, items[i]);
            i += 1;
        }
    }

    for (split.items) |*c| c.* = uni.toLower(c.*);
    return encode(allocator, split.items, &.{});
}

fn isAsciiDigit(c: u21) bool {
    return c >= '0' and c <= '9';
}

/// The `preserveConsecutiveUppercase` path: lowercase isolated
/// uppercase letters, then split an uppercase run from a following
/// uppercase-plus-lowercase sequence without destroying the run.
fn preserveUppercase(a: std.mem.Allocator, input: []const u21, sep: []const u21) Error![]const u21 {
    var buf1 = std.ArrayList(u21).empty;
    defer buf1.deinit(a);

    // Lowercase single uppercase letters (or digits, which map to
    // themselves) that are surrounded by non-uppercase, non-digit
    // characters — they are one-letter words, not acronyms.
    for (input, 0..) |c, i| {
        const is_word_char = uni.isUppercaseLetter(c) or isAsciiDigit(c);
        if (is_word_char) {
            const prev_ok = i == 0 or
                !(uni.isUppercaseLetter(input[i - 1]) or isAsciiDigit(input[i - 1]));
            const next_ok = i + 1 == input.len or
                !(uni.isUppercaseLetter(input[i + 1]) or isAsciiDigit(input[i + 1]));
            if (prev_ok and next_ok) {
                try buf1.append(a, uni.toLower(c));
                continue;
            }
        }
        try buf1.append(a, c);
    }

    // Split the boundary between an uppercase run and the last
    // uppercase letter that starts a lowercase sequence, preserving and
    // keeping uppercase everything before the boundary:
    // `data_for_USACounties` → `data_for_USA_counties`.
    var buf2 = std.ArrayList(u21).empty;
    defer buf2.deinit(a);
    const items = buf1.items;
    var i: usize = 0;
    while (i < items.len) {
        if (!uni.isUppercaseLetter(items[i]) or
            (i > 0 and uni.isUppercaseLetter(items[i - 1])))
        {
            try buf2.append(a, items[i]);
            i += 1;
            continue;
        }

        // Greedy uppercase run starting at i.
        var run_end = i;
        while (run_end < items.len and uni.isUppercaseLetter(items[run_end])) run_end += 1;

        // The regex backtracks from the longest run, so look for the
        // latest split point s with an uppercase at s followed by a
        // lowercase letter.
        var split: ?usize = null;
        var cand = run_end - 1;
        while (cand > i) : (cand -= 1) {
            if (cand + 1 < items.len and uni.isLowercaseLetter(items[cand + 1])) {
                split = cand;
                break;
            }
        }

        if (split) |sp| {
            try buf2.appendSlice(a, items[i..sp]);
            try buf2.appendSlice(a, sep);
            var k = sp;
            while (k < items.len and (k == sp or uni.isLowercaseLetter(items[k]))) : (k += 1) {
                try buf2.append(a, uni.toLower(items[k]));
            }
            i = k;
        } else {
            try buf2.appendSlice(a, items[i..run_end]);
            i = run_end;
        }
    }
    return buf2.toOwnedSlice(a);
}

fn decode(a: std.mem.Allocator, input: []const u8) Error![]u21 {
    var out = std.ArrayList(u21).empty;
    errdefer out.deinit(a);
    var view = std.unicode.Utf8View.initUnchecked(input);
    var it = view.iterator();
    while (it.nextCodepoint()) |c| try out.append(a, c);
    return out.toOwnedSlice(a);
}

fn encode(allocator: std.mem.Allocator, body: []const u21, tail: []const u21) Error![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);
    var scratch: [4]u8 = undefined;
    for (body) |c| try buf.appendSlice(allocator, scratch[0 .. std.unicode.utf8Encode(c, &scratch) catch unreachable]);
    for (tail) |c| try buf.appendSlice(allocator, scratch[0 .. std.unicode.utf8Encode(c, &scratch) catch unreachable]);
    return buf.toOwnedSlice(allocator);
}

test {
    _ = @import("unicode_data.zig");
    _ = @import("tests.zig");
}
