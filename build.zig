const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "riregi-data",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const AndroidBuild = struct {
        sub_path: []const u8,
        target: std.zig.CrossTarget,
    };

    const android_os = .linux;
    const android_abi = .android;
    const android_builds = [_]AndroidBuild{
        AndroidBuild{
            .sub_path = "arm64-v8a/libriregi-data.so",
            .target = std.zig.CrossTarget{
                .cpu_arch = .aarch64,
                .os_tag = android_os,
                .abi = android_abi,
                .cpu_model = .baseline,
                .cpu_features_add = std.Target.aarch64.featureSet(&.{.v8a}),
            },
        },

        AndroidBuild{
            .sub_path = "armeabi-v7a/libriregi-data.so",
            .target = std.zig.CrossTarget{
                .cpu_arch = .arm,
                .os_tag = android_os,
                .abi = android_abi,
                .cpu_model = .baseline,
                .cpu_features_add = std.Target.arm.featureSet(&.{.v7a}),
            },
        },

        // AndroidBuild{
        //     .sub_path = "x86/libriregi-data.so",
        //     .target = std.zig.CrossTarget{
        //         .cpu_arch = .x86,
        //         .os_tag = android_os,
        //         .abi = android_abi,
        //         .cpu_model = .baseline,
        //     },
        // },

        AndroidBuild{
            .sub_path = "x86_64/libriregi-data.so",
            .target = std.zig.CrossTarget{
                .cpu_arch = .x86_64,
                .os_tag = android_os,
                .abi = android_abi,
                .cpu_model = .baseline,
            },
        },
    };

    for (android_builds) |a| {
        const android_lib = b.addSharedLibrary(.{
            .name = "riregi-data",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = a.target,
            .optimize = .ReleaseSafe,
            .link_libc = false,
        });
        android_lib.link_gc_sections = true;
        android_lib.link_emit_relocs = false;
        android_lib.link_eh_frame_hdr = false;
        android_lib.force_pic = true;
        android_lib.link_function_sections = false;
        android_lib.bundle_compiler_rt = true;
        android_lib.strip = (optimize == .ReleaseSmall);
        android_lib.export_table = true;
        android_lib.addCSourceFile(.{
            .file = .{ .path = "src/stub.c" },
            .flags = &[_][]const u8{
                "-fno-sanitize=undefined",
            },
        });

        const install = b.addInstallArtifact(android_lib, .{
            .dest_sub_path = a.sub_path,
        });
        b.getInstallStep().dependOn(&install.step);
    }

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
