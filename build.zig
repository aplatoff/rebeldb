const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "rebeldb",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    //

    const exe = b.addExecutable(.{
        .name = "rebeldb",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    //

    const zbench_dep = b.dependency("zbench", .{
        .target = target,
        .optimize = optimize,
    });

    // Add benchmark executable
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_exe.root_module.addImport("zbench", zbench_dep.module("zbench"));

    //

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    //

    const bench_cmd = b.addRunArtifact(bench_exe);
    bench_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        bench_cmd.addArgs(args);
    }

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&bench_cmd.step);

    //

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // Add example executables
    const basic_usage = b.addExecutable(.{
        .name = "basic_usage",
        .root_source_file = b.path("docs/examples/basic_usage.zig"),
        .target = target,
        .optimize = optimize,
    });
    basic_usage.root_module.addImport("rebeldb", &lib.root_module);

    const page_config = b.addExecutable(.{
        .name = "page_config",
        .root_source_file = b.path("docs/examples/page_configuration.zig"),
        .target = target,
        .optimize = optimize,
    });
    page_config.root_module.addImport("rebeldb", &lib.root_module);

    const mem_mgmt = b.addExecutable(.{
        .name = "mem_mgmt",
        .root_source_file = b.path("docs/examples/memory_management.zig"),
        .target = target,
        .optimize = optimize,
    });
    mem_mgmt.root_module.addImport("rebeldb", &lib.root_module);

    // Add examples step
    const examples_step = b.step("examples", "Build example executables");
    const basic_usage_install = b.addInstallArtifact(basic_usage, .{});
    const page_config_install = b.addInstallArtifact(page_config, .{});
    const mem_mgmt_install = b.addInstallArtifact(mem_mgmt, .{});

    examples_step.dependOn(&basic_usage_install.step);
    examples_step.dependOn(&page_config_install.step);
    examples_step.dependOn(&mem_mgmt_install.step);
}
