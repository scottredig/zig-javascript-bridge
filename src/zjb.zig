const std = @import("std");

pub fn string(b: []const u8) Handle {
    if (b.len == 0) {
        return @enumFromInt(2);
    }
    return zjb.string(b.ptr, b.len);
}

pub fn constString(comptime b: []const u8) ConstHandle {
    return struct {
        var handle: ?ConstHandle = null;
        fn get() ConstHandle {
            if (handle) |h| {
                return h;
            }
            handle = @enumFromInt(@intFromEnum(string(b)));
            return handle.?;
        }
    }.get();
}

pub fn global(comptime b: []const u8) ConstHandle {
    return struct {
        var handle: ?ConstHandle = null;
        fn get() ConstHandle {
            if (handle) |h| {
                return h;
            }
            handle = @enumFromInt(@intFromEnum(ConstHandle.global.get(b, Handle)));
            return handle.?;
        }
    }.get();
}

pub fn fnHandle(comptime name: []const u8, comptime f: anytype) ConstHandle {
    comptime exportFn(name, f);

    return struct {
        var handle: ?ConstHandle = null;
        fn get() ConstHandle {
            if (handle) |h| {
                return h;
            }
            handle = @enumFromInt(@intFromEnum(ConstHandle.exports.get(name, Handle)));
            return handle.?;
        }
    }.get();
}

pub fn exportFn(comptime name: []const u8, comptime f: anytype) void {
    comptime var export_name: []const u8 = "zjb_fn_";
    const type_info = @typeInfo(@TypeOf(f)).Fn;
    inline for (type_info.params) |param| {
        export_name = export_name ++ comptime shortTypeName(param.type orelse @compileError("zjb exported functions need specified types."));
    }
    export_name = export_name ++ "_" ++ comptime shortTypeName(type_info.return_type orelse null) ++ "_" ++ name;

    @export(f, .{ .name = export_name });
}

pub fn i8ArrayView(data: []const i8) Handle {
    return zjb.i8ArrayView(data.ptr, data.len);
}
pub fn u8ArrayView(data: []const u8) Handle {
    return zjb.u8ArrayView(data.ptr, data.len);
}
pub fn u8ClampedArrayView(data: []const u8) Handle {
    return zjb.u8ClampedArrayView(data.ptr, data.len);
}
pub fn i16ArrayView(data: []const i16) Handle {
    return zjb.i16ArrayView(data.ptr, data.len);
}
pub fn u16ArrayView(data: []const u16) Handle {
    return zjb.u16ArrayView(data.ptr, data.len);
}
pub fn i32ArrayView(data: []const i32) Handle {
    return zjb.i32ArrayView(data.ptr, data.len);
}
pub fn u32ArrayView(data: []const u32) Handle {
    return zjb.u32ArrayView(data.ptr, data.len);
}
pub fn i64ArrayView(data: []const i64) Handle {
    return zjb.i64ArrayView(data.ptr, data.len);
}
pub fn u64ArrayView(data: []const u64) Handle {
    return zjb.u64ArrayView(data.ptr, data.len);
}
pub fn f32ArrayView(data: []const f32) Handle {
    return zjb.f32ArrayView(data.ptr, data.len);
}
pub fn f64ArrayView(data: []const f64) Handle {
    return zjb.f64ArrayView(data.ptr, data.len);
}

pub fn dataView(data: anytype) Handle {
    switch (@typeInfo(@TypeOf(data))) {
        .Pointer => |ptr| {
            if (ptr.size == .One) {
                return zjb.dataview(data, @sizeOf(ptr.child));
            } else if (ptr.size == .Slice) {
                return zjb.dataview(data.ptr, data.len * @sizeOf(ptr.child));
            } else {
                @compileError("dataview pointers must be single objects or slices, got: " ++ @typeName(@TypeOf(data)));
            }
        },
        else => {
            @compileError("dataview must get a pointer or a slice, got: " ++ @typeName(@TypeOf(data)));
        },
    }
}

pub const ConstHandle = enum(i32) {
    null = 0,
    global = 1,
    empty_string = 2,
    exports = 3,
    _,

    pub fn isNull(handle: ConstHandle) bool {
        return handle == .null;
    }

    fn asHandle(handle: ConstHandle) Handle {
        // Generally not a safe conversion, as turning into a handle and releasing elsewhere
        // will invalidate all other uses of the constant.
        return @enumFromInt(@intFromEnum(handle));
    }

    pub fn get(handle: ConstHandle, comptime field: []const u8, comptime RetType: type) RetType {
        return handle.asHandle().get(field, RetType);
    }
    pub fn set(handle: ConstHandle, comptime field: []const u8, value: anytype) void {
        handle.asHandle().set(field, value);
    }
    pub fn indexGet(handle: ConstHandle, arg: anytype, comptime RetType: type) RetType {
        return handle.asHandle().indexGet(arg, RetType);
    }
    pub fn indexSet(handle: ConstHandle, arg: anytype, value: anytype) void {
        handle.asHandle().indexSet(arg, value);
    }
    pub fn call(handle: ConstHandle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        return handle.asHandle().call(method, args, RetType);
    }
    pub fn new(handle: ConstHandle, args: anytype) Handle {
        return handle.asHandle().new(args);
    }
};

