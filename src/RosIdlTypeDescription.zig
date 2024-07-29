const RosIdlTypeDescription = @This();

const std = @import("std");
const PathFile = @import("RosIdlGenerator.zig").PathFile;
const RosIdlGenerator = @import("RosIdlGenerator.zig");

args: *RosIdlTypeDescriptionArgumentsStep,
generator: *std.Build.Step.Run,

const RosIdlTypeDescriptionArgumentsStep = struct {
    step: std.Build.Step,
    package_name: []const u8,
    output_dir: std.Build.LazyPath,
    include_paths: std.ArrayList(PathFile),
    args_write_file_step: *std.Build.Step.WriteFile,
    arguments_path: std.Build.LazyPath,
    idl_tuples: ?[]const []const u8,

    pub fn create(owner: *std.Build, package_name: []const u8, output_dir: std.Build.LazyPath) *RosIdlTypeDescriptionArgumentsStep {
        var self = owner.allocator.create(RosIdlTypeDescriptionArgumentsStep) catch @panic("OOM");
        const args_write_file = owner.addWriteFiles();
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "RosIdlTypeDescriptionArguments",
                .owner = owner,
                .makeFn = RosIdlTypeDescriptionArgumentsStep.make,
            }),
            .package_name = package_name,
            .output_dir = output_dir,
            .include_paths = std.ArrayList(PathFile).init(owner.allocator),
            .args_write_file_step = args_write_file,
            .arguments_path = args_write_file.getDirectory().path(owner, "rosidl_generator_type_description__arguments.json"),
            .idl_tuples = null, // Must be set before make runs
        };

        self.args_write_file_step.step.dependOn(&self.step);
        return self;
    }

    pub fn addIncludePath(self: *RosIdlTypeDescriptionArgumentsStep, include_path: PathFile) void {
        self.include_paths.append(.{
            .path = include_path.path.dupe(self.step.owner),
            .name = self.step.owner.dupe(include_path.name),
        }) catch @panic("OOM");
    }

    pub fn addIncludePaths(self: *RosIdlTypeDescriptionArgumentsStep, include_paths: []const PathFile) void {
        for (include_paths) |include_path| {
            self.addIncludePath(include_path.*);
        }
    }

    fn make(step: *std.Build.Step, prog_node: std.Progress.Node) anyerror!void {
        _ = prog_node;
        const b = step.owner;
        var self: *RosIdlTypeDescriptionArgumentsStep = @fieldParentPtr("step", step);

        var json_args_str = std.ArrayList(u8).init(b.allocator);

        var arena = std.heap.ArenaAllocator.init(b.allocator);
        defer arena.deinit();

        var string_include_paths = std.ArrayList([]const u8).init(arena.allocator());
        for (self.include_paths.items) |include_path| {
            try string_include_paths.append(try std.fmt.allocPrint(
                arena.allocator(),
                "{s}:{s}",
                .{ include_path.file, include_path.path.getPath(b) },
            ));
        }

        const idl_tuples = self.idl_tuples orelse @panic("type description argument generator step called without any idl tuples set!");

        try std.json.stringify(.{
            .package_name = self.package_name,
            .output_dir = self.output_dir.getPath(b),
            .idl_tuples = idl_tuples,
            .include_paths = string_include_paths.items,
        }, .{ .whitespace = .indent_2 }, json_args_str.writer());

        _ = self.args_write_file_step.add("rosidl_generator_type_description__arguments.json", json_args_str.items);
    }
};

pub fn create(generator: *RosIdlGenerator, package_name: []const u8, output_dir: std.Build.LazyPath) *RosIdlTypeDescription {
    const to_return = generator.owner.allocator.create(RosIdlTypeDescription) catch @panic("OOM");
    to_return.args = RosIdlTypeDescriptionArgumentsStep.create(generator.owner, package_name, output_dir);
    to_return.generator = RosIdlGenerator.pythonRunner(.{
        .b = generator.owner,
        .python_runner = generator.python_runner,
        .python_dependencies = &.{
            generator.rosidl_parser,
            generator.rosidl_pycommon,
            generator.rosidl_generator_type_description,
        },
        .python_executable = generator.rosidl_generator_type_description.getDirectory().path(
            generator.owner,
            "bin/rosidl_generator_type_description",
        ),
        .arguments = &.{
            .{ .string = "--generator-arguments-file" },
            .{ .lazy_path = to_return.args.arguments_path },
        },
    });
    to_return.generator.step.dependencies.appendSlice(&.{
        &generator.rosidl_parser.step,
        &generator.rosidl_pycommon.step,
        &generator.rosidl_generator_type_description.step,
        &to_return.args.step,
    }) catch @panic("OOM");

    to_return.args.step.dependOn(&generator.step);
    to_return.args.step.dependOn(generator.idl_step.getStep());

    return to_return;
}

// The top level RosIdlGenerator must call this in its make step before the arguments step runs
pub fn setIdlTuples(self: *RosIdlTypeDescription, idl_tuples: []const []const u8) void {
    self.args.idl_tuples = idl_tuples;
}
