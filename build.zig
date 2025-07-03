const std = @import("std");
const LazyPath = std.build.LazyPath;

const go_src_dir = "libs/gocv/";
const zig_src_dir = "src/";
const c_build_options: []const []const u8 = &.{
    "-Wall",
    "-Wextra",
    "-std=c++11",
};

var ensure_submodule: bool = false;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    ensureSubmodulesExist(b);

    const zigcv_lib = b.addStaticLibrary(.{
        .name = "zigcv",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = mode,
    });

    const opencv_lib = buildOpenCVLib(b, target, mode);
    zigcv_lib.linkLibrary(opencv_lib);
    linkToOpenCV(zigcv_lib);

    b.installArtifact(zigcv_lib);

    const zigcv_module = b.addModule("zigcv", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = mode,
    });

    zigcv_module.addIncludePath(b.path(go_src_dir));
    zigcv_module.addIncludePath(b.path(zig_src_dir));

    zigcv_module.linkLibrary(opencv_lib);
    linkSystemLibrariesToModule(zigcv_module);

    const examples = [_]Program{
        .{
            .name = "hello",
            .path = "examples/hello/main.zig",
            .desc = "Show Webcam",
        },
        .{
            .name = "version",
            .path = "examples/version/main.zig",
            .desc = "Print OpenCV Version",
        },
        .{
            .name = "show_image",
            .path = "examples/showimage/main.zig",
            .desc = "Show Image Demo",
        },
        .{
            .name = "face_detection",
            .path = "examples/facedetect/main.zig",
            .desc = "Face Detection Demo",
        },
        .{
            .name = "face_blur",
            .path = "examples/faceblur/main.zig",
            .desc = "Face Detection and Blur Demo",
        },
        .{
            .name = "dnn_detection",
            .path = "examples/dnndetection/main.zig",
            .desc = "DNN Detection Demo",
        },
        .{
            .name = "saveimage",
            .path = "examples/saveimage/main.zig",
            .desc = "Save Image Demo",
        },
        .{
            .name = "detail_enhance",
            .path = "examples/detail_enhance/main.zig",
            .desc = "Detail Enhanced Image Demo",
        },
    };

    const examples_step = b.step("examples", "Builds all the examples");

    for (examples) |ex| {
        const exe = b.addExecutable(.{
            .name = ex.name,
            .root_source_file = b.path(ex.path),
            .target = target,
            .optimize = mode,
        });
        const exe_step = &exe.step;

        b.installArtifact(exe);

        linkZigCV(b, exe);
        addZigCVAsPackage(exe, "zigcv");

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step(ex.name, ex.desc);
        const artifact_step = &b.addInstallArtifact(exe, .{}).step;
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_step.dependOn(artifact_step);
        run_step.dependOn(&run_cmd.step);
        examples_step.dependOn(exe_step);
        examples_step.dependOn(artifact_step);
    }

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter") orelse null;
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = mode,
        .filter = test_filter,
    });
    linkZigCV(b, unit_tests);
    addZigCVAsPackage(unit_tests, "zigcv");

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

const Program = struct {
    name: []const u8,
    path: []const u8,
    desc: []const u8,
    fstage1: bool = false,
};

fn addZigCVAsPackage(exe: *std.Build.Step.Compile, name: []const u8) void {
    const owner = exe.step.owner;
    const module = owner.createModule(.{
        .root_source_file = owner.path("src/root.zig"),
        .imports = &.{},
    });

    module.addIncludePath(owner.path(go_src_dir));
    module.addIncludePath(owner.path(zig_src_dir));

    exe.root_module.addImport(name, module);
}

fn linkZigCV(b: *std.Build, exe: *std.Build.Step.Compile) void {
    ensureSubmodules(exe);

    const target = exe.root_module.resolved_target.?;
    const mode = exe.root_module.optimize.?;

    const opencv_lib = buildOpenCVLib(b, target, mode);
    exe.linkLibrary(opencv_lib);
    linkToOpenCV(exe);
}

