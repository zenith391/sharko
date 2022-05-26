// 'Sharko' IDE
const std = @import("std");
const zgt = @import("zgt");

const FlatText = @import("text.zig").FlatText;
const TextBuffer = @import("buffer.zig").TextBuffer;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const zgtAllocator = gpa.allocator();

var buffer: TextBuffer = undefined;
const filePath: [:0]const u8 = "src/text.zig";

pub fn onSave(button: *zgt.Button_Impl) !void {
    _ = button;
    std.log.info("Saving to {s}", .{filePath});

    const file = try std.fs.cwd().createFile(filePath, .{});
    defer file.close();

    const writer = file.writer();
    try writer.writeAll(buffer.text.get());
    std.log.info("Saved.", .{});
}

pub fn onRun(_: *zgt.Button_Impl) !void {
    const allocator = zgt.internal.scratch_allocator;
    var childProcess = std.ChildProcess.init(&.{ "zig", "build", "run" }, allocator);
    // TODO: set CWD to project directory
    // childProcess.cwd = "";
    try childProcess.spawn();
    // TODO: clean using wait()
}

pub fn onProfile(_: *zgt.Button_Impl) !void {
    const allocator = zgt.internal.scratch_allocator;
    std.log.debug("Build project", .{});
    var buildProcess = std.ChildProcess.init(&.{ "zig", "build" }, allocator);
    _ = try buildProcess.spawnAndWait();

    std.log.debug("Run project (callgrind)", .{});
    var valgrindProcess = std.ChildProcess.init(&.{ "valgrind", "--tool=callgrind",
        "--callgrind-out-file=callgrind.out", "zig-out/bin/sharko" }, allocator);
    _ = try valgrindProcess.spawnAndWait();

    // TODO: integrate the viewing directly in sharko, and
    //       run it simultaneously with the valgrind process
    std.log.debug("Run viewer (kcachegrind)", .{});
    var viewerProcess = std.ChildProcess.init(&.{ "kcachegrind", "callgrind.out" }, allocator);
    _ = try viewerProcess.spawnAndWait();
}

pub fn main() !void {
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zgt.backend.init();
    var window = try zgt.Window.init();

    const file = try std.fs.cwd().openFile(filePath, .{ .mode = .read_only });
    defer file.close();

    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    buffer = TextBuffer.from(allocator, text);
    defer buffer.deinit();

    const tabLabel = try allocator.dupeZ(u8, std.fs.path.basename(filePath));
    defer allocator.free(tabLabel);

    try window.set(zgt.Column(.{}, .{
        zgt.Row(.{}, .{
            zgt.Button(.{ .label = "Tree" }),
            zgt.Column(.{}, .{
                (try zgt.Row(.{}, .{
                    zgt.Button(.{ .label = "▶", .onclick = onRun }),
                    zgt.Button(.{ .label = "💾", .onclick = onSave }),
                    // TODO: do profiling using valgrind and show with kcachegrind
                    zgt.Button(.{ .label = "▶ (Profiling)", .onclick = onProfile }),
                })).setAlignX(0),
                zgt.Expanded(
                    zgt.Tabs(.{
                        zgt.Tab(.{ .label = tabLabel }, zgt.Expanded(FlatText(.{ .buffer = &buffer }))),
                    }),
                ),
            })
        }),
    }));

    window.resize(1000, 600);
    window.show();

    zgt.runEventLoop();
}
