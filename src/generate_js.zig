const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len != 4) {
        return ExtractError.BadArguments;
    }

    var imports = std.ArrayList([]const u8).init(alloc);
    defer imports.deinit();
    var exports = std.ArrayList([]const u8).init(alloc);
    defer exports.deinit();

    {
        var file = try std.fs.openFileAbsolute(args[3], .{});
        defer file.close();

        const bytes = try file.readToEndAlloc(alloc, std.math.maxInt(usize));
        defer alloc.free(bytes);
        var r = Reader{ .slice = bytes };

        {
            const magic = try r.bytes(4);
            if (!std.mem.eql(u8, magic, &[4]u8{ 0x00, 0x61, 0x73, 0x6d })) {
                return ExtractError.WasmWrongMagic;
            }

            const version = try r.bytes(4);
            if (!std.mem.eql(u8, version, &[4]u8{ 0x01, 0x00, 0x00, 0x00 })) {
                return ExtractError.WasmWrongVersion;
            }
        }

        while (r.slice.len > 0) {
            const section_id = try r.byte();
            const section_length = try r.getU32();
            if (section_id == 2) {
                const import_count = try r.getU32();
                for (0..import_count) |_| {
                    const module_length = try r.getU32();
                    const module = try r.bytes(module_length);

                    const name_length = try r.getU32();
                    const name = try r.bytes(name_length);

                    const desc_type = try r.byte();
                    const desc_index = try r.getU32();
                    _ = desc_index;

                    if (std.mem.eql(u8, module, "zjb")) {
                        if (desc_type != 0) { // Not a function?
                            return ExtractError.ImportTypeNotSupported;
                        }
                        try imports.append(try alloc.dupe(u8, name));
                    }
                }
            } else if (section_id == 7) {
                const export_count = try r.getU32();
                for (0..export_count) |_| {
                    const name_length = try r.getU32();
                    const name = try r.bytes(name_length);

                    const desc_type = try r.byte();
                    const desc_index = try r.getU32();
                    _ = desc_index;

                    if (desc_type == 0 and std.mem.startsWith(u8, name, "zjb_fn")) {
                        try exports.append(try alloc.dupe(u8, name));
                    }
                }
            } else {
                _ = try r.bytes(section_length);
            }
        }
    }

    std.sort.insertion([]const u8, imports.items, {}, strBefore);
    std.sort.insertion([]const u8, exports.items, {}, strBefore);

    var out_file = try std.fs.createFileAbsolute(args[1], .{});
    defer out_file.close();
    const writer = out_file.writer();

    try writer.writeAll("const ");
    try writer.writeAll(args[2]);
    // keep the "3" and "12" in sync with the size of DynamicString.Header
    try writer.writeAll(
        \\ = class {
        \\  new_handle(value) {
        \\    if (value === null) {
        \\      return 0;
        \\    }
        \\    const result = this._next_handle;
        \\    this._handles.set(result, value);
        \\    this._next_handle++;
        \\    return result;
        \\  }
        \\  alloc_string(string) {
        \\    const encodedString = this._encoder.encode(String(string));
        \\    const pointer = this.instance.exports.alloc_string(encodedString.length + 12);
        \\    const buffer = this.instance.exports.memory.buffer;
        \\    let header = new Uint32Array(buffer, pointer, 3);
        \\    header[0] = 0;
        \\    header[1] = pointer;
        \\    header[2] = encodedString.length + 12;
        \\    const arr = new Uint8Array(buffer, pointer + 12, encodedString.length);
        \\    arr.set(encodedString);
        \\    return pointer;
        \\  }
        \\  free_string(pointer) {
        \\    this.instance.exports.free_string(pointer)
        \\  }
        \\  constructor() {
        \\    this._decoder = new TextDecoder();
        \\    this._encoder = new TextEncoder();
        \\    this.imports = {
        \\
    );

    var lastFunc: []const u8 = "";
    var func_args = std.ArrayList(ArgType).init(alloc);
    defer func_args.deinit();

    implement_functions: for (imports.items) |func| {
        if (std.mem.eql(u8, lastFunc, func)) {
            continue;
        }
        lastFunc = func;
        func_args.clearRetainingCapacity();

        var np = NameParser{ .slice = func };

        inline for (builtins) |fn_bytes| {
            const open_quote = comptime std.mem.indexOf(u8, fn_bytes, "\"") orelse @compileError("bad buildin");
            const close_quote = comptime open_quote + 1 + (std.mem.indexOf(u8, fn_bytes[open_quote + 1 ..], "\"") orelse @compileError("bad buildin"));
            if (np.maybeExact(fn_bytes[open_quote + 1 .. close_quote])) {
                try writer.writeAll(fn_bytes);
                try writer.writeAll("\n");
                continue :implement_functions;
            }
        }

        const Methods = enum {
            get,
            set,
            indexGet,
            indexSet,
            call,
            new,
        };
        const method = blk: {
            if (np.maybe("get_")) {
                break :blk Methods.get;
            }
            if (np.maybe("set_")) {
                break :blk Methods.set;
            }
            if (np.maybe("indexGet_")) {
                break :blk Methods.indexGet;
            }
            if (np.maybe("indexSet_")) {
                break :blk Methods.indexSet;
            }
            if (np.maybe("call_")) {
                break :blk Methods.call;
            }
            if (np.maybe("new_")) {
                break :blk Methods.new;
            }
            return ExtractError.InvalidExportedName;
        };

        if (method != .get) {
            while (!(np.maybe("_") or np.slice.len == 0)) {
                try func_args.append(try np.mustType());
            }
        }
        switch (method) {
            .get => {
                if (func_args.items.len != 0) {
                    return ExtractError.InvalidExportedName;
                }
            },
            .set, .indexGet => {
                if (func_args.items.len != 1) {
                    return ExtractError.InvalidExportedName;
                }
            },
            .indexSet => {
                if (func_args.items.len != 2) {
                    return ExtractError.InvalidExportedName;
                }
            },
            else => {},
        }

        const ret_type = switch (method) {
            .new => ArgType.object,
            .set, .indexSet => ArgType.void,
            else => try np.mustType(),
        };

        switch (method) {
            .new, .indexGet, .set, .indexSet => {},
            else => {
                try np.must("_");
            },
        }

        const target = np.slice;

        //////////////////////////////////

        try writer.writeAll("      \"");
        try writer.writeAll(func);
        try writer.writeAll("\": (");
        for (0..func_args.items.len) |i| {
            try writer.print("arg{d}, ", .{i});
        }

        try writer.writeAll("id) => {\n        ");
        switch (ret_type) {
            .void => {},
            .bool => {
                try writer.writeAll("return Boolean(");
            },
            .object => {
                try writer.writeAll("return this.new_handle(");
            },
            .number => {
                try writer.writeAll("return ");
            },
            .string => {
                try writer.writeAll("return this.alloc_string(");
            },
        }

        switch (method) {
            .get, .set, .call => {
                try writer.writeAll("this._handles.get(id).");
                try writer.writeAll(target);
            },
            .indexGet, .indexSet => {
                try writer.writeAll("this._handles.get(id)[");
                try writeArg(writer, func_args.items[0], 0);
                try writer.writeAll("]");
            },
            .new => {
                try writer.writeAll("new (this._handles.get(id))");
            },
        }

        switch (method) {
            .get, .indexGet => {},
            .call, .new => {
                try writer.writeAll("(");

                for (func_args.items, 0..) |arg, i| {
                    if (i > 0) {
                        try writer.writeAll(", ");
                    }
                    try writeArg(writer, arg, i);
                }

                try writer.writeAll(")");
            },
            .set => {
                try writer.writeAll(" = ");
                try writeArg(writer, func_args.items[0], 0);
            },
            .indexSet => {
                try writer.writeAll(" = ");
                try writeArg(writer, func_args.items[1], 1);
            },
        }

        switch (ret_type) {
            .bool, .object, .string => {
                try writer.writeAll(")");
            },
            .void, .number => {},
        }

        try writer.writeAll(";\n      },\n");
    }
    try writer.writeAll("    };\n"); // end imports

    try writer.writeAll("    this.exports = {\n");

    var export_names = std.ArrayList([]const u8).init(alloc);
    defer export_names.deinit();

    for (exports.items) |func| {
        func_args.clearRetainingCapacity();

        var np = NameParser{ .slice = func };
        try np.must("zjb_fn_");

        while (!(np.maybe("_") or np.slice.len == 0)) {
            try func_args.append(try np.mustType());
        }

        const ret_type = try np.mustType();
        try np.must("_");

        const name = np.slice;
        try export_names.append(name);

        //////////////////////////////////

        try writer.writeAll("      \"");
        try writer.writeAll(name);
        try writer.writeAll("\": (");

        for (0..func_args.items.len) |i| {
            if (i > 0) {
                try writer.writeAll(", ");
            }
            try writer.print("arg{d}", .{i});
        }

        try writer.writeAll(") => {\n");

        for (func_args.items, 0..) |arg, i| {
            switch (arg) {
                .string => {
                    try writer.print("        let str{} = this.alloc_string(arg{});\n", .{ i, i });
                },
                else => {},
            }
        }

        try writer.writeAll("        let r = ");
        switch (ret_type) {
            .void => {},
            .bool => {
                try writer.writeAll("Boolean(");
            },
            .object => {
                try writer.writeAll("this._handles.get(");
            },
            .number => {},
            .string => {
                try writer.writeAll("this.alloc_string(");
            },
        }

        try writer.writeAll("this.instance.exports.");
        try writer.writeAll(func);
        try writer.writeAll("(");

        for (func_args.items, 0..) |arg, i| {
            if (i > 0) {
                try writer.writeAll(", ");
            }
            switch (arg) {
                .void => {
                    return ExtractError.InvalidExportedName;
                },
                .bool => {
                    try writer.print("Boolean(arg{d})", .{i});
                },
                .object => {
                    try writer.print("this.new_handle(arg{d})", .{i});
                },
                .number => {
                    try writer.print("arg{d}", .{i});
                },
                .string => {
                    try writer.print("str{d}", .{i});
                },
            }
        }

        try writer.writeAll(")");

        switch (ret_type) {
            .bool, .object => {
                try writer.writeAll(")");
            },
            .string => unreachable,
            .void, .number => {},
        }
        try writer.writeAll(";\n");

        for (func_args.items, 0..) |arg, i| {
            switch (arg) {
                .string => {
                    try writer.print("        this.free_string(str{});\n", .{i});
                },
                else => {},
            }
        }

        try writer.writeAll("        return r;\n");
        try writer.writeAll("      },\n");
    }
    try writer.writeAll("    };\n"); // end exports

    try writer.writeAll(
        \\    this._export_reverse_handles = {};
        \\    this._handles = new Map();
        \\    this._handles.set(0, null);
        \\    this._handles.set(1, window);
        \\    this._handles.set(2, "");
        \\    this._handles.set(3, this.exports);
        \\    this._next_handle = 4;
        \\
    );

    try writer.writeAll(
        \\  }
        \\};
        \\
    );

    std.sort.insertion([]const u8, export_names.items, {}, strBefore);
    if (export_names.items.len > 1) {
        for (0..export_names.items.len - 1) |i| {
            if (std.mem.eql(u8, export_names.items[i], export_names.items[i + 1])) {
                std.debug.print("ERROR: function export name used twice: {s}.\n", .{export_names.items[i]});
                std.posix.exit(1);
            }
        }
    }

    try out_file.sync();
}

