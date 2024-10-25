const std = @import("std");

const RosIdlGenerator = @This();
const RosIdlTypeDescription = @import("RosIdlTypeDescription.zig");
const CodeGenerator = @import("RosIdlGeneratorTemplate.zig").CodeGenerator;
const RosIdlAdapter = @import("RosIdlAdapter.zig");

const NamedDependency = struct {
    const Self = @This();
    name: []const u8,
    dependency: *std.Build.Dependency,

    // Duplicate the named dependency. copies the name but not the dependency.
    // panics on error.
    pub fn dupe(self: Self, b: *std.Build) NamedDependency {
        return .{
            .name = b.dupe(self.name),
            .dependency = self.dependency,
        };
    }

    // Grabs the step that produces the final "share" directory.
    // Contains .msg, .idl, and .json files
    pub fn shareStep(self: Self) *std.Build.Step.WriteFile {
        return self.dependency.namedWriteFiles(self.name);
    }

    // Grabs the compile step for rosidl_generator_c
    pub fn generatorC(self: Self) *std.Build.Step.Compile {
        const name = std.fmt.allocPrint(
            self.dependency.builder.allocator,
            "{s}__rosidl_generator_c",
            .{self.name},
        ) catch @panic("OOM");
        defer self.dependency.builder.allocator.free(name);

        return self.dependency.artifact(name);
    }

    // Grabs the compile step for rosidl_typesupport_c
    pub fn typesupportC(self: Self) *std.Build.Step.Compile {
        const name = std.fmt.allocPrint(self.dependency.builder.allocator, "{s}__rosidl_typesupport_c", .{self.name}) catch @panic("OOM");
        defer self.dependency.builder.allocator.free(name);

        return self.dependency.artifact(name);
    }

    // Grabs the named write file step for rosidl_generator_cpp
    pub fn generatorCpp(self: Self) *std.Build.Step.WriteFile {
        const name = std.fmt.allocPrint(self.dependency.builder.allocator, "{s}__rosidl_generator_cpp", .{self.name}) catch @panic("OOM");
        defer self.dependency.builder.allocator.free(name);

        return self.dependency.namedWriteFiles(name);
    }

    // Grabs the compile step for rosidl_typesupport_introspection_c
    pub fn typeSupportIntrospectionC(self: Self) *std.Build.Step.Compile {
        const name = std.fmt.allocPrint(self.dependency.builder.allocator, "{s}__rosidl_typesupport_introspection_c", .{self.name}) catch @panic("OOM");
        defer self.dependency.builder.allocator.free(name);

        return self.dependency.artifact(name);
    }
};

const RosIdlGeneratorC = CodeGenerator(
    .c,
    .h,
    &.{
        "{s}/{s}/detail/{s}__description.c",
        "{s}/{s}/detail/{s}__functions.c",
        "{s}/{s}/detail/{s}__type_support.c",
    },
);

const RosIdlGeneratorCpp = CodeGenerator(
    .header_only,
    .hpp,
    &.{},
);

const RosIdlTypesupportC = CodeGenerator(
    .cpp,
    null,
    &.{"{s}/{s}/{s}__type_support.cpp"},
);

const RosIdlTypesupportCpp = CodeGenerator(
    .cpp,
    null,
    &.{"{s}/{s}/{s}__type_support.cpp"},
);

const RosIdlTypesupportIntrospectionC = CodeGenerator(
    .c,
    .h,
    &.{"{s}/{s}/detail/{s}__type_support.c"},
);

const RosIdlTypesupportIntrospectionCpp = CodeGenerator(
    .cpp,
    null,
    &.{"{s}/{s}/detail/{s}__type_support.cpp"},
);

