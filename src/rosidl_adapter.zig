const std = @import("std");
const RosIdlGenerator = @import("RosIdlGenerator.zig");

pub const Msg2Idl = struct {
    run_step: *std.Build.Step.Run,

    pub fn create(generator: *RosIdlGenerator) *Msg2Idl {
        const to_return = generator.owner.allocator.create(Msg2Idl) catch @panic("OOM");
        to_return.run_step = RosIdlGenerator.pythonRunner(.{
            .b = generator.owner,
            .python_runner = generator.python_runner,
            .python_dependencies = &.{
                generator.rosidl_cli,
                generator.rosidl_adapter,
                generator.rosidl_parser,
                generator.rosidl_pycommon,
            },
            .current_working_directory = generator.write_files.getDirectory(),
            .python_executable = generator.rosidl_adapter.getDirectory().path(generator.owner, "scripts/msg2idl.py"),
            // .python_executable_root = generator.rosidl_adapter.getDirectory(),
            // .python_executable_sub_path = "scripts/msg2idl.py",
            .arguments = &.{},
        });

        to_return.run_step.step.dependencies.appendSlice(&.{
            &generator.rosidl_cli.step,
            &generator.rosidl_adapter.step,
            &generator.rosidl_parser.step,
            &generator.rosidl_pycommon.step,
            &generator.step,
        }) catch @panic("OOM");

        // The rosidl_adapter package relies on having the package.xml to get the package name.
        // We could copy over the real xml package but having an xml file for just a package name
        // feels rather excessive. Instead we generate a stub with the already provided package name.
        // Maybe this is a bad idea IDK.
        const package_xml = std.fmt.allocPrint(
            generator.owner.allocator,
            \\<?xml version="1.0"?>
            \\<?xml-model href="http://download.ros.org/schema/package_format3.xsd" schematypens="http://www.w3.org/2001/XMLSchema"?>
            \\<package format="3">
            \\  <name>{s}</name>
            \\  <version>42.69.420</version>
            \\  <description>There's a lot of reliance on random files in ROS</description>
            \\  <license>See upstream package</license>
            \\  <maintainer email="nope@notgoingtohappen.com">none</maintainer>
            \\</package>
        ,
            .{generator.package_name},
        ) catch @panic("OOM");
        defer generator.owner.allocator.free(package_xml);

        _ = generator.write_files.add("package.xml", package_xml);

        return to_return;
    }

    // This should be called in the parent RosIdlGenerator make step before the Msg2Idl step runs
    pub fn addMsg(self: *Msg2Idl, msg: std.Build.LazyPath) void {
        self.run_step.addFileArg(msg);
    }

    // This is just to avoid chaining too many .step calls.
    // without this, the call in the generator is idl_step.step.step which feels excessive
    pub fn getStep(self: *Msg2Idl) *std.Build.Step {
        return &self.run_step.step;
    }
};
