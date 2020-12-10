# lint+

An improved linting plugin for [lite](https://github.com/rxi/lite).

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
- It's not compatible with existing `linter` linters, but that should be a
  relatively easy fix.

Problems related to `io.popen` *may* get fixed if I started using an external
native library for reading output from the linter, but currently I don't really
want to hassle with luarocks.

## Development

I've found that the easiest way of developing lint+ is cloning the repository to
your `plugins` folder and symlinking all .lua files from `plugins/lint+` to
`plugins`. Unfortunately just cloning lint+ doesn't work since lite's plugin
loader seems to only look for .lua files and not directories.
