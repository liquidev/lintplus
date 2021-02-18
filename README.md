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

- It can only show "warnings" - there's no severity levels
  (info/hint/warning/error).
- It doesn't show the messages after lines (ErrorLens style), you have to hover
  over the warning first.
- It spam-runs the linter command, but Nim (and possibly other languages)
  compiles relatively slowly, which lags the editor to hell.
- It is not async, so when the lint command takes its sweet time your editor
  freezes completely.
- It doesn't display the first or current error message on the status view.

lint+ aims to fix all of the above problems.

### Why not just fix `linter`?

- It works fundamentally differently from lint+, so fixing it would be more
  costly than just making a new plugin.
- I haven't ever made my own linter support plugin, so this was a good exercise.

## Installation

Navigate to your `plugins` folder, and clone the repository:

```sh
$ git clone https://github.com/liquidev/lintplus
```

Then, copy `lintplus.lua` to the parent directory, or better yet, create a
symbolic link:

```sh
# I'm not sure whether `ln` is available under Git for Windows.
# Your mileage may vary.
$ ln -s $PWD/{lintplus/lintplus,lintplus}.lua
```

To enable plugins for different languages, do the same thing, but with
`lintplus_*.lua`. For example, to enable support for Nim and Rust:

```sh
$ ln -s $PWD/{lintplus/lintplus_nim,lintplus_nim}.lua
$ ln -s $PWD/{lintplus/lintplus_rust,lintplus_rust}.lua
```

If you want to use plugins designed for the other `linter`, you will also need
to enable the compatibility plugin `linter.lua` *from this repository*.

```sh
$ ln -s $PWD/{lintplus/linter,linter}.lua
```

Keep in mind that plugins designed for `linter` will not work as well as lint+
plugins, because of `linter`'s lack of multiple severity levels. All warnings
reported by `linter` linters will be reported with the `warning` level.

lint+ will add a command `lint+:lint`, which upon execution, will run the
appropriate linter command for the current view and update messages accordingly.

You may also want to add this to your `user/init.lua` to enable automatic
linting upon opening/saving a file:
```lua
local lintplus = require "plugins.lintplus"
lintplus.setup.lint_on_doc_load()
lintplus.setup.lint_on_doc_save()
```
This overrides `Doc.load` and `Doc.save` with some extra behavior to enable
automatic linting.

### Asynchrony

By default, lint+ runs in synchronous mode, which can cause a few problems along
the way:

- If the linter takes a while to run, your entire editor will freeze until the
  linter is done running.
- On Windows, a cmd.exe window will get opened, which can get annoying.

Both of these are limitations of `io.popen`, and there's no easy way to fix this
from within lint+ itself. However, lint+ can operate in *asynchronous* mode,
which requires using a native library to do all the hard work of spawning and
reading output from a process. This is done by a helper library called
`liteipc`, which can be found in the source tree under a separate directory.

This library is written in Rust, so you will need to install it in order to
compile it. Compiling `liteipc` should be as simple as executing one of these
scripts, depending on your OS:

- Windows: `liteipc/build-liteipc.bat` (TODO)
- Linux: `liteipc/build-liteipc.sh`
- macOS is not currently supported. Please open a pull request updating the
  README if you're able to port the .sh script to support macOS dylib.

After building `liteipc`, there's still one thing left to do. That thing is
recompiling lite to use dynamically linked Lua. The official distribution of
lite links Lua statically, which prevents C libraries from loading properly.
I'd recommend switching to [Lite XL](https://github.com/franko/lite-xl), which
allows for linking to Lua dynamically during compilation.

I'm not sure whether this process is required on Windows and macOS at all, but
here's how to do it on Arch Linux:
```sh
# We'll need to grab Lua 5.2 first, so that Meson links to it dynamically.
# On other distros this may require you to download a separate development
# header package
$ doas pacman -S lua52

# Then, we can build the actual executable
$ git clone https://github.com/franko/lite-xl
$ cd lite-xl
$ ./build-packages.sh 1.15.3 x86_64
# If you don't necessarily want to port over your configuration from official
# lite, it's possible to specify the -portable option, like so:
$ ./build-packages.sh -portable 1.15.3 x86_64
```

