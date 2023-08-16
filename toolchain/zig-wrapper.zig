// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License
//
// A wrapper for `zig` subcommands.
//
// In simple cases it is usually enough to:
//
//      zig c++ -target <triple> <...>
//
// However, there are some caveats:
//
// * Sometimes toolchains (looking at you, Go, see an example in
// https://github.com/golang/go/pull/55966) skip CFLAGS to the underlying
// compiler. Doing that carries a cost, because zig may need to spend ~30s
// compiling libc++ for an innocent feature test. Having an executable per
// target platform (like GCC does things, e.g. aarch64-linux-gnu-<tool>) is
// what most toolchains are designed to work with. So we need a wrapper per zig
// sub-command per target. As of writing, the layout is:
//
//   tools/
//   ├── ar
//   ├── ld.lld
//   ├── lld-link
//   ├── zig-wrapper
//   ├── x86_64-linux-gnu.2.34
//   │   └── c++
//   ├── x86_64-linux-musl
//   │   └── c++
//   ├── x86_64-macos-none
//   │   └── c++
//   ...
// * ZIG_LIB_DIR controls the output of `zig c++ -MF -MD <...>`. Bazel uses
// command to understand which input files were used to the compilation. If any
// of the files are not in `external/<...>/`, Bazel will understand and
// complain that the compiler is using undeclared directories on the host file
// system. We do not declare prerequisites using absolute paths, because that
// busts Bazel's remote cache.
// * HERMETIC_CC_TOOLCHAIN_CACHE_PREFIX is configurable per toolchain instance, and
// ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR must be set to its value for
// all `zig` invocations.
//
// zig-wrapper, when invoked directly, will invoke "zig" with the same args and
// ZIG_GLOBAL_CACHE_DIR, ZIG_LOCAL_CACHE_DIR, ZIG_LIB_DIR. `ar` will run `zig
// ar` and pass the sub-commands.
//
// Adding new subcommands
//------------------------
// Other zig subcommands should added here only if they are required for the
// Bazel's understanding of the zig toolchain. Users are expected to call
// `zig-wrapper` directly if they need another zig subcommand instead of
// adding them here.

const builtin = @import("builtin");
const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const ChildProcess = std.ChildProcess;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const sep = fs.path.sep_str;

const EXE = switch (builtin.target.os.tag) {
    .windows => ".exe",
    else => "",
};

const CACHE_DIR = "{HERMETIC_CC_TOOLCHAIN_CACHE_PREFIX}";

const usage =
    \\
    \\Usage: <...>/tools/<target-triple>/{[arg0_noexe]s}{[exe]s} <args>...
    \\
    \\Wraps the "zig" multi-call binary. It determines the target platform from
    \\the directory where it was called. Then sets ZIG_LIB_DIR,
    \\ZIG_GLOBAL_CACHE_DIR, ZIG_LOCAL_CACHE_DIR and then calls:
    \\
    \\  zig c++ -target <target-triple> <args>...
;

const Action = enum {
    err,
    exec,
};

const ExecParams = struct {
    args: ArrayListUnmanaged([]const u8),
    env: process.EnvMap,
};

const ParseResults = union(Action) {
    err: []const u8,
    exec: ExecParams,
};

// sub-commands in the same folder as `zig-wrapper`
const sub_commands_target = std.ComptimeStringMap(void, .{
    .{"ar"},
    .{"ld.lld"},
    .{"lld-link"},
});

const RunMode = union(enum) {
    wrapper, // plain zig-wrapper

    // commands in the same directory as zig-wrapper
    arg1,

    // the venerable one
    cc: []const u8, // cc -target <...>
};

pub fn main() u8 {
    const allocator = if (builtin.link_libc)
        std.heap.c_allocator
    else blk: {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        break :blk gpa.allocator();
    };
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var argv_it = process.argsWithAllocator(arena) catch |err|
        return fatal("error parsing args: {s}\n", .{@errorName(err)});

    const action = parseArgs(arena, fs.cwd(), &argv_it) catch |err|
        return fatal("error: {s}\n", .{@errorName(err)});

    switch (action) {
        .err => |msg| return fatal("{s}", .{msg}),
        .exec => |params| {
            if (builtin.os.tag == .windows)
                return spawnWindows(arena, params)
            else
                return execUnix(arena, params);
        },
    }
}

fn spawnWindows(arena: mem.Allocator, params: ExecParams) u8 {
    var proc = ChildProcess.init(params.args.items, arena);
    proc.env_map = &params.env;
    const ret = proc.spawnAndWait() catch |err|
        return fatal(
        "error spawning {s}: {s}\n",
        .{ params.args.items[0], @errorName(err) },
    );

    switch (ret) {
        .Exited => |code| return code,
        else => |other| return fatal("abnormal exit: {any}\n", .{other}),
    }
}

