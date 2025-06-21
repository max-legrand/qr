const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{
        .name = "qr",
        .root_source_file = b.path("main-cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const lib_mod = b.addModule("qr", .{
        .root_source_file = b.path("src/index.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "qr",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const wasm = b.addExecutable(.{
        .name = "qr",
        .root_source_file = b.path("main-wasm.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    const wasmInstall = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .prefix },
    });

    const wasmStep = b.step("wasm", "Build wasm module");
    wasmStep.dependOn(&wasmInstall.step);
}
