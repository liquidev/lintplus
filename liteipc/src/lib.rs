use std::time::Duration;

use mlua::prelude::*;
use subprocess::*;

struct Process {
    popen: Popen,
    comms: Communicator,
    read_buffer: String,
}

impl Process {
    fn start(_: &Lua, command: Vec<String>) -> LuaResult<Process> {
        let mut popen = match Popen::create(&command, PopenConfig {
            stdout: Redirection::Pipe,
            stderr: Redirection::Merge,
            .. Default::default()
        }) {
            Ok(x) => x,
            Err(e) => return Err(LuaError::RuntimeError(format!("{}", e))),
        };
        let comms = popen.communicate_start(None)
            .limit_time(Duration::default());
        Ok(Self {
            popen,
            comms,
            read_buffer: String::new(),
        })
    }

    fn communicate(&mut self, output_callback: LuaFunction) -> LuaResult<()> {

        // read data from the process
        let comm_result = self.comms.read_string();
        let mut data = String::new();
        match comm_result {
            Ok((Some(s), _)) => data = s,
            Err(e) => {
                if let (Some(s), _) = e.capture {
                    match String::from_utf8(s) {
                        Ok(s) => data = s,
                        _ => (),
                    };
                }
            },
            _ => (),
        }

        // append it to the buffer
        self.read_buffer.push_str(&data);

        // look for line breaks in the buffer
        while !self.read_buffer.is_empty() {
            let mut line = String::new();
            let mut found_lf = false;
            for (i, c) in self.read_buffer.char_indices() {
                match c {
                    '\r' => (),
                    '\n' => {
                        output_callback.call::<_, ()>(line.clone())?;
                        self.read_buffer = self.read_buffer.get(i + 1 ..)
                            .unwrap_or("")
                            .to_string();
                        found_lf = true;
                        break;
                    },
                    _ => line.push(c),
                }
            }
            if !found_lf {
                break;
            }
        }

        Ok(())

    }

    // the callback will always receive whole lines of output from the process, with line separators stripped
    fn poll(_: &Lua, this: &mut Self, output_callback: LuaFunction) -> LuaResult<(Option<String>, Option<i32>)> {
        this.communicate(output_callback)?;
        Ok(
            if let Some(status) = this.popen.poll() {
                let r: (_, i32) = match status {
                    ExitStatus::Exited(code) => ("exit", code as _),
                    ExitStatus::Signaled(signal) => ("signal", signal as _),
                    ExitStatus::Other(code) => ("other", code),
                    ExitStatus::Undetermined => ("undetermined", 0),
                };
                (Some(r.0.to_string()), Some(r.1))
            } else {
                (None, None)
            }
        )
    }
}

impl LuaUserData for Process {
    fn add_methods<'lua, M: LuaUserDataMethods<'lua, Self>>(methods: &mut M) {
        methods.add_method_mut("poll", Self::poll);
    }
}

#[mlua::lua_module]
fn liteipc_native(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;

    exports.set("start_process", lua.create_function(Process::start)?)?;

    Ok(exports)
}
