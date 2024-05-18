// Example for readme
const zjb = @import("zjb");

export fn main() void {
    zjb.global("console").call("log", .{zjb.constString("Hello from Zig")}, void);
}
