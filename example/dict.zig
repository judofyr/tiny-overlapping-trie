const std = @import("std");
const trie = @import("trie");

const bench_hash = true;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked) @panic("leaked memory");
    }

    var t = try trie.OverlappingTrie.init(gpa.allocator());
    defer t.deinit(gpa.allocator());

    const file = try std.fs.openFileAbsolute("/usr/share/dict/words", .{});
    defer file.close();

    var buf = std.io.bufferedReader(file.reader());
    var reader = buf.reader();

    var hash_set = std.StringHashMap(void).init(gpa.allocator());
    defer hash_set.deinit();

    var words = std.ArrayList([]u8).init(gpa.allocator());
    defer words.deinit();

    var bytes: usize = 0;

    {
        var i: usize = 0;

        var line_buf: [1024]u8 = undefined;
        while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| : (i += 1) {
            var copy = try gpa.allocator().dupe(u8, line);
            try words.append(copy);

            bytes += line.len;

            t.insert(line) catch |err| switch (err) {
                error.OutOfCapacity => break,
            };

            try hash_set.put(copy, {});
        }
    }

    std.debug.print("load factor = {d}\n", .{@intToFloat(f64, t.next_id) / 1024.0});
    std.debug.print("total bytes = {d}\n", .{bytes});

    const N = 100000;
    const Timer = std.time.Timer;

    if (bench_hash) {
        var timer = try Timer.start();
        const start = timer.lap();
        var found: usize = 0;
        var i: usize = 0;
        while (i < N) : (i += 1) {
            for (words.items) |word| {
                if (hash_set.contains(word)) found += 1;
            }
        }

        const end = timer.read();
        const elapsed_hash = (end - start) / (N * words.items.len);
        std.debug.print("hash_set elapsed: {} (found={})\n", .{ elapsed_hash, found / N });
    }

    {
        var timer = try Timer.start();
        const start = timer.lap();
        var found: usize = 0;
        var i: usize = 0;
        while (i < N) : (i += 1) {
            for (words.items) |word| {
                if (t.contains(word)) found += 1;
            }
        }

        const end = timer.read();
        const elapsed_trie = (end - start) / (N * words.items.len);
        std.debug.print("trie elapsed: {} (found={})\n", .{ elapsed_trie, found / N });
    }

    for (words.items) |word| {
        gpa.allocator().free(word);
    }
}
