const std = @import("std");
const capy = @import("capy");

const FlatText = @import("text.zig").FlatText;
const TextBuffer = @import("buffer.zig").TextBuffer;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const capyAllocator = gpa.allocator();

var buffer: TextBuffer = undefined;
const filePath: [:0]const u8 = "src/text.zig";

var window: capy.Window = undefined;

pub fn onSave(button: *capy.Button_Impl) !void {
    _ = button;
    std.log.info("Saving to {s}", .{filePath});

    const file = try std.fs.cwd().createFile(filePath, .{});
    defer file.close();

    const writer = file.writer();
    try writer.writeAll(buffer.text.get());
    std.log.info("Saved.", .{});
}

pub fn onRun(_: *capy.Button_Impl) !void {
    const allocator = capy.internal.scratch_allocator;
    var childProcess = std.ChildProcess.init(&.{ "zig", "build", "run" }, allocator);
    // TODO: set CWD to project directory
    // childProcess.cwd = "";
    try childProcess.spawn();
    // TODO: clean using wait()
}

pub fn onProfile(_: *capy.Button_Impl) !void {
    const allocator = capy.internal.scratch_allocator;
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

    try capy.backend.init();
    window = try capy.Window.init();

    const file = try std.fs.cwd().openFile(filePath, .{ .mode = .read_only });
    defer file.close();

    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    buffer = TextBuffer.from(allocator, text);
    defer buffer.deinit();

    const tabLabel = try allocator.dupeZ(u8, std.fs.path.basename(filePath));
    defer allocator.free(tabLabel);

    try window.set(capy.Column(.{}, .{
        capy.Row(.{ .spacing = 0 }, .{
            capy.Button(.{ .label = "Tree" }),
            capy.Column(.{}, .{
                (try capy.Row(.{ .spacing = 10 }, .{
                    capy.Button(.{ .label = "▶", .onclick = onRun }),
                    capy.Button(.{ .label = "💾", .onclick = onSave }),
                    // TODO: do profiling using valgrind and show with kcachegrind
                    capy.Button(.{ .label = "▶ (Profiling)", .onclick = onProfile }),
                })).set("alignX", 0),
                capy.Expanded(
                    capy.Tabs(.{
                        capy.Tab(.{ .label = tabLabel }, capy.Expanded(FlatText(.{ .buffer = &buffer }))),
                    }),
                ),
            }),
        }),
    }));
    window.setMenuBar(capy.MenuBar(.{
        capy.Menu(.{ .label = "File" }, .{
            capy.Menu(.{ .label = "New" }, .{
                capy.MenuItem(.{ .label = "Project" }),
                capy.MenuItem(.{ .label = "Zig File" }),
            }),
            capy.MenuItem(.{ .label = "Open Project.." }),
            capy.MenuItem(.{ .label = "Save" }),
            capy.MenuItem(.{ .label = "Exit", .onClick = exitCallback }),
        }),
        capy.Menu(.{ .label = "Edit" }, .{
            capy.MenuItem(.{ .label = "Find" }),
            capy.MenuItem(.{ .label = "Replace" }),
        }),
        capy.Menu(.{ .label = "Run" }, .{
            // TODO: the name of the default step in tooltip
            capy.MenuItem(.{ .label = "Run" }),
            capy.MenuItem(.{ .label = "Debug" }),
            capy.Menu(.{ .label = "Run As" }, .{
                // filled per project
            }),
            capy.Menu(.{ .label = "Debug As" }, .{
                // filled per project
            }),
            capy.Menu(.{ .label = "Profile As" }, .{
                // filled per project
            }),
            capy.Menu(.{ .label = "Coverage As" }, .{
                // filled per project
            }),
        }),
    }));

    window.resize(1000, 600);
    window.setTitle("Sharko");
    window.show();

    capy.runEventLoop();
}

fn exitCallback() void {
    window.deinit();
}
