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
// compiler. Doing that may carry a huge cost, because zig may need to spend
// ~30s compiling libc++ for an innocent feature test. Having an executable per
// target platform (like GCC does things, e.g. aarch64-linux-gnu-<tool>) is
// what most toolchains are designed to work with. So we need a wrapper per
// zig sub-command per target. As of writing, the layout is:
//   tools/
//   ├── x86_64-linux-gnu.2.34
//   │   ├── ar
//   │   ├── c++
//   │   └── ld.lld
//   ├── x86_64-linux-musl
//   │   ├── ar
//   │   ├── c++
//   │   └── ld.lld
//   ├── x86_64-macos-none
//   │   ├── ar
//   │   ├── c++
//   │   └── ld64.lld
//   ...
// * ZIG_LIB_DIR controls the output of `zig c++ -MF -MD <...>`. Bazel uses
// command to understand which input files were used to the compilation. If any
// of the files are not in `external/<...>/`, Bazel will understand and
// complain that the compiler is using undeclared directories on the host file
// system. We do not declare prerequisites using absolute paths, because that
// busts Bazel's remote cache.
// * BAZEL_ZIG_CC_CACHE_PREFIX is configurable per toolchain instance, and
// ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR must be set to its value for
// all `zig` invocations.
//
// Originally this was a Bash script, then a POSIX shell script, then two
// scripts (one with pre-defined BAZEL_ZIG_CC_CACHE_PREFIX, one without). Then
// Windows came along with two PowerShell scripts (ports of the POSIX shell
// scripts), which I kept breaking. Then Bazel 6 came with
// `--experimental_use_hermetic_linux_sandbox`, which hermetizes the sandbox to
// the extreme: the sandbox has nothing that is not declared. /bin/sh and its
// dependencies (/lib/x86_64-linux-gnu/libc.so.6 on my system) are obviously
// not declared. So one can either declare those dependencies, bundle a shell
// to execute the wrapper, or port the shell logic to a cross-platform program
// that compiles to a static binary. By a chance we happen to already ship a
// toolchain of a language that could compile such program. And behold, the
// program is below.

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

const CACHE_DIR = "{BAZEL_ZIG_CC_CACHE_PREFIX}";

// cannot use multiline constant syntax due to
// https://github.com/ziglang/zig/issues/9257#issuecomment-878534090
const usage_cpp = "" ++
    "Usage: <...>/tools/<target-triple>/{[zig_tool]s}{[exe]s} <args>...\n" ++
    "\n" ++
    "Wraps the \"zig\" multi-call binary. It determines the target platform from\n" ++
    "the directory where it was called. Then sets ZIG_LIB_DIR,\n" ++
    "ZIG_GLOBAL_CACHE_DIR, ZIG_LOCAL_CACHE_DIR and then calls:\n" ++
    "\n" ++
    "  zig c++ -target <target-triple> <args>...\n";

const usage_other = "" ++
    "Usage: <...>/tools/<target-triple>/{[zig_tool]s}{[exe]s} <args>...\n" ++
    "\n" ++
    "Wraps the \"zig\" multi-call binary. It sets ZIG_LIB_DIR,\n" ++
    "ZIG_GLOBAL_CACHE_DIR, ZIG_LOCAL_CACHE_DIR, and then calls:\n" ++
    "\n" ++
    "  zig {[zig_tool]s} <args>...\n";

const Action = enum {
    early_ok,
    early_err,
    exec,
};

const ExecParams = struct {
    args: ArrayListUnmanaged([]const u8),
    env: process.EnvMap,
};

const ParseResults = union(Action) {
    early_ok,
    early_err: []const u8,
    exec: ExecParams,
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

    var argv_it = process.argsWithAllocator(arena) catch |err| {
        std.debug.print("error parsing args: {s}\n", .{@errorName(err)});
        return 1;
    };

    const action = parseArgs(arena, fs.cwd(), &argv_it) catch |err| {
        std.debug.print("error: {s}\n", .{@errorName(err)});
        return 1;
    };

    switch (action) {
        .early_ok => return 0,
        .early_err => |msg| {
            std.io.getStdErr().writeAll(msg) catch {};
            return 1;
        },
        .exec => |params| {
            if (builtin.os.tag == .windows) {
                return spawnWindows(arena, params);
            } else {
                return execUnix(arena, params);
            }
        },
    }
}

