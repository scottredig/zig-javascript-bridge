const std = @import("std");

pub fn string(b: []const u8) Handle {
    if (b.len == 0) {
        return Handle{ .id = 2 };
    }
    return Handle{ .id = zjb.string(b.ptr, b.len) };
}

pub fn i8ArrayView(data: []const i8) Handle {
    return Handle{ .id = zjb.i8ArrayView(data.ptr, data.len) };
}
pub fn u8ArrayView(data: []const u8) Handle {
    return Handle{ .id = zjb.u8ArrayView(data.ptr, data.len) };
}
pub fn u8ClampedArrayView(data: []const u8) Handle {
    return Handle{ .id = zjb.u8ClampedArrayView(data.ptr, data.len) };
}
pub fn i16ArrayView(data: []const i16) Handle {
    return Handle{ .id = zjb.i16ArrayView(data.ptr, data.len) };
}
pub fn u16ArrayView(data: []const u16) Handle {
    return Handle{ .id = zjb.u16ArrayView(data.ptr, data.len) };
}
pub fn i32ArrayView(data: []const i32) Handle {
    return Handle{ .id = zjb.i32ArrayView(data.ptr, data.len) };
}
pub fn u32ArrayView(data: []const u32) Handle {
    return Handle{ .id = zjb.u32ArrayView(data.ptr, data.len) };
}
pub fn i64ArrayView(data: []const i64) Handle {
    return Handle{ .id = zjb.i64ArrayView(data.ptr, data.len) };
}
pub fn u64ArrayView(data: []const u64) Handle {
    return Handle{ .id = zjb.u64ArrayView(data.ptr, data.len) };
}
pub fn f32ArrayView(data: []const f32) Handle {
    return Handle{ .id = zjb.f32ArrayView(data.ptr, data.len) };
}
pub fn f64ArrayView(data: []const f64) Handle {
    return Handle{ .id = zjb.f64ArrayView(data.ptr, data.len) };
}

pub fn dataView(data: anytype) Handle {
    switch (@typeInfo(@TypeOf(data))) {
        .Pointer => |ptr| {
            if (ptr.size == .One) {
                return Handle{ .id = zjb.dataview(data, @sizeOf(ptr.child)) };
            } else if (ptr.size == .Slice) {
                return Handle{ .id = zjb.dataview(data.ptr, data.len * @sizeOf(ptr.child)) };
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
    return Handle{ .id = 1 };
}

pub const Handle = struct {
    id: i32,

    pub fn getNull() Handle {
        return .{ .id = 0 };
    }

    pub fn isNull(self: Handle) bool {
        return self.id == 0;
    }

    pub fn release(self: Handle) void {
        if (self.id > 2) {
            zjb.release(self.id);
        }
    }

    pub fn get(self: Handle, comptime field: []const u8, comptime RetType: type) RetType {
        // validateReturn(RetType);
        const name = comptime "get_" ++ shortTypeName(RetType) ++ "_" ++ field;
        const F = fn (i32) callconv(.C) mapType(RetType);
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        return unmapValue(RetType, @call(.auto, f, .{self.id}));
    }

    pub fn set(self: Handle, comptime field: []const u8, value: anytype) void {
        const name = comptime "set_" ++ shortTypeName(@TypeOf(value)) ++ "_" ++ field;
        const F = fn (mapType(@TypeOf(value)), i32) callconv(.C) void;
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        @call(.auto, f, .{ mapValue(value), self.id });
    }

    pub fn indexGet(self: Handle, arg: anytype, comptime RetType: type) RetType {
        const name = comptime "indexGet_" ++ shortTypeName(@TypeOf(arg)) ++ "_" ++ shortTypeName(RetType);
        const F = fn (mapType(@TypeOf(arg)), i32) callconv(.C) mapType(RetType);
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        return unmapValue(RetType, @call(.auto, f, .{ mapValue(arg), self.id }));
    }

    pub fn indexSet(self: Handle, arg: anytype, value: anytype) void {
        const name = comptime "indexSet_" ++ shortTypeName(@TypeOf(arg)) ++ shortTypeName(@TypeOf(value));
        const F = fn (mapType(@TypeOf(arg)), mapType(@TypeOf(value)), i32) callconv(.C) void;
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        @call(.auto, f, .{ mapValue(arg), mapValue(value), self.id });
    }

    pub fn call(self: Handle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        return self.invoke(args, RetType, "call_", "_" ++ method);
    }

    pub fn new(self: Handle, args: anytype) Handle {
        return self.invoke(args, Handle, "new_", "");
    }

    fn invoke(self: Handle, args: anytype, comptime RetType: type, comptime prefix: []const u8, comptime suffix: []const u8) RetType {
        const args_struct = comptime @typeInfo(@TypeOf(args)).Struct;
        const fields = comptime args_struct.fields;
        comptime var call_fields: [fields.len + 1]std.builtin.Type.StructField = undefined;
        comptime var call_params: [fields.len + 1]std.builtin.Type.Fn.Param = undefined;
        comptime var extern_name: []const u8 = prefix;

        call_fields[fields.len] = .{
            .name = "0",
            .type = i32,
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };

        call_params[fields.len] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = i32,
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
            .alignment = 0,
            .is_generic = false,
            .is_var_args = false,
            .return_type = if (RetType == Handle) i32 else RetType,
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
        s[fields.len] = self.id;

        inline for (fields, 0..) |field, i| {
            if (field.type == Handle) {
                s[i] = args[i].id;
            } else {
                s[i] = args[i];
            }
        }

        if (RetType == Handle) {
            return Handle{ .id = @call(.auto, f, s) };
        } else {
            return @call(.auto, f, s);
        }
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
    if (T == Handle) {
        return i32;
    }
    if (T == comptime_int or T == comptime_float) {
        return f64;
    }
    return T;
}

fn mapValue(value: anytype) mapType(@TypeOf(value)) {
    if (@TypeOf(value) == Handle) {
        return value.id;
    }
    return value;
}

fn unmapValue(T: type, value: anytype) T {
    if (T == Handle) {
        return Handle{ .id = value };
    }
    return value;
}

const zjb = struct {
    extern "zjb" fn release(id: i32) void;
    extern "zjb" fn string(ptr: [*]const u8, len: u32) i32;
    extern "zjb" fn dataview(ptr: *const anyopaque, size: u32) i32;

    extern "zjb" fn i8ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn u8ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn u8ClampedArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn i16ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn u16ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn i32ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn u32ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn i64ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn u64ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn f32ArrayView(ptr: *const anyopaque, size: u32) i32;
    extern "zjb" fn f64ArrayView(ptr: *const anyopaque, size: u32) i32;
};