owner: *std.Build,
package_name: []const u8,
rosidl: *std.Build.Dependency,
rosidl_cli: *std.Build.Step.WriteFile,
rosidl_adapter: *std.Build.Step.WriteFile,
rosidl_parser: *std.Build.Step.WriteFile,
rosidl_pycommon: *std.Build.Step.WriteFile,
rosidl_typesupport_interface: *std.Build.Step.WriteFile,
rosidl_generator_type_description: *std.Build.Step.WriteFile,
rosidl_generator_c: *std.Build.Step.WriteFile,
rosidl_generator_cpp: *std.Build.Step.WriteFile,
rosidl_runtime_c: *std.Build.Step.Compile,
rosidl_runtime_cpp: *std.Build.Step.WriteFile,
rosidl_typesupport_c: *std.Build.Step.WriteFile,
rosidl_typesupport_c_lib: *std.Build.Step.Compile,
rosidl_typesupport_cpp: *std.Build.Step.WriteFile,
rosidl_typesupport_cpp_lib: *std.Build.Step.Compile,
rosidl_typesupport_introspection_c: *std.Build.Step.WriteFile,
rosidl_typesupport_introspection_c_lib: *std.Build.Step.Compile,
rosidl_typesupport_introspection_cpp: *std.Build.Step.WriteFile,
rosidl_typesupport_introspection_cpp_lib: *std.Build.Step.Compile,
rcutils: *std.Build.Step.Compile,
msg_files: std.ArrayList([]const u8),
srv_files: std.ArrayList([]const u8),
interface_files_str: std.ArrayList([]const u8),
idl_tuples_str: std.ArrayList([]const u8),
include_paths_str: std.ArrayList([]const u8),
named_write_files: *std.Build.Step.WriteFile,
type_description_generator: *std.Build.Step.Compile,
adapter_generator: *std.Build.Step.Compile,
code_generator: *std.Build.Step.Compile,
adapter: *RosIdlAdapter,
type_description: *RosIdlTypeDescription,
type_description_tuples_str: std.ArrayList([]const u8),
generator_c: *RosIdlGeneratorC,
generator_cpp: *RosIdlGeneratorCpp,
typesupport_c: *RosIdlTypesupportC,
typesupport_cpp: *RosIdlTypesupportCpp,
typesupport_introspection_c: *RosIdlTypesupportIntrospectionC,
typesupport_introspection_cpp: *RosIdlTypesupportIntrospectionCpp,
dependency: std.Build.Dependency,