fn writeArg(writer: anytype, arg: ArgType, i: usize) !void {
    switch (arg) {
        .void => {
            return ExtractError.InvalidExportedName;
        },
        .bool => {
            try writer.print("Boolean(arg{d})", .{i});
        },
        .object => {
            try writer.print("this._handles.get(arg{d})", .{i});
        },
        .number => {
            try writer.print("arg{d}", .{i});
        },
        .string => {
            try writer.print("this.allocString(arg{d})", .{i});
        },
    }
}

const Reader = struct {
    slice: []const u8,

    fn getU32(self: *Reader) !u32 {
        var r: u32 = 0;
        var offset: u8 = 0;
        while (true) {
            const b = try self.byte();
            r |= @as(u32, b & 0b0111_1111) << @intCast(offset);
            if (b < 0b1000_0000) {
                return r;
            }
            offset += 7;
        }
    }

    fn byte(self: *Reader) !u8 {
        if (self.slice.len < 1) {
            return ExtractError.UnexpectedEndOfFile;
        }
        const r = self.slice[0];
        self.slice = self.slice[1..];
        return r;
    }

    fn bytes(self: *Reader, length: u32) ExtractError![]const u8 {
        if (self.slice.len < length) {
            return ExtractError.UnexpectedEndOfFile;
        }
        const r = self.slice[0..length];
        self.slice = self.slice[length..];
        return r;
    }
};

