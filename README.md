# Zig package for rosidl and rosidl_typesupport

This provides a zig package for the ROS2 rosidl project, as well as some zig helpers to streamline
interface generation within the zig build system. This currently targets zig 0.13 and ROS Jazzy.

It also includes the rosidl_typesupport and rosidl_dynamic_typesupport repo since they also use the
 same style of generators and depend largely on rosidl.

## TODO

### Missing ROS features
 - Action generation

### Zig antipaterns
 - Build script inversion (probably not a real issue)
   - Note Mr. Kelley has suggested that passing off build script configurations to dependencies may
     be an anti-pattern. See this summary for an overview and people defending inversion:
     https://github.com/ziglang/zig/issues/18808
     Since ROS has such a sprawling list of dependencies, and relies heavily on code 
     generation, I think we'll need build time tools for at least interface generation. The Link
     time problem of dependency sprawl can be maintained by going to a mono package route for when
     zig wants to build everything from source. This mono package approach will also be more
     efficient, as right now the zig package manager will rebuild common dependencies if they
     appear more than once in the dependency tree.
 - Using custom build steps (will be an issue in the next zig release)
   - To implement message generation, this package relies heavily on custom build steps.
     Mr. Kelley has made it known that he plans to separate the config vs build steps into separate
     processes, which renders custom steps impossible to implement as they rely on providing a make
     function. It should be achievable to reimplement these custom steps as run steps as he
     suggests. See here: https://github.com/ziglang/zig/issues/20981

https://github.com/ros2/rosidl/tree/jazzy
https://github.com/ros2/rosidl_typesupport/tree/jazzy