pub fn create(
    b: *std.Build,
    package_name: []const u8,
    rosidl_dep: *std.Build.Dependency,
    // TODO depending on generator output and args shouldn't be needed anymore??    // rcutils: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
) *RosIdlGenerator {
    const to_return = b.allocator.create(RosIdlGenerator) catch @panic("OOM");
    to_return.* = .{
        .owner = b,
        .package_name = b.dupe(package_name),
        .rosidl = rosidl_dep,
        .rosidl_cli = rosidl_dep.namedWriteFiles("rosidl_cli"),
        .rosidl_adapter = rosidl_dep.namedWriteFiles("rosidl_adapter"),
        .rosidl_parser = rosidl_dep.namedWriteFiles("rosidl_parser"),
        .rosidl_pycommon = rosidl_dep.namedWriteFiles("rosidl_pycommon"),
        .rosidl_typesupport_interface = rosidl_dep.namedWriteFiles("rosidl_typesupport_interface"),
        .rosidl_generator_type_description = rosidl_dep.namedWriteFiles("rosidl_generator_type_description"),
        .rosidl_generator_c = rosidl_dep.namedWriteFiles("rosidl_generator_c"),
        .rosidl_generator_cpp = rosidl_dep.namedWriteFiles("rosidl_generator_cpp"),
        .rosidl_runtime_c = rosidl_dep.artifact("rosidl_runtime_c"),
        .rosidl_runtime_cpp = rosidl_dep.namedWriteFiles("rosidl_runtime_cpp"),
        .rosidl_typesupport_c = rosidl_dep.namedWriteFiles("rosidl_typesupport_c"),
        .rosidl_typesupport_c_lib = rosidl_dep.artifact("rosidl_typesupport_c"),
        .rosidl_typesupport_cpp = rosidl_dep.namedWriteFiles("rosidl_typesupport_cpp"),
        .rosidl_typesupport_cpp_lib = rosidl_dep.artifact("rosidl_typesupport_cpp"),
        .rosidl_typesupport_introspection_c = rosidl_dep.namedWriteFiles("rosidl_typesupport_introspection_c"),
        .rosidl_typesupport_introspection_c_lib = rosidl_dep.artifact("rosidl_typesupport_introspection_c"),
        .rosidl_typesupport_introspection_cpp = rosidl_dep.namedWriteFiles("rosidl_typesupport_introspection_cpp"),
        .rosidl_typesupport_introspection_cpp_lib = rosidl_dep.artifact("rosidl_typesupport_introspection_cpp"),
        .rcutils = rosidl_dep.builder.dependency("rcutils", .{
            .target = target,
            .optimize = optimize,
            .linkage = linkage,
        }).artifact("rcutils"),
        .msg_files = std.ArrayList([]const u8).init(b.allocator),
        .srv_files = std.ArrayList([]const u8).init(b.allocator),
        .interface_files_str = std.ArrayList([]const u8).init(b.allocator),
        .idl_tuples_str = std.ArrayList([]const u8).init(b.allocator),
        .include_paths_str = std.ArrayList([]const u8).init(b.allocator),
        .named_write_files = b.addNamedWriteFiles(package_name),
        .type_description_generator = rosidl_dep.artifact("type_description_generator"),
        .adapter_generator = rosidl_dep.artifact("adapter_generator"),
        .code_generator = rosidl_dep.artifact("code_generator"),
        .adapter = undefined,
        .type_description = undefined,
        .type_description_tuples_str = std.ArrayList([]const u8).init(b.allocator),
        .generator_c = undefined,
        .generator_cpp = undefined,
        .typesupport_c = undefined,
        .typesupport_cpp = undefined,
        .typesupport_introspection_c = undefined,
        .typesupport_introspection_cpp = undefined,
        .dependency = .{ .builder = b },
    };

    to_return.adapter = RosIdlAdapter.create(to_return, package_name);
    _ = to_return.named_write_files.addCopyDirectory(
        to_return.adapter.output,
        "",
        .{ .include_extensions = &.{".idl"} },
    );

    to_return.type_description = RosIdlTypeDescription.create(to_return, package_name);
    _ = to_return.named_write_files.addCopyDirectory(
        to_return.type_description.output,
        "",
        .{ .include_extensions = &.{".json"} },
    );
    // to_return.type_description.generator.step.dependOn(&to_return.adapter.generator.step);

    to_return.generator_c = RosIdlGeneratorC.create(
        to_return,
        package_name,
        target,
        optimize,
        linkage,
        "rosidl_generator_c",
        to_return.rosidl_generator_c,
        &.{.{ .lib = to_return.rosidl_runtime_c }},
        null,
    );

    to_return.generator_cpp = RosIdlGeneratorCpp.create(
        to_return,
        package_name,
        target,
        optimize,
        linkage,
        "rosidl_generator_cpp",
        to_return.rosidl_generator_cpp,
        null,
        &.{to_return.rosidl_generator_c.getDirectory()},
    );

    to_return.typesupport_introspection_c = RosIdlTypesupportIntrospectionC.create(
        to_return,
        package_name,
        target,
        optimize,
        linkage,
        "rosidl_typesupport_introspection_c",
        to_return.rosidl_typesupport_introspection_c,
        &.{
            .{ .lib = to_return.rosidl_runtime_c },
            .{ .lib = to_return.rosidl_typesupport_introspection_c_lib },
            .{ .lib = to_return.generator_c.artifact },
        },
        &.{to_return.rosidl_generator_c.getDirectory()},
    );

    to_return.typesupport_introspection_cpp = RosIdlTypesupportIntrospectionCpp.create(
        to_return,
        package_name,
        target,
        optimize,
        linkage,
        "rosidl_typesupport_introspection_cpp",
        to_return.rosidl_typesupport_introspection_cpp,
        &.{
            .{ .lib = to_return.rosidl_runtime_c },
            .{ .header_only = to_return.rosidl_runtime_cpp },
            .{ .lib = to_return.rosidl_typesupport_introspection_cpp_lib },
            .{ .lib = to_return.rosidl_typesupport_cpp_lib },
            .{ .lib = to_return.generator_c.artifact },
            .{ .header_only = to_return.generator_cpp.artifact },
            .{ .lib = to_return.rosidl_typesupport_introspection_c_lib },
        },
        &.{
            to_return.rosidl_generator_cpp.getDirectory(),
            to_return.rosidl_generator_c.getDirectory(),
        },
    );

    to_return.typesupport_c = RosIdlTypesupportC.create(
        to_return,
        package_name,
        target,
        optimize,
        linkage,
        "rosidl_typesupport_c",
        to_return.rosidl_typesupport_c,
        &.{
            .{ .lib = to_return.rosidl_runtime_c },
            .{ .lib = to_return.generator_c.artifact },
            .{ .lib = to_return.rosidl_typesupport_c_lib },
            .{ .lib = to_return.typesupport_introspection_c.artifact },
        },
        &.{to_return.rosidl_generator_c.getDirectory()},
    );

    // TODO move this extra arg somewhere?
    // The type supports normally come from the ament index. Search for `ament_index_register_resource("rosidl_typesupport_c`) on github in ros to get a list
    // For now we only support the standard dynamic typesupport_introspection versions
    // TODO this will be broken since there's no way to forrward additional args? (move to comptime template?)
    to_return.typesupport_c.generator.addArg("-A--typesupports rosidl_typesupport_introspection_c");

    to_return.typesupport_cpp = RosIdlTypesupportCpp.create(
        to_return,
        package_name,
        target,
        optimize,
        linkage,
        "rosidl_typesupport_cpp",
        to_return.rosidl_typesupport_cpp,
        &.{
            .{ .lib = to_return.rosidl_runtime_c },
            .{ .lib = to_return.generator_c.artifact },
            .{ .header_only = to_return.generator_cpp.artifact },
            .{ .header_only = to_return.rosidl_runtime_cpp },
            .{ .lib = to_return.rosidl_typesupport_cpp_lib },
            .{ .lib = to_return.typesupport_introspection_cpp.artifact },
            .{ .lib = to_return.rosidl_typesupport_introspection_cpp_lib },
        },
        &.{to_return.rosidl_generator_c.getDirectory()},
    );

    // TODO move this extra arg somewhere?
    // The type supports normally come from the ament index. Search for `ament_index_register_resource("rosidl_typesupport_c`) on github in ros to get a list
    // For now we only support the standard dynamic typesupport_introspection versions
    // todo this will be broken since there's no way to forrward additional args? (move to comptime template?)
    to_return.typesupport_cpp.generator.addArg("-A--typesupports rosidl_typesupport_introspection_cpp");

    return to_return;
}

