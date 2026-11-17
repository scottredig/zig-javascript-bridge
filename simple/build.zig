const std = @import("std");
const demo_webserver = @import("demo_webserver");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const zjb = b.dependency("javascript_bridge", .{});

    const simple = b.addExecutable(.{
        .name = "simple",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/simple.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = optimize,
        }),
    });
    simple.root_module.addImport("zjb", zjb.module("zjb"));
    simple.entry = .disabled;
    simple.rdynamic = true;

    const extract_simple = b.addRunArtifact(zjb.artifact("generate_js"));
    const extract_simple_out = extract_simple.addOutputFileArg("zjb_extract.js");
    extract_simple.addArg("Zjb"); // Name of js class.
    extract_simple.addArtifactArg(simple);

    const write_files = b.addWriteFiles();
    _ = write_files.addCopyDirectory(simple.getEmittedBinDirectory(), "", .{});
    _ = write_files.addCopyDirectory(b.path("static"), "", .{});
    _ = write_files.addCopyFile(extract_simple_out, "zjb_extract.js");

    const run_demo_server = demo_webserver.runDemoServer(b, write_files, .{});
    const serve = b.step("serve", "serve website locally");
    serve.dependOn(run_demo_server);
}
