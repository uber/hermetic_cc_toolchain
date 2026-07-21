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
const Io = std.Io;
const Dir = std.Io.Dir;
const Environ = std.process.Environ;
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
    env: *Environ.Map,
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

pub fn main(init: std.process.Init) u8 {
    // Juicy Main (Zig 0.16): the runtime hands us a pre-initialized arena,
    // Io implementation and environment map. Everything that blocks or
    // touches the OS (args, env, filesystem, exec) now flows through `io`.
    const arena = init.arena.allocator();
    const io = init.io;

    var argv_it = init.minimal.args.iterateAllocator(arena) catch |err|
        return fatal("error parsing args: {s}\n", .{@errorName(err)});

    const action = parseArgs(arena, io, Dir.cwd(), &argv_it, init.environ_map) catch |err|
        return fatal("error: {s}\n", .{@errorName(err)});

    switch (action) {
        .err => |msg| return fatal("{s}", .{msg}),
        .exec => |params| {
            // execve-style replacement where supported (POSIX); spawn+wait
            // on platforms that cannot replace the process image (Windows).
            if (process.can_replace)
                return replaceProcess(io, params)
            else
                return spawnAndWait(io, params);
        },
    }
}

fn spawnAndWait(io: Io, params: ExecParams) u8 {
    var child = process.spawn(io, .{
        .argv = params.args.items,
        .environ_map = params.env,
    }) catch |err|
        return fatal(
            "error spawning {s}: {s}\n",
            .{ params.args.items[0], @errorName(err) },
        );

    const term = child.wait(io) catch |err|
        return fatal(
            "error waiting for {s}: {s}\n",
            .{ params.args.items[0], @errorName(err) },
        );

    switch (term) {
        .exited => |code| return code,
        else => |other| return fatal("abnormal exit: {any}\n", .{other}),
    }
}

fn replaceProcess(io: Io, params: ExecParams) u8 {
    const err = process.replace(io, .{
        .argv = params.args.items,
        .environ_map = params.env,
    });
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
    io: Io,
    cwd: Dir,
    argv_it: anytype,
    env: *Environ.Map,
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
            io,
            "external" ++ sep ++ "zig_sdk" ++ sep ++ "lib",
            .{ .access_sub_paths = false, .follow_symlinks = false },
        );

        if (dir) |*dir_exists| {
            dir_exists.close(io);
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

    const cache_dir = blk: {
        if (CACHE_DIR.len > 0) break :blk @as([]const u8, CACHE_DIR);
        if (builtin.os.tag == .windows) {
            if (env.get("LOCALAPPDATA")) |local_app_data| {
                if (local_app_data.len > 0)
                    break :blk try fs.path.join(arena, &[_][]const u8{ local_app_data, "zig" });
            }
            break :blk @as([]const u8, "C:\\Temp\\zig-cache");
        }
        if (env.get("HOME")) |home| {
            if (home.len > 0)
                break :blk try fs.path.join(arena, &[_][]const u8{ home, ".cache", "zig" });
        }
        break :blk @as([]const u8, if (builtin.os.tag == .macos) "/var/tmp/zig-cache" else "/tmp/zig-cache");
    };

    try env.put("ZIG_LIB_DIR", zig_lib_dir);
    try env.put("ZIG_LOCAL_CACHE_DIR", cache_dir);
    try env.put("ZIG_GLOBAL_CACHE_DIR", cache_dir);

    // Zig 0.14.0 locates the macOS SDK by running `xcrun --show-sdk-path`.
    // Bazel clears PATH via `exec env -`, making xcrun unfindable. Restore
    // the minimal system PATH so xcrun works in the sandbox.
    if (builtin.target.os.tag == .macos) {
        const existing = env.get("PATH") orelse "";
        const path = if (existing.len > 0)
            try std.fmt.allocPrint(arena, "{s}:/usr/bin:/bin", .{existing})
        else
            "/usr/bin:/bin";
        try env.put("PATH", path);
    }

    // args is the path to the zig binary and args to it.
    var args: ArrayListUnmanaged([]const u8) = .empty;
    try args.appendSlice(arena, &[_][]const u8{zig_exe});

    switch (run_mode) {
        .wrapper => {},
        .arg1, .cc => try args.appendSlice(arena, &[_][]const u8{arg0_noexe}),
    }

    // Zig 0.15 compiles C/C++ with UBSan instrumentation by default, which
    // surfaces as `ld.lld: error: undefined symbol: __ubsan_handle_*` when
    // the instrumented objects are linked. Disable it by default; the flag
    // is added before the caller's args, so an explicit -fsanitize=undefined
    // from the caller still takes precedence.
    if (run_mode == RunMode.cc)
        try args.appendSlice(arena, &[_][]const u8{"-fno-sanitize=undefined"});

    // Go's cgo unconditionally appends the MinGW-only `-mthreads` flag when
    // targeting Windows (golang/go#80290). Since llvm/llvm-project D151590,
    // clang's driver treats MinGW link flags as target-specific, and zig's
    // clang rejects `-mthreads` for windows-gnu. The flag is redundant for
    // zig's always-threadsafe mingw-w64 runtime, so drop it when targeting
    // Windows. The upstream fix is pending in Go 1.27.
    const strip_mthreads = switch (run_mode) {
        .cc => |triple| mem.indexOf(u8, triple, "windows") != null,
        else => false,
    };

    while (argv_it.next()) |arg| {
        if (strip_mthreads and mem.eql(u8, arg, "-mthreads")) continue;
        try args.append(arena, arg);
    }

    // Zig 0.15's linker cannot read thin archives (ziglang/zig#25694):
    //     error: unexpected token in LD script: literal: '!<thin>'
    // Some build systems (e.g. Meson) create thin archives for internal
    // static libraries by passing the `T` modifier to ar. Archives created
    // by this toolchain are also consumed by it, so drop the thin-archive
    // request and create regular archives instead.
    if (run_mode == RunMode.arg1 and mem.eql(u8, arg0_noexe, "ar"))
        try stripThinArchiveFlags(arena, &args);

    // Workaround for https://github.com/ziglang/zig/issues/23287: zig 0.14.0
    // lld does not handle the colon-link syntax (-l :filename or -l:filename).
    // Resolve such flags to full paths by searching the -L directories.
    if (run_mode == RunMode.cc)
        try resolveColonLibraries(arena, io, cwd, &args);

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

    return ParseResults{ .exec = .{ .args = args, .env = env } };
}

