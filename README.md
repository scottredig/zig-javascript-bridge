# zig-javascript-bridge

This library creates bindings for accessing Javascript from within a WASM runtime.  For example:

```zig
const zjb = @import("zjb");

export fn main() void {
    zjb.global("console").call("log", .{zjb.constString("Hello from Zig")}, void);
}

```

Is equivalent to this Javascript:
```javascript
console.log("Hello from Zig");
```

## Projet Status

ZJB is fully functional and is ready to be used in other projects.  However 1.0 will not be tagged until there is significant enough usage that confidence in the API not needing further changes is high.  There's currently no release schedule for point releases, so your `build.zig.zon` file should reference `https://github.com/scottredig/zig-javascript-bridge/archive/<HASH OF COMMIT MAIN IS ON>.zip`.

## Why

Calling Javascript functions from Zig is a pain.  WASM has restrictions on the function API surface, and how references to the runtime environment (Javascript) can be stored.  So to access Javascript functionality from Zig, you must create: a function in Zig which is friendly to call, a function export, and a function in Javascript which translates into the call you actually want.

This isn't too bad so far, but the Javascript API surface is large, has a lot of variadic functions, and accepts many types.  The result is that your programming loop of just wanting to write code slows down writing a large amount of ill fitting boilerplate whenever you must cross the Zig to Javascript boundary.

This package is clearly inspired by Go's solution to this problem: https://pkg.go.dev/syscall/js  However, there are a few significant deviations to note if you're familiar with that library:

1. Every call from Go's package involves string decoding, garbage creation, and reflection calls.
2. Go has a one size fits all Javascript file, while zjb uses a generator to produce Javascript for the calls you use.
3. Go's garbage collection and finalizers allows for automatically cleaning up references from Go to Javascript, while zjb requires manual Handle releasing.
4. Zig has no runtime, so there's none of Go's weirdness about blocking on the main thread.

## Usage

As of May 2024, zjb requires Zig 0.12.0 or greater.

Call into Javascript using `zjb`, generate the Javascript side code, and then build an html page to combine them.

An end to end example is in the example folder.  It includes:

- `main.zig` has usage examples for the `zjb` Zig import.
- `build.zig`'s example for how to set up your build file.
- `example/static` includes HTML and Javascript files to run the example.

To view the example in action, run `zig build example`.  Then host a webserver from `zig-out/bin`.

Zjb functions which return a value from Javascript require specifying which type is returned.  As arguments or return types to be passed into Javascript, zjb supports:

- `i32`, `i64`, `f32`, `f64`.  These are the only numerical types that are supported by the WebAssembly JavaScript Interface, so you must cast to one of these before passing.
- `comptime_int`, `comptime_float`.  These are valid as arguments, and are passed as f64 to Javascript, which is Javascript's main number type.
- `zjb.Handle`.  The Zig side type for referring to Javascript values.  Most of the time this will be a Javascript object of some kind, but in some rare cases it might be something else, such as null, a Number, NaN, or undefined.  Used as an argument, it is automatically converted into the value that is held in zjb's Javascript `_handles` map.  When used as a return value, it is automatically added to zjb's Javascript `_handles` map.  It is the caller's responsibility to call `release` to remove it from the `_handles` map when you're done using it.
- `zjb.ConstHandle` as arguments but not return types.  These values are returned by `zjb.constString`, `zjb.global`, and `zjb.fnHandle`.  `zjb.ConstHandle` works similarly to `zjb.Handle`, with a few notable exceptions: 1. Values are memoized upon first use on the Zig side, so they can be used any number of times without churning garbage.  2. There is no `release` function.  These values are intended to be around for the lifetime of your program, with reduced friction of using them.  As the functions which produce ConstHandle values all take only comptime arguments, these cannot balloon uncontrolably at runtime.  Some values are always defined as handles, `zjb.ConstHandle.null` is Javascript's `null`, `zjb.ConstHandle.global` is the global scope, and `zjb.ConstHandle.empty_string` is a Javascript empty string.
- `void` is a valid type for method calls which have no return value.

Zjb supports multiple ways to expose Zig functions to Javascript:
- `zjb.exportFn` exposes the function with the passed name to Javascript.  This supports `zjb.Handle`, so if you pass an object from a Javascript function, a handle will automaticlaly be created and passed into Zig.  It is the responsibility of the Zig function being called to call `release` on any handles in its arguments at the appropriate time to avoid memory leaks.
- `zjb.fnHandle` uses `zjb.exportFn` and additionally returns a `zjb.ConstHandle` to that function.  This can be used as a callback argument in Javascript functions.
- Zig's `export` keyword on functions works as it always does in WASM, but doesn't support `zjb.Handle` correctly.

A few extra notes:

`zjb.string([]const u8)` decodes the slice of memory as a utf-8 string, returning a Handle.  The string will NOT update to reflect changes in the slice in Zig.

`zjb.global` will be set to the value of that global variable the first time it is called.  As it is intended to be used for Javascript objects or classes defined in the global scope, that usage will be safe.  For example, `console`, `document` or `Map`.  If you use it to retrieve a value or object you've defined in Javascript, ensure it's defined before your program runs and doesn't change.

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
    this.exports = {
    };
    this._export_reverse_handles = {};
    this._handles = new Map();
    this._handles.set(0, null);
    this._handles.set(1, window);
    this._handles.set(2, "");
    this._handles.set(3, this.exports);
    this._next_handle = 4;
  }
};

```
