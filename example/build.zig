const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    example.entry = .disabled;
    example.rdynamic = true;

    const js_basename = "zjb_extract.js";
    const zjb = b.dependency("zjb", .{
        .@"wasm-bindgen-bin" = example.getEmittedBin(),
        .@"wasm-bindgen-name" = @as([]const u8, js_basename),
        .@"wasm-bindgen-classname" = @as([]const u8, "Zjb"),
    });
    const extract_example_out = zjb.namedLazyPath(js_basename);

    example.root_module.addImport("zjb", zjb.module("zjb"));

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