pub fn asDependency(self: *RosIdlGenerator) *std.Build.Dependency {
    return &self.dependency;
}

// TODO decide if we want to support deinit, fill it out properly
// Optional really since we use the build allocator.
// Don't defer this in the build function as this data needs to persist until the build has completed
pub fn deinit(self: *RosIdlGenerator) void {
    self.msg_files.deinit();
    self.dependency_names.deinit();
}

pub fn addInterfaces(
    self: *RosIdlGenerator,
    base_path: std.Build.LazyPath,
    files: []const []const u8,
) void {
    // TODO add actions
    for (files) |file| {
        self.msg_files.append(self.owner.dupe(file)) catch @panic("OOM");
        self.adapter.addInterface(base_path, file);

        const idl = std.fmt.allocPrint(
            self.owner.allocator,
            "{s}idl",
            .{file[0 .. file.len - 3]},
        ) catch @panic("OOM");

        self.type_description.addIdlTuple(idl, self.adapter.output);

        const type_description = std.fmt.allocPrint(
            self.owner.allocator,
            "{s}json",
            .{file[0 .. file.len - 3]},
        ) catch @panic("OOM");

        self.generator_c.addInterface(base_path, file);
        self.generator_c.addIdlTuple(idl, self.adapter.output);
        self.generator_c.addTypeDescription(
            idl,
            self.type_description.output.path(self.owner, type_description),
        );

        self.generator_cpp.addInterface(base_path, file);
        self.generator_cpp.addIdlTuple(idl, self.adapter.output);
        self.generator_cpp.addTypeDescription(
            idl,
            self.type_description.output.path(self.owner, type_description),
        );

        self.typesupport_introspection_c.addInterface(base_path, file);
        self.typesupport_introspection_c.addIdlTuple(idl, self.adapter.output);
        self.typesupport_introspection_c.addTypeDescription(
            idl,
            self.type_description.output.path(self.owner, type_description),
        );

        self.typesupport_introspection_cpp.addInterface(base_path, file);
        self.typesupport_introspection_cpp.addIdlTuple(idl, self.adapter.output);
        self.typesupport_introspection_cpp.addTypeDescription(
            idl,
            self.type_description.output.path(self.owner, type_description),
        );

        self.typesupport_c.addInterface(base_path, file);
        self.typesupport_c.addIdlTuple(idl, self.adapter.output);
        self.typesupport_c.addTypeDescription(
            idl,
            self.type_description.output.path(self.owner, type_description),
        );

        self.typesupport_cpp.addInterface(base_path, file);
        self.typesupport_cpp.addIdlTuple(idl, self.adapter.output);
        self.typesupport_cpp.addTypeDescription(
            idl,
            self.type_description.output.path(self.owner, type_description),
        );

        const path = base_path.path(self.owner, file);
        _ = self.named_write_files.addCopyFile(path, file);
        // _ = self.write_files.addCopyFile(path, file);
    }
}