fn buildOpenCVLib(b: *std.Build, target: std.Build.ResolvedTarget, mode: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const target_os = target.result.os.tag;

    if (target_os == .linux) {
        return buildOpenCVLibLinux(b, target, mode);
    }

    const go_src_files = .{
        "asyncarray.cpp",
        "calib3d.cpp",
        "core.cpp",
        "dnn.cpp",
        "features2d.cpp",
        "highgui.cpp",
        "imgcodecs.cpp",
        "imgproc.cpp",
        "objdetect.cpp",
        "photo.cpp",
        "svd.cpp",
        "version.cpp",
        "video.cpp",
        "videoio.cpp",
    };

    const cv = b.addStaticLibrary(.{
        .name = "opencv",
        .target = target,
        .optimize = mode,
    });

    var build_flags = std.ArrayList([]const u8).init(b.allocator);
    defer build_flags.deinit();

    for (c_build_options) |flag| {
        build_flags.append(flag) catch unreachable;
    }

    inline for (go_src_files) |file| {
        const c_file_path = b.pathJoin(&.{ go_src_dir, file });
        cv.addCSourceFile(.{
            .file = b.path(c_file_path),
            .flags = build_flags.items,
        });
    }

    linkToOpenCV(cv);
    return cv;
}

fn buildOpenCVLibLinux(b: *std.Build, target: std.Build.ResolvedTarget, mode: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const cv = b.addStaticLibrary(.{
        .name = "opencv",
        .target = target,
        .optimize = mode,
    });

    const pkg_result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "pkg-config", "--cflags", "--libs", "opencv4" },
    }) catch |err| {
        std.log.err("pkg-config failed: {}. Please install opencv4 development packages.", .{err});
        std.process.exit(1);
    };

    if (pkg_result.term.Exited != 0) {
        std.log.err("pkg-config opencv4 failed. Please install opencv4 development packages.", .{});
        std.process.exit(1);
    }

    const go_src_files = [_][]const u8{
        "asyncarray.cpp",
        "calib3d.cpp",
        "core.cpp",
        "dnn.cpp",
        "features2d.cpp",
        "highgui.cpp",
        "imgcodecs.cpp",
        "imgproc.cpp",
        "objdetect.cpp",
        "photo.cpp",
        "svd.cpp",
        "version.cpp",
        "video.cpp",
        "videoio.cpp",
    };

    // Create build directory
    const build_dir = b.pathJoin(&.{ b.cache_root.path.?, "opencv_objs" });
    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", build_dir });

    for (go_src_files) |src_file| {
        const obj_name = b.fmt("{s}.o", .{src_file[0 .. src_file.len - 4]});
        const obj_path = b.pathJoin(&.{ build_dir, obj_name });
        const src_path = b.pathJoin(&.{ go_src_dir, src_file });

        const compile_cmd = b.addSystemCommand(&.{
            "g++", "-c", "-fPIC", "-O2", "-std=c++17", "-I/usr/include/opencv4",
        });

        compile_cmd.addArg(b.fmt("-I{s}", .{go_src_dir}));
        compile_cmd.addFileArg(b.path(src_path));
        compile_cmd.addArg("-o");
        compile_cmd.addArg(obj_path);
        compile_cmd.step.dependOn(&mkdir_cmd.step);

        cv.addObjectFile(.{ .cwd_relative = obj_path });
        cv.step.dependOn(&compile_cmd.step);
    }

    linkToOpenCV(cv);
    return cv;
}

