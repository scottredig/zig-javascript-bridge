const std = @import("std");

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
}
