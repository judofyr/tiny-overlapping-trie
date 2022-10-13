const std = @import("std");

const IdType = u10;

// Number of entries per bin
const N = 4;

const Entry = packed struct {
    id: IdType,
    parent_id: IdType,
    is_primary: bool,
    other_bin: u8,
    is_duplicate: bool,
    is_leaf: bool,
};

comptime {
    std.debug.assert(@sizeOf(Entry) == 4);
}

// Random table for Pearson hashing
const T1 = [256]u8{ 37, 115, 211, 221, 30, 249, 253, 176, 138, 194, 158, 85, 74, 18, 113, 167, 104, 128, 200, 48, 186, 95, 228, 151, 159, 5, 102, 109, 136, 49, 189, 166, 9, 73, 23, 32, 204, 213, 215, 118, 135, 93, 180, 226, 236, 208, 67, 232, 55, 192, 100, 87, 98, 90, 187, 196, 117, 178, 146, 127, 51, 105, 134, 123, 14, 220, 65, 84, 41, 235, 75, 34, 197, 212, 59, 1, 111, 89, 68, 121, 82, 245, 205, 216, 66, 27, 26, 181, 230, 114, 172, 71, 103, 175, 153, 214, 142, 170, 33, 143, 24, 45, 144, 207, 0, 155, 198, 149, 218, 8, 185, 78, 50, 107, 247, 171, 188, 53, 31, 129, 63, 224, 209, 47, 210, 120, 29, 122, 131, 182, 83, 174, 46, 169, 137, 244, 156, 17, 227, 39, 168, 190, 21, 3, 60, 219, 40, 254, 243, 62, 56, 177, 241, 250, 15, 165, 61, 133, 239, 160, 152, 225, 202, 145, 191, 184, 164, 76, 126, 88, 35, 101, 20, 163, 58, 141, 70, 28, 233, 11, 92, 43, 195, 193, 124, 6, 201, 99, 94, 79, 150, 42, 240, 91, 255, 57, 148, 173, 110, 251, 238, 19, 199, 4, 96, 16, 140, 248, 237, 80, 116, 38, 206, 222, 130, 252, 217, 132, 242, 119, 162, 12, 25, 97, 54, 246, 22, 223, 108, 36, 229, 13, 7, 72, 106, 183, 161, 112, 86, 10, 52, 81, 157, 234, 125, 154, 139, 44, 69, 2, 203, 147, 231, 77, 64, 179 };
const T2 = [256]u8{ 151, 237, 34, 213, 1, 20, 99, 126, 72, 149, 174, 57, 112, 68, 71, 246, 238, 244, 23, 169, 64, 190, 150, 252, 137, 221, 32, 216, 243, 181, 50, 21, 141, 107, 192, 206, 6, 210, 146, 100, 163, 103, 78, 108, 160, 156, 115, 9, 203, 159, 179, 247, 25, 31, 240, 133, 168, 152, 193, 196, 7, 45, 90, 56, 186, 167, 250, 53, 183, 55, 122, 235, 241, 5, 41, 11, 91, 123, 104, 48, 227, 184, 131, 62, 231, 220, 96, 132, 165, 12, 106, 110, 10, 162, 170, 15, 254, 212, 83, 109, 164, 208, 127, 2, 93, 242, 199, 232, 128, 180, 89, 222, 215, 230, 225, 249, 29, 175, 205, 145, 17, 253, 8, 61, 51, 255, 39, 105, 119, 59, 14, 171, 245, 28, 248, 49, 125, 73, 251, 148, 35, 224, 66, 228, 63, 98, 217, 177, 204, 58, 46, 226, 154, 92, 223, 153, 197, 102, 166, 33, 139, 200, 214, 113, 236, 95, 135, 118, 43, 120, 157, 195, 134, 229, 116, 85, 188, 3, 87, 144, 42, 27, 143, 47, 234, 182, 176, 185, 52, 207, 19, 129, 84, 37, 114, 24, 38, 130, 187, 79, 76, 209, 88, 36, 233, 173, 74, 16, 18, 201, 161, 218, 44, 69, 75, 86, 121, 54, 124, 178, 94, 138, 67, 97, 140, 136, 211, 13, 239, 101, 0, 172, 30, 22, 80, 65, 142, 60, 155, 189, 191, 219, 82, 202, 117, 111, 4, 40, 198, 26, 147, 81, 77, 70, 158, 194 };

