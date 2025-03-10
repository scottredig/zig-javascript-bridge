const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    const zjb = b.dependency("javascript_bridge", .{});

    const simple = b.addExecutable(.{
        .name = "simple",
        .root_source_file = b.path("src/simple.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    simple.root_module.addImport("zjb", zjb.module("zjb"));
    simple.entry = .disabled;
    simple.rdynamic = true;

    const extract_simple = b.addRunArtifact(zjb.artifact("generate_js"));
    const extract_simple_out = extract_simple.addOutputFileArg("zjb_extract.js");
    extract_simple.addArg("Zjb"); // Name of js class.
    extract_simple.addArtifactArg(simple);

    const simple_step = b.step("simple", "Build the hello Zig example");
    simple_step.dependOn(&b.addInstallArtifact(simple, .{
        .dest_dir = .{ .override = dir },
    }).step);
    simple_step.dependOn(&b.addInstallFileWithDir(extract_simple_out, dir, "zjb_extract.js").step);
    simple_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);
}
