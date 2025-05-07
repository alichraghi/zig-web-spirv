const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sc, const sc_translate = buildSpirvCross(b, target, optimize);
    b.installArtifact(sc);

    const shader_target = b.resolveTargetQuery(try std.Build.parseTargetQuery(.{
        .arch_os_abi = "spirv-vulkan",
        .cpu_features = "generic+v1_5+shader",
        .object_format = "spirv",
    }));

    const vert = b.addObject(.{
        .name = "vert",
        .root_source_file = b.path("src/vert.zig"),
        .target = shader_target,
        .optimize = optimize,
        .use_llvm = false,
    });
    {
        const install = b.addInstallBinFile(vert.getEmittedBin(), "vert.spv");
        b.getInstallStep().dependOn(&install.step);
    }

    const frag = b.addObject(.{
        .name = "frag",
        .root_source_file = b.path("src/frag.zig"),
        .target = shader_target,
        .optimize = optimize,
        .use_llvm = false,
    });
    {
        const install = b.addInstallBinFile(frag.getEmittedBin(), "frag.spv");
        b.getInstallStep().dependOn(&install.step);
    }

    const s2g = b.addExecutable(.{
        .name = "s2g",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    s2g.root_module.addImport("sc", sc_translate);
    s2g.linkLibrary(sc);
    b.installArtifact(s2g);
    b.installFile("www/index.html", "index.html");

    {
        const run_cmd = b.addRunArtifact(s2g);
        run_cmd.addFileArg(vert.getEmittedBin());
        const output = run_cmd.addOutputFileArg("vert.glsl");
        const install = b.addInstallBinFile(output, "vert.glsl");
        b.getInstallStep().dependOn(&install.step);
    }
    {
        const run_cmd = b.addRunArtifact(s2g);
        run_cmd.addFileArg(frag.getEmittedBin());
        const output = run_cmd.addOutputFileArg("frag.glsl");
        const install = b.addInstallBinFile(output, "frag.glsl");
        b.getInstallStep().dependOn(&install.step);
    }
}

fn buildSpirvCross(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) struct { *std.Build.Step.Compile, *std.Build.Module } {
    const sc = b.dependency("spirv_cross", .{});

    const lib = b.addStaticLibrary(.{
        .name = "spirv_cross",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.linkLibCpp();

    // if (target.result.os.tag.isDarwin()) {
    //     const apple_sdk = @import("apple_sdk");
    //     try apple_sdk.addPaths(b, lib.root_module);
    // }

    lib.addCSourceFiles(.{
        .root = sc.path(""),
        .files = &.{
            "spirv_cross.cpp",
            "spirv_parser.cpp",
            "spirv_cross_parsed_ir.cpp",
            "spirv_cfg.cpp",

            "spirv_cross_c.cpp",
            "spirv_glsl.cpp",
        },

        .flags = &.{"-DSPIRV_CROSS_C_API_GLSL=1"},
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = sc.path("spirv_cross_c.h"),
        .target = target,
        .optimize = optimize,
    });

    return .{ lib, translate_c.createModule() };
}
