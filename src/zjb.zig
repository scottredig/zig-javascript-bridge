const std = @import("std");

pub fn string(b: []const u8) Handle {
    if (b.len == 0) {
        return @enumFromInt(2);
    }
    return zjb.string(b.ptr, b.len);
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

pub fn global() Handle {
    return @enumFromInt(1);
}

pub const Handle = enum(i32) {
    _,

    pub fn getNull() Handle {
        return @enumFromInt(0);
    }

    pub fn isNull(handle: Handle) bool {
        return @intFromEnum(handle) == 0;
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
        @call(.auto, f, .{ mapValue(value), handle });
    }

    pub fn indexGet(handle: Handle, arg: anytype, comptime RetType: type) RetType {
        const name = comptime "indexGet_" ++ shortTypeName(@TypeOf(arg)) ++ "_" ++ shortTypeName(RetType);
        const F = fn (mapType(@TypeOf(arg)), Handle) callconv(.C) mapType(RetType);
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        return @call(.auto, f, .{ mapValue(arg), handle });
    }

    pub fn indexSet(handle: Handle, arg: anytype, value: anytype) void {
        const name = comptime "indexSet_" ++ shortTypeName(@TypeOf(arg)) ++ shortTypeName(@TypeOf(value));
        const F = fn (mapType(@TypeOf(arg)), mapType(@TypeOf(value)), Handle) callconv(.C) void;
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        @call(.auto, f, .{ mapValue(arg), mapValue(value), handle });
    }

    pub fn call(handle: Handle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        return handle.invoke(args, RetType, "call_", "_" ++ method);
    }

    pub fn new(handle: Handle, args: anytype) Handle {
        return handle.invoke(args, Handle, "new_", "");
    }

    fn invoke(handle: Handle, args: anytype, comptime RetType: type, comptime prefix: []const u8, comptime suffix: []const u8) RetType {
        const args_struct = comptime @typeInfo(@TypeOf(args)).Struct;
        const fields = comptime args_struct.fields;
        comptime var call_fields: [fields.len + 1]std.builtin.Type.StructField = undefined;
        comptime var call_params: [fields.len + 1]std.builtin.Type.Fn.Param = undefined;
        comptime var extern_name: []const u8 = prefix;

        call_fields[fields.len] = .{
            .name = std.fmt.comptimePrint("{d}", .{fields.len}),
            .type = Handle,
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };

        call_params[fields.len] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = Handle,
        };

        inline for (fields, 0..) |field, i| {
            // validateParam(field.type);
            call_fields[i] = .{
                .name = field.name,
                .type = mapType(field.type),
                .default_value = null,
                .is_comptime = false,
                .alignment = field.alignment,
            };

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

        const S = @Type(.{ .Struct = .{
            .layout = args_struct.layout,
            .fields = &call_fields,
            .decls = &.{},
            .is_tuple = true,
        } });

        var s: S = undefined;
        s[fields.len] = handle;

        inline for (0..fields.len) |i| {
            s[i] = args[i];
        }

        return @call(.auto, f, s);
    }
};

fn shortTypeName(comptime T: type) []const u8 {
    return switch (T) {
        Handle => "o",
        void => "v",
        bool => "b",
        // The number types map to the same name, even though
        // the function signatures are different.  Zig and Wasm
        // handle this just fine, and produces fewer unique methods
        // in javascript so there's no reason not to do it.
        i32, i64, f32, f64, comptime_int, comptime_float => "n",
        else => {
            @compileError("unexpected type" ++ @typeName(T));
        },
    };
}

fn mapType(comptime T: type) type {
    if (T == comptime_int or T == comptime_float) {
        return f64;
    }
    return T;
}

fn mapValue(value: anytype) mapType(@TypeOf(value)) {
    return value;
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