// Workaround for https://github.com/ziglang/zig/issues/23287: zig 0.14.0 lld
// does not handle the colon-link syntax (-l:filename). When we see "-l" followed
// by ":filename", resolve it to a full path by searching the -L directories.
fn resolveColonLibraries(
    arena: mem.Allocator,
    io: Io,
    cwd: Dir,
    args: *ArrayListUnmanaged([]const u8),
) error{OutOfMemory}!void {
    var lib_paths: ArrayListUnmanaged([]const u8) = .empty;
    for (args.items) |arg| {
        if (mem.startsWith(u8, arg, "-L") and arg.len > 2)
            try lib_paths.append(arena, arg[2..]);
    }

    var i: usize = 0;
    while (i + 1 < args.items.len) : (i += 1) {
        if (!mem.eql(u8, args.items[i], "-l")) continue;
        const next = args.items[i + 1];
        if (!mem.startsWith(u8, next, ":")) continue;

        const filename = next[1..];
        for (lib_paths.items) |lib_path| {
            const full_path = try fs.path.join(arena, &[_][]const u8{ lib_path, filename });
            cwd.access(io, full_path, .{}) catch continue;
            args.items[i] = full_path;
            _ = args.orderedRemove(i + 1);
            break;
        }
    }
}

// Workaround for https://github.com/ziglang/zig/issues/25694: drop
// thin-archive requests from `ar` invocations, so that regular archives are
// created instead. `--thin` args are removed, and the `T` modifier is
// stripped from the operation string (the first non-option argument, e.g.
// "rcsT" or "-csrDT").
fn stripThinArchiveFlags(
    arena: mem.Allocator,
    args: *ArrayListUnmanaged([]const u8),
) error{OutOfMemory}!void {
    // args.items[0] is the zig binary, args.items[1] is "ar".
    var i: usize = 2;
    var seen_operation = false;
    while (i < args.items.len) {
        const arg = args.items[i];
        if (mem.eql(u8, arg, "--thin")) {
            _ = args.orderedRemove(i);
            continue;
        }
        if (!seen_operation and !mem.startsWith(u8, arg, "--")) {
            seen_operation = true;
            if (mem.indexOfScalar(u8, arg, 'T') != null) {
                var stripped = try ArrayListUnmanaged(u8).initCapacity(arena, arg.len);
                for (arg) |c| {
                    if (c != 'T') stripped.appendAssumeCapacity(c);
                }
                args.items[i] = stripped.items;
            }
        }
        i += 1;
    }
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
        res.exec.env.get("ZIG_LIB_DIR").?,
    );
}

test "zig-wrapper:parseArgs" {
    // not using testing.allocator, because parseArgs is designed to be used
    // with an arena.
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    const io = std.testing.io;

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
                        "-fno-sanitize=undefined",
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
            // thin-archive requests are dropped (ziglang/zig#25694): the `T`
            // modifier is stripped from the operation string and `--thin` is
            // removed.
            .args = &[_][:0]const u8{
                "external_zig_sdk" ++ sep ++ "tools" ++ sep ++
                    "ar" ++ EXE,
                "--format=gnu",
                "csrDT",
                "--thin",
                "out.a",
                "in.o",
            },
            .precreate_dir = "external" ++ sep ++ "zig_sdk" ++ sep ++ "lib",
            .want_result = .{
                .exec = .{
                    .args = &[_][:0]const u8{
                        "external" ++ sep ++ "zig_sdk" ++ sep ++ "zig" ++ EXE,
                        "ar",
                        "--format=gnu",
                        "csrD",
                        "out.a",
                        "in.o",
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
                        "-fno-sanitize=undefined",
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
            try tmp.dir.createDirPath(io, dir);

        var env = Environ.Map.init(allocator);
        var argv_it = TestArgIterator{ .argv = tt.args };
        const res = try parseArgs(allocator, io, tmp.dir, &argv_it, &env);

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

test "zig-wrapper:cache dir override" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    const io = std.testing.io;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = Environ.Map.init(allocator);
    var argv_it = TestArgIterator{ .argv = &[_][:0]const u8{
        "tools" ++ sep ++ "x86_64-linux-musl" ++ sep ++ "c++" ++ EXE,
        "main.c",
    } };
    const res = try parseArgs(allocator, io, tmp.dir, &argv_it, &env);

    const cache_dir = res.exec.env.get("ZIG_LOCAL_CACHE_DIR").?;
    const global_cache_dir = res.exec.env.get("ZIG_GLOBAL_CACHE_DIR").?;

    try testing.expectEqualStrings(cache_dir, global_cache_dir);
    try testing.expectEqualStrings(CACHE_DIR, cache_dir);
}

fn noExe(b: []const u8) []const u8 {
    if (builtin.target.os.tag == .windows and
        std.ascii.eqlIgnoreCase(".exe", b[b.len - 4 ..]))
        return b[0 .. b.len - 4];

    return b;
}
