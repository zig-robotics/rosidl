const std = @import("std");
const builtin = @import("builtin");

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
    var generator_name: ?[]const u8 = null;
    var output_dir: ?[]const u8 = null;
    var template_dir: ?[]const u8 = null;
    var program: ?[]const u8 = null;
    var idl_tuples = std.ArrayList([]const u8).init(arena.allocator());
    var type_description_tuples = std.ArrayList([]const u8).init(arena.allocator());
    var interface_files = std.ArrayList([]const u8).init(arena.allocator());
    var python_path_args = std.ArrayList([]const u8).init(arena.allocator());
    var additional_args = std.ArrayList([]const u8).init(arena.allocator());

    var logging = false;

    for (args[1..]) |arg| if (arg.len < 2) {
        std.log.err("invalid argument, length must be greater than 2", .{});
        return error.InvalidArgument;
    } else if (std.mem.eql(u8, "-X", arg[0..2])) {
        program = arg[2..];
    } else if (std.mem.eql(u8, "-P", arg[0..2])) {
        try python_path_args.append(arg[2..]);
    } else if (std.mem.eql(u8, "-A", arg[0..2])) {
        try additional_args.append(arg[2..]);
    } else if (std.mem.eql(u8, "-D", arg[0..2])) {
        var it = std.mem.tokenizeAny(u8, arg[2..], ":");
        const idl = it.next() orelse return error.IdlTupleEmpty;
        const path = it.next() orelse return error.IdlTupleMissingDelimiter;
        try idl_tuples.append(try std.fmt.allocPrint(arena.allocator(), "{s}:{s}", .{ path, idl }));
    } else if (std.mem.eql(u8, "-Y", arg[0..2])) {
        try type_description_tuples.append(arg[2..]);
    } else if (std.mem.eql(u8, "-I", arg[0..2])) {
        try interface_files.append(arg[2..]);
    } else if (std.mem.eql(u8, "-N", arg[0..2])) {
        if (package_name) |_| return error.MultiplePackageNamesProvided;
        package_name = arg[2..];
    } else if (std.mem.eql(u8, "-G", arg[0..2])) {
        if (generator_name) |_| return error.MultipleGeneratorNamesProvided;
        generator_name = arg[2..];
    } else if (std.mem.eql(u8, "-O", arg[0..2])) {
        if (output_dir) |_| return error.MultipleOutputDirsProvided;
        output_dir = arg[2..];
    } else if (std.mem.eql(u8, "-T", arg[0..2])) {
        if (template_dir) |_| return error.MultipleTemplateDirsProvided;
        template_dir = arg[2..];
    } else if (std.mem.eql(u8, "-l", arg[0..2])) {
        logging = true;
        if (builtin.mode != .Debug) {
            std.log.info("Logging is set to true but build mode is not debug. Switch to debug to see logs.", .{});
        }
    };

    var json_args_str = std.ArrayList(u8).init(arena.allocator());

    const ros_interface_dependencies: []const []const u8 = &.{}; // TODO dependencies (no generator actually uses these it seems)
    const target_dependencies: []const []const u8 = &.{}; // TODO dependencies (no generator actually uses these it seems) TODO the upstream IDL files seem to end up here again? also there's boiler plate depenedncies that we don't seem to need?

    try std.json.stringify(.{
        .package_name = package_name orelse return error.PackageNameNotProvided,
        .output_dir = try std.fmt.allocPrint(arena.allocator(), "{s}/{s}", .{
            output_dir orelse return error.OutputDirNotProvided,
            package_name orelse return error.PackageNameNotProvided, // Need to include package name for header paths to work
        }),
        .template_dir = template_dir orelse return error.TemplateDirNotProvided,
        .idl_tuples = idl_tuples.items,
        .ros_interface_files = interface_files.items,
        .ros_interface_dependencies = ros_interface_dependencies,
        .target_dependencies = target_dependencies,
        .type_description_tuples = type_description_tuples.items,
    }, .{ .whitespace = .indent_2 }, json_args_str.writer());

    const args_file_path = try std.fmt.allocPrint(arena.allocator(), "{s}/{s}__arguments.json", .{
        output_dir orelse return error.OutputDirNotProvided,
        generator_name orelse return error.GeneratorNameNotProvided,
    });
    var output_file = try std.fs.createFileAbsolute(args_file_path, .{});
    defer output_file.close();

    try output_file.writeAll(json_args_str.items);
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

    try writer.print(" --generator-arguments-file {s}", .{args_file_path});

    for (additional_args.items) |arg| {
        try writer.print(" {s}", .{arg});
    }

    if (builtin.mode == .Debug and logging) {
        std.log.info("I'm going to run this command: {s}", .{command_string.items});
    }

    // TODO set env instead of using bash -c?
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
