# lint+

An improved linting plugin for [lite](https://github.com/rxi/lite).

Includes compatibility layer for [`linter`](https://github.com/drmargarido/linters).

## Screenshots

![1st screenshot](screenshots/1.png)
<p align="center">
Features ErrorLens-style warnings and error messages for quickly scanning
through code for errors.
</p>

<br>

![2nd screenshot](screenshots/2.png)
<p align="center">
The status view shows either the first error, or the full message of the error
under your text cursor. No mouse interaction needed!
</p>


## Motivation

There were a few problems I had with the existing `linter` plugin:

- It can only show "warnings" - there's no severity levels (hint/warning/error).
- It doesn't show the messages after lines (ErrorLens style), you have to hover
  over the warning first.
- It spam-runs the linter command, but Nim (and possibly other languages)
  compiles relatively slowly, which lags the editor to hell.
- It is not async, so when the lint command takes its sweet time your editor
  freezes completely.
- It doesn't display the first or current error message on the status view.

lint+ aims to fix all of the above problems.

### Why not just fix `linter`?

- It works fundamentally differently from `lint+`, so fixing it would be more
  costly than just making a new plugin.
- I haven't ever made my own linter support plugin, so this was a good exercise.

## Installation

Download `lint+.lua` into your `plugins` folder. Then, pick whatever linters you
need and download them into the `plugins` folder.

If you want to use plugins designed for the other `linter`, you will also need
to download the compatibility plugin `linter.lua` *from this repository*.
Keep in mind that plugins designed for `linter` will not work as well as lint+
plugins, because of `linter`'s lack of multiple severity levels. All warnings
reported by `linter` linters will be reported with the `warning` level.

lint+ will add a command `lint+:lint`, which upon execution, will run the
appropriate linter command for the current view and update messages accordingly.

You may also want to add this to your `user/init.lua` to enable automatic
linting upon opening/saving a file:
```lua
local lintplus = require "plugins.lint+"
lintplus.setup.lint_on_doc_load()
lintplus.setup.lint_on_doc_save()
```
This overrides `Doc.load` and `Doc.save` with some extra behavior to enable
automatic linting.

## Configuration

lint+ itself looks for the following configuration options:

- `config.lint.kind_pretty_names`
  - table:
    - `hint`: string = `"H"`
    - `warning`: string = `"W"`
    - `error`: string = `"E"`
  - controls the prefix prepended to messages displayed on the status bar.
    for example, setting `error` to `Error` will display `Error: …` or
    `line 10 Error: …` instead of `E: …` or `line 10 E: …`.

All options are unset (`nil`) by default, so eg. setting
`config.lint.kind_pretty_names.hint` will *not* work because
`config.lint.kind_pretty_names` does not exist.

Individual plugins may also look for options in the `config.lint` table.
Refer to each plugin's source code for more information.

### Styling

The screenshots above use a theme with extra colors for the linter's messages.
The default color is the same color used for literals, which isn't always what
you want. Most of the time you want to have some clear visual distinction
between severity levels, so lint+ is fully stylable.

- `style.lint`
  - table:
    - `hint`: Color - the color used for hints
    - `warning`: Color - the color used for warnings
    - `error`: Color - the color used for errors

Example:

```lua
local style = require "common.style"
style.lint = {
  hint = style.syntax["function"],
  warning = style.syntax["operator"],
  error = { common.color "#FF3333" }
}
```

As with config, you need to provide all or no colors.

## Creating new linters

Just like `linter`, lint+ allows you to create new linters for languages not
supported out of the box. The API is very simple:

```lua
Severity: enum {
  "hint",
  "warning",
  "error",
}

lintplus.add(linter_name: string)(linter: table {
  filename: pattern,
  procedure: table {
    command: function (filename: string): string,
      -- Returns the lint command for the given filename.
    interpreter: function (filename, line: string):
      (ok: bool,
       filename: string, line, column: number,
       kind: Severity, message: string)
      -- Interprets a line from the lint command.
      -- Returns `false` when the line is not valid output, or `true` and the
      -- rest of arguments when the line was correctly interpreted as a message
      -- line.
  }
})
```

Because writing command and interpreter functions can quickly get tedious, there
are some helpers that return pre-built functions for you:

```lua
lintplus.command(cmd: string)
  -- Returns a function that replaces "$filename" in the given string with the
  -- filename passed to it.
lintplus.interpreter(spec: table {
  hint: pattern or nil,
  warning: pattern or nil,
  error: pattern or nil,
    -- Defines patterns for all the severity levels. Each pattern must have
    -- four captures: the first one being the filename, the second and third
    -- being the line and column, and the fourth being the message.
    -- When any of these are nil, the interpreter simply will not produce the
    -- given severity levels.
  strip: pattern or nil,
    -- Defines a pattern for stripping unnecessary information from the message
    -- capture from one of the previously defined patterns. When this is `nil`,
    -- nothing is stripped and the message remains as-is.
})
```

An example linter built with these primitives:

```lua
lintplus.add("nim") {
  filename = "%.nim$",
  procedure = {
    command = lintplus.command "nim check --listFullPaths --stdout $filename",
    interpreter = lintplus.interpreter {
      -- The format for these three in Nim is almost exactly the same:
      hint = "(.-)%((%d+), (%d+)%) Hint: (.+)",
      warning = "(.-)%((%d+), (%d+)%) Warning: (.+)",
      error = "(.-)%((%d+), (%d+)%) Error: (.+)",
      -- We want to strip annotations like [XDeclaredButNotUsed] from the end:
      strip = "%s%[%w+%]$",
    },
  },
}
```

Note that unlike `linter`, lint+ does not define a standard way for passing
user-defined arguments to the lint command. The main reason for this is because
`io.popen` opens the program in the user's shell, and every shell behaves
differently, so supporting this would be an escaping nightmare.
`linter` does this in a very unsafe, and honestly wrong way, by simply
table.concating the user-defined table of strings with spaces. This is a very
bad and unsafe idea, because it imposes an assumption that every string is a
separate argument on the user, but that assumption is obviously wrong. A case
like `{"Hello World"}` showcases this perfectly, because contrary to common
sense, two arguments `"Hello"` and `"World"` are passed to the lint command.

Instead of a solution common across all linters, each linter should provide its
own, preferably being just a simple string config option like this:

```lua
...
    command = lintplus.command(
      "luacheck --formatter=plain " ..
      lintplus.config.luacheck_args ..
      " $filename"
    )
...
```

Then the user provides arguments like so:

```lua
config.lint.luacheck_args = "--max-line-length=80 --std=love"
```

which doesn't hide that these arguments are really just a string concatenation
to the lint command.

## Known problems

- Despite its asyncness, it still lags your editor a tiny bit when linting.
  This cannot be fixed easily due to the fact that `io.popen` operations are
  blocking, so if the lint command doesn't output anything for a while the
  linter thread will stall until it gets some output.
- Due to the fact that it shows the most severe message at the end of the
  line, displaying more than one message per line is really difficult with
  the limited horizontal real estate, so it can only display one message per
  line.
- It is unable to underline the offending token, simply because linter error
  messages do not contain enough information about where the error start and
  end is. It will highlight the correct line and column, though.
- Just like `linter`, using it on Windows will be quite annoying because Lua's
  `io.popen` opens the lint command in a `cmd.exe` window.

Problems related to `io.popen` *may* get fixed if I started using an external
native library for reading output from the linter, but currently I don't really
want to hassle with luarocks.


## Development

I've found that the easiest way of developing lint+ is cloning the repository to
your `plugins` folder and symlinking all .lua files from `plugins/lint+` to
`plugins`. Unfortunately just cloning lint+ doesn't work since lite's plugin
loader seems to only look for .lua files and not directories.