fn linkToOpenCV(exe: *std.Build.Step.Compile) void {
    const target_os = exe.root_module.resolved_target.?.result.os.tag;

    exe.addIncludePath(exe.step.owner.path(go_src_dir));
    exe.addIncludePath(exe.step.owner.path(zig_src_dir));
    switch (target_os) {
        .windows => {
            exe.addIncludePath(exe.step.owner.path("c:/msys64/mingw64/include"));
            exe.addIncludePath(exe.step.owner.path("c:/msys64/mingw64/include/c++/12.2.0"));
            exe.addIncludePath(exe.step.owner.path("c:/msys64/mingw64/include/c++/12.2.0/x86_64-w64-mingw32"));
            exe.addLibraryPath(exe.step.owner.path("c:/msys64/mingw64/lib"));
            exe.addIncludePath(exe.step.owner.path("c:/opencv/build/install/include"));
            exe.addLibraryPath(exe.step.owner.path("c:/opencv/build/install/x64/mingw/staticlib"));

            exe.linkSystemLibrary("opencv4");
            exe.linkSystemLibrary("stdc++.dll");
            exe.linkSystemLibrary("unwind");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("c");
        },
        .linux => {
            exe.addIncludePath(.{ .cwd_relative = "/usr/include/opencv4" });
            exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });

            exe.linkSystemLibrary("opencv_core");
            exe.linkSystemLibrary("opencv_imgproc");
            exe.linkSystemLibrary("opencv_imgcodecs");
            exe.linkSystemLibrary("opencv_highgui");
            exe.linkSystemLibrary("opencv_features2d");
            exe.linkSystemLibrary("opencv_calib3d");
            exe.linkSystemLibrary("opencv_objdetect");
            exe.linkSystemLibrary("opencv_dnn");
            exe.linkSystemLibrary("opencv_ml");
            exe.linkSystemLibrary("opencv_flann");
            exe.linkSystemLibrary("opencv_photo");
            exe.linkSystemLibrary("opencv_video");
            exe.linkSystemLibrary("opencv_videoio");

            exe.addObjectFile(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/libstdc++.so.6" });
            exe.linkSystemLibrary("unwind");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("c");
        },
        else => {
            exe.linkSystemLibrary("opencv4");
            exe.linkSystemLibrary("stdc++");
            exe.linkSystemLibrary("unwind");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("c");
        },
    }
}

fn linkSystemLibrariesToModule(module: *std.Build.Module) void {
    const target_os = module.resolved_target.?.result.os.tag;

    switch (target_os) {
        .windows => {
            module.linkSystemLibrary("opencv4", .{});
            module.linkSystemLibrary("stdc++.dll", .{});
            module.linkSystemLibrary("unwind", .{});
            module.linkSystemLibrary("m", .{});
            module.linkSystemLibrary("c", .{});
        },
        .linux => {
            const opencv_libs = [_][]const u8{ "opencv_core", "opencv_imgproc", "opencv_imgcodecs", "opencv_highgui", "opencv_features2d", "opencv_calib3d", "opencv_objdetect", "opencv_dnn", "opencv_ml", "opencv_flann", "opencv_photo", "opencv_video", "opencv_videoio" };

            for (opencv_libs) |lib| {
                module.linkSystemLibrary(lib, .{});
            }

            module.linkSystemLibrary("stdc++", .{});
            module.linkSystemLibrary("unwind", .{});
            module.linkSystemLibrary("m", .{});
            module.linkSystemLibrary("c", .{});
        },
        else => {
            module.linkSystemLibrary("opencv4", .{});
            module.linkSystemLibrary("stdc++", .{});
            module.linkSystemLibrary("unwind", .{});
            module.linkSystemLibrary("m", .{});
            module.linkSystemLibrary("c", .{});
        },
    }
}

fn ensureSubmodulesExist(b: *std.Build) void {
    const submodule_check_file = "libs/gocv/version.cpp";

    if (std.fs.cwd().access(submodule_check_file, .{})) |_| {
        return;
    } else |_| {
        std.log.info("Initializing git submodules...", .{});

        const result = std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{ "git", "submodule", "update", "--init", "--recursive" },
        }) catch |err| {
            std.log.err("Failed to run git submodule command: {}", .{err});
            std.process.exit(1);
        };

        if (result.term.Exited != 0) {
            std.log.err("Git submodule command failed with exit code: {}", .{result.term.Exited});
            std.log.err("stdout: {s}", .{result.stdout});
            std.log.err("stderr: {s}", .{result.stderr});
            std.process.exit(1);
        }

        std.log.info("Git submodules initialized successfully", .{});
    }
}