fn execUnix(arena: mem.Allocator, params: ExecParams) u8 {
    const err = process.execve(arena, params.args.items, &params.env);
    std.debug.print(
        "error execing {s}: {s}\n",
        .{ params.args.items[0], @errorName(err) },
    );
    return 1;
}

// argv_it is an object that has such method:
//     fn next(self: *Self) ?[]const u8
// in non-testing code it is *process.ArgIterator.
// Leaks memory: the name of the first argument is arena not by chance.
fn parseArgs(
    arena: mem.Allocator,
    cwd: fs.Dir,
    argv_it: anytype,
) error{OutOfMemory}!ParseResults {
    const arg0 = argv_it.next() orelse
        return parseFatal(arena, "error: argv[0] cannot be null", .{});

    const arg0_noexe = noExe(fs.path.basename(arg0));

    const run_mode = getRunMode(arg0, arg0_noexe) catch |err| switch (err) {
        error.BadParent => {
            return parseFatal(arena, usage, .{
                .arg0_noexe = arg0_noexe,
                .exe = EXE,
            });
        },
        else => |e| return e,
    };

    const root = blk: {
        var dir = cwd.openDir(
            "external" ++ sep ++ "zig_sdk" ++ sep ++ "lib",
            .{ .access_sub_paths = false, .no_follow = true },
        );

        if (dir) |*dir_exists| {
            dir_exists.close();
            break :blk "external" ++ sep ++ "zig_sdk";
        } else |_| {}

        // directory does not exist or there was an error opening it
        const here = fs.path.dirname(arg0) orelse ".";

        break :blk try fs.path.join(
            arena,
            switch (run_mode) {
                .wrapper, .arg1 => &[_][]const u8{ here, ".." },
                .cc => &[_][]const u8{ here, "..", ".." },
            },
        );
    };

    const zig_lib_dir = try fs.path.join(arena, &[_][]const u8{ root, "lib" });
    const zig_exe = try fs.path.join(
        arena,
        &[_][]const u8{ root, "zig" ++ EXE },
    );

    var env = process.getEnvMap(arena) catch |err|
        return parseFatal(arena, "error getting env: {s}", .{@errorName(err)});

    try env.put("ZIG_LIB_DIR", zig_lib_dir);
    try env.put("ZIG_LOCAL_CACHE_DIR", CACHE_DIR);
    try env.put("ZIG_GLOBAL_CACHE_DIR", CACHE_DIR);

    // args is the path to the zig binary and args to it.
    var args = ArrayListUnmanaged([]const u8){};
    try args.appendSlice(arena, &[_][]const u8{zig_exe});

    switch (run_mode) {
        .wrapper => {},
        .arg1 => try args.appendSlice(arena, &[_][]const u8{arg0_noexe}),
        .cc => |target| try args.appendSlice(arena, &[_][]const u8{
            arg0_noexe,
            "-target",
            target,
        }),
    }

    while (argv_it.next()) |arg| {
        // This is an opt-out flag that Zig doesn't support yet, so just ignore it.
        // See https://github.com/ziglang/zig/issues/16855
        if (mem.eql(u8, arg, "-Wl,--no-undefined-version")) {
            continue;
        }

        try args.append(arena, arg);
    }

    return ParseResults{ .exec = .{ .args = args, .env = env } };
}

fn parseFatal(
    arena: mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) error{OutOfMemory}!ParseResults {
    const msg = try std.fmt.allocPrint(arena, fmt ++ "\n", args);
    return ParseResults{ .err = msg };
}

pub fn fatal(comptime fmt: []const u8, args: anytype) u8 {
    std.debug.print(fmt, args);
    return 1;
}

fn getRunMode(self_exe: []const u8, self_base_noexe: []const u8) error{BadParent}!RunMode {
    if (mem.eql(u8, "zig-wrapper", self_base_noexe))
        return .wrapper;

    if (sub_commands_target.has(self_base_noexe)) {
        return .arg1;
    }

    // only zig-wrapper, c++ and ar and ar are supported
    if (!mem.eql(u8, "c++", self_base_noexe))
        return error.BadParent;

    // what follows is the validation that `-target` is a plausible string.
    const here = fs.path.dirname(self_exe) orelse return error.BadParent;
    const triple = fs.path.basename(here);

    // Validating the triple now will help users catch errors even if they
    // don't yet need the target. yes yes the validation will miss things
    // strings `is.it.x86_64?-stallinux,macos-`; we are trying to aid users
    // that run things from the wrong directory, not trying to punish the ones
    // having fun.
    var it = mem.split(u8, triple, "-");

    const arch = it.next() orelse return error.BadParent;
    if (mem.indexOf(u8, "aarch64,x86_64", arch) == null)
        return error.BadParent;

    const got_os = it.next() orelse return error.BadParent;
    if (mem.indexOf(u8, "linux,macos,windows", got_os) == null)
        return error.BadParent;

    // ABI triple is too much of a moving target
    if (it.next() == null) return error.BadParent;
    // but the target needs to have 3 dashes.
    if (it.next() != null) return error.BadParent;

    return RunMode{ .cc = triple };
}

