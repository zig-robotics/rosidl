const std = @import("std");
const RosIdlGenerator = @import("RosIdlGenerator.zig");

fn pascalToSnake(allocator: std.mem.Allocator, in: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    var prev_is_lower = false;
    if (in.len == 0) return "";

    try out.append(std.ascii.toLower(in[0]));

    const isLower = std.ascii.isLower;
    const isUpper = std.ascii.isUpper;
    const isDigit = std.ascii.isDigit;

    if (in.len > 2) {
        for (in[0 .. in.len - 2], in[1 .. in.len - 1], in[2..]) |previous, current, next| {
            if ((isLower(previous) and isUpper(current)) or
                (isUpper(current) and isLower(next)) or
                (isDigit(previous) and isUpper(current)))
            {
                try out.append('_');
                prev_is_lower = false;
            }
            try out.append(std.ascii.toLower(current));
        }
        try out.append(std.ascii.toLower(in[in.len - 1]));
    } else if (in.len == 2) {
        try out.append(std.ascii.toLower(in[1]));
    }

    return out.toOwnedSlice();
}

test pascalToSnake {
    var allocator = std.testing.allocator;

    const empty_string = try pascalToSnake(allocator, "");
    defer allocator.free(empty_string);
    try std.testing.expectEqualSlices(u8, "", empty_string);

    const single = try pascalToSnake(allocator, "A");
    defer allocator.free(single);
    try std.testing.expectEqualSlices(u8, "a", single);

    const double = try pascalToSnake(allocator, "Ab");
    defer allocator.free(double);
    try std.testing.expectEqualSlices(u8, "ab", double);

    const double2 = try pascalToSnake(allocator, "AB");
    defer allocator.free(double2);
    try std.testing.expectEqualSlices(u8, "ab", double2);

    const multi = try pascalToSnake(allocator, "TestPascal42");
    defer allocator.free(multi);
    try std.testing.expectEqualSlices(u8, "test_pascal42", multi);

    const all_upper = try pascalToSnake(allocator, "GID");
    defer allocator.free(all_upper);
    try std.testing.expectEqualSlices(u8, "gid", all_upper);

    const leading_upper = try pascalToSnake(allocator, "GPSFix");
    defer allocator.free(leading_upper);
    try std.testing.expectEqualSlices(u8, "gps_fix", leading_upper);

    const trailing_upper = try pascalToSnake(allocator, "FileUUID");
    defer allocator.free(trailing_upper);
    try std.testing.expectEqualSlices(u8, "file_uuid", trailing_upper);

    const mid_upper = try pascalToSnake(allocator, "FileUUIDTest");
    defer allocator.free(mid_upper);
    try std.testing.expectEqualSlices(u8, "file_uuid_test", mid_upper);

    const a_bit_of_everything = try pascalToSnake(allocator, "File42GPS7T3st6Wow");
    defer allocator.free(a_bit_of_everything);
    try std.testing.expectEqualSlices(u8, "file42_gps7_t3st6_wow", a_bit_of_everything);
}

pub const CodeType = enum {
    c,
    cpp,
    header_only,
};

pub const VisibilityControlType = enum {
    h,
    hpp,
};

