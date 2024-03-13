local lintplus = require "plugins.lintplus"

lintplus.add("lacheck") {
  filename = "%.tex$",
  procedure = {
    command = lintplus.command {
      "lacheck", lintplus.filename
    },
    interpreter = lintplus.interpreter {
      warning = string.format('"%s"', lintplus.filename) .. "," .. "\\sline:\\s\\d+\\:\\s[a-z]+"
    }
  }
}

lintplus.setup.lint_on_doc_load()  -- enable automatic linting upon opening a file
lintplus.setup.lint_on_doc_save()  -- enable automatic linting upon saving a file
lintplus.load({"lacheck"})