pub fn addDependency(self: *RosIdlGenerator, dependency: NamedDependency) void {
    self.type_description.addIncludePath(dependency.name, dependency.shareStep().getDirectory());

    self.generator_c.artifact.linkLibrary(dependency.generatorC());

    self.typesupport_c.artifact.linkLibrary(dependency.generatorC());
    // TODO I'm not sure this one is technically needed? but it makes later calls to "linkLibraryRecursive" far more convenietn
    self.typesupport_c.artifact.linkLibrary(dependency.typesupportC());

    self.typesupport_cpp.artifact.linkLibrary(dependency.generatorC());
    self.typesupport_cpp.artifact.addIncludePath(dependency.generatorCpp().getDirectory());

    self.typesupport_introspection_c.artifact.linkLibrary(dependency.typeSupportIntrospectionC());
    self.typesupport_introspection_c.artifact.linkLibrary(dependency.generatorC());

    self.typesupport_introspection_cpp.artifact.addIncludePath(dependency.generatorCpp().getDirectory());
    self.typesupport_introspection_cpp.artifact.linkLibrary(dependency.generatorC());
}

const PythonArguments = union(enum) {
    string: []const u8,
    lazy_path: std.Build.LazyPath,
};

pub fn installArtifacts(self: *RosIdlGenerator) void {
    var b = self.owner;
    b.installDirectory(.{
        .source_dir = self.named_write_files.getDirectory(),
        .install_dir = .{ .custom = self.package_name },
        .install_subdir = "",
    });

    b.installArtifact(self.generator_c.artifact);

    b.installDirectory(.{
        .source_dir = self.generator_cpp.artifact.getDirectory(),
        .install_dir = .header,
        .install_subdir = "",
    });

    b.installArtifact(self.typesupport_c.artifact);
    b.installArtifact(self.typesupport_cpp.artifact);
    b.installArtifact(self.typesupport_introspection_c.artifact);
    b.installArtifact(self.typesupport_introspection_cpp.artifact);
}

// TODO add tests or some build of this during this packages build to verify it works
// right now this is only built in other packages
