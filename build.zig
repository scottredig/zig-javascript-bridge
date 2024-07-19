const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    /////////////////////////////////////////////////////////////
    // generate js exe
    const generate_js = b.addExecutable(.{
        .name = "generate_js",
        .root_source_file = b.path("src/generate_js.zig"),
        .target = b.host,
        // Reusing this will occur more often than compiling this, as
        // it usually can be cached.  So faster execution is worth slower
        // initial build.
        .optimize = .ReleaseSafe,
    });
    b.installArtifact(generate_js);

    /////////////////////////////////////////////////////////////
    // module

    const module = b.addModule("zjb", .{
        .root_source_file = b.path("src/zjb.zig"),
    });

    /////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////
    // Example follows. Lines which are different because it's
    // defined in the same build.zig have a commented version if
    // you're using this library as a dependancy.

    // Optimize and target are unused except for by the example.
    // const zjb = b.dependency("zjb", .{});

    /////////////////////////////////////////////////////////////
    // example.wasm
    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("example/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    example.root_module.addImport("zjb", module);
    // example.root_module.addImport("zjb", zjb.module("zjb"));
    example.entry = .disabled;
    example.rdynamic = true;

    /////////////////////////////////////////////////////////////
    // generate js for example.wasm
    const extract_example = b.addRunArtifact(generate_js);
    // const extract_example = b.addRunArtifact(zjb.artifact("generate_js"));
    const extract_example_out = extract_example.addOutputFileArg("zjb_extract.js");
    extract_example.addArg("Zjb"); // Name of js class.
    extract_example.addArtifactArg(example);

    /////////////////////////////////////////////////////////////
    // example install
    const example_step = b.step("example", "Build the end to end example");

    example_step.dependOn(&b.addInstallArtifact(example, .{
        .dest_dir = .{ .override = dir },
    }).step);
    example_step.dependOn(&b.addInstallFileWithDir(extract_example_out, dir, "zjb_extract.js").step);

    example_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("example/static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);

    /////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////
    // Simpler example for the README.md

    const simple = b.addExecutable(.{
        .name = "simple",
        .root_source_file = b.path("simple/simple.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    simple.root_module.addImport("zjb", module);
    simple.entry = .disabled;
    simple.rdynamic = true;

    const extract_simple = b.addRunArtifact(generate_js);
    // const extract_simple = b.addRunArtifact(zjb.artifact("generate_js"));
    const extract_simple_out = extract_simple.addOutputFileArg("zjb_extract.js");
    extract_simple.addArg("Zjb"); // Name of js class.
    extract_simple.addArtifactArg(simple);

    const simple_step = b.step("simple", "Build the hello Zig example");
    simple_step.dependOn(&b.addInstallArtifact(simple, .{
        .dest_dir = .{ .override = dir },
    }).step);
    simple_step.dependOn(&b.addInstallFileWithDir(extract_simple_out, dir, "zjb_extract.js").step);
    simple_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("simple/static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);
}