pub const Handle = enum(i32) {
    null = 0,
    _,

    pub fn isNull(handle: Handle) bool {
        return handle == .null;
    }

    pub fn release(handle: Handle) void {
        if (@intFromEnum(handle) > 2) {
            zjb.release(handle);
        }
    }

    pub fn get(handle: Handle, comptime field: []const u8, comptime RetType: type) RetType {
        // validateReturn(RetType);
        const name = comptime "get_" ++ shortTypeName(RetType) ++ "_" ++ field;
        const F = fn (Handle) callconv(.C) mapType(RetType);
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        return @call(.auto, f, .{handle});
    }

    pub fn set(handle: Handle, comptime field: []const u8, value: anytype) void {
        const name = comptime "set_" ++ shortTypeName(@TypeOf(value)) ++ "_" ++ field;
        const F = fn (mapType(@TypeOf(value)), Handle) callconv(.C) void;
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        @call(.auto, f, .{ value, handle });
    }

    pub fn indexGet(handle: Handle, arg: anytype, comptime RetType: type) RetType {
        const name = comptime "indexGet_" ++ shortTypeName(@TypeOf(arg)) ++ "_" ++ shortTypeName(RetType);
        const F = fn (mapType(@TypeOf(arg)), Handle) callconv(.C) mapType(RetType);
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        return @call(.auto, f, .{ arg, handle });
    }

    pub fn indexSet(handle: Handle, arg: anytype, value: anytype) void {
        const name = comptime "indexSet_" ++ shortTypeName(@TypeOf(arg)) ++ shortTypeName(@TypeOf(value));
        const F = fn (mapType(@TypeOf(arg)), mapType(@TypeOf(value)), Handle) callconv(.C) void;
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        @call(.auto, f, .{ arg, value, handle });
    }

    pub fn call(handle: Handle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        return handle.invoke(args, RetType, "call_", "_" ++ method);
    }

    pub fn new(handle: Handle, args: anytype) Handle {
        return handle.invoke(args, Handle, "new_", "");
    }

    fn invoke(handle: Handle, args: anytype, comptime RetType: type, comptime prefix: []const u8, comptime suffix: []const u8) RetType {
        const fields = comptime @typeInfo(@TypeOf(args)).Struct.fields;
        comptime var call_params: [fields.len + 1]std.builtin.Type.Fn.Param = undefined;
        comptime var extern_name: []const u8 = prefix;

        call_params[fields.len] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = Handle,
        };

        inline for (fields, 0..) |field, i| {
            call_params[i] = .{
                .is_generic = false,
                .is_noalias = false,
                .type = mapType(field.type),
            };
            extern_name = extern_name ++ comptime shortTypeName(field.type);
        }

        const F = @Type(.{ .Fn = .{
            .calling_convention = .C,
            .is_generic = false,
            .is_var_args = false,
            .return_type = RetType,
            .params = &call_params,
        } });
        extern_name = extern_name ++ "_" ++ comptime shortTypeName(RetType) ++ suffix;

        const f = @extern(*const F, .{ .library_name = "zjb", .name = extern_name });
        return @call(.auto, f, args ++ .{handle});
    }
};

fn shortTypeName(comptime T: type) []const u8 {
    return switch (T) {
        Handle, ConstHandle => "o",
        void => "v",
        bool => "b",
        // The number types map to the same name, even though
        // the function signatures are different.  Zig and Wasm
        // handle this just fine, and produces fewer unique methods
        // in javascript so there's no reason not to do it.
        i32, i64, f32, f64, comptime_int, comptime_float => "n",
        else => {
            @compileError("unexpected type " ++ @typeName(T) ++ ". Supported types: zjb.Handle, bool, i32, i64, f32, f64, comptime_int, copmtime_float, void (as return type).");
        },
    };
}

fn mapType(comptime T: type) type {
    if (T == comptime_int or T == comptime_float) {
        return f64;
    }
    return T;
}

const zjb = struct {
    extern "zjb" fn release(id: Handle) void;
    extern "zjb" fn string(ptr: [*]const u8, len: u32) Handle;
    extern "zjb" fn dataview(ptr: *const anyopaque, size: u32) Handle;

    extern "zjb" fn i8ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn u8ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn u8ClampedArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn i16ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn u16ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn i32ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn u32ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn i64ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn u64ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn f32ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn f64ArrayView(ptr: *const anyopaque, size: u32) Handle;
};
