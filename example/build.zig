const std = @import("std");
const demo_webserver = @import("demo_webserver");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const zjb = b.dependency("javascript_bridge", .{});

    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = optimize,
        }),
    });
    example.root_module.addImport("zjb", zjb.module("zjb"));
    example.entry = .disabled;
    example.rdynamic = true;

    const extract_example = b.addRunArtifact(zjb.artifact("generate_js"));
    const extract_example_out = extract_example.addOutputFileArg("zjb_extract.js");
    extract_example.addArg("Zjb"); // Name of js class.
    extract_example.addArtifactArg(example);

    const write_files = b.addWriteFiles();
    _ = write_files.addCopyDirectory(example.getEmittedBinDirectory(), "", .{});
    _ = write_files.addCopyDirectory(b.path("static"), "", .{});
    _ = write_files.addCopyFile(extract_example_out, "zjb_extract.js");

    const run_demo_server = demo_webserver.runDemoServer(b, write_files, .{});
    const serve = b.step("serve", "serve website locally");
    serve.dependOn(run_demo_server);
}
