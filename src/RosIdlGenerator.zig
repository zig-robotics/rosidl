const std = @import("std");

const RosIdlGenerator = @This();
const RosIdlTypeDescription = @import("RosIdlTypeDescription.zig");
// const RosIdlGeneratorC = @import("RosIdlGeneratorC.zig");
const CodeGenerator = @import("RosIdlGeneratorTemplate.zig").CodeGenerator;
const rosidl_adapter = @import("rosidl_adapter.zig");

const RosIdlGeneratorC = CodeGenerator(
    .c,
    .h,
    &.{
        "{s}/msg/detail/{s}__description.c",
        "{s}/msg/detail/{s}__functions.c",
        "{s}/msg/detail/{s}__type_support.c",
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
    &.{"{s}/msg/{s}__type_support.cpp"},
);

const RosIdlTypesupportCpp = CodeGenerator(
    .cpp,
    null,
    &.{"{s}/msg/{s}__type_support.cpp"},
);

const RosIdlTypesupportIntrospectionC = CodeGenerator(
    .c,
    .h,
    &.{"{s}/msg/detail/{s}__type_support.c"},
);

const RosIdlTypesupportIntrospectionCpp = CodeGenerator(
    .cpp,
    null,
    &.{"{s}/msg/detail/{s}__type_support.cpp"},
);

owner: *std.Build,
step: std.Build.Step,
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
msg_files: std.ArrayList(PathFile),
msg_files_str: std.ArrayList([]const u8),
artifact_dependencies: std.ArrayList(*const std.Build.Step.Compile),
write_file_dependencies: std.ArrayList(*const std.Build.Step.WriteFile),
dependency_names: std.ArrayList([]const u8),
idl_tuples_str: std.ArrayList([]const u8),
named_write_files: *std.Build.Step.WriteFile,
write_files: *std.Build.Step.WriteFile,
python_runner: *std.Build.Step.Compile,
idl_step: *rosidl_adapter.Msg2Idl,
type_description: *RosIdlTypeDescription,
type_description_tuples_str: std.ArrayList([]const u8),
generator_c: *RosIdlGeneratorC,
generator_cpp: *RosIdlGeneratorCpp,
typesupport_c: *RosIdlTypesupportC,
typesupport_cpp: *RosIdlTypesupportCpp,
typesupport_introspection_c: *RosIdlTypesupportIntrospectionC,
typesupport_introspection_cpp: *RosIdlTypesupportIntrospectionCpp,

pub const PathFile = struct {
    path: std.Build.LazyPath,
    file: []const u8,
};

pub fn create(
    b: *std.Build,
    package_name: []const u8,
    rosidl_dep: *std.Build.Dependency,
    rcutils: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
) *RosIdlGenerator {
    const to_return = b.allocator.create(RosIdlGenerator) catch @panic("OOM");
    to_return.* = .{
        .owner = b,
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "RosIdlGenerator", // In other steps, the name seems to also just be the step type?
            .owner = b,
            .makeFn = make,
        }),
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
        .rcutils = rcutils,
        .msg_files = std.ArrayList(PathFile).init(b.allocator),
        .msg_files_str = std.ArrayList([]const u8).init(b.allocator),
        .idl_tuples_str = std.ArrayList([]const u8).init(b.allocator),
        .artifact_dependencies = std.ArrayList(*const std.Build.Step.Compile).init(b.allocator),
        .write_file_dependencies = std.ArrayList(*const std.Build.Step.WriteFile).init(b.allocator),
        .dependency_names = std.ArrayList([]const u8).init(b.allocator),
        .named_write_files = b.addNamedWriteFiles(package_name),
        .write_files = b.addWriteFiles(),
        .python_runner = rosidl_dep.artifact("python_runner"),
        .idl_step = undefined,
        .type_description = undefined,
        .type_description_tuples_str = std.ArrayList([]const u8).init(b.allocator),
        .generator_c = undefined,
        .generator_cpp = undefined,
        .typesupport_c = undefined,
        .typesupport_cpp = undefined,
        .typesupport_introspection_c = undefined,
        .typesupport_introspection_cpp = undefined,
    };

    // to_return.write_files.step.dependOn(&to_return.step);
    to_return.step.dependOn(&to_return.write_files.step);

    to_return.idl_step = rosidl_adapter.Msg2Idl.create(to_return);
    to_return.idl_step.getStep().dependOn(&to_return.write_files.step);
    to_return.named_write_files.step.dependOn(to_return.idl_step.getStep());

    to_return.type_description = RosIdlTypeDescription.create(to_return, package_name, to_return.write_files.getDirectory());
    to_return.named_write_files.step.dependOn(&to_return.type_description.generator.step);
    to_return.type_description.args.step.dependOn(to_return.idl_step.getStep());
    to_return.named_write_files.step.dependOn(&to_return.type_description.generator.step);

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
    to_return.generator_c.generator.step.dependOn(&to_return.type_description.generator.step);

    to_return.generator_cpp = RosIdlGeneratorCpp.create(
        to_return,
        package_name,
        target,
        optimize,
        linkage,
        "rosidl_generator_cpp",
        to_return.rosidl_generator_cpp,
        null,
        null,
    );
    to_return.generator_cpp.generator.step.dependOn(&to_return.type_description.generator.step);

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
        &.{to_return.rosidl_generator_c},
    );
    to_return.typesupport_introspection_c.generator.step.dependOn(&to_return.type_description.generator.step);
    to_return.typesupport_introspection_c.generator.step.dependOn(&to_return.generator_c.generator.step);

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
            to_return.rosidl_generator_cpp,
            to_return.rosidl_generator_c,
        },
    );
    to_return.typesupport_introspection_cpp.generator.step.dependOn(&to_return.type_description.generator.step);

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
        &.{to_return.rosidl_generator_c},
    );

    // TODO move this extra arg somewhere?
    // The type supports normally come from the ament index. Search for `ament_index_register_resource("rosidl_typesupport_c`) on github in ros to get a list
    // For now we only support the standard dynamic typesupport_introspection versions
    to_return.typesupport_c.generator.addArgs(&.{ "--typesupports", "rosidl_typesupport_introspection_c" });
    to_return.typesupport_c.generator.step.dependOn(&to_return.type_description.generator.step);

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
        &.{to_return.rosidl_generator_c},
    );

    // TODO move this extra arg somewhere?
    // The type supports normally come from the ament index. Search for `ament_index_register_resource("rosidl_typesupport_c`) on github in ros to get a list
    // For now we only support the standard dynamic typesupport_introspection versions
    to_return.typesupport_cpp.generator.addArgs(&.{ "--typesupports", "rosidl_typesupport_introspection_cpp" });
    to_return.typesupport_cpp.generator.step.dependOn(&to_return.type_description.generator.step);

    _ = to_return.named_write_files.addCopyDirectory(
        to_return.write_files.getDirectory(),
        "",
        .{ .include_extensions = &.{ ".idl", ".msg", ".json" } },
    );

    return to_return;
}

