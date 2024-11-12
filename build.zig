const std = @import("std");

// To access modules at build time in other packages, they must be included here in the build file
pub const RosIdlGenerator = @import("src/RosIdlGenerator.zig");

// Adds a named write file and install step using the given name and path.
// Optionally include a binary directory as well
fn exportPythonLibrary(b: *std.Build, name: []const u8, source_path: std.Build.LazyPath, bin_path: ?std.Build.LazyPath) void {
    var write_files = b.addNamedWriteFiles(name);

    // TODO figure out way to exclude test directories?
    _ = write_files.addCopyDirectory(source_path, "", .{ .include_extensions = &.{ ".py", ".em", ".in", ".json", ".lark" } });

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

    const rcpputils_dep = b.dependency("rcpputils", .{
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
            .pic = if (linkage == .dynamic) true else null,
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
        .flags = &.{"-fvisibility=hidden"},
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
            .pic = if (linkage == .dynamic) true else null,
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
        .flags = &.{"-fvisibility=hidden"},
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
            .pic = if (linkage == .dynamic) true else null,
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
        .flags = &.{
            "--std=c++17",
            "-fvisibility=hidden",
            "-fvisibility-inlines-hidden",
        },
    });

    rosidl_typesupport_introspection_cpp.installHeadersDirectory(
        upstream.path("rosidl_typesupport_introspection_cpp/include"),
        "",
        .{ .include_extensions = &.{ ".h", ".hpp" } },
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

    // rosidl_typesupport
    const typesupport_upstream = b.dependency("rosidl_typesupport", .{});

    var rosidl_typesupport_c = std.Build.Step.Compile.create(b, .{
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .pic = if (linkage == .dynamic) true else null,
        },
        .name = "rosidl_typesupport_c",
        .kind = .lib,
        .linkage = linkage,
    });

    rosidl_typesupport_c.linkLibCpp();
    rosidl_typesupport_c.step.dependOn(&rosidl_typesupport_interface.step);
    rosidl_typesupport_c.linkLibrary(rcutils_dep.artifact("rcutils"));
    rosidl_typesupport_c.linkLibrary(rcpputils_dep.artifact("rcpputils"));
    rosidl_typesupport_c.linkLibrary(rosidl_runtime_c);
    rosidl_typesupport_c.addIncludePath(rosidl_typesupport_interface.getDirectory());
    rosidl_typesupport_c.addIncludePath(typesupport_upstream.path("rosidl_typesupport_c/include"));

    rosidl_typesupport_c.addCSourceFiles(.{
        .root = typesupport_upstream.path("rosidl_typesupport_c"),
        .files = &.{
            "src/identifier.c",
        },
        .flags = &.{"-fvisibility=hidden"},
    });

    rosidl_typesupport_c.addCSourceFiles(.{
        .root = typesupport_upstream.path("rosidl_typesupport_c"),
        .files = &.{
            "src/message_type_support_dispatch.cpp",
            "src/service_type_support_dispatch.cpp",
        },
        .flags = &.{
            "--std=c++17",
            "-fvisibility=hidden",
            "-fvisibility-inlines-hidden",
        },
    });

    rosidl_typesupport_c.installHeadersDirectory(
        typesupport_upstream.path("rosidl_typesupport_c/include"),
        "",
        .{ .include_extensions = &.{ ".h", ".hpp" } },
    );

    if (target.result.os.tag == .windows) {
        // Note windows is untested, this just tires to match the upstream CMake
        rosidl_typesupport_c.root_module.addCMacro("ROSIDL_TYPESUPPORT_C_BUILDING_DLL", "");
    }

    b.installArtifact(rosidl_typesupport_c);

    var rosidl_typesupport_cpp = std.Build.Step.Compile.create(b, .{
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .pic = if (linkage == .dynamic) true else null,
        },
        .name = "rosidl_typesupport_cpp",
        .kind = .lib,
        .linkage = linkage,
    });

    rosidl_typesupport_cpp.linkLibCpp();
    rosidl_typesupport_cpp.step.dependOn(&rosidl_typesupport_interface.step);
    rosidl_typesupport_cpp.linkLibrary(rcutils_dep.artifact("rcutils"));
    rosidl_typesupport_cpp.linkLibrary(rcpputils_dep.artifact("rcpputils"));
    rosidl_typesupport_cpp.linkLibrary(rosidl_runtime_c);
    rosidl_typesupport_cpp.linkLibrary(rosidl_typesupport_c);
    rosidl_typesupport_cpp.addIncludePath(rosidl_typesupport_interface.getDirectory());
    rosidl_typesupport_cpp.addIncludePath(typesupport_upstream.path("rosidl_typesupport_cpp/include"));

    rosidl_typesupport_cpp.addCSourceFiles(.{
        .root = typesupport_upstream.path("rosidl_typesupport_cpp"),
        .files = &.{
            "src/identifier.cpp",
            "src/message_type_support_dispatch.cpp",
            "src/service_type_support_dispatch.cpp",
        },
        .flags = &.{
            "--std=c++17",
            "-fvisibility=hidden",
            "-fvisibility-inlines-hidden",
        },
    });

    rosidl_typesupport_cpp.installHeadersDirectory(
        typesupport_upstream.path("rosidl_typesupport_cpp/include"),
        "",
        .{ .include_extensions = &.{ ".h", ".hpp" } },
    );

    if (target.result.os.tag == .windows) {
        // Note windows is untested, this just tires to match the upstream CMake
        rosidl_typesupport_cpp.root_module.addCMacro("ROSIDL_TYPESUPPORT_CPP_BUILDING_DLL", "");
    }

    b.installArtifact(rosidl_typesupport_cpp);

    exportPythonLibrary(
        b,
        "rosidl_typesupport_c",
        typesupport_upstream.path("rosidl_typesupport_c"),
        typesupport_upstream.path("rosidl_typesupport_c/bin"),
    );
    exportPythonLibrary(
        b,
        "rosidl_typesupport_cpp",
        typesupport_upstream.path("rosidl_typesupport_cpp"),
        typesupport_upstream.path("rosidl_typesupport_cpp/bin"),
    );

    // rosidl_dynamic_typesupport
    const dynamic_typesupport_upstream = b.dependency("rosidl_dynamic_typesupport", .{});

    var rosidl_dynamic_typesupport = std.Build.Step.Compile.create(b, .{
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .pic = if (linkage == .dynamic) true else null,
        },
        .name = "rosidl_dynamic_typesupport",
        .kind = .lib,
        .linkage = linkage,
    });

    rosidl_dynamic_typesupport.linkLibC();
    rosidl_dynamic_typesupport.linkLibrary(rcutils_dep.artifact("rcutils"));
    rosidl_dynamic_typesupport.linkLibrary(rosidl_runtime_c);
    rosidl_dynamic_typesupport.addIncludePath(rosidl_typesupport_interface.getDirectory());
    rosidl_dynamic_typesupport.addIncludePath(dynamic_typesupport_upstream.path("include"));

    rosidl_dynamic_typesupport.addCSourceFiles(.{
        .root = dynamic_typesupport_upstream.path(""),
        .files = &.{
            "src/api/serialization_support.c",
            "src/api/dynamic_data.c",
            "src/api/dynamic_type.c",
            "src/dynamic_message_type_support_struct.c",
            "src/identifier.c",
        },
        .flags = &.{"-fvisibility=hidden"},
    });

    rosidl_dynamic_typesupport.installHeadersDirectory(
        dynamic_typesupport_upstream.path("include"),
        "",
        .{},
    );

    if (target.result.os.tag == .windows) {
        // Note windows is untested, this just tires to match the upstream CMake
        rosidl_dynamic_typesupport.root_module.addCMacro("ROSIDL_TYPESUPPORT_C_BUILDING_DLL", "");
    }

    b.installArtifact(rosidl_dynamic_typesupport);

    // Zig specific stuff to replace all the CMake magic involved in interface generation

    const type_description_generator = b.addExecutable(.{
        .name = "type_description_generator",
        .target = b.graph.host, // This is only used in run artifacts, don't cross compile
        .optimize = optimize,
        .root_source_file = b.path("src/type_description_generator.zig"),
    });
    b.installArtifact(type_description_generator);

    const adapter_generator = b.addExecutable(.{
        .name = "adapter_generator",
        .target = b.graph.host, // This is only used in run artifacts, don't cross compile
        .optimize = optimize,
        .root_source_file = b.path("src/adapter_generator.zig"),
    });
    b.installArtifact(adapter_generator);

    const code_generator = b.addExecutable(.{
        .name = "code_generator",
        .target = b.graph.host, // This is only used in run artifacts, don't cross compile
        .optimize = optimize,
        .root_source_file = b.path("src/code_generator.zig"),
    });
    b.installArtifact(code_generator);

    const rosidl_generator = b.addModule("RosIdlGenerator", .{ .root_source_file = b.path("src/RosIdlGenerator.zig") });
    _ = rosidl_generator;

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/RosIdlGeneratorTemplate.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
