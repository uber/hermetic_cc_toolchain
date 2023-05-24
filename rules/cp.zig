const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const argv = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), argv);

    if (argv.len != 3) return error.InvalidUsage;
    try std.fs.cwd().copyFile(argv[1], std.fs.cwd(), argv[2], .{});
}
