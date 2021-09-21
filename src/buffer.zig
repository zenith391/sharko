const zgt = @import("zgt");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TextBuffer = struct {
    text: zgt.StringDataWrapper,
    allocator: *Allocator,

    /// Asserts 'text' is allocated with 'allocator'
    pub fn from(allocator: *Allocator, text: []const u8) TextBuffer {
        return TextBuffer {
            .allocator = allocator,
            .text = zgt.StringDataWrapper.of(text)
        };
    }

    pub fn append(self: *TextBuffer, pos: usize, slice: []const u8) !void {
        const oldText = self.text.get();
        const newText = try std.mem.concat(self.allocator, u8, &[_][]const u8 {
            oldText[0..pos], slice, oldText[pos..]
        });
        self.text.set(newText);
        self.allocator.free(oldText); // free the old text
    }

    pub fn remove(self: *TextBuffer, pos: usize, len: usize) !void {
        // TODO: remove unicode codepoint, not the byte !!
        const oldText = self.text.get();
        const newText = try std.mem.concat(self.allocator, u8, &[_][]const u8 {
            oldText[0..pos], oldText[pos+len..]
        }); // TODO: reuse the memory from oldText, thus making this operation non-faillible
        self.text.set(newText);
        self.allocator.free(oldText); // free the old text
    }

    pub fn deinit(self: *TextBuffer) void {
        self.allocator.free(self.text.get());
        self.* = undefined;
    }

};