const testing = std.testing;

pub const TestArgIterator = struct {
    index: usize = 0,
    argv: []const [:0]const u8,

    pub fn next(self: *TestArgIterator) ?[:0]const u8 {
        if (self.index == self.argv.len) return null;

        defer self.index += 1;
        return self.argv[self.index];
    }
};

fn compareExec(
    res: ParseResults,
    want_args: []const [:0]const u8,
    want_env_zig_lib_dir: []const u8,
) !void {
    try testing.expectEqual(want_args.len, res.exec.args.items.len);

    for (want_args, res.exec.args.items) |want_arg, got_arg|
        try testing.expectEqualStrings(want_arg, got_arg);

    try testing.expectEqualStrings(
        want_env_zig_lib_dir,
        res.exec.env.get("ZIG_LIB_DIR").?,
    );
}

test "zig-wrapper:parseArgs" {
    // not using testing.allocator, because parseArgs is designed to be used
    // with an arena.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const tests = [_]struct {
        args: []const [:0]const u8,
        precreate_dir: ?[]const u8 = null,
        want_result: union(Action) {
            err: []const u8,
            exec: struct {
                args: []const [:0]const u8,
                env_zig_lib_dir: []const u8,
            },
        },
    }{
        .{
            .args = &[_][:0]const u8{"c++" ++ EXE},
            .want_result = .{
                .err = comptime std.fmt.comptimePrint(usage ++ "\n", .{
                    .arg0_noexe = "c++",
                    .exe = EXE,
                }),
            },
        },
        .{
            .args = &[_][:0]const u8{
                "tools" ++ sep ++ "x86_64-linux-musl" ++ sep ++ "c++" ++ EXE,
                "main.c",
                "-o",
                "/dev/null",
            },
            .want_result = .{
                .exec = .{
                    .args = &[_][:0]const u8{
                        "tools" ++ sep ++ "x86_64-linux-musl" ++ sep ++
                            ".." ++ sep ++ ".." ++ sep ++ "zig" ++ EXE,
                        "c++",
                        "-target",
                        "x86_64-linux-musl",
                        "main.c",
                        "-o",
                        "/dev/null",
                    },
                    .env_zig_lib_dir = "tools" ++ sep ++ "x86_64-linux-musl" ++
                        sep ++ ".." ++ sep ++ ".." ++ sep ++ "lib",
                },
            },
        },
        .{
            .args = &[_][:0]const u8{
                "external_zig_sdk" ++ sep ++ "tools" ++ sep ++
                    "ar" ++ EXE,
                "rcs",
            },
            .precreate_dir = "external" ++ sep ++ "zig_sdk" ++ sep ++ "lib",
            .want_result = .{
                .exec = .{
                    .args = &[_][:0]const u8{
                        "external" ++ sep ++ "zig_sdk" ++ sep ++ "zig" ++ EXE,
                        "ar",
                        "rcs",
                    },
                    .env_zig_lib_dir = "external" ++ sep ++ "zig_sdk" ++
                        sep ++ "lib",
                },
            },
        },
        .{
            .args = &[_][:0]const u8{
                "external_zig_sdk" ++ sep ++ "tools" ++ sep ++
                    "x86_64-linux-gnu.2.28" ++ sep ++ "c++" ++ EXE,
                "main.c",
                "-o",
                "/dev/null",
            },
            .precreate_dir = "external" ++ sep ++ "zig_sdk" ++ sep ++ "lib",
            .want_result = .{
                .exec = .{
                    .args = &[_][:0]const u8{
                        "external" ++ sep ++ "zig_sdk" ++ sep ++ "zig" ++ EXE,
                        "c++",
                        "-target",
                        "x86_64-linux-gnu.2.28",
                        "main.c",
                        "-o",
                        "/dev/null",
                    },
                    .env_zig_lib_dir = "external" ++ sep ++ "zig_sdk" ++
                        sep ++ "lib",
                },
            },
        },
    };

    for (tests) |tt| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();

        if (tt.precreate_dir) |dir|
            try tmp.dir.makePath(dir);

        var argv_it = TestArgIterator{ .argv = tt.args };
        var res = try parseArgs(allocator, tmp.dir, &argv_it);

        switch (tt.want_result) {
            .err => |want_msg| try testing.expectEqualStrings(
                want_msg,
                res.err,
            ),
            .exec => |want| {
                try compareExec(res, want.args, want.env_zig_lib_dir);
            },
        }
    }
}

fn noExe(b: []const u8) []const u8 {
    if (builtin.target.os.tag == .windows and
        std.ascii.eqlIgnoreCase(".exe", b[b.len - 4 ..]))
        return b[0 .. b.len - 4];

    return b;
}
