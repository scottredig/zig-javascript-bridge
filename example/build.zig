const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    const zjb = b.dependency("javascript_bridge", .{});

    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    example.root_module.addImport("zjb", zjb.module("zjb"));
    example.entry = .disabled;
    example.rdynamic = true;

    const extract_example = b.addRunArtifact(zjb.artifact("generate_js"));
    const extract_example_out = extract_example.addOutputFileArg("zjb_extract.js");
    extract_example.addArg("Zjb"); // Name of js class.
    extract_example.addArtifactArg(example);

    const example_step = b.step("example", "Build the hello Zig example");
    example_step.dependOn(&b.addInstallArtifact(example, .{
        .dest_dir = .{ .override = dir },
    }).step);
    example_step.dependOn(&b.addInstallFileWithDir(extract_example_out, dir, "zjb_extract.js").step);
    example_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);
}
