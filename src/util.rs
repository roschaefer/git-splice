//! Logging, failures and running git.

use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

/// How a step failed, after it printed why.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Fail {
    /// Fails this splice's step: the command goes on with the next splice.
    Soft,
    /// Ends the command.
    Hard,
    /// A git command the step ran exited with this status.
    Code(i32),
}

pub type Res<T> = Result<T, Fail>;

/// Ends the command with a message.
pub fn die<T>(message: impl AsRef<str>) -> Res<T> {
    log_err(message);
    Err(Fail::Hard)
}

/// Fails this splice's step with a message.
pub fn fail<T>(message: impl AsRef<str>) -> Res<T> {
    log_err(message);
    Err(Fail::Soft)
}

/// Keeps a failure from ending the command: the caller decides what it means.
pub fn contained<T>(result: Res<T>) -> Res<T> {
    result.map_err(|fail| match fail {
        Fail::Hard => Fail::Soft,
        other => other,
    })
}

/// Stderr of everything is off while set: the command's own messages and git's.
static QUIET: AtomicBool = AtomicBool::new(false);

/// Runs `step` without any message on stderr.
pub fn quietly<T>(step: impl FnOnce() -> T) -> T {
    QUIET.store(true, Ordering::Relaxed);
    let result = step();
    QUIET.store(false, Ordering::Relaxed);
    result
}

fn eprint_line(line: &str) {
    if !QUIET.load(Ordering::Relaxed) {
        let _ = writeln!(std::io::stderr(), "{line}");
    }
}

/// Prints to stdout. A reader that's gone, e.g. a pager that was quit, isn't an
/// error here: the git commands that write to it next end on it.
pub fn say(line: impl AsRef<str>) {
    let mut out = std::io::stdout();
    let _ = writeln!(out, "{}", line.as_ref());
    let _ = out.flush();
}

pub fn log_ok(message: impl AsRef<str>) {
    say(format!("ok   {}", message.as_ref()));
}

pub fn log_step(message: impl AsRef<str>) {
    say(format!("===  {}", message.as_ref()));
}

pub fn log_warn(message: impl AsRef<str>) {
    eprint_line(&format!("??   {}", message.as_ref()));
}

pub fn log_err(message: impl AsRef<str>) {
    eprint_line(&format!("!!   {}", message.as_ref()));
}

/// Prints text to stderr as it is.
pub fn eprint_text(text: &str) {
    if !QUIET.load(Ordering::Relaxed) {
        let _ = write!(std::io::stderr(), "{text}");
    }
}

/// The status a shell would report: 128 + the signal that ended a command.
pub fn status_code(status: ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0))
}

/// A git command to run.
pub struct Git {
    command: Command,
    input: Option<Vec<u8>>,
    quiet: bool,
}

pub fn git(args: &[&str]) -> Git {
    let mut command = Command::new("git");
    command.args(args);
    Git {
        command,
        input: None,
        quiet: QUIET.load(Ordering::Relaxed),
    }
}

impl Git {
    pub fn env(mut self, key: &str, value: impl AsRef<std::ffi::OsStr>) -> Self {
        self.command.env(key, value);
        self
    }

    pub fn input(mut self, input: impl Into<Vec<u8>>) -> Self {
        self.input = Some(input.into());
        self
    }

    /// Sends stderr nowhere.
    pub fn q(mut self) -> Self {
        self.quiet = true;
        self
    }

    fn stderr(&self) -> Stdio {
        if self.quiet {
            Stdio::null()
        } else {
            Stdio::inherit()
        }
    }

