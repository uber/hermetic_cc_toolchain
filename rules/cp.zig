const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const argv = try init.minimal.args.toSlice(init.arena.allocator());

    if (argv.len != 3) return error.InvalidUsage;
    const cwd = std.Io.Dir.cwd();
    try cwd.copyFile(argv[1], cwd, argv[2], io, .{});
}