// source template must accept three strings in the order "package", "type (msg/srv/action)", "name"
pub fn CodeGenerator(
    comptime code_type: CodeType,
    comptime visibility_control: ?VisibilityControlType,
    comptime source_templates: []const []const u8,
) type {
    return struct {
        const Self = @This();

        args: *ArgumentsStep,
        generator: *std.Build.Step.Run,
        source_dir: *std.Build.Step.WriteFile,
        artifact: switch (code_type) {
            .c, .cpp => *std.Build.Step.Compile,
            .header_only => *std.Build.Step.WriteFile,
        },
        visibility_control_header: if (visibility_control) |_| *std.Build.Step.ConfigHeader else void,

        const ArgumentsStep = struct {
            step: std.Build.Step,
            package_name: []const u8,
            output_dir: std.Build.LazyPath,
            template_dir: std.Build.LazyPath,
            idl_tuples: ?[]const []const u8,
            ros_interface_files: ?[]const []const u8,
            ros_interface_dependencies: ?[]const []const u8,
            target_dependencies: ?[]const []const u8,
            type_description_tuples: ?[]const []const u8,
            file_name: []const u8,
            args_write_file_step: *std.Build.Step.WriteFile,
            arguments_path: std.Build.LazyPath,

            pub fn create(
                owner: *std.Build,
                generator_name: []const u8,
                package_name: []const u8,
                output_dir: *std.Build.Step.WriteFile,
                template_dir: *std.Build.Step.WriteFile,
            ) *ArgumentsStep {
                var self = owner.allocator.create(ArgumentsStep) catch @panic("OOM");
                const args_write_file = owner.addWriteFiles();

                const file_name = std.fmt.allocPrint(owner.allocator, "{s}__arguments.json", .{generator_name}) catch @panic("OOM");
                self.* = .{
                    .step = std.Build.Step.init(.{
                        .id = .custom,
                        .name = generator_name, // In other steps, the name seems to also just be the step type?
                        .owner = owner,
                        .makeFn = ArgumentsStep.make,
                    }),
                    .package_name = owner.dupe(package_name),
                    .output_dir = output_dir.getDirectory().path(owner, package_name),
                    .template_dir = template_dir.getDirectory().path(owner, "resource"),
                    .idl_tuples = null, // must be set before make
                    .ros_interface_files = null, // must be set before make
                    .ros_interface_dependencies = null, // must be set before make
                    .target_dependencies = null, // must be set before make
                    .type_description_tuples = null, // must be set before make
                    .file_name = file_name,
                    .args_write_file_step = args_write_file,
                    .arguments_path = args_write_file.getDirectory().path(owner, file_name),
                };

                self.args_write_file_step.step.name = "WriteFile Arguments";

                self.args_write_file_step.step.dependOn(&self.step);
                self.step.dependOn(&template_dir.step);
                self.step.dependOn(&output_dir.step);
                return self;
            }

            fn make(step: *std.Build.Step, prog_node: std.Progress.Node) anyerror!void {
                _ = prog_node;
                const b = step.owner;
                var self: *ArgumentsStep = @fieldParentPtr("step", step);

                var json_args_str = std.ArrayList(u8).init(b.allocator);

                const idl_tuples = self.idl_tuples orelse @panic("argument generator step called without any idl tuples set!");
                const ros_interface_files = self.ros_interface_files orelse @panic("argument generator step called without any ROS interface files set!");
                const ros_interface_dependencies = self.ros_interface_dependencies orelse &.{}; // No dependencies
                const target_dependencies = self.target_dependencies orelse &.{}; // no dependencies; TODO the upstream IDL files seem to end up here again? also there's boiler plate depenedncies that we don't seem to need?
                const type_description_tuples = self.type_description_tuples orelse @panic("argument generator step called without any type description tuples set!");

                try std.json.stringify(.{
                    .package_name = self.package_name,
                    .output_dir = self.output_dir.getPath(b),
                    .template_dir = self.template_dir.getPath(b),
                    .idl_tuples = idl_tuples,
                    .ros_interface_files = ros_interface_files,
                    .ros_interface_dependencies = ros_interface_dependencies,
                    .target_dependencies = target_dependencies,
                    .type_description_tuples = type_description_tuples,
                }, .{ .whitespace = .indent_2 }, json_args_str.writer());

                _ = self.args_write_file_step.add(self.file_name, try json_args_str.toOwnedSlice());
            }
        };

        const Libraries = union(enum) {
            lib: *std.Build.Step.Compile,
            header_only: *std.Build.Step.WriteFile,
        };

        pub fn create(
            generator: *RosIdlGenerator,
            package_name: []const u8,
            target: std.Build.ResolvedTarget,
            optimize: std.builtin.OptimizeMode,
            linkage: std.builtin.LinkMode,
            generator_name: []const u8,
            generator_root: *std.Build.Step.WriteFile,
            link_libs: ?[]const Libraries,
            additional_python_paths: ?[]const *std.Build.Step.WriteFile,
        ) *Self {
            const to_return = generator.owner.allocator.create(Self) catch @panic("OOM");
            const generator_output = generator.owner.addWriteFiles();
            _ = generator_output.add(std.fmt.allocPrint(generator.owner.allocator, "{s}_{s}_generator_output", .{ package_name, generator_name }) catch @panic("OOM"), generator_name); // dump the generator name to make unique, zig seems to issue the same cache dir if the write file does not contain a unique structure at make time (an issue for us since we create blank write files if there's no visibility control file)
            generator_output.step.name = "generator output write files";
            const args = ArgumentsStep.create(
                generator.owner,
                generator_name,
                package_name,
                generator_output,
                generator_root,
            );

            const package_name_upper = generator.owner.dupe(package_name);
            _ = std.ascii.upperString(package_name_upper, package_name_upper);

            const artifact_name = std.fmt.allocPrint(generator.owner.allocator, "{s}__{s}", .{ package_name, generator_name }) catch @panic("OOM");
            defer generator.owner.allocator.free(artifact_name);

            var python_paths = std.ArrayList(*std.Build.Step.WriteFile).init(generator.owner.allocator);

            python_paths.appendSlice(&.{
                generator.rosidl_parser,
                generator.rosidl_pycommon,
                generator.rosidl_generator_type_description,
                generator_root,
            }) catch @panic("OOM");

            if (additional_python_paths) |paths| {
                python_paths.appendSlice(paths) catch @panic("OOM");
            }

            to_return.* = Self{
                .args = args,
                .generator = RosIdlGenerator.pythonRunner(.{
                    .b = generator.owner,
                    .python_runner = generator.python_runner,
                    .python_dependencies = python_paths.toOwnedSlice() catch @panic("OOM"),
                    .python_executable = generator_root.getDirectory().path(generator.owner, std.fmt.allocPrint(
                        generator.owner.allocator,
                        "bin/{s}",
                        .{generator_name},
                    ) catch @panic("OOM")),
                    // .python_executable_root = generator_root.getDirectory(),
                    // .python_executable_sub_path = std.fmt.allocPrint(generator.owner.allocator, "bin/{s}", .{generator_name}) catch @panic("OOM"),
                    .arguments = &.{
                        .{ .string = "--generator-arguments-file" },
                        .{ .lazy_path = args.arguments_path },
                    },
                    .enable_logging = false,
                }),
                .source_dir = generator.owner.addWriteFiles(),
                .artifact = undefined,
                .visibility_control_header = undefined,
            };

            _ = to_return.source_dir.add(std.fmt.allocPrint(generator.owner.allocator, "{s}_source", .{artifact_name}) catch @panic("OOM"), generator_name); // for uniqueness

            to_return.source_dir.step.name = "write file actual source dir";
            _ = to_return.source_dir.addCopyDirectory(
                generator_output.getDirectory(),
                "",
                .{ .include_extensions = &.{ ".c", ".cpp", ".h", ".hpp" } },
            );
            to_return.source_dir.step.dependOn(&to_return.generator.step);

            to_return.generator.step.dependencies.appendSlice(&.{
                &generator.rosidl_parser.step,
                &generator.rosidl_pycommon.step,
                &generator.rosidl_generator_type_description.step,
                &generator_root.step,
                &to_return.args.step,
                &generator_output.step,
            }) catch @panic("OOM");

            to_return.args.step.dependOn(&generator.step);

            if (visibility_control) |control_type| {
                to_return.visibility_control_header = generator.owner.addConfigHeader(
                    .{ .style = .{
                        .cmake = generator_root.getDirectory()
                            .path(
                            generator.owner,
                            std.fmt.allocPrint(
                                generator.owner.allocator,
                                "resource/{s}__visibility_control.{s}.in",
                                .{ generator_name, @tagName(control_type) },
                            ) catch @panic("OOM"),
                        ),
                    } },
                    .{ .PROJECT_NAME = package_name, .PROJECT_NAME_UPPER = package_name_upper },
                );
                to_return.visibility_control_header.step.dependOn(&generator_root.step);
                generator_output.step.dependOn(&to_return.visibility_control_header.step);

                const visibility_control_output =
                    std.fmt.allocPrint(generator.owner.allocator, "{s}/msg/{s}__visibility_control.{s}", .{
                    package_name,
                    generator_name,
                    @tagName(control_type),
                }) catch @panic("OOM");
                defer generator.owner.allocator.free(visibility_control_output);

                _ = generator_output.addCopyFile(to_return.visibility_control_header.getOutput(), visibility_control_output);
            }

            switch (code_type) {
                .c, .cpp => {
                    to_return.artifact = std.Build.Step.Compile.create(generator.owner, .{
                        .root_module = .{
                            .target = target,
                            .optimize = optimize,
                        },
                        .name = artifact_name,
                        .kind = .lib,
                        .linkage = linkage,
                    });

                    to_return.artifact.addIncludePath(generator.rosidl_typesupport_interface.getDirectory());
                    if (link_libs) |libs| for (libs) |lib| switch (lib) {
                        .lib => |l| to_return.artifact.linkLibrary(l),
                        .header_only => |h| to_return.artifact.addIncludePath(h.getDirectory()),
                    };
                    to_return.artifact.linkLibrary(generator.rcutils);
                    to_return.artifact.addIncludePath(to_return.source_dir.getDirectory());
                    to_return.artifact.installHeadersDirectory(
                        to_return.source_dir.getDirectory(),
                        "",
                        .{ .include_extensions = &.{ ".h", ".hpp" } },
                    );

                    to_return.artifact.step.dependOn(&to_return.source_dir.step);
                },
                .header_only => {
                    to_return.artifact = generator.owner.addNamedWriteFiles(std.fmt.allocPrint(
                        generator.owner.allocator,
                        "{s}__{s}",
                        .{ package_name, generator_name },
                    ) catch @panic("OOM"));
                    _ = to_return.artifact.addCopyDirectory(
                        to_return.source_dir.getDirectory().path(generator.owner, package_name), // This is a work around for the CPP generator which seems to include the package name automatically where the c generator did not. Other generators may or may not require this extra dir, we'll see
                        package_name,
                        .{ .include_extensions = &.{ ".h", ".hpp" } },
                    );
                },
            }

            // TODO dependencies
            return to_return;
        }

        // The top level RosIdlGenerator must call this in its make step before the arguments step runs
        pub fn setIdlTuples(self: *Self, idl_tuples: []const []const u8) void {
            self.args.idl_tuples = idl_tuples;
        }

        // The top level RosIdlGenerator must call this in its make step before the arguments step runs
        pub fn setRosInterfaceFiles(self: *Self, allocator: std.mem.Allocator, files: []const []const u8) !void {
            self.args.ros_interface_files = files;
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            switch (code_type) {
                .c, .cpp => {
                    var c_files = std.ArrayList([]u8).init(arena.allocator());
                    defer c_files.deinit();

                    for (files) |file| {
                        var it = std.mem.tokenizeAny(u8, file, "/.");
                        var suffix: []const u8 = "";
                        var base_in: ?[]const u8 = null;
                        // second last token should be our base file
                        while (it.next()) |token| {
                            base_in = suffix;
                            suffix = token;
                        }
                        const base = try pascalToSnake(arena.allocator(), base_in orelse return error.InvalidFile);
                        inline for (source_templates) |template| {
                            try c_files.append(try std.fmt.allocPrint(arena.allocator(), template, .{ self.args.package_name, suffix, base }));
                        }
                    }

                    switch (code_type) {
                        .c => {
                            self.artifact.addCSourceFiles(.{
                                .root = self.source_dir.getDirectory(),
                                .files = c_files.items,
                            });
                            self.artifact.linkLibC();
                        },
                        .cpp => {
                            self.artifact.addCSourceFiles(.{
                                .root = self.source_dir.getDirectory(),
                                .files = c_files.items,
                                .flags = &.{"--std=c++17"},
                            });
                            self.artifact.linkLibCpp();
                        },
                        .header_only => {},
                    }
                },
                .header_only => {},
            }
        }

        // The top level RosIdlGenerator may call this in its make step before the arguments step runs
        pub fn setRosInterfaceDependencies(self: *Self, files: []const []const u8) void {
            self.args.ros_interface_dependencies = files;
        }

        // The top level RosIdlGenerator may call this in its make step before the arguments step runs
        pub fn setTargetDependencies(self: *Self, files: []const []const u8) void {
            self.args.target_dependencies = files;
        }

        // The top level RosIdlGenerator must call this in its make step before the arguments step runs
        pub fn setTypeDescriptionTuples(self: *Self, files: []const []const u8) void {
            self.args.type_description_tuples = files;
        }
    };
}