fn make(step: *std.Build.Step, prog_node: std.Progress.Node) anyerror!void {
    _ = prog_node;
    const self: *RosIdlGenerator = @fieldParentPtr("step", step);

    for (self.msg_files.items) |msg| {
        const msg_out = self.write_files.getDirectory().path(self.owner, msg.file);

        self.idl_step.addMsg(msg_out);

        const idl_rename = self.step.owner.dupe(msg.file);
        defer self.owner.allocator.free(idl_rename);
        _ = std.mem.replace(u8, msg.file, ".msg", ".idl", idl_rename);

        try self.idl_tuples_str.append(try std.fmt.allocPrint(
            self.owner.allocator,
            "{s}:{s}",
            .{ self.write_files.getDirectory().getPath(self.owner), idl_rename },
        ));

        const json_rename = try self.owner.allocator.alloc(u8, std.mem.replacementSize(u8, msg.file, ".msg", ".json"));
        defer self.owner.allocator.free(json_rename);
        _ = std.mem.replace(u8, msg.file, ".msg", ".json", json_rename);

        try self.type_description_tuples_str.append(try std.fmt.allocPrint(
            self.owner.allocator,
            "{s}:{s}/{s}",
            .{
                idl_rename,
                self.write_files.getDirectory().getPath(self.owner),
                json_rename,
            },
        ));

        try self.msg_files_str.append(try std.fmt.allocPrint(
            self.owner.allocator,
            "{s}/{s}",
            .{
                self.write_files.getDirectory().getPath(self.owner),
                msg.file,
            },
        ));

        // TODO dependencies?
    }

    self.type_description.setIdlTuples(self.idl_tuples_str.items);

    self.generator_c.setIdlTuples(self.idl_tuples_str.items);
    try self.generator_c.setRosInterfaceFiles(self.owner.allocator, self.msg_files_str.items);
    self.generator_c.setTypeDescriptionTuples(self.type_description_tuples_str.items);

    self.generator_cpp.setIdlTuples(self.idl_tuples_str.items);
    try self.generator_cpp.setRosInterfaceFiles(self.owner.allocator, self.msg_files_str.items);
    self.generator_cpp.setTypeDescriptionTuples(self.type_description_tuples_str.items);

    self.typesupport_introspection_c.setIdlTuples(self.idl_tuples_str.items);
    try self.typesupport_introspection_c.setRosInterfaceFiles(self.owner.allocator, self.msg_files_str.items);
    self.typesupport_introspection_c.setTypeDescriptionTuples(self.type_description_tuples_str.items);

    self.typesupport_introspection_cpp.setIdlTuples(self.idl_tuples_str.items);
    try self.typesupport_introspection_cpp.setRosInterfaceFiles(self.owner.allocator, self.msg_files_str.items);
    self.typesupport_introspection_cpp.setTypeDescriptionTuples(self.type_description_tuples_str.items);

    self.typesupport_c.setIdlTuples(self.idl_tuples_str.items);
    try self.typesupport_c.setRosInterfaceFiles(self.owner.allocator, self.msg_files_str.items);
    self.typesupport_c.setTypeDescriptionTuples(self.type_description_tuples_str.items);

    self.typesupport_cpp.setIdlTuples(self.idl_tuples_str.items);
    try self.typesupport_cpp.setRosInterfaceFiles(self.owner.allocator, self.msg_files_str.items);
    self.typesupport_cpp.setTypeDescriptionTuples(self.type_description_tuples_str.items);
}

