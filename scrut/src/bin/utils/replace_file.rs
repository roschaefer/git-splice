/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use std::fs;
use std::fs::OpenOptions;
use std::path::Path;
use std::path::PathBuf;

use anyhow::Context;
use anyhow::Result;

/// Writes `contents` to `path` through a hidden temporary file next to it,
/// renamed into place, so that a document running at the same time (see
/// `--jobs`) reads either the old or the new contents, never a half-written
/// file. Keeps the permissions of an existing file and writes through a
/// symlink, like [`fs::write`]. Where renaming would do something
/// `fs::write` doesn't, it uses `fs::write`, see [`replaceable_target`].
pub(crate) fn replace_file(path: &Path, contents: impl AsRef<[u8]>) -> Result<()> {
    let Some(target) = replaceable_target(path) else {
        return fs::write(path, contents).with_context(|| format!("write {:?}", path));
    };
    let mut temp_name = std::ffi::OsString::from(".");
    temp_name.push(target.file_name().context("path without a file name")?);
    temp_name.push(format!(".{}.tmp", std::process::id()));
    let temp_path = target.with_file_name(temp_name);

    let written = fs::write(&temp_path, contents)
        .with_context(|| format!("write temporary file {:?}", temp_path))
        .and_then(|_| match fs::metadata(&target) {
            Ok(metadata) => fs::set_permissions(&temp_path, metadata.permissions())
                .with_context(|| format!("copy permissions of {:?}", target)),
            Err(_) => Ok(()),
        })
        .and_then(|_| {
            fs::rename(&temp_path, &target)
                .with_context(|| format!("rename {:?} to {:?}", temp_path, target))
        });
    if written.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    written
}

/// The file that renaming a new file onto replaces just as `fs::write` would
/// overwrite it: an existing regular file, reached through any symlinks, that
/// can be opened for writing and has no other hard links. Otherwise `None`:
/// `fs::write` creates a missing file, also behind a dangling symlink,
/// refuses one it can't write, and keeps its hard links.
fn replaceable_target(path: &Path) -> Option<PathBuf> {
    let target = fs::canonicalize(path).ok()?;
    let metadata = fs::metadata(&target).ok()?;
    if !metadata.is_file() || OpenOptions::new().write(true).open(&target).is_err() {
        return None;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if metadata.nlink() > 1 {
            return None;
        }
    }
    Some(target)
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::*;

    #[test]
    fn creates_a_new_file_and_leaves_no_temporary_file() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("doc.md");
        replace_file(&path, "new").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "new");
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
    }

    #[test]
    fn replaces_an_existing_file() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("doc.md");
        fs::write(&path, "old and longer").unwrap();
        replace_file(&path, "new").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "new");
    }

    #[cfg(unix)]
    #[test]
    fn keeps_the_permissions_of_the_existing_file() {
        use std::os::unix::fs::PermissionsExt;

        let dir = TempDir::new().unwrap();
        let path = dir.path().join("doc.md");
        fs::write(&path, "old").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o640)).unwrap();
        replace_file(&path, "new").unwrap();
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o640
        );
    }

    #[cfg(unix)]
    #[test]
    fn refuses_a_file_it_cannot_write_like_fs_write() {
        use std::os::unix::fs::PermissionsExt;

        let dir = TempDir::new().unwrap();
        let path = dir.path().join("doc.md");
        fs::write(&path, "old").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o444)).unwrap();
        if OpenOptions::new().write(true).open(&path).is_ok() {
            return; // root can write anyway
        }
        assert!(replace_file(&path, "new").is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), "old");
    }

    #[cfg(unix)]
    #[test]
    fn writes_through_a_hard_link() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("doc.md");
        let other = dir.path().join("other.md");
        fs::write(&path, "old").unwrap();
        fs::hard_link(&path, &other).unwrap();
        replace_file(&path, "new").unwrap();
        assert_eq!(fs::read_to_string(&other).unwrap(), "new");
    }

    #[cfg(unix)]
    #[test]
    fn creates_the_target_of_a_dangling_symlink() {
        let dir = TempDir::new().unwrap();
        let target = dir.path().join("target.md");
        let link = dir.path().join("link.md");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        replace_file(&link, "new").unwrap();
        assert!(
            fs::symlink_metadata(&link)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_eq!(fs::read_to_string(&target).unwrap(), "new");
    }

    #[cfg(unix)]
    #[test]
    fn writes_through_a_symlink() {
        let dir = TempDir::new().unwrap();
        let target = dir.path().join("target.md");
        let link = dir.path().join("link.md");
        fs::write(&target, "old").unwrap();
        std::os::unix::fs::symlink(&target, &link).unwrap();
        replace_file(&link, "new").unwrap();
        assert!(
            fs::symlink_metadata(&link)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_eq!(fs::read_to_string(&target).unwrap(), "new");
    }
}
