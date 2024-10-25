const std = @import("std");
const RosIdlGenerator = @import("RosIdlGenerator.zig");

fn pascalToSnake(allocator: std.mem.Allocator, in: []const u8) std.mem.Allocator.Error![]const u8 {
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

        generator: *std.Build.Step.Run,
        generator_output: std.Build.LazyPath,
        package_name: []const u8,
        artifact: switch (code_type) {
            .c, .cpp => *std.Build.Step.Compile,
            .header_only => *std.Build.Step.WriteFile,
        },
        visibility_control_header: if (visibility_control) |_| *std.Build.Step.ConfigHeader else void,

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
            additional_python_paths: ?[]const std.Build.LazyPath,
        ) *Self {
            const to_return = generator.owner.allocator.create(Self) catch @panic("OOM");
            to_return.generator = generator.owner.addRunArtifact(generator.code_generator);

            to_return.generator_output = to_return.generator.addPrefixedOutputDirectoryArg("-O", std.fmt.allocPrint(
                generator.owner.allocator,
                "{s}_{s}_generator_output",
                .{ package_name, generator_name },
            ) catch @panic("OOM")); // use generator name and package name for uniquness

            // TODO should this dupe? really need to decide if we're being proper with memory everywhere...
            to_return.package_name = package_name;

            const package_name_upper = generator.owner.dupe(package_name);
            _ = std.ascii.upperString(package_name_upper, package_name_upper);

            const artifact_name = std.fmt.allocPrint(
                generator.owner.allocator,
                "{s}__{s}",
                .{ package_name, generator_name },
            ) catch @panic("OOM");
            defer generator.owner.allocator.free(artifact_name);

            var python_paths = std.ArrayList(std.Build.LazyPath).init(generator.owner.allocator);

            python_paths.appendSlice(&.{
                generator.rosidl_parser.getDirectory(),
                generator.rosidl_pycommon.getDirectory(),
                generator.rosidl_generator_type_description.getDirectory(),
                generator_root.getDirectory(),
            }) catch @panic("OOM");

            if (additional_python_paths) |paths| {
                python_paths.appendSlice(paths) catch @panic("OOM");
            }

            for (python_paths.items) |path| {
                to_return.generator.addPrefixedDirectoryArg("-P", path);
            }

            to_return.generator.addPrefixedFileArg(
                "-X",
                generator_root.getDirectory().path(generator.owner, std.fmt.allocPrint(
                    generator.owner.allocator,
                    "bin/{s}",
                    .{generator_name},
                ) catch @panic("OOM")),
            );

            to_return.generator.addArg(std.fmt.allocPrint(
                generator.owner.allocator,
                "-N{s}",
                .{package_name},
            ) catch @panic("OOM"));

            to_return.generator.addPrefixedDirectoryArg(
                "-T",
                generator_root.getDirectory().path(generator.owner, "resource"),
            );

            to_return.generator.addArg(std.fmt.allocPrint(
                generator.owner.allocator,
                "-G{s}",
                .{generator_name},
            ) catch @panic("OOM"));

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
                    }, .include_path = std.fmt.allocPrint(
                        generator.owner.allocator,
                        "{s}/msg/{s}__visibility_control.{s}",
                        .{ package_name, generator_name, @tagName(control_type) },
                    ) catch @panic("OOM") },
                    .{ .PROJECT_NAME = package_name, .PROJECT_NAME_UPPER = package_name_upper },
                );
                to_return.visibility_control_header.step.dependOn(&generator_root.step);
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
                    to_return.artifact.addIncludePath(to_return.generator_output);
                    to_return.artifact.installHeadersDirectory(
                        to_return.generator_output,
                        "",
                        .{ .include_extensions = &.{ ".h", ".hpp" } },
                    );
                    if (visibility_control) |_| {
                        to_return.artifact.addConfigHeader(to_return.visibility_control_header);
                        to_return.artifact.installConfigHeader(to_return.visibility_control_header);
                    }
                },
                .header_only => {
                    to_return.artifact = generator.owner.addNamedWriteFiles(std.fmt.allocPrint(
                        generator.owner.allocator,
                        "{s}__{s}",
                        .{ package_name, generator_name },
                    ) catch @panic("OOM"));
                    _ = to_return.artifact.addCopyDirectory(
                        to_return.generator_output.path(generator.owner, package_name), // This is a work around for the CPP generator which seems to include the package name automatically where the c generator did not. Other generators may or may not require this extra dir, we'll see
                        package_name,
                        .{ .include_extensions = &.{ ".h", ".hpp" } },
                    );
                    if (visibility_control) |_| {
                        _ = to_return.artifact.addCopyFile(
                            to_return.visibility_control_header.getOutput(),
                            to_return.visibility_control_header.include_path,
                        );
                    }
                },
            }

            return to_return;
        }

        // TODO move batched call to here so we can group the call to add c source files?
        pub fn addInterface(self: *Self, path: std.Build.LazyPath, interface: []const u8) void {
            self.generator.addPrefixedDirectoryArg(
                "-I",
                path.path(self.generator.step.owner, interface),
            );
            self.addInterfaceFiles(interface);
        }

        pub fn addIdlTuple(
            self: *Self,
            name: []const u8,
            path: std.Build.LazyPath,
        ) void {
            self.generator.addPrefixedDirectoryArg(
                std.fmt.allocPrint(
                    self.generator.step.owner.allocator,
                    "-D{s}:",
                    .{name},
                ) catch @panic("OOM"),
                path,
            );
        }

        pub fn addTypeDescription(
            self: *Self,
            name: []const u8,
            path: std.Build.LazyPath,
        ) void {
            self.generator.addPrefixedDirectoryArg(
                std.fmt.allocPrint(
                    self.generator.step.owner.allocator,
                    "-Y{s}:",
                    .{name},
                ) catch @panic("OOM"),
                path,
            );
        }

        pub fn addInterfaceFiles(self: *Self, interface: []const u8) void {
            // TODO this does nice memory management while basically nowhere else does
            var arena = std.heap.ArenaAllocator.init(self.generator.step.owner.allocator);
            defer arena.deinit();

            switch (code_type) {
                .c, .cpp => {
                    var c_files = std.ArrayList([]u8).init(arena.allocator());
                    defer c_files.deinit();

                    var it = std.mem.tokenizeAny(u8, interface, "/.");
                    var suffix: []const u8 = "";
                    var base_in: ?[]const u8 = null;
                    // second last token should be our base file
                    while (it.next()) |token| {
                        base_in = suffix;
                        suffix = token;
                    }
                    const base = pascalToSnake(
                        arena.allocator(),
                        base_in orelse @panic("Bad input file"),
                    ) catch @panic("OOM");
                    inline for (source_templates) |template| {
                        c_files.append(std.fmt.allocPrint(
                            arena.allocator(),
                            template,
                            .{ self.package_name, suffix, base },
                        ) catch @panic("OOM")) catch @panic("OOM");
                    }

                    switch (code_type) {
                        .c => {
                            self.artifact.addCSourceFiles(.{
                                .root = self.generator_output,
                                .files = c_files.items,
                            });
                            self.artifact.linkLibC();
                        },
                        .cpp => {
                            self.artifact.addCSourceFiles(.{
                                .root = self.generator_output,
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
    };
}