// Optional really since we use the build allocator.
// Don't defer this in the build function as this data needs to persist until the build has completed
pub fn deinit(self: *RosIdlGenerator) void {
    self.msg_files.deinit();
    self.artifact_dependencies.deinit();
    self.write_file_dependencies.deinit();
    self.dependency_names.deinit();
}

// Files are simply stored for later, steps are generated only when dependents are added
// This allows for this line to be called multiple times, for services and actions to be added,
// generators to be configured, or custom generators to be added
pub fn addMsgs(self: *RosIdlGenerator, files: []const PathFile) void {
    for (files) |file| {
        self.msg_files.append(.{
            .path = file.path.dupe(self.step.owner),
            .file = self.step.owner.dupe(file.file),
        }) catch @panic("OOM");

        const path = file.path.path(self.owner, file.file);
        _ = self.write_files.addCopyFile(path, file.file);
    }
}

// This expects the passed dependency to contain an artifact and a named write file both with the passed package name.
// The artifact should be the C/C++ library (include files, libs), and the named write file should be the misc generated
// files (.ild, type_description json, etc)
pub fn addDependency(self: *RosIdlGenerator, dependency: *const std.Build.Dependency, package: []const u8) void {
    self.artifact_dependencies.append(dependency.artifact(package)) catch @panic("OOM");
    self.write_file_dependencies.append(dependency.namedWriteFiles(package)) catch @panic("OOM");
    self.dependency_names.append(self.owner.dupe(package)) catch @panic("OOM");
}

const PythonArguments = union(enum) {
    string: []const u8,
    lazy_path: std.Build.LazyPath,
};

const PythonRunnerArgs = struct {
    b: *std.Build,
    python_runner: *std.Build.Step.Compile,
    python_dependencies: []const *std.Build.Step.WriteFile,
    current_working_directory: ?std.Build.LazyPath = null,
    python_executable: std.Build.LazyPath,
    arguments: []const PythonArguments,
    enable_logging: bool = false,
};

pub fn pythonRunner(args: PythonRunnerArgs) *std.Build.Step.Run {
    var step = args.b.addRunArtifact(args.python_runner);
    switch (args.python_executable) {
        .generated => |exe| if (exe.sub_path.len > 0) step.setName(exe.sub_path) else step.setName("PythonRunner"),
        else => step.setName("PythonRunner"),
    }
    step.step.dependOn(&args.python_runner.step);

    if (args.enable_logging) {
        step.addArg("-l");
    }

    for (args.python_dependencies) |dep| {
        step.addPrefixedFileArg("-P", dep.getDirectory());
        step.step.dependOn(&dep.step);
    }

    if (args.current_working_directory) |cwd| {
        step.addPrefixedFileArg("-D", cwd);
    }

    step.addFileArg(args.python_executable);

    for (args.arguments) |arg| switch (arg) {
        .string => |str| step.addArg(str),
        .lazy_path => |path| step.addFileArg(path),
    };

    return step;
}

// TODO add tests or some build of this during this packages build to verify it works
// right now this is only built in other packages
