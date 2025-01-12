const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    /////////////////////////////////////////////////////////////
    // generate js exe
    const generate_js = b.addExecutable(.{
        .name = "generate_js",
        .root_source_file = b.path("src/generate_js.zig"),
        .target = b.graph.host,
        // Reusing this will occur more often than compiling this, as
        // it usually can be cached.  So faster execution is worth slower
        // initial build.
        .optimize = .ReleaseSafe,
    });
    b.installArtifact(generate_js);

    /////////////////////////////////////////////////////////////
    // module

    _ = b.addModule("zjb", .{
        .root_source_file = b.path("src/zjb.zig"),
    });

    // Generate JS for binary supplied through options
    // usage from build.zig through the Dependency Interface:
    //
    // const js_basename = "zjb_extract.js";
    // const zjb = b.dependency("zjb", .{
    //     .@"wasm-bindgen-bin" = example.getEmittedBin(),
    //     .@"wasm-bindgen-name" = @as([]const u8, js_basename),
    //     .@"wasm-bindgen-classname" = @as([]const u8, "Zjb"),
    // });
    // const extract_example_out = zjb.namedLazyPath(js_basename);
    //
    const wasm_bindgen_name = b.option(
        []const u8,
        "wasm-bindgen-name",
        "js Bindings Basename",
    ) orelse "zjb_extract.js";
    const wasm_bindgen_classname = b.option(
        []const u8,
        "wasm-bindgen-classname",
        "js Bindings Classname",
    ) orelse "Zjb";
    const wasm_bindgen_bin = b.option(
        LazyPath,
        "wasm-bindgen-bin",
        "wasm Binary for Binding Generation",
    );
    const wasm_bindgen_module = b.option(
        bool,
        "wasm-bindgen-module",
        "output an ES6 module export",
    ) orelse false;

    if (wasm_bindgen_bin) |wasm_bin| {
        const extract_js = b.addRunArtifact(generate_js);
        const extract_js_out = extract_js.addOutputFileArg(wasm_bindgen_name);
        extract_js.addArg(wasm_bindgen_classname);
        extract_js.addFileArg(wasm_bin);
        b.addNamedLazyPath(wasm_bindgen_name, extract_js_out);
        extract_js.addArg(if (wasm_bindgen_module) "true" else "false");
    }
}
