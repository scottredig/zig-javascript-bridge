const std = @import("std");
const zjb = @import("zjb");

export fn foobar(i: i32) void {
    _ = i;
}

export fn main() void {
    const console = zjb.Handle.global.get("console", zjb.Handle);
    defer console.release();

    {
        const str = zjb.string("Hello from Zig");
        defer str.release();

        console.call("log", .{str}, void);
    }

    {
        var arr = [_]u16{ 1, 2, 3 };
        const obj = zjb.u16ArrayView(&arr);
        defer obj.release();

        console.call("log", .{obj}, void);
        console.call("log", .{obj.get("length", f64)}, void); // 3

        // Update is visible in Javascript
        arr[0] = 4;
        console.call("log", .{obj}, void);
        console.call("log", .{obj.get("length", f64)}, void); // 3

        // Unless wasm's memory grows, which causes the ArrayView to be invalidated.
        _ = @wasmMemoryGrow(0, 1);
        arr[0] = 5;
        console.call("log", .{obj}, void);
        console.call("log", .{obj.get("length", f64)}, void); // 0
    }

    {
        const arr = [_]u16{ 1, 2, 3 };
        const obj = zjb.dataView(&arr);
        defer obj.release();

        console.call("log", .{obj}, void);
    }

    {
        const S = extern struct {
            a: u16,
            b: u16,
            c: u32,
        };
        const s = S{ .a = 1, .b = 2, .c = 3 };
        const obj = zjb.dataView(&s);
        defer obj.release();

        console.call("log", .{obj}, void);
    }

    {
        const map = zjb.Handle.global.get("Map", zjb.Handle);
        defer map.release();

        const obj = map.new(.{});
        defer obj.release();

        const myI32: i32 = 0;
        obj.indexSet(myI32, 0);
        const myI64: i64 = 0;
        obj.indexSet(myI64, 1);

        obj.set("Hello", obj.indexGet(myI64, f64));

        const str = zjb.string("some_key");
        defer str.release();
        obj.indexSet(str, 2);

        console.call("log", .{obj}, void);
    }

    const document = zjb.Handle.global.get("document", zjb.Handle);
    defer document.release();

    {
        const id = zjb.string("canvas");
        defer id.release();

        const canvas = document.call("getElementById", .{id}, zjb.Handle);
        defer canvas.release();

        canvas.set("width", 153);
        canvas.set("height", 140);

        const str2D = zjb.string("2d");
        defer str2D.release();

        const context = canvas.call("getContext", .{str2D}, zjb.Handle);
        defer context.release();

        const style = zjb.string("#F7A41D");
        defer style.release();

        context.set("fillStyle", style);

        // Zig logo by Zig Software Foundation, github.com/ziglang/logo
        const shapes = [_][]const f64{
            &[_]f64{ 46, 22, 28, 44, 19, 30 },
            &[_]f64{ 46, 22, 33, 33, 28, 44, 22, 44, 22, 95, 31, 95, 20, 100, 12, 117, 0, 117, 0, 22 },
            &[_]f64{ 31, 95, 12, 117, 4, 106 },

            &[_]f64{ 56, 22, 62, 36, 37, 44 },
            &[_]f64{ 56, 22, 111, 22, 111, 44, 37, 44, 56, 32 },
            &[_]f64{ 116, 95, 97, 117, 90, 104 },
            &[_]f64{ 116, 95, 100, 104, 97, 117, 42, 117, 42, 95 },
            &[_]f64{ 150, 0, 52, 117, 3, 140, 101, 22 },

            &[_]f64{ 141, 22, 140, 40, 122, 45 },
            &[_]f64{ 153, 22, 153, 117, 106, 117, 120, 105, 125, 95, 131, 95, 131, 45, 122, 45, 132, 36, 141, 22 },
            &[_]f64{ 125, 95, 130, 110, 106, 117 },
        };

        for (shapes) |shape| {
            context.call("moveTo", .{ shape[0], shape[1] }, void);
            for (1..shape.len / 2) |i| {
                context.call("lineTo", .{ shape[2 * i], shape[2 * i + 1] }, void);
            }
            context.call("fill", .{}, void);
        }
    }

    {
        const str = zjb.string("keydown");
        defer str.release();

        console.call("log", .{keydownCallbackHandle()}, void);
        document.call("addEventListener", .{ str, keydownCallbackHandle() }, void);
    }

    zjb.Handle.global.call("setTimeout", .{ zjb.exportFn("timeout", timeout)(), 500 }, void);
}

fn timeout() callconv(.C) void {
    const console = zjb.Handle.global.get("console", zjb.Handle);
    defer console.release();

    const str = zjb.string("Hello from timeout callback");
    defer str.release();

    console.call("log", .{str}, void);
}

fn keydownCallback(event: zjb.Handle) callconv(.C) void {
    defer event.release();

    const console = zjb.Handle.global.get("console", zjb.Handle);
    defer console.release();

    const str = zjb.string("Hello from keydown callback");
    defer str.release();

    console.call("log", .{ str, event }, void);
}

var value: i32 = 0;
fn incrementAndGet(increment: i32) callconv(.C) i32 {
    value += increment;
    return value;
}

const keydownCallbackHandle = zjb.exportFn("keydownCallback", keydownCallback);

comptime {
    _ = zjb.exportFn("incrementAndGet", incrementAndGet);
}
