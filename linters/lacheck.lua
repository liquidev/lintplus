local lintplus = require "plugins.lintplus"

lintplus.add("lacheck") {
  filename = "%.tex$",
  procedure = {
    command = lintplus.command {
      "lacheck", lintplus.filename
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