fn ensureSubmodules(exe: *std.Build.Step.Compile) void {
    const b = exe.step.owner;
    if (!ensure_submodule) {
        const git_submodule_cmd = b.addSystemCommand(&.{ "git", "submodule", "update", "--init", "--recursive" });
        exe.step.dependOn(&git_submodule_cmd.step);
        ensure_submodule = true;
    }
}

pub const contrib = struct {
    pub fn addAsPackage(exe: *std.Build.Step.Compile) void {
        addAsPackageWithCustomName(exe, "zigcv_contrib");
    }

    pub fn addAsPackageWithCustomName(exe: *std.Build.Step.Compile, name: []const u8) void {
        const owner = exe.step.owner;
        const module = owner.createModule(.{
            .root_source_file = owner.path("src/contrib/main.zig"),
            .imports = &.{},
        });
        exe.root_module.addImport(name, module);
    }

    pub fn link(b: *std.Build, exe: *std.Build.Step.Compile) void {
        ensureSubmodules(exe);

        const target = exe.root_module.resolved_target.?;
        const optimize = exe.root_module.optimize.?;

        const contrib_dir = b.pathJoin(&.{ go_src_dir, "contrib/" });
        const contrib_files = .{
            "aruco.cpp",
            "bgsegm.cpp",
            "face.cpp",
            "img_hash.cpp",
            "tracking.cpp",
            "wechat_qrcode.cpp",
            "xfeatures2d.cpp",
            "ximgproc.cpp",
            "xphoto.cpp",
        };

        const cv_contrib = b.addStaticLibrary(.{
            .name = "opencv_contrib",
            .target = target,
            .optimize = optimize,
        });
        cv_contrib.force_pic = true;
        for (contrib_files) |file| {
            const c_path = b.pathJoin(&.{ contrib_dir, file });
            cv_contrib.addCSourceFile(.{
                .file = b.path(c_path),
                .flags = c_build_options,
            });
        }
        cv_contrib.addIncludePath(b.path(contrib_dir));
        linkToOpenCV(cv_contrib);

        exe.linkLibrary(cv_contrib);
        linkToOpenCV(exe);
    }
};

pub const cuda = struct {
    pub fn addAsPackage(exe: *std.Build.Step.Compile) void {
        addAsPackageWithCustomName(exe, "zigcv_cuda");
    }

    pub fn addAsPackageWithCustomName(exe: *std.Build.Step.Compile, name: []const u8) void {
        const owner = exe.step.owner;
        const module = owner.createModule(.{
            .root_source_file = owner.path("src/cuda/main.zig"),
            .imports = &.{},
        });
        exe.root_module.addImport(name, module);
    }

    pub fn link(b: *std.Build, exe: *std.Build.Step.Compile) void {
        ensureSubmodules(exe);

        const target = exe.root_module.resolved_target.?;
        const optimize = exe.root_module.optimize.?;

        const cuda_dir = b.pathJoin(&.{ go_src_dir, "cuda/" });
        const cuda_files = .{
            "arithm.cpp",
            "bgsegm.cpp",
            "core.cpp",
            "cuda.cpp",
            "filters.cpp",
            "imgproc.cpp",
            "objdetect.cpp",
            "optflow.cpp",
            "warping.cpp",
        };

        const cv_cuda = b.addStaticLibrary(.{
            .name = "opencv_cuda",
            .target = target,
            .optimize = optimize,
        });
        cv_cuda.force_pic = true;
        for (cuda_files) |file| {
            const c_path = b.pathJoin(&.{ cuda_dir, file });
            cv_cuda.addCSourceFile(.{
                .file = b.path(c_path),
                .flags = c_build_options,
            });
        }
        cv_cuda.addIncludePath(b.path(go_src_dir));
        linkToOpenCV(cv_cuda);

        exe.linkLibrary(cv_cuda);
        linkToOpenCV(exe);
    }
};
