// Example for readme
const zjb = @import("zjb");

export fn main() void {
    const console = zjb.Handle.global.get("console", zjb.Handle);
    defer console.release();

    const str = zjb.string("Hello from Zig");
    defer str.release();

    console.call("log", .{str}, void);
}
