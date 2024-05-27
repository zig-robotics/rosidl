const std = @import("std");

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

    // TODO this is a header only lib? not sure how to handle this in zig.
    // var rosidl_typesupport_interface = std.Build.Step.Compile.create(b, .{
    //     .root_module = .{
    //         .target = target,
    //         .optimize = optimize,
    //     },
    //     .name = "rosidl_typesupport_interface",
    //     .kind = .lib,
    //     .linkage = linkage,
    // });

    // rosidl_typesupport_interface.addIncludePath(.{
    //     .dependency = .{ .dependency = upstream, .sub_path = "rosidl_typesupport_interface/include" },
    // });

    // rosidl_typesupport_interface.installHeadersDirectory(
    //     .{ .dependency = .{ .dependency = upstream, .sub_path = "rosidl_typesupport_interface/include" } },
    //     "",
    //     .{},
    // );
    // b.installArtifact(rosidl_typesupport_interface);

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

    rosidl_runtime_c.linkLibrary(rcutils_dep.artifact("rcutils"));
    rosidl_runtime_c.addIncludePath(upstream.path("rosidl_typesupport_interface/include"));
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
    rosidl_typesupport_introspection_c.addIncludePath(upstream.path("rosidl_typesupport_interface/include"));
    rosidl_typesupport_introspection_c.addIncludePath(upstream.path("rosidl_typesupport_introspection_c/include"));

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
    rosidl_typesupport_introspection_cpp.addIncludePath(upstream.path("rosidl_typesupport_interface/include"));
    rosidl_typesupport_introspection_cpp.addIncludePath(upstream.path("rosidl_runtime_cpp/include"));
    rosidl_typesupport_introspection_cpp.addIncludePath(upstream.path("rosidl_typesupport_introspection_cpp/include"));

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
}
