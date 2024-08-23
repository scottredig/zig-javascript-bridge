const std = @import("std");
const zjb = @import("zjb");
const alloc = std.heap.wasm_allocator;

fn log(v: anytype) void {
    zjb.global("console").call("log", .{v}, void);
}
fn logStr(str: []const u8) void {
    const handle = zjb.string(str);
    defer handle.release();
    zjb.global("console").call("log", .{handle}, void);
}

pub const panic = zjb.panic;
export fn main() void {
    zjb.global("console").call("log", .{zjb.constString("Hello from Zig")}, void);

    {
        const formatted = std.fmt.allocPrint(alloc, "Runtime string: current timestamp {d}", .{zjb.global("Date").call("now", .{}, f32)}) catch |e| zjb.throwError(e);
        defer alloc.free(formatted);

        const str = zjb.string(formatted);
        defer str.release();

        zjb.global("console").call("log", .{str}, void);
    }

    logStr("\n============================= Array View Example =============================");
    {
        var arr = [_]u16{ 1, 2, 3 };
        const obj = zjb.u16ArrayView(&arr);
        defer obj.release();

        logStr("View of Zig u16 array from Javascript, with its length");
        log(obj);
        log(obj.get("length", f64)); // 3

        arr[0] = 4;
        logStr("Changes from Zig are visible in Javascript");
        log(obj);

        logStr("Unless wasm's memory grows, which causes the ArrayView to be invalidated.");
        _ = @wasmMemoryGrow(0, 1);
        arr[0] = 5;
        log(obj);
        log(obj.get("length", f64)); // 0
    }

    logStr("\n============================= Data View Examples =============================");
    logStr("dataView allows extraction of numbers from WASM's memory.");
    {
        const arr = [_]u16{ 1, 2, 3 };
        const obj = zjb.dataView(&arr);
        defer obj.release();

        logStr("dataView works for arrays.");
        log(obj);
        log(obj.call("getUint16", .{ @sizeOf(u16) * 0, true }, f32));
        log(obj.call("getUint16", .{ @sizeOf(u16) * 1, true }, f32));
        log(obj.call("getUint16", .{ @sizeOf(u16) * 2, true }, f32));
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

        logStr("dataView also works for structs, make sure they're extern!");
        log(obj);
        log(obj.call("getUint16", .{ @offsetOf(S, "a"), true }, f32));
        log(obj.call("getUint16", .{ @offsetOf(S, "b"), true }, f32));
        log(obj.call("getUint32", .{ @offsetOf(S, "c"), true }, f32));
    }

    logStr("\n============================= Maps and index getting/setting =============================");
    {
        const obj = zjb.global("Map").new(.{});
        defer obj.release();

        const myI32: i32 = 0;
        obj.indexSet(myI32, 0);
        const myI64: i64 = 0;
        obj.indexSet(myI64, 1);

        obj.set("Hello", obj.indexGet(myI64, f64));

        const str = zjb.string("some_key");
        defer str.release();
        obj.indexSet(str, 2);

        log(obj);
    }

    logStr("\n============================= html canvas example =============================");
    {
        const canvas = zjb.global("document").call("getElementById", .{zjb.constString("canvas")}, zjb.Handle);
        defer canvas.release();

        canvas.set("width", 153);
        canvas.set("height", 140);

        const context = canvas.call("getContext", .{zjb.constString("2d")}, zjb.Handle);
        defer context.release();

        context.set("fillStyle", zjb.constString("#F7A41D"));

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

    logStr("\n============================= Exporting functions (press a key for a callback) =============================");
    zjb.global("document").call("addEventListener", .{ zjb.constString("keydown"), zjb.fnHandle("keydownCallback", keydownCallback) }, void);

    logStr("\n============================= Handle vs ConstHandle =============================");
    {
        logStr("zjb.global and zjb.constString add their ConstHandle on first use, and remember for subsiquent uses.  They can't be released.");
        logStr("While zjb.string and Handle return values must be released after being used or they'll leak.");
        logStr("See that some string remain in handles, while others have been removed after use.");
        const handles = zjb.global("zjb").get("_handles", zjb.Handle);
        defer handles.release();
        log(handles);
    }

    logStr("\n============================= Testing for unreleased handles =============================");
    logStr("\nIt's good to do this often.  Assert that the count is <= the number of handles you'll keep stored in long term state.");
    std.debug.assert(zjb.unreleasedHandleCount() == 0);
}

fn keydownCallback(event: zjb.Handle) callconv(.C) void {
    defer event.release();

    zjb.global("console").call("log", .{ zjb.constString("From keydown callback, event:"), event }, void);
}

var value: i32 = 0;
fn incrementAndGet(increment: i32) callconv(.C) i32 {
    value += increment;
    return value;
}

var test_var: f32 = 1337.7331;
fn checkTestVar() callconv(.C) f32 {
    return test_var;
}

fn setTestVar() callconv(.C) f32 {
    test_var = 42.24;
    return test_var;
}

comptime {
    zjb.exportFn("incrementAndGet", incrementAndGet);

    zjb.exportGlobal("test_var", &test_var);
    zjb.exportFn("checkTestVar", checkTestVar);
    zjb.exportFn("setTestVar", setTestVar);
}
