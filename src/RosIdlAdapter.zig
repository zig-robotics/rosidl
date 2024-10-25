const Interface2Idl = @This();

const std = @import("std");
const RosIdlGenerator = @import("RosIdlGenerator.zig");

generator: *std.Build.Step.Run,
output: std.Build.LazyPath,

pub fn create(generator: *RosIdlGenerator, package_name: []const u8) *Interface2Idl {
    const to_return = generator.owner.allocator.create(Interface2Idl) catch @panic("OOM");
    to_return.generator = generator.owner.addRunArtifact(generator.adapter_generator);

    to_return.output = to_return.generator.addPrefixedOutputDirectoryArg(
        "-O",
        std.fmt.allocPrint(
            generator.owner.allocator,
            "{s}__rosidl_adapter_output",
            .{package_name},
        ) catch @panic("OOM"),
    );
    to_return.generator.addArg(std.fmt.allocPrint(
        generator.owner.allocator,
        "-N{s}",
        .{package_name},
    ) catch @panic("OOM"));

    to_return.generator.addPrefixedDirectoryArg("-P", generator.rosidl_cli.getDirectory());
    to_return.generator.addPrefixedDirectoryArg("-P", generator.rosidl_adapter.getDirectory());
    to_return.generator.addPrefixedDirectoryArg("-P", generator.rosidl_parser.getDirectory());
    to_return.generator.addPrefixedDirectoryArg("-P", generator.rosidl_pycommon.getDirectory());

    return to_return;
}

pub fn addInterface(self: *Interface2Idl, path: std.Build.LazyPath, interface: []const u8) void {
    self.generator.addPrefixedDirectoryArg(
        std.fmt.allocPrint(
            self.generator.step.owner.allocator,
            "-D{s}:",
            .{interface},
        ) catch @panic("OOM"),
        path,
    );
}
