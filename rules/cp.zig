const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var argv_it = try std.process.Args.Iterator.initAllocator(
        init.minimal.args,
        arena,
    );
    _ = argv_it.next();
    const src = argv_it.next() orelse return error.InvalidUsage;
    const dst = argv_it.next() orelse return error.InvalidUsage;
    if (argv_it.next() != null) return error.InvalidUsage;
    try std.Io.Dir.copyFile(std.Io.Dir.cwd(), src, std.Io.Dir.cwd(), dst, init.io, .{});
}
