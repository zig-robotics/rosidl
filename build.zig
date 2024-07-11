const std = @import("std");

// Adds a named write file and install step using the given name and path.
// Optionally include a binary directory as well
fn exportPythonLibrary(b: *std.Build, name: []const u8, source_path: std.Build.LazyPath, bin_path: ?std.Build.LazyPath) void {
    var write_files = b.addNamedWriteFiles(name);

    // TODO figure out way to exclude test directories?
    _ = write_files.addCopyDirectory(source_path, "", .{ .include_extensions = &.{ ".py", ".em", ".in", ".json" } });

    if (bin_path) |bin| {
        _ = write_files.addCopyDirectory(bin, "bin", .{});
    }

    // Install step is optional really, it's just nice to have if local builds want to use the output in zig-out
    var install_step = b.addInstallDirectory(.{
        .source_dir = write_files.getDirectory(),
        .install_dir = .{ .custom = "python" },
        .install_subdir = name,
    });
    install_step.step.dependOn(&write_files.step);
    b.getInstallStep().dependOn(&install_step.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const linkage =
        b.option(std.builtin.LinkMode, "linkage", "Specify static or dynamic linkage") orelse .dynamic;
    const upstream = b.dependency("rosidl", .{});

    const rcutils_dep = b.dependency("rcutils", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    var rosidl_typesupport_interface = b.addNamedWriteFiles("rosidl_typesupport_interface");
    _ = rosidl_typesupport_interface.addCopyDirectory(upstream.path("rosidl_typesupport_interface/include"), "", .{});

    // Install step is optional really, it's just nice to have if local builds want to use the output in zig-out
    var rosidl_typesupport_interface_install = b.addInstallDirectory(.{
        .source_dir = rosidl_typesupport_interface.getDirectory(),
        .install_dir = .header,
        .install_subdir = "",
    });
    rosidl_typesupport_interface_install.step.dependOn(&rosidl_typesupport_interface.step);
    b.getInstallStep().dependOn(&rosidl_typesupport_interface_install.step);

    var rosidl_runtime_c = std.Build.Step.Compile.create(b, .{
        .root_module = .{
            .target = target,
            .optimize = optimize,
        },
        .name = "rosidl_runtime_c",
        .kind = .lib,
        .linkage = linkage,
    });

    rosidl_runtime_c.linkLibC();
    rosidl_runtime_c.step.dependOn(&rosidl_typesupport_interface.step);
    rosidl_runtime_c.linkLibrary(rcutils_dep.artifact("rcutils"));
    rosidl_runtime_c.addIncludePath(rosidl_typesupport_interface.getDirectory());
    rosidl_runtime_c.addIncludePath(upstream.path("rosidl_runtime_c/include"));

    rosidl_runtime_c.addCSourceFiles(.{
        .root = upstream.path("rosidl_runtime_c"),
        .files = &.{
            "src/message_type_support.c",
            "src/primitives_sequence_functions.c",
            "src/sequence_bound.c",
            "src/service_type_support.c",
            "src/string_functions.c",
            "src/type_hash.c",
            "src/u16string_functions.c",
            "src/type_description_utils.c",
            "src/type_description/field__description.c",
            "src/type_description/field__functions.c",
            "src/type_description/field_type__description.c",
            "src/type_description/field_type__functions.c",
            "src/type_description/individual_type_description__description.c",
            "src/type_description/individual_type_description__functions.c",
            "src/type_description/key_value__description.c",
            "src/type_description/key_value__functions.c",
            "src/type_description/type_description__description.c",
            "src/type_description/type_description__functions.c",
            "src/type_description/type_source__description.c",
            "src/type_description/type_source__functions.c",
        },
    });

    rosidl_runtime_c.installHeadersDirectory(
        upstream.path("rosidl_runtime_c/include"),
        "",
        .{},
    );
    b.installArtifact(rosidl_runtime_c);

    // rosidl_runtime_cpp is header only
    var rosidl_runtime_cpp = b.addNamedWriteFiles("rosidl_runtime_cpp");
    _ = rosidl_runtime_cpp.addCopyDirectory(upstream.path("rosidl_runtime_cpp/include"), "", .{});

    // Install step is optional really
    var rosidl_runtime_cpp_install = b.addInstallDirectory(.{
        .source_dir = rosidl_runtime_cpp.getDirectory(),
        .install_dir = .header,
        .install_subdir = "",
    });
    rosidl_runtime_cpp_install.step.dependOn(&rosidl_runtime_cpp.step);
    b.getInstallStep().dependOn(&rosidl_runtime_cpp_install.step);

    var rosidl_typesupport_introspection_c = std.Build.Step.Compile.create(b, .{
        .root_module = .{
            .target = target,
            .optimize = optimize,
        },
        .name = "rosidl_typesupport_introspection_c",
        .kind = .lib,
        .linkage = linkage,
    });

    rosidl_typesupport_introspection_c.linkLibC();

    rosidl_typesupport_introspection_c.linkLibrary(rosidl_runtime_c);
    rosidl_typesupport_introspection_c.addIncludePath(rosidl_typesupport_interface.getDirectory());
    rosidl_typesupport_introspection_c.addIncludePath(upstream.path("rosidl_typesupport_introspection_c/include"));

    rosidl_typesupport_introspection_c.step.dependOn(&rosidl_typesupport_interface.step);

    rosidl_typesupport_introspection_c.addCSourceFiles(.{
        .root = upstream.path("rosidl_typesupport_introspection_c"),
        .files = &.{
            "src/identifier.c",
        },
    });

    rosidl_typesupport_introspection_c.installHeadersDirectory(
        upstream.path("rosidl_typesupport_introspection_c/include"),
        "",
        .{},
    );
    b.installArtifact(rosidl_typesupport_introspection_c);

    var rosidl_typesupport_introspection_cpp = std.Build.Step.Compile.create(b, .{
        .root_module = .{
            .target = target,
            .optimize = optimize,
        },
        .name = "rosidl_typesupport_introspection_cpp",
        .kind = .lib,
        .linkage = linkage,
    });

    rosidl_typesupport_introspection_cpp.linkLibCpp();

    rosidl_typesupport_introspection_cpp.linkLibrary(rosidl_runtime_c);
    rosidl_typesupport_introspection_cpp.addIncludePath(rosidl_typesupport_interface.getDirectory());
    rosidl_typesupport_introspection_cpp.addIncludePath(rosidl_runtime_cpp.getDirectory());
    rosidl_typesupport_introspection_cpp.addIncludePath(upstream.path("rosidl_typesupport_introspection_cpp/include"));

    rosidl_typesupport_introspection_cpp.step.dependOn(&rosidl_typesupport_interface.step);
    rosidl_typesupport_introspection_cpp.step.dependOn(&rosidl_runtime_cpp.step);

    rosidl_typesupport_introspection_cpp.addCSourceFiles(.{
        .root = upstream.path("rosidl_typesupport_introspection_cpp"),
        .files = &.{
            "src/identifier.cpp",
        },
        .flags = &[_][]const u8{
            "--std=c++17",
        },
    });

    rosidl_typesupport_introspection_cpp.installHeadersDirectory(
        upstream.path("rosidl_typesupport_introspection_cpp/include"),
        "",
        .{ .include_extensions = &.{".hpp"} },
    );
    b.installArtifact(rosidl_typesupport_introspection_cpp);

    // Export python libraries as named write files
    exportPythonLibrary(b, "rosidl_adapter", upstream.path("rosidl_adapter"), null);
    exportPythonLibrary(b, "rosidl_cli", upstream.path("rosidl_cli"), null);
    exportPythonLibrary(b, "rosidl_pycommon", upstream.path("rosidl_pycommon"), null);

    exportPythonLibrary(
        b,
        "rosidl_generator_c",
        upstream.path("rosidl_generator_c"),
        upstream.path("rosidl_generator_c/bin"),
    );
    exportPythonLibrary(
        b,
        "rosidl_generator_cpp",
        upstream.path("rosidl_generator_cpp"),
        upstream.path("rosidl_generator_cpp/bin"),
    );
    exportPythonLibrary(
        b,
        "rosidl_generator_type_description",
        upstream.path("rosidl_generator_type_description"),
        upstream.path("rosidl_generator_type_description/bin"),
    );
    exportPythonLibrary(
        b,
        "rosidl_parser",
        upstream.path("rosidl_parser"),
        upstream.path("rosidl_parser/bin"),
    );
    exportPythonLibrary(
        b,
        "rosidl_typesupport_introspection_c",
        upstream.path("rosidl_typesupport_introspection_c"),
        upstream.path("rosidl_typesupport_introspection_c/bin"),
    );
    exportPythonLibrary(
        b,
        "rosidl_typesupport_introspection_cpp",
        upstream.path("rosidl_typesupport_introspection_cpp"),
        upstream.path("rosidl_typesupport_introspection_cpp/bin"),
    );
}