const ExtractError = error{
    BadArguments,
    UnexpectedEndOfFile,
    WasmWrongMagic,
    WasmWrongVersion,
    ImportTypeNotSupported,
    InvalidExportedName,
};

fn strBefore(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs).compare(std.math.CompareOperator.lt);
}

const ArgType = enum {
    number,
    bool,
    void,
    object,
    string,
};

const NameParser = struct {
    slice: []const u8,

    fn maybe(self: *NameParser, attempt: []const u8) bool {
        if (self.slice.len >= attempt.len and std.mem.eql(u8, self.slice[0..attempt.len], attempt)) {
            self.slice = self.slice[attempt.len..];
            return true;
        }
        return false;
    }

    fn maybeExact(self: *NameParser, attempt: []const u8) bool {
        if (self.slice.len == attempt.len and std.mem.eql(u8, self.slice[0..attempt.len], attempt)) {
            self.slice = self.slice[attempt.len..];
            return true;
        }
        return false;
    }

    fn must(self: *NameParser, attempt: []const u8) !void {
        if (!self.maybe(attempt)) {
            return ExtractError.InvalidExportedName;
        }
    }

    fn mustType(self: *NameParser) !ArgType {
        if (self.maybe("n")) {
            return .number;
        }
        if (self.maybe("b")) {
            return .bool;
        }
        if (self.maybe("v")) {
            return .void;
        }
        if (self.maybe("o")) {
            return .object;
        }
        if (self.maybe("s")) {
            return .string;
        }
        return ExtractError.InvalidExportedName;
    }
};