fn spawnWindows(arena: mem.Allocator, params: ExecParams) u8 {
    var proc = ChildProcess.init(params.args.items, arena);
    proc.env_map = &params.env;
    const ret = proc.spawnAndWait() catch |err| {
        std.debug.print(
            "error spawning {s}: {s}\n",
            .{ params.args.items[0], @errorName(err) },
        );
        return 1;
    };

    switch (ret) {
        .Exited => |code| return code,
        else => |other| {
            std.debug.print("abnormal exit: {any}\n", .{other});
            return 1;
        },
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
        return fatal(arena, "error: argv[0] cannot be null", .{});

    const zig_tool = blk: {
        const b = fs.path.basename(arg0);
        if (builtin.target.os.tag == .windows and
            std.ascii.eqlIgnoreCase(".exe", b[b.len - 4 ..]))
            break :blk b[0 .. b.len - 4];

        break :blk b;
    };
    const maybe_target = getTarget(arg0) catch |err| switch (err) {
        error.BadParent => {
            const fmt_args = .{ .zig_tool = zig_tool, .exe = EXE };
            if (mem.eql(u8, zig_tool, "c++")) {
                return fatal(arena, usage_cpp, fmt_args);
            } else return fatal(arena, usage_other, fmt_args);
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
        break :blk try fs.path.join(arena, &[_][]const u8{ here, "..", ".." });
    };

    const zig_lib_dir = try fs.path.join(arena, &[_][]const u8{ root, "lib" });
    const zig_exe = try fs.path.join(
        arena,
        &[_][]const u8{ root, "zig" ++ EXE },
    );

    var env = process.getEnvMap(arena) catch |err| {
        return fatal(
            arena,
            "error getting process environment: {s}",
            .{@errorName(err)},
        );
    };
    try env.put("ZIG_LIB_DIR", zig_lib_dir);
    try env.put("ZIG_LOCAL_CACHE_DIR", CACHE_DIR);
    try env.put("ZIG_GLOBAL_CACHE_DIR", CACHE_DIR);

    // args is the path to the zig binary and args to it.
    var args = ArrayListUnmanaged([]const u8){};
    try args.appendSlice(arena, &[_][]const u8{ zig_exe, zig_tool });
    if (maybe_target) |target|
        try args.appendSlice(arena, &[_][]const u8{ "-target", target });

    while (argv_it.next()) |arg|
        try args.append(arena, arg);

    if (mem.eql(u8, zig_tool, "c++") and shouldReturnEarly(args.items))
        return .early_ok;

    return ParseResults{ .exec = .{ .args = args, .env = env } };
}

fn fatal(
    arena: mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) error{OutOfMemory}!ParseResults {
    const msg = try std.fmt.allocPrint(arena, fmt ++ "\n", args);
    return ParseResults{ .early_err = msg };
}

// Golang probing for a particular linker flag causes many unneeded stubs to be
// built, e.g. glibc, musl, libc++. The hackery can probably be deleted after
// Go 1.20 is released. In particular,
// https://go-review.googlesource.com/c/go/+/436884
fn shouldReturnEarly(args: []const []const u8) bool {
    const prelude = comptimeSplit("-Wl,--no-gc-sections -x c - -o /dev/null");
    if (args.len < prelude.len)
        return false;
    for (prelude) |arg, i|
        if (!mem.eql(u8, arg, args[args.len - prelude.len + i]))
            return false;
    return true;
}

fn getTarget(self_exe: []const u8) error{BadParent}!?[]const u8 {
    const here = fs.path.dirname(self_exe) orelse return error.BadParent;
    const triple = fs.path.basename(here);

    // Validating the triple now will help users catch errors even if they
    // don't yet need the target. yes yes the validation will miss things
    // strings `is.it.x86_64?-stallinux,macos-`; we are trying to aid users
    // that run things from the wrong directory, not trying to punish the ones
    // having fun.
    {
        var it = mem.split(u8, triple, "-");
        if (it.next()) |arch| {
            if (mem.indexOf(u8, "aarch64,x86_64", arch) == null)
                return error.BadParent;
        } else return error.BadParent;

        if (it.next()) |got_os| {
            if (mem.indexOf(u8, "linux,macos,windows", got_os) == null)
                return error.BadParent;
        } else return error.BadParent;

        // ABI triple is too much of a moving target
        if (it.next() == null) return error.BadParent;

        // but the target needs to have 3 dashes.
        if (it.next() != null) return error.BadParent;
    }

    if (mem.eql(u8, "c++" ++ EXE, fs.path.basename(self_exe))) {
        return triple;
    } else return null;
}

fn comptimeSplit(comptime str: []const u8) [countWords(str)][]const u8 {
    var arr: [countWords(str)][]const u8 = undefined;
    var i: usize = 0;
    var it = mem.split(u8, str, " ");
    while (it.next()) |arg| : (i += 1)
        arr[i] = arg;
    return arr;
}

fn countWords(str: []const u8) usize {
    return mem.count(u8, str, " ") + 1;
}

const testing = std.testing;

test "launcher:shouldReturnEarly" {
    inline for (.{
        "-Wl,--no-gc-sections -x c - -o /dev/null",
        "foo.c -o main -Wl,--no-gc-sections -x c - -o /dev/null",
    }) |tt| try testing.expect(shouldReturnEarly(comptimeSplit(tt)[0..]));

    inline for (.{
        "",
        "cc -Wl,--no-gc-sections -x c - -o /dev/null x",
        "-Wl,--no-gc-sections -x c - -o",
        "incorrect-value -x c - -o /dev/null",
    }) |tt| try testing.expect(!shouldReturnEarly(comptimeSplit(tt)[0..]));
}

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

    for (want_args) |want_arg, i|
        try testing.expectEqualStrings(want_arg, res.exec.args.items[i]);

    try testing.expectEqualStrings(
        want_env_zig_lib_dir,
        res.exec.env.get("ZIG_LIB_DIR").?,
    );
}

test "launcher:parseArgs" {
    // not using testing.allocator, because parseArgs is designed to be used
    // with an arena.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const tests = [_]struct {
        args: []const [:0]const u8,
        precreate_dir: ?[]const u8 = null,
        want_result: union(Action) {
            early_ok,
            early_err: []const u8,
            exec: struct {
                args: []const [:0]const u8,
                env_zig_lib_dir: []const u8,
            },
        },
    }{
        .{
            .args = &[_][:0]const u8{"ar" ++ EXE},
            .want_result = .{
                .early_err = std.fmt.comptimePrint(usage_other ++ "\n", .{
                    .zig_tool = "ar",
                    .exe = EXE,
                }),
            },
        },
        .{
            .args = &[_][:0]const u8{"c++" ++ EXE},
            .want_result = .{
                .early_err = std.fmt.comptimePrint(usage_cpp ++ "\n", .{
                    .zig_tool = "c++",
                    .exe = EXE,
                }),
            },
        },
        .{
            .args = &[_][:0]const u8{
                "external" ++ sep ++ "zig_sdk" ++ "tools" ++ sep ++
                    "x86_64-linux-musl" ++ sep ++ "c++" ++ EXE,
                "-Wl,--no-gc-sections",
                "-x",
                "c",
                "-",
                "-o",
                "/dev/null",
            },
            .want_result = .early_ok,
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
                "tools" ++ sep ++ "x86_64-linux-musl" ++ sep ++ "ar" ++ EXE,
                "-rcs",
                "all.a",
                "main.o",
                "foo.o",
            },
            .want_result = .{
                .exec = .{
                    .args = &[_][:0]const u8{
                        "tools" ++ sep ++ "x86_64-linux-musl" ++ sep ++ ".." ++
                            sep ++ ".." ++ sep ++ "zig" ++ EXE,
                        "ar",
                        "-rcs",
                        "all.a",
                        "main.o",
                        "foo.o",
                    },
                    .env_zig_lib_dir = "tools" ++ sep ++ "x86_64-linux-musl" ++
                        sep ++ ".." ++ sep ++ ".." ++ sep ++ "lib",
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

        var res = try parseArgs(allocator, tmp.dir, &TestArgIterator{
            .argv = tt.args,
        });

        switch (tt.want_result) {
            .early_ok => try testing.expectEqual(res, .early_ok),
            .early_err => |want_msg| try testing.expectEqualStrings(
                want_msg,
                res.early_err,
            ),
            .exec => |want| {
                try compareExec(res, want.args, want.env_zig_lib_dir);
            },
        }
    }
}
