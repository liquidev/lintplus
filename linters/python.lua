 local lintplus = require "plugins.lintplus"

 lintplus.add("flake8") {
   filename = "%.py$",
   procedure = {
     command = lintplus.args_command(
       { "flake8",
         lintplus.args,
         lintplus.filename },
         "flake8_args"
     ),
     interpreter = lintplus.interpreter {
       warning = "(.-):(%d+):(%d+): [FCW]%d+ (.+)",
       error = "(.-):(%d+):(%d+): E%d+ (.+)",
     }
   },
 }