// Must have function name between start and first paren with no whitespace, because I'm too
// lazy to write each function name twice and put it in a map.
const builtins = [_][]const u8{
    \\      "string": (ptr, len) => {
    \\        return this.new_handle(this._decoder.decode(new Uint8Array(this.instance.exports.memory.buffer, ptr, len)));
    \\      },
    ,
    \\      "release": (id) => {
    \\        this._handles.delete(id);
    \\      },
    ,
    \\      "dataview": (ptr, len) => {
    \\        return this.new_handle(new DataView(this.instance.exports.memory.buffer,ptr, len));
    \\      },
    ,
    \\      "throw": (id) => {
    \\        throw this._handles.get(id);
    \\      },
    ,
    \\      "throwAndRelease": (id) => {
    \\        var message = this._handles.get(id);
    \\        this._handles.delete(id);
    \\        throw message;
    \\      },
    ,
    \\      "equal": (a, b) => {
    \\        return this._handles.get(a) === this._handles.get(b);
    \\      },
    ,

    \\      "i8ArrayView": (ptr, len) => {
    \\        return this.new_handle(new Int8Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "u8ArrayView": (ptr, len) => {
    \\        return this.new_handle(new Uint8Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "u8ClampedArrayView": (ptr, len) => {
    \\        return this.new_handle(new Uint8ClampedArray(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "i16ArrayView": (ptr, len) => {
    \\        return this.new_handle(new Int16Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "u16ArrayView": (ptr, len) => {
    \\        return this.new_handle(new Uint16Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "i32ArrayView": (ptr, len) => {
    \\        return this.new_handle(new Int32Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "u32ArrayView": (ptr, len) => {
    \\        return this.new_handle(new Uint32Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "i64ArrayView": (ptr, len) => {
    \\        return this.new_handle(new BigInt64Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "u64ArrayView": (ptr, len) => {
    \\        return this.new_handle(new BigUint64Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "f32ArrayView": (ptr, len) => {
    \\        return this.new_handle(new Float32Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
    \\      "f64ArrayView": (ptr, len) => {
    \\        return this.new_handle(new Float64Array(this.instance.exports.memory.buffer, ptr, len));
    \\      },
    ,
};
