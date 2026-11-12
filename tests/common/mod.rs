use std::path::PathBuf;
use std::process::Command;

const CHILD: &str = "SPLICE_PUBLIC_API_TEST";

struct Directory(PathBuf);

impl Drop for Directory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub fn with_repository(test: impl FnOnce()) {
    let thread = std::thread::current();
    let name = thread.name().unwrap();
    if std::env::var(CHILD).as_deref() == Ok(name) {
        test();
        return;
    }
    let output = Command::new("mktemp").arg("-d").output().unwrap();
    assert!(output.status.success());
    let directory = Directory(PathBuf::from(
        String::from_utf8(output.stdout).unwrap().trim(),
    ));
    let home = directory.0.join("home");
    let repository = directory.0.join("monorepo");
    std::fs::create_dir(&home).unwrap();
    std::fs::create_dir(&repository).unwrap();
    let mut command = Command::new(std::env::current_exe().unwrap());
    for (key, _) in std::env::vars_os() {
        if key.to_string_lossy().starts_with("GIT_") {
            command.env_remove(key);
        }
    }
    let output = command
        .args(["--exact", name, "--nocapture", "--test-threads=1"])
        .current_dir(repository)
        .env(CHILD, name)
        .env("HOME", &home)
        .env("XDG_CONFIG_HOME", home.join(".config"))
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_TERMINAL_PROMPT", "0")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

pub fn git(args: &[&str]) -> String {
    let output = Command::new("git")
        .args(["-c", "user.name=Test", "-c", "user.email=test@example.com"])
        .args(args)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap().trim_end().into()
}

pub fn push_ahead() {
    git(&["init", "-q", "--initial-branch=main"]);
    git(&["config", "init.defaultBranch", "main"]);
    git(&["config", "user.name", "Test"]);
    git(&["config", "user.email", "test@example.com"]);
    git(&[
        "init",
        "-q",
        "--bare",
        "--initial-branch=main",
        "../upstream.git",
    ]);
    std::fs::create_dir_all("vendor/a").unwrap();
    std::fs::write("vendor/a/file.txt", "local change\n").unwrap();
    std::fs::write(
        "vendor/a/.splice",
        "[splice]\n id = public-api\n[upstream \"origin\"]\n url = ../upstream.git\n",
    )
    .unwrap();
    git(&["add", "."]);
    git(&["commit", "-qm", "mount splice"]);
}
