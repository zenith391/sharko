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
    const childProcess = try std.ChildProcess.init(&.{ "zig", "build", "run" }, allocator);
    defer childProcess.deinit();
    // TODO: set CWD to project directory
    // childProcess.cwd = "";
    const termination = try childProcess.spawnAndWait();
    if (termination.Exited != 0) {
        std.log.info("Build failure", .{});
    }
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
        (try zgt.Row(.{}, .{
            zgt.Button(.{ .label = "Save", .onclick = onSave }),
            zgt.Button(.{ .label = "Run", .onclick = onRun }),
            // TODO: do profiling using valgrind and show with kcachegrind
            zgt.Button(.{ .label = "Profile" }),
        })).setAlignX(0),
        zgt.Row(.{}, .{
            zgt.Button(.{ .label = "Tree" }),
            zgt.Expanded(
                zgt.Tabs(.{
                    zgt.Tab(.{ .label = tabLabel }, FlatText(.{ .buffer = &buffer })),
                }),
            ),
        }),
    }));

    window.resize(1000, 600);
    window.show();

    zgt.runEventLoop();
}
