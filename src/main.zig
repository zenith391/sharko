const std = @import("std");
const zgt = @import("zgt");

const FlatText = @import("text.zig").FlatText;
const TextBuffer = @import("buffer.zig").TextBuffer;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const zgtAllocator = gpa.allocator();

var buffer: TextBuffer = undefined;
const filePath: [:0]const u8 = "src/text.zig";

var window: zgt.Window = undefined;

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
    var valgrindProcess = std.ChildProcess.init(&.{ "valgrind", "--tool=callgrind", "--callgrind-out-file=callgrind.out", "zig-out/bin/sharko" }, allocator);
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
    window = try zgt.Window.init();

    const file = try std.fs.cwd().openFile(filePath, .{ .mode = .read_only });
    defer file.close();

    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    buffer = TextBuffer.from(allocator, text);
    defer buffer.deinit();

    const tabLabel = try allocator.dupeZ(u8, std.fs.path.basename(filePath));
    defer allocator.free(tabLabel);

    try window.set(zgt.Column(.{}, .{
        zgt.Row(.{ .spacing = 0 }, .{
            zgt.Button(.{ .label = "Tree" }),
            zgt.Column(.{}, .{
                (try zgt.Row(.{ .spacing = 10 }, .{
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
            }),
        }),
    }));
    window.setMenuBar(zgt.MenuBar(.{
        zgt.Menu(.{ .label = "File" }, .{
            zgt.Menu(.{ .label = "New" }, .{
                zgt.MenuItem(.{ .label = "Project" }),
                zgt.MenuItem(.{ .label = "Zig File" }),
            }),
            zgt.MenuItem(.{ .label = "Open Project.." }),
            zgt.MenuItem(.{ .label = "Save" }),
            zgt.MenuItem(.{ .label = "Exit", .onClick = exitCallback }),
        }),
        zgt.Menu(.{ .label = "Edit" }, .{
            zgt.MenuItem(.{ .label = "Find" }),
            zgt.MenuItem(.{ .label = "Replace" }),
        }),
        zgt.Menu(.{ .label = "Run" }, .{
            // TODO: the name of the default step in tooltip
            zgt.MenuItem(.{ .label = "Run" }),
            zgt.MenuItem(.{ .label = "Debug" }),
            zgt.Menu(.{ .label = "Run As" }, .{
                // filled per project
            }),
            zgt.Menu(.{ .label = "Debug As" }, .{
                // filled per project
            }),
            zgt.Menu(.{ .label = "Profile As" }, .{
                // filled per project
            }),
            zgt.Menu(.{ .label = "Coverage As" }, .{
                // filled per project
            }),
        }),
    }));

    window.resize(1000, 600);
    window.setTitle("Sharko");
    window.show();

    zgt.runEventLoop();
}

fn exitCallback() void {
    window.deinit();
}