After compiling, a tar.gz archive will be created containing the custom build
of Lite XL. Now we're on the final stretch: simply unpack the build somewhere,
possibly port your configuration according to information in
[Lite XL's release notes](https://github.com/franko/lite-xl/releases/tag/v1.13-lite-xl)
if you weren't using it prior to installing lint+.

Finally, with all of that, enabling async mode should be as simple as flipping
a switch:

```lua
local lintplus = require "plugins.lintplus"
lintplus.enable_async()
```

This will throw an error if async mode can't be enabled (for instance, if you
try to use async mode without dynamically linked Lua).

## Configuration

lint+ itself looks for the following configuration options:

- `config.lint.kind_pretty_names`
  - table:
    - `info`: string = `"I"`
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
    - `info`: Color - the color used for infos
    - `hint`: Color - the color used for hints
    - `warning`: Color - the color used for warnings
    - `error`: Color - the color used for errors

Example:

```lua
local style = require "common.style"
style.lint = {
  info = style.syntax["keyword2"],
  hint = style.syntax["function"],
  warning = style.syntax["function"],
  error = { common.color "#FF3333" }
}
```

As with config, you need to provide all or no colors.

## Creating new linters

Just like `linter`, lint+ allows you to create new linters for languages not
supported out of the box. The API is very simple:

```lua
Severity: enum {
  "info",     -- suggestions on how to fix things, may be used in tandem with
              -- other messages
  "hint",     -- suggestions on small things that don't affect program behavior
  "warning",  -- warnings about possible mistakes that may affect behavior
  "error",    -- syntax or semantic errors that prevent compilation
}

lintplus.add(linter_name: string)(linter: table {
  filename: pattern,
  procedure: table {
    command: function (filename: string): {string},
      -- Returns the lint command for the given filename.
    interpreter: (function (filename, line: string):
      function ():
        nil or
        (filename: string, line, column: number,
         kind: Severity, message: string)) or "bail"
      -- Creates and returns a message iterator, which yields all messages
      -- from the line.
      -- If the return value is "bail", reading the lint command is aborted
      -- immediately. This is done as a mitigation for processes that may take
      -- too long to execute or block indefinitely.
  }
})
```

Because writing command and interpreter functions can quickly get tedious, there
are some helpers that return pre-built functions for you:

```lua
lintplus.command(cmd: {string}): function (string): {string}
  -- Returns a function that replaces `lintplus.filename` in the given table
  -- with the linted file's name.
lintplus.interpreter(spec: table {
  info: pattern or nil,
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
    command = lintplus.command {
      "nim", "check", "--listFullPaths", "--stdout", lintplus.filename
    },
    interpreter = lintplus.interpreter {
      -- The format for these three in Nim is almost exactly the same:
      hint = "(.-)%((%d+), (%d+)%) Hint: (.+)",
      warning = "(.-)%((%d+), (%d+)%) Warning: (.+)",
      error = "(.-)%((%d+), (%d+)%) Error: (.+)",
      -- We want to strip annotations like [XDeclaredButNotUsed] from the end:
      strip = "%s%[%w+%]$",
      -- Note that info was omitted. This is because all of the severity levels
      -- are optional, so eg. you don't have to provide an info pattern.
    },
  },
}
```

Note that when not using async mode, lint+ tries its best to escape the command
before passing it onto `io.popen`, but this may fail, so that's yet another
reason to switch to async mode.

lint+'s solution to this is a wrapper function over `lintplus.command`,
called `lintplus.args_command`:

```lua
...
    command = lintplus.args_command(
      { "luacheck",
        lintplus.args,
        "--formatter=visual_studio",
        lintplus.filename },
      "luacheck_args"
    )
...
```

The second argument to this function is the name of the field in the
`config.lint` table. Then, the user provides arguments like so:

```lua
config.lint.luacheck_args = { "--max-line-length=80", "--std=love" }
```

Again, under synchronous mode, these are escaped to lint+'s best effort.

## Known problems

- Getting async to work is difficult.
- Due to the fact that it shows the most severe message at the end of the
  line, displaying more than one message per line is really difficult with
  the limited horizontal real estate, so it can only display one message per
  line.
- It is unable to underline the offending token, simply because some linter
  error messages do not contain enough information about where the error start
  and end is. It will highlight the correct line and column, though.

