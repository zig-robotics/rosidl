const RosIdlTypeDescription = @This();

const std = @import("std");
const RosIdlGenerator = @import("RosIdlGenerator.zig");

generator: *std.Build.Step.Run,
output: std.Build.LazyPath,

pub fn create(generator: *RosIdlGenerator, package_name: []const u8) *RosIdlTypeDescription {
    const to_return = generator.owner.allocator.create(RosIdlTypeDescription) catch @panic("OOM");
    to_return.generator = generator.owner.addRunArtifact(
        generator.type_description_generator,
    );

    to_return.output = to_return.generator.addPrefixedOutputDirectoryArg("-O", std.fmt.allocPrint(
        generator.owner.allocator,
        "{s}_rosidl_generator_type_description_output",
        .{package_name},
    ) catch @panic("OOM")); // use generator name and package name for uniquness

    to_return.generator.addArg(std.fmt.allocPrint(generator.owner.allocator, "-N{s}", .{package_name}) catch @panic("OOM"));
    to_return.generator.addPrefixedDirectoryArg("-P", generator.rosidl_parser.getDirectory());
    to_return.generator.addPrefixedDirectoryArg("-P", generator.rosidl_pycommon.getDirectory());
    to_return.generator.addPrefixedDirectoryArg("-P", generator.rosidl_generator_type_description.getDirectory());

    to_return.generator.addPrefixedFileArg(
        "-X",
        generator.rosidl_generator_type_description.getDirectory().path(
            generator.owner,
            "bin/rosidl_generator_type_description",
        ),
    );

    return to_return;
}

pub fn addIncludePath(
    self: *RosIdlTypeDescription,
    name: []const u8,
    path: std.Build.LazyPath,
) void {
    self.generator.addPrefixedDirectoryArg(
        std.fmt.allocPrint(
            self.generator.step.owner.allocator,
            "-I{s}:",
            .{name},
        ) catch @panic("OOM"),
        path,
    );
}

pub fn addIdlTuple(
    self: *RosIdlTypeDescription,
    name: []const u8,
    path: std.Build.LazyPath,
) void {
    self.generator.addPrefixedDirectoryArg(
        std.fmt.allocPrint(self.generator.step.owner.allocator, "-D{s}:", .{name}) catch @panic("OOM"),
        path,
    );
}
