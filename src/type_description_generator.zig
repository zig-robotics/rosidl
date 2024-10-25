const std = @import("std");
const builtin = @import("builtin");

// Usage:
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (builtin.mode == .Debug) {
        _ = gpa.deinit();
    };

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer if (builtin.mode == .Debug) {
        arena.deinit();
    };

    const args = try std.process.argsAlloc(arena.allocator());

    var package_name: ?[]const u8 = null;
    var output_dir: ?[]const u8 = null;
    var idl_tuples = std.ArrayList([]const u8).init(arena.allocator());
    var include_paths = std.ArrayList([]const u8).init(arena.allocator());

    var program: ?[]const u8 = null;
    var python_path_args = std.ArrayList([]const u8).init(arena.allocator());

    var logging = false;

    for (args[1..]) |arg| if (arg.len < 2) {
        std.log.err("invalid argument, length must be greater than 2", .{});
        return error.InvalidArgument;
    } else if (std.mem.eql(u8, "-P", arg[0..2])) {
        try python_path_args.append(arg[2..]);
    } else if (std.mem.eql(u8, "-X", arg[0..2])) {
        program = arg[2..];
    } else if (std.mem.eql(u8, "-D", arg[0..2])) {
        var it = std.mem.tokenizeAny(u8, arg[2..], ":");
        const idl = it.next() orelse return error.IdlTupleEmpty;
        const path = it.next() orelse return error.IdlTupleMissingDelimiter;
        try idl_tuples.append(try std.fmt.allocPrint(arena.allocator(), "{s}:{s}", .{ path, idl }));
    } else if (std.mem.eql(u8, "-I", arg[0..2])) {
        try include_paths.append(arg[2..]);
    } else if (std.mem.eql(u8, "-N", arg[0..2])) {
        if (package_name) |_| return error.MultiplePackageNamesProvided;
        package_name = arg[2..];
    } else if (std.mem.eql(u8, "-O", arg[0..2])) {
        if (output_dir) |_| return error.MultipleOutputDirsProvided;
        output_dir = arg[2..];
    } else if (std.mem.eql(u8, "-l", arg[0..2])) {
        logging = true;
        if (builtin.mode != .Debug) {
            std.log.info("Logging is set to true but build mode is not debug. Switch to debug to see logs.", .{});
        }
    };

    var json_args_str = std.ArrayList(u8).init(arena.allocator());

    try std.json.stringify(.{
        .package_name = package_name orelse return error.PackageNameNotProvided,
        .output_dir = output_dir orelse return error.OutputDirNotProvided,
        .idl_tuples = idl_tuples.items,
        .include_paths = include_paths.items,
    }, .{ .whitespace = .indent_2 }, json_args_str.writer());

    const args_file_path = try std.fmt.allocPrint(arena.allocator(), "{s}/rosidl_generator_type_description__arguments.json", .{
        output_dir orelse return error.OutputDirNotProvided,
    });
    var output_file = try std.fs.createFileAbsolute(args_file_path, .{});
    defer output_file.close();

    try output_file.writeAll(json_args_str.items);

    // TODO use the zig version of python
    var command_string = std.ArrayList(u8).init(arena.allocator());
    var writer = command_string.writer();
    if (python_path_args.items.len > 0) {
        try writer.writeAll("PYTHONPATH=");
        for (python_path_args.items) |python_path| {
            try writer.writeAll(python_path);
            try writer.writeAll(":");
        }
        // remove trailing :
        command_string.shrinkRetainingCapacity(command_string.items.len - 1);
    }

    try writer.print(" {s} ", .{
        program orelse {
            std.log.err("Error, no program provided!", .{});
            return error.NoProgram;
        },
    });

    try writer.print("--generator-arguments-file {s}", .{args_file_path});

    if (builtin.mode == .Debug and logging) {
        std.log.info("I'm going to run this command: {s}", .{command_string.items});
    }

    // TODO set env instead of using bash -c?
    // TODO python as a build artifact?
    var child = std.process.Child.init(&.{ "bash", "-c", command_string.items }, arena.allocator());

    child.stdin_behavior = .Ignore;

    if (logging) {
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
    } else {
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
    }

    try child.spawn();
    switch (try child.wait()) {
        .Exited => |val| return val,
        else => return error.ChildDidNotExit,
    }
    unreachable;
}
