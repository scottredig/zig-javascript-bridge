const std = @import("std");
const demo_webserver = @import("demo_webserver");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.prefix;

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

    const install_step = b.getInstallStep();
    install_step.dependOn(&b.addInstallArtifact(simple, .{
        .dest_dir = .{ .override = dir },
    }).step);
    install_step.dependOn(&b.addInstallFileWithDir(extract_simple_out, dir, "zjb_extract.js").step);
    install_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);

    const run_demo_server = demo_webserver.runDemoServer(b, install_step, .{});
    const serve = b.step("serve", "serve website locally");
    serve.dependOn(run_demo_server);
}