    fn capture(mut self) -> Option<(ExitStatus, Vec<u8>)> {
        let stderr = self.stderr();
        self.command.stdout(Stdio::piped()).stderr(stderr);
        self.command.stdin(if self.input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
        let mut child = self.command.spawn().ok()?;
        let writer = self.input.take().and_then(|input| {
            let mut stdin = child.stdin.take()?;
            Some(std::thread::spawn(move || {
                let _ = stdin.write_all(&input);
            }))
        });
        let output = child.wait_with_output().ok()?;
        if let Some(writer) = writer {
            let _ = writer.join();
        }
        Some((output.status, output.stdout))
    }

    /// Its stdout as it is, if it succeeds.
    pub fn bytes(self) -> Option<Vec<u8>> {
        let (status, stdout) = self.capture()?;
        status.success().then_some(stdout)
    }

    /// Its stdout without trailing newlines, if it succeeds.
    pub fn out(self) -> Option<String> {
        self.bytes().map(|stdout| text(&stdout))
    }

    /// Its stdout without trailing newlines, whether it succeeds or not.
    pub fn out_anyway(self) -> String {
        self.capture()
            .map(|(_, stdout)| text(&stdout))
            .unwrap_or_default()
    }

    /// Its stdout as it is and its status, whether it succeeds or not.
    pub fn bytes_and_status(self) -> Option<(ExitStatus, Vec<u8>)> {
        self.capture()
    }

    /// Whether it succeeds, its stdout gone.
    pub fn ok(mut self) -> bool {
        let stderr = self.stderr();
        self.command.stdout(Stdio::null()).stderr(stderr);
        self.capture_status().is_some_and(|status| status.success())
    }

    fn capture_status(mut self) -> Option<ExitStatus> {
        self.command.stdin(if self.input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
        let mut child = self.command.spawn().ok()?;
        if let Some(input) = self.input.take() {
            let mut stdin = child.stdin.take()?;
            let _ = stdin.write_all(&input);
        }
        child.wait().ok()
    }

    /// Its status, with stdout and stderr where ours go.
    pub fn run(mut self) -> i32 {
        let stderr = self.stderr();
        self.command.stderr(stderr);
        self.capture_status().map_or(1, status_code)
    }

    /// Stdout and stderr together, and whether it succeeded.
    pub fn out_and_err(mut self) -> (bool, String) {
        self.command.stdin(Stdio::null());
        match self.command.output() {
            Ok(output) => {
                let mut all = text(&output.stderr);
                let out = text(&output.stdout);
                if !out.is_empty() {
                    if !all.is_empty() {
                        all.push('\n');
                    }
                    all.push_str(&out);
                }
                (output.status.success(), all)
            }
            Err(error) => (false, error.to_string()),
        }
    }

    /// Its stderr without trailing newlines.
    pub fn err_text(mut self) -> String {
        self.command.stdin(Stdio::null()).stdout(Stdio::null());
        self.command
            .output()
            .map(|output| text(&output.stderr))
            .unwrap_or_default()
    }

    /// The command itself, to spawn with pipes.
    pub fn into_command(self) -> Command {
        self.command
    }
}

/// A path git printed, byte for byte: a folder's name need not be UTF-8.
pub fn path_from_output(mut bytes: Vec<u8>) -> PathBuf {
    use std::os::unix::ffi::OsStringExt;
    while bytes.last() == Some(&b'\n') {
        bytes.pop();
    }
    PathBuf::from(std::ffi::OsString::from_vec(bytes))
}

/// `$(...)`: text without trailing newlines.
pub fn text(bytes: &[u8]) -> String {
    let mut text = String::from_utf8_lossy(bytes).into_owned();
    while text.ends_with('\n') {
        text.pop();
    }
    text
}

/// Fields of output separated by NUL, without the empty one after the last.
pub fn nul_fields(bytes: &[u8]) -> Vec<String> {
    let mut fields: Vec<String> = bytes
        .split(|&byte| byte == 0)
        .map(|field| String::from_utf8_lossy(field).into_owned())
        .collect();
    if fields.last().is_some_and(String::is_empty) {
        fields.pop();
    }
    fields
}

static TEMP_COUNTER: AtomicU32 = AtomicU32::new(0);

/// A path for a temporary file or folder, removed when it's dropped.
pub struct Temp {
    pub path: PathBuf,
}

impl Temp {
    pub fn new() -> Temp {
        let number = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        Temp {
            path: std::env::temp_dir().join(format!("git-splice-{}-{number}", std::process::id())),
        }
    }

    pub fn str(&self) -> String {
        self.path.to_string_lossy().into_owned()
    }
}

impl Drop for Temp {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

/// The first 7 characters: a short commit id.
pub fn short(id: &str) -> &str {
    id.char_indices().nth(7).map_or(id, |(end, _)| &id[..end])
}

/// One shell word for a ready-to-run command we print: as it is if it only
/// has characters no shell treats specially, else single-quoted.
pub fn shell_quote(word: &str) -> String {
    let plain = !word.is_empty()
        && word
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_./:@%+=,-".contains(c));
    if plain {
        word.to_string()
    } else {
        format!("'{}'", word.replace('\'', "'\\''"))
    }
}

/// Names for a message: 'a', 'a' and 'b', or 'a', 'b' and 'c'.
pub fn join_names(names: &[String]) -> String {
    let mut out = String::new();
    for (i, name) in names.iter().enumerate() {
        if i == 0 {
            out.push_str(&format!("'{name}'"));
        } else if i + 1 == names.len() {
            out.push_str(&format!(" and '{name}'"));
        } else {
            out.push_str(&format!(", '{name}'"));
        }
    }
    out
}

/// The path without a leading "./" and trailing slashes, as splice paths are
/// compared and stored.
pub fn normalize_path(path: &str) -> String {
    let path = path.strip_prefix("./").unwrap_or(path);
    path.trim_end_matches('/').to_string()
}
