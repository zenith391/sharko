const std = @import("std");
const zgt = @import("zgt");

const FlatText = @import("text.zig").FlatText;
const TextBuffer = @import("buffer.zig").TextBuffer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    try zgt.backend.init();
    var window = try zgt.Window.init();

    const file = try std.fs.cwd().openFile("src/main.zig", .{ .read = true });
    defer file.close();

    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    var buffer = TextBuffer.from(allocator, text);
    defer buffer.deinit();

    try window.set(
        zgt.Row(.{}, .{
            zgt.Button(.{ .label = "Treee" }),
            zgt.Expanded(
                FlatText(.{ .buffer = &buffer })
            ),
            zgt.Button(.{ .label = "Misc" })
        })
    );

    window.resize(1000, 600);
    window.show();
    zgt.runEventLoop();
}