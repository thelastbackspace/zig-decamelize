# decamelize

[![CI](https://github.com/thelastbackspace/zig-decamelize/actions/workflows/ci.yml/badge.svg)](https://github.com/thelastbackspace/zig-decamelize/actions/workflows/ci.yml)

Convert camelCase to a separated form: `unicornRainbow` →
`unicorn_rainbow`.

```zig
const decamelize = @import("decamelize");

const a = try decamelize.decamelize(allocator, "unicornRainbow", .{}); // "unicorn_rainbow"
const b = try decamelize.decamelize(allocator, "myURLString", .{
    .preserve_consecutive_uppercase = true,
}); // "my_URL_string"
const c = try decamelize.decamelize(allocator, "unicornRainbow", .{ .separator = "-" }); // "unicorn-rainbow"
// Caller owns the returned memory.
```

## Installation

Requires Zig 0.16.0.

```sh
zig fetch --save git+https://github.com/thelastbackspace/zig-decamelize#v1.0.0
```

Then in `build.zig`:

```zig
const decamelize = b.dependency("decamelize", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("decamelize", decamelize.module("decamelize"));
```

## API

### `decamelize(allocator, text: []const u8, options: Options) ![]u8`

Convert one string. A separator is inserted at each
lowercase-or-digit → uppercase transition, and before the last
uppercase letter of an acronym followed by lowercase text
(`URLString` → `url_string`). The result is lowercased. Caller owns
the returned memory.

### `Options`

- `separator: []const u8 = "_"` — inserted between words; may be any
  string, including empty.
- `preserve_consecutive_uppercase: bool = false` — keep acronym runs
  intact and lowercase only one-letter words:
  `myURLString` → `my_URL_string`, `data_For_USACounties` →
  `data_for_USA_counties`.

## Notes

- Case mapping and letter classification use simple Unicode mappings
  (Unicode 16.0.0) generated into `src/unicode_data.zig`.
- Text is processed by Unicode code point.
- Input is expected to be valid UTF-8.

## Testing

```sh
zig build test
```

The suite ports the upstream project's test file, including the long
mixed-case strings and the pathological-input cases (those assert
correctness here; the wall-clock bounds exist upstream to guard against
regex backtracking, which a linear scan does not have).

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The CI gate
(`zig fmt --check`, tests, build) must pass.

## Credits

Behavior and the test suite follow the npm package
[`decamelize`](https://github.com/sindresorhus/decamelize) v6.0.1 (MIT,
© Sindre Sorhus); the implementation is original, and the Unicode
tables are generated from the Unicode Character Database 16.0.0. Zig
implementation © 2026 thelastbackspace, MIT — see [LICENSE](LICENSE).
