const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    const simple = b.addExecutable(.{
        .name = "simple",
        .root_source_file = b.path("src/simple.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    simple.entry = .disabled;
    simple.rdynamic = true;

    const zjb = b.dependency("zjb", .{
        .@"wasm-bindgen-bin" = simple.getEmittedBin(),
    });
    const extract_simple_out = zjb.namedLazyPath("zjb_extract.js");

    simple.root_module.addImport("zjb", zjb.module("zjb"));

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
