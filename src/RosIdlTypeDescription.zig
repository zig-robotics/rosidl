const RosIdlTypeDescription = @This();

const std = @import("std");
const RosIdlGenerator = @import("RosIdlGenerator.zig");

args: *RosIdlTypeDescriptionArgumentsStep,
generator: *std.Build.Step.Run,

const RosIdlTypeDescriptionArgumentsStep = struct {
    step: std.Build.Step,
    package_name: []const u8,
    output_dir: std.Build.LazyPath,
    args_write_file_step: *std.Build.Step.WriteFile,
    arguments_path: std.Build.LazyPath,
    idl_tuples: ?[]const []const u8,
    include_paths: ?[]const []const u8,

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
            .args_write_file_step = args_write_file,
            .arguments_path = args_write_file.getDirectory().path(owner, "rosidl_generator_type_description__arguments.json"),
            .idl_tuples = null, // Must be set before make runs
            .include_paths = null, // optionally set before make runs
        };

        self.args_write_file_step.step.dependOn(&self.step);
        return self;
    }

    fn make(step: *std.Build.Step, prog_node: std.Progress.Node) anyerror!void {
        _ = prog_node;
        const b = step.owner;
        var self: *RosIdlTypeDescriptionArgumentsStep = @fieldParentPtr("step", step);

        var json_args_str = std.ArrayList(u8).init(b.allocator);

        const idl_tuples = self.idl_tuples orelse @panic("type description argument generator step called without any idl tuples set!");

        const include_paths = self.include_paths orelse &.{};

        try std.json.stringify(.{
            .package_name = self.package_name,
            .output_dir = self.output_dir.getPath(b),
            .idl_tuples = idl_tuples,
            .include_paths = include_paths,
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
        .enable_logging = false,
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
// Top level RosIdlGenerator must maintain the idl_tuples str passed in.
// This lets each generator use the same strings, avoiding copies.
pub fn setIdlTuples(self: *RosIdlTypeDescription, idl_tuples: []const []const u8) void {
    self.args.idl_tuples = idl_tuples;
}

// The top level RosIdlGenerator may call this if this package has dependencies
// Top level RosIdlGenerator must maintain the include_paths str passed in.
// This lets each generator use the same strings, avoiding copies.
pub fn setIncludePaths(self: *RosIdlTypeDescription, include_paths: []const []const u8) void {
    self.args.include_paths = include_paths;
}
