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

    /// Removes text on the left of 'pos'
    /// Asserts the text buffer starting from 'pos' contains valid UTF-8
    /// 'len' is the number of codepoints (soon to be grapheme clusters) to remove
    /// 'pos' is the BYTE position of the cursor
    /// Returns the number of bytes that have been removed
    pub fn removeBackwards(self: *TextBuffer, pos: usize, len: usize) !usize {
        const oldText = self.text.get();

        // The number of bytes to remove

        // 4 is the maximum number of bytes an UTF-8 codepoint can take
        // we use saturating substraction to cap it to 0
        var start: usize = pos -| len*4;
        var view = try std.unicode.Utf8View.init(oldText[start..]);
        var iterator = view.iterator();

        while (iterator.nextCodepointSlice()) |codepoint| {
            if (start + codepoint.len > pos - len) {
                break;
            }
            start += codepoint.len;
        }

        return try self.remove(start, len);
    }

    /// Removes text on the right of 'pos'
    /// Asserts the text buffer starting from 'pos' contains valid UTF-8
    /// 'len' is the number of codepoints (soon to be grapheme clusters) to remove
    /// 'pos' is the BYTE position of the cursor
    /// Returns the number of bytes that have been removed
    pub fn remove(self: *TextBuffer, pos: usize, len: usize) !usize {
        // TODO: use https://github.com/jecolon/ziglyph to remove grapheme clusters, not codepoints
        const oldText = self.text.get();

        // The number of bytes to remove
        var byteLength: usize = 0;
        var view = try std.unicode.Utf8View.init(oldText[pos..]);
        var iterator = view.iterator();

        var i: usize = 0;
        while (i < len) : (i += 1) {
            if (iterator.nextCodepointSlice()) |codepoint| {
                byteLength += codepoint.len;
            } else {
                break; // 'len' is longer than the text
            }
        }

        const newText = try std.mem.concat(self.allocator, u8, &[_][]const u8 {
            oldText[0..pos], oldText[pos+byteLength..]
        }); // TODO: reuse the memory from oldText, thus making this operation non-faillible
        self.text.set(newText);
        self.allocator.free(oldText); // free the old text

        return byteLength;
    }

    pub fn deinit(self: *TextBuffer) void {
        self.allocator.free(self.text.get());
        self.* = undefined;
    }

};
