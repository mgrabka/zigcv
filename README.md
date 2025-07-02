# ZIGCV

[![ci](https://github.com/ryoppippi/zigcv/actions/workflows/ci.yml/badge.svg)](https://github.com/ryoppippi/zigcv/actions/workflows/ci.yml)

<div align="center">
  <img src="./logo/zigcv.png" width="50%" />
</div>

The ZIGCV library provides Zig language bindings for the [OpenCV 4](http://opencv.org/) computer vision library.

The ZIGCV library works on Zig 0.14.0 and OpenCV (v4.11.0) on Linux, macOS, and Windows.

## Caution

Still under development, so the zig APIs will be dynamically changed.

You can use `const c_api = @import("zigcv").c_api;` to call c bindings directly.
This C-API is currently fixed.

## Install

```sh
zig fetch --save "git+https://github.com/ryoppippi/zigcv"
```

```zig
const zigcv_dep = b.dependency("zigcv", .{});
exe.root_module.addImport("zigcv", zigcv_dep.module("zigcv"))
```

[See documentation](https://ziglang.org/learn/build-system/) for more information about the Zig Build System.


## Examples

```sh
zig build examples
./zig-out/bin/face_detection 0
```

You can also use devbox:

```sh
devbox run build examples
./zig-out/bin/face_detection 0
```

<div align="center">
  <img width="400" alt="face detection" src="https://user-images.githubusercontent.com/1560508/188515175-4d344660-5680-43e7-9b74-3bad92507430.gif">
</div>

You can see the full example list by `zig build --help`.

## Technical restrictions

Due to zig being a relatively new language it does [not have full C ABI support](https://github.com/ziglang/zig/issues/1481) at the moment.
For use that mainly means we can't use any functions that return structs that are less than 16 bytes large on x86, and passing structs to any functions may cause memory error on arm.

## Sponsors

<p align="center">
	<a href="https://github.com/sponsors/ryoppippi">
		<img src="https://cdn.jsdelivr.net/gh/ryoppippi/sponsors/sponsors.svg">
	</a>
</p>

## License

MIT

## Author

Ryotaro "Justin" Kimura (a.k.a. ryoppippi)
