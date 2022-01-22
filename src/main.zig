const std = @import("std");
const zgt = @import("zgt");

const FlatText = @import("text.zig").FlatText;
const TextBuffer = @import("buffer.zig").TextBuffer;

var buffer: TextBuffer = undefined;
const filePath: []const u8 = "src/text.zig";

pub fn onSave(button: *zgt.Button_Impl) !void {
    _ = button;
    std.log.info("Saving to {s}", .{ filePath });

    const file = try std.fs.cwd().createFile(filePath, .{ });
    defer file.close();

    const writer = file.writer();
    try writer.writeAll(buffer.text.get());
    std.log.info("Saved.", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zgt.backend.init();
    var window = try zgt.Window.init();

    const file = try std.fs.cwd().openFile(filePath, .{ .read = true });
    defer file.close();

    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    buffer = TextBuffer.from(allocator, text);
    defer buffer.deinit();

    try window.set(
        zgt.Column(.{}, .{
            (try zgt.Row(.{}, .{
                zgt.Button(.{ .label = "Save", .onclick = onSave }),
                zgt.Button(.{ .label = "Run" }),
            })).setAlignX(0),
            zgt.Row(.{}, .{
                zgt.Button(.{ .label = "Treee" }),
                zgt.Expanded(
                    // zgt.Tabs(&.{
                    //     zgt.TabItem(.{ .label = filePath }, 
                    FlatText(.{ .buffer = &buffer })
                    // )})
                ),
            })
        })
    );

    window.resize(1000, 600);
    window.show();

    zgt.runEventLoop();
}
