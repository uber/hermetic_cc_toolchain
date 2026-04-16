// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License
//
// A wrapper for `zig` subcommands.
//
// In simple cases it is usually enough to:
//
//      zig c++ <...> -target <triple>
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
//   │   └── c++
//   ├── x86_64-linux-musl
//   │   └── c++
//   ├── x86_64-macos-none
//   │   └── c++
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
const Io = std.Io;
const mem = std.mem;
const path = std.fs.path;
const process = std.process;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const sep = path.sep_str;

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
    environ_map: process.Environ.Map,
};

const ParseResults = union(Action) {
    err: []const u8,
    exec: ExecParams,
};

// sub-commands in the same folder as `zig-wrapper`
const sub_commands_target = std.StaticStringMap(void).initComptime(.{
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

pub fn main(init: process.Init) u8 {
    const arena = init.arena.allocator();

    var argv_it = process.Args.Iterator.initAllocator(
        init.minimal.args,
        arena,
    ) catch |err|
        return fatal("error initializing args iterator: {s}\n", .{@errorName(err)});

    const action = parseArgs(arena, init.io, init.minimal.environ, std.Io.Dir.cwd(), &argv_it) catch |err|
        return fatal("error: {s}\n", .{@errorName(err)});

    switch (action) {
        .err => |msg| return fatal("{s}", .{msg}),
        .exec => |params| {
            if (builtin.os.tag == .windows)
                return spawnWindows(init.io, arena, params)
            else
                return execUnix(init.io, arena, params);
        },
    }
}

fn spawnWindows(io: Io, _: mem.Allocator, params: ExecParams) u8 {
    var child = process.spawn(io, .{
        .argv = params.args.items,
        .environ_map = &params.environ_map,
    }) catch |err|
        return fatal(
            "error spawning {s}: {s}\n",
            .{ params.args.items[0], @errorName(err) },
        );

    const term = child.wait(io) catch |err|
        return fatal("error waiting for {s}: {s}\n", .{ params.args.items[0], @errorName(err) });

    switch (term) {
        .exited => |code| return code,
        else => |other| return fatal("abnormal exit: {any}\n", .{other}),
    }
}

fn execUnix(io: Io, _: mem.Allocator, params: ExecParams) u8 {
    const err = process.replace(io, .{
        .argv = params.args.items,
        .environ_map = &params.environ_map,
    });
    std.debug.print(
        "error execing {s}: {s}\n",
        .{ params.args.items[0], @errorName(err) },
    );
    return 1;
}

// argv_it is an object that has such method:
//     fn next(self: *Self) ?[]const u8
// in non-testing code it is *process.Args.Iterator.
// Leaks memory: the name of the first argument is arena not by chance.
fn parseArgs(
    arena: mem.Allocator,
    io: Io,
    environ: process.Environ,
    cwd: Io.Dir,
    argv_it: anytype,
) error{OutOfMemory}!ParseResults {
    const arg0 = argv_it.next() orelse
        return parseFatal(arena, "error: argv[0] cannot be null", .{});

    const arg0_noexe = noExe(path.basename(arg0));

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
        var dir = Io.Dir.openDir(cwd, io, "external" ++ sep ++ "zig_sdk" ++ sep ++ "lib", .{
            .access_sub_paths = false,
        });

        if (dir) |*dir_exists| {
            dir_exists.close(io);
            break :blk "external" ++ sep ++ "zig_sdk";
        } else |_| {}

        // directory does not exist or there was an error opening it
        const here = path.dirname(arg0) orelse ".";

        break :blk try path.join(
            arena,
            switch (run_mode) {
                .wrapper, .arg1 => &[_][]const u8{ here, ".." },
                .cc => &[_][]const u8{ here, "..", ".." },
            },
        );
    };

    const zig_lib_dir = try path.join(arena, &[_][]const u8{ root, "lib" });
    const zig_exe = try path.join(
        arena,
        &[_][]const u8{ root, "zig" ++ EXE },
    );

    var environ_map = process.Environ.createMap(environ, arena) catch |err|
        return parseFatal(arena, "error getting env: {s}", .{@errorName(err)});

    try environ_map.put("ZIG_LIB_DIR", zig_lib_dir);
    try environ_map.put("ZIG_LOCAL_CACHE_DIR", CACHE_DIR);
    try environ_map.put("ZIG_GLOBAL_CACHE_DIR", CACHE_DIR);

    var args = ArrayListUnmanaged([]const u8).empty;
    try args.appendSlice(arena, &[_][]const u8{zig_exe});

    switch (run_mode) {
        .wrapper => {},
        .arg1, .cc => try args.appendSlice(arena, &[_][]const u8{arg0_noexe}),
    }

    while (argv_it.next()) |arg| {
        // Filter unsupported flags that are meaningless for zig but get
        // passed by toolchains like Go's CGO (which adds -mthreads for
        // MinGW targets). Under -Werror these cause build failures.
        if (mem.eql(u8, arg, "-mthreads")) continue;
        try args.append(arena, arg);
    }

    // Add -target as the last parameter. The wrapper should overwrite
    // the target specified by other tools calling the wrapper.
    // Some tools might pass LLVM target triple, which are rejected by zig.
    // https://github.com/uber/hermetic_cc_toolchain/issues/222
    if (run_mode == RunMode.cc) {
        try args.appendSlice(arena, &[_][]const u8{
            "-target",
            run_mode.cc,
        });
    }

    return ParseResults{ .exec = .{ .args = args, .environ_map = environ_map } };
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
    const here = path.dirname(self_exe) orelse return error.BadParent;
    const triple = path.basename(here);

    // Validating the triple now will help users catch errors even if they
    // don't yet need the target. yes yes the validation will miss things
    // strings `is.it.x86_64?-stallinux,macos-`; we are trying to aid users
    // that run things from the wrong directory, not trying to punish the ones
    // having fun.
    var it = mem.splitScalar(u8, triple, '-');

    const arch = it.next() orelse return error.BadParent;
    if (mem.indexOf(u8, "aarch64,x86_64,wasm32", arch) == null)
        return error.BadParent;

    const got_os = it.next() orelse return error.BadParent;
    if (mem.indexOf(u8, "linux,macos,windows,wasi,freestanding", got_os) == null)
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
        res.exec.environ_map.get("ZIG_LIB_DIR").?,
    );
}

test "zig-wrapper:parseArgs" {
    // not using testing.allocator, because parseArgs is designed to be used
    // with an arena.
    const allocator = std.heap.page_allocator;

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
                        "main.c",
                        "-o",
                        "/dev/null",
                        "-target",
                        "x86_64-linux-musl",
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
                        "main.c",
                        "-o",
                        "/dev/null",
                        "-target",
                        "x86_64-linux-gnu.2.28",
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
            try tmp.dir.createDirPath(testing.io, dir);

        var argv_it = TestArgIterator{ .argv = tt.args };
        const res = try parseArgs(allocator, testing.io, .{ .block = .empty }, tmp.dir, &argv_it);

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
