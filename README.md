# zig-javascript-bridge

This library creates bindings for accessing Javascript from within a WASM runtime.  For example:

```zig
// Example for readme
const zjb = @import("zjb");

export fn main() void {
    zjb.global("console").call("log", .{zjb.constString("Hello from Zig")}, void);
}

```

Is equivalent to this Javascript:
```javascript
console.log("Hello from Zig");
```

## Why

Calling Javascript functions from Zig is a pain.  WASM has restrictions on the function API surface, and how references to the runtime environment (Javascript) can be stored.  So to access Javascript functionality from Zig, you must create: a function in Zig which is friendly to call, a function export, and a function in Javascript which translates into the call you actually want.

This isn't too bad so far, but the Javascript API surface is large, has a lot of variadic functions, and accepts many types.  The result is that your programming loop of just wanting to write code slows down writing a large amount of ill fitting boilerplate whenever you must cross the Zig to Javascript boundary.

This package is clearly inspired by Go's solution to this problem: https://pkg.go.dev/syscall/js  However, there are a few significant deviations to note if you're familiar with that library:

1. Every call from Go's package involves string decoding, garbage creation, and reflection calls.
2. Go has a one size fits all Javascript file, while zjb uses a generator to produce Javascript for the calls you use.
3. Go's garbage collection and finalizers allows for automatically cleaning up references from Go to Javascript, while zjb requires manual Handle releasing.
4. Zig has no runtime, so there's none of Go's weirdness about blocking on the main thread.

## Usage

As of March 2024, zjb requires Zig's master version, not 0.11.

Call into Javascript using `zjb`, generate the Javascript side code, and then build an html page to combine them.

An end to end example is in the example folder.  It includes:

- `main.zig` has usage examples for the `zjb` Zig import.
- `build.zig`'s example for how to set up your build file.
- `example/static` includes an HTML and a Javascript to run the example.

To view the example in action, run `zig build example`.  Then host a webserver from `zig-out/bin`.

Zjb functions which return a value from Javascript require specifying which type is returned.  As arguments or return types to be passed into Javascript, zjb supports:

- `i32`, `i64`, `f32`, `f64`.  These are the only numerical types that are supported by the WASM runtime export function signature, so you must cast to one of these before passing.
- `comptime_int`, `comptime_float`.  These are valid as arguments, and are passed as f64 to Javascript, which is Javascript's main number type.
- `zjb.Handle`.  The Zig side type for referring to Javascript values.  Most of the time this will be a Javascript object of some kind, but in some rare cases it might be something else, such as null, a Number, NaN, or undefined.  Used as an argument, it is automatically converted into the value that is held in zjb's Javascript `_handles` map.  When used as a return value, it is automatically added to zjb's Javascript `_handles` map.  It is the caller's responsibility to call `release` to remove it from the `_handles` map when you're done using it.
- `void` is a valid type for method calls which have no return value.

A few extra notes:

`zjb.string([]const u8)` decodes the slice of memory as a utf-8 string, returning a Handle.  The string will NOT update to reflect changes in the slice in Zig.

The \_ArrayView functions (`i8ArrayView`, `u8ArrayView`, etc) create the respective JavaScript typed array backed by the same memory as the Zig WASM instance.

`dataView` is similar in functionality to the ArrayView functions, but returns a DataView object.  Accepts any pointer or slice.

> [!CAUTION]
> There are three important notes about using the \_ArrayView and dataView functions:
>
> The \_ArrayView and dataView functions will accept const values.  If you pass one (such as []const u8), you are exposing Zig's memory to Javascript.  Changing the values from Javascript may lead to undefined behavior.  Zjb allows this as there are plenty of use cases which only read the data, and requiring non-const values throughout your program if they are eventually passed to Javascript isn't a desirable API.  It's up to you to be safe here.
>
> Changes to the values in either Zig or Javascript will be visible in the other.  HOWEVER, if the wasm memory grows for whatever reason (either through a direct @wasmMemoryGrow call or through allocators), all \_ArrayViews and DataViews are invalided, and their length will be zero.  You have (roughly speaking) three choices to handle this:
> 1. Always create just before using, and release immediately after use.
> 1. Never allocate after using these functions.
> 1. Check their length before any use, if it does not match the intended length, release and recreate the Handle.
>
> Javascripts's DataView allows pulling out arbitrary values from offsets.  This may be useful for working with Zig structs from Javascript, however remember that Zig may reorder the fields for structs.  Use `extern struct` to be safe here.

## How

To solve the general problem of referencing Javascript objects from Zig, an object on the Javascript side with integer indices is used.  When passing to Javascript, the object is added to the map with a unique ID, and that ID is passed to Zig.  When calling from Zig, Javascript will translate the ID into the object stored on the map before calling the intended function.  To avoid building up garbage endlessly inside the object map, zjb code must call release to delete the reference from the map.

zjb works with two steps:

1. Your Zig code calls zjb functions.  Many functions use comptime to create export functions with specialized export signatures.  Only methods which are actually used are in the final WASM file.
2. Run an extract methods program on the WASM file, producing a Javascript file to use along with your WASM file.  The example above produces this export, for example:

```javascript
const Zjb = class {
  new_handle(value) {
    if (value === null) {
      return 0;
    }
    const result = this._next_handle;
    this._handles.set(result, value);
    this._next_handle++;
    return result;
  }
  constructor() {
    this._decoder = new TextDecoder();
    this._handles = new Map();
    this._handles.set(0, null);
    this._handles.set(1, window);
    this._handles.set(2, "");
    this._next_handle = 3;
    this.imports = {
      "call_o_v_log": (arg0, id) => {
        this._handles.get(id).log(this._handles.get(arg0));
      },
      "get_o_console": (id) => {
        return this.new_handle(this._handles.get(id).console);
      },
      "string": (ptr, len) => {
        return this.new_handle(this._decoder.decode(new Uint8Array(this.instance.exports.memory.buffer, ptr, len)));
      },
    };
  }
};

```

## Todo/Wishlist

Things that this doesn't have yet, but would be nice:

- Exposing a function that has Handles in arguments, automatically handling everything.  Ability to pass in one of those functions as a callback into calls from Zig side.  Eg, being able to do setTimeout, or handle async networking tasks entirely from Zig.
- Tests (need to run from a js environment somehow).
- Better error handling.  (Both handling javascript exceptions as returned errors, but also properly printing panic's error messages).
- Other random javascript stuff like instanceof, or converting a handle to a number  (typically not needed, but might be if you don't know what type something is until after you've got the handle).
- It may be useful to add a method to copy strings from Javascript to Zig.