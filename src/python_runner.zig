const std = @import("std");
const builtin = @import("builtin");

// {set cwd} PYTHONPATH=somepath:somepath:somepath rosidl_adapter std_msgs/msg/Int32.msg
// {set cwd} PYTHONPATH=somepath:somepath:somepath rosidl_generator_type_description --generator-arguments-file path_to_some_file

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

    var python_path_args = std.ArrayList([]const u8).init(arena.allocator());

    var current_working_directory: ?[]const u8 = null;

    var logging = false;

    var program: ?[]const u8 = null;
    var program_args = std.ArrayList([]const u8).init(arena.allocator());

    for (args[1..]) |arg| if (std.mem.eql(u8, "-P", arg[0..2])) {
        try python_path_args.append(arg[2..]);
    } else if (std.mem.eql(u8, "-D", arg[0..2])) {
        if (current_working_directory == null) {
            current_working_directory = arg[2..];
        } else {
            std.log.err("Error, more than one working directory specified!", .{});
            return error.MoreThanOneWorkingDir;
        }
    } else if (std.mem.eql(u8, "-l", arg[0..2])) {
        logging = true;
        if (builtin.mode != .Debug) {
            std.log.info("Logging is set to true but build mode is not debug. Switch to debug to see logs.", .{});
        }
    } else {
        if (program == null) {
            program = arg;
        } else {
            try program_args.append(arg);
        }
    };
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

    for (program_args.items) |python_path| {
        try writer.print(" {s}", .{python_path});
    }

    if (builtin.mode == .Debug and logging) {
        std.log.info("I'm going to run this command: {s}", .{command_string.items});
    }

    // TODO set env instead of using bash -c?
    var child = std.process.Child.init(&.{ "bash", "-c", command_string.items }, arena.allocator());
    if (current_working_directory) |cwd| {
        child.cwd = cwd;
    }

    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    switch (try child.wait()) {
        .Exited => |val| return val,
        else => return error.ChildDidNotExit,
    }
    unreachable;
}