const MultiEntry = union(enum) {
    nothing: void,
    primary_entry: *Entry,
    secondary_entry: *Entry,
    double_entry: [2]*Entry,

    fn fromOptionals(entry1: ?*Entry, entry2: ?*Entry) MultiEntry {
        if (entry1 == null and entry2 == null) return .nothing;
        if (entry2 == null) return .{ .primary_entry = entry1.? };
        if (entry1 == null) return .{ .secondary_entry = entry2.? };
        return .{ .double_entry = [2]*Entry{ entry1.?, entry2.? } };
    }

    fn fromEntry(entry: *Entry, is_primary: bool) MultiEntry {
        if (is_primary) {
            return .{ .primary_entry = entry };
        } else {
            return .{ .secondary_entry = entry };
        }
    }
};

const HashDetails = packed struct {
    bin1_start: u8,
    bin2_start: u8,
    rest: u48,
};

pub const OverlappingTrie = struct {
    const Self = @This();
    const Error = error{OutOfCapacity};

    entries: *[256][N]Entry,
    seed: u64 = 1,
    next_id: IdType = 1,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var entries = try allocator.alloc(Entry, 256 * N);
        std.mem.set(Entry, entries, std.mem.zeroes(Entry));
        return Self{
            .entries = @ptrCast(*[256][N]Entry, entries[0 .. 256 * N]),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        self.* = undefined;
    }

    fn findEntry(self: *Self, bin: u8, parent_id: u64, is_primary: bool) ?*Entry {
        for (self.entries[bin]) |*entry| {
            if (entry.id != 0 and entry.parent_id == parent_id and entry.is_primary == is_primary) {
                return entry;
            }
        }
        return null;
    }

    fn findEmpty(self: *Self, bin: u8) ?*Entry {
        for (self.entries[bin]) |*entry| {
            if (entry.id == 0) return entry;
        }
        return null;
    }

    fn findGhost(self: *Self, bin: u8) ?*Entry {
        for (self.entries[bin]) |*entry| {
            if (entry.is_duplicate) return entry;
        }
        return null;
    }

    fn getEntry(
        self: *Self,
        parent_id: IdType,
        bin1: u8,
        bin2: u8,
    ) ?*Entry {
        if (self.findEntry(bin1, parent_id, true)) |entry| return entry;
        if (self.findEntry(bin2, parent_id, false)) |entry| return entry;
        return null;
    }

    fn kickGhost(
        self: *Self,
        bin: u8,
    ) ?*Entry {
        if (self.findGhost(bin)) |entry| {
            var other_entry = self.findEntry(entry.other_bin, entry.parent_id, !entry.is_primary).?;
            std.debug.assert(other_entry.id == entry.id);
            other_entry.is_duplicate = false;
            return entry;
        }

        return null;
    }

    fn kickRandom(
        self: *Self,
        bin: u8,
    ) ?*Entry {
        for (self.entries[bin]) |*entry| {
            std.debug.assert(entry.id != 0 and !entry.is_duplicate);

            const new_empty = self.findEmpty(entry.other_bin) orelse self.kickGhost(entry.other_bin);
            if (new_empty) |other| {
                other.* = entry.*;
                other.is_primary = !entry.is_primary;
                other.other_bin = bin;
                return entry;
            }
        }

        return null;
    }

    fn makeSpace(
        self: *Self,
        bin1: u8,
        bin2: u8,
    ) MultiEntry {
        var result = MultiEntry.fromOptionals(
            self.findEmpty(bin1),
            self.findEmpty(bin2),
        );

        if (result == .nothing) {
            if (self.kickGhost(bin1)) |entry| return MultiEntry.fromEntry(entry, true);
            if (self.kickGhost(bin2)) |entry| return MultiEntry.fromEntry(entry, false);
            if (self.kickRandom(bin1)) |entry| return MultiEntry.fromEntry(entry, true);
            if (self.kickRandom(bin2)) |entry| return MultiEntry.fromEntry(entry, false);
        }

        return result;
    }

    fn getOrInsertEntry(
        self: *Self,
        parent_id: IdType,
        bin1: u8,
        bin2: u8,
    ) MultiEntry {
        const existing = MultiEntry.fromOptionals(
            self.findEntry(bin1, parent_id, true),
            self.findEntry(bin2, parent_id, false),
        );

        if (existing != .nothing) return existing;

        var primary_entry = Entry{
            .id = self.next_id,
            .parent_id = parent_id,
            .other_bin = bin2,
            .is_primary = true,
            .is_duplicate = false,
            .is_leaf = false,
        };

        var secondary_entry = Entry{
            .id = self.next_id,
            .parent_id = parent_id,
            .other_bin = bin1,
            .is_primary = false,
            .is_duplicate = false,
            .is_leaf = false,
        };

        const result = self.makeSpace(bin1, bin2);

        switch (result) {
            .nothing => {
                return .nothing;
            },
            .primary_entry => |entry| {
                entry.* = primary_entry;
            },
            .secondary_entry => |entry| {
                entry.* = secondary_entry;
            },
            .double_entry => |entries| {
                primary_entry.is_duplicate = true;
                secondary_entry.is_duplicate = true;
                entries[0].* = primary_entry;
                entries[1].* = secondary_entry;
            },
        }

        self.next_id += 1;

        return result;
    }

    pub fn insert(self: *Self, key: []const u8) Error!void {
        std.debug.assert(key.len > 0);

        var bin1_start: u8 = 0;
        var bin2_start: u8 = 127;

        var parent_id: IdType = 0;
        for (key) |symbol, idx| {
            var bins = [2]u8{ bin1_start +% symbol, bin2_start +% symbol };
            if (bins[0] == bins[1]) bins[1] += 1;

            var is_last = idx + 1 == key.len;

            switch (self.getOrInsertEntry(parent_id, bins[0], bins[1])) {
                .nothing => {
                    return error.OutOfCapacity;
                },
                .primary_entry, .secondary_entry => |entry| {
                    parent_id = entry.id;
                    if (is_last) {
                        entry.is_leaf = true;
                    }
                },
                .double_entry => |double_entry| {
                    parent_id = double_entry[0].id;
                    if (is_last) {
                        double_entry[0].is_leaf = true;
                        double_entry[1].is_leaf = true;
                    }
                },
            }
            bin1_start = T1[bin1_start ^ symbol];
            bin2_start = T2[bin2_start ^ symbol];
        }
    }

    pub fn contains(self: *Self, key: []const u8) bool {
        std.debug.assert(key.len > 0);

        var bin1_start: u8 = 0;
        var bin2_start: u8 = 127;

        var parent_id: IdType = 0;
        var entry: *Entry = undefined;
        for (key) |symbol| {
            var bins = [2]u8{ bin1_start +% symbol, bin2_start +% symbol };
            if (bins[0] == bins[1]) bins[1] += 1;
            if (self.getEntry(parent_id, bins[0], bins[1])) |child_entry| {
                entry = child_entry;
                parent_id = entry.id;
                bin1_start = T1[bin1_start ^ symbol];
                bin2_start = T2[bin2_start ^ symbol];
            } else {
                return false;
            }
        }
        return entry.is_leaf;
    }
};

const testing = std.testing;

test "basic add functionality" {
    var trie = try OverlappingTrie.init(testing.allocator);
    defer trie.deinit(testing.allocator);

    try trie.insert("hel");
    try trie.insert("hello");
    try trie.insert("world");

    try testing.expect(trie.contains("hello"));
    try testing.expect(trie.contains("hel"));
    try testing.expect(trie.contains("world"));
    try testing.expect(!trie.contains("worl"));
    try testing.expect(!trie.contains("other"));
}
