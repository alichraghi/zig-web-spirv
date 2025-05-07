const std = @import("std");
const sc = @import("sc");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var context: sc.spvc_context = undefined;
    if (sc.spvc_context_create(&context) != sc.SPVC_SUCCESS) return error.Failed;
    defer sc.spvc_context_destroy(context);

    sc.spvc_context_set_error_callback(context, @ptrCast(&struct {
        fn callback(_: ?*anyopaque, msg_ptr: [*c]const u8) callconv(.C) void {
            const msg = std.mem.sliceTo(msg_ptr, 0);
            std.log.warn("spirv-cross error message={s}", .{msg});
        }
    }.callback), null);

    const spv = try std.fs.cwd().readFileAllocOptions(
        allocator,
        args[1],
        10 * 1024 * 1024,
        null,
        .@"4",
        null,
    );
    defer allocator.free(spv);

    var ir: sc.spvc_parsed_ir = undefined;
    if (sc.spvc_context_parse_spirv(
        context,
        @ptrCast(@alignCast(spv.ptr)),
        spv.len / 4,
        &ir,
    ) != sc.SPVC_SUCCESS) return error.Failed;

    var compiler: sc.spvc_compiler = undefined;
    if (sc.spvc_context_create_compiler(
        context,
        sc.SPVC_BACKEND_GLSL,
        ir,
        sc.SPVC_CAPTURE_MODE_TAKE_OWNERSHIP,
        &compiler,
    ) != sc.SPVC_SUCCESS) return error.Failed;

    var options: sc.spvc_compiler_options = undefined;
    _ = sc.spvc_compiler_create_compiler_options(compiler, &options);
    _ = sc.spvc_compiler_options_set_uint(options, sc.SPVC_COMPILER_OPTION_GLSL_ES, sc.SPVC_TRUE);
    _ = sc.spvc_compiler_options_set_uint(options, sc.SPVC_COMPILER_OPTION_GLSL_VERSION, 200);
    _ = sc.spvc_compiler_install_compiler_options(compiler, options);

    var result: [*:0]const u8 = undefined;
    if (sc.spvc_compiler_compile(
        compiler,
        @ptrCast(&result),
    ) != sc.SPVC_SUCCESS) return error.Failed;

    const output_file = try std.fs.createFileAbsolute(args[2], .{});
    defer output_file.close();
    try output_file.writeAll(std.mem.span(result));
}
