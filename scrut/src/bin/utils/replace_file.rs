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
    let contents = contents.as_ref();
    let write_in_place = || fs::write(path, contents).with_context(|| format!("write {:?}", path));
    let Some(target) = replaceable_target(path) else {
        return write_in_place();
    };
    let mut temp_name = std::ffi::OsString::from(".");
    temp_name.push(target.file_name().context("path without a file name")?);
    temp_name.push(format!(".{}.tmp", std::process::id()));
    let temp_path = target.with_file_name(temp_name);

    // a folder new files can't be created in, or a document someone else
    // owns, which renaming would hand over to us
    if fs::write(&temp_path, contents).is_err() {
        let _ = fs::remove_file(&temp_path);
        return write_in_place();
    }
    if !same_owner(&temp_path, &target) {
        let _ = fs::remove_file(&temp_path);
        return write_in_place();
    }

    let replaced = fs::metadata(&target)
        .and_then(|metadata| fs::set_permissions(&temp_path, metadata.permissions()))
        .with_context(|| format!("copy permissions of {:?}", target))
        .and_then(|_| {
            fs::rename(&temp_path, &target)
                .with_context(|| format!("rename {:?} to {:?}", temp_path, target))
        });
    if replaced.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    replaced
}

/// Whether both files have the same owner and group
#[cfg(unix)]
fn same_owner(a: &Path, b: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;

    match (fs::metadata(a), fs::metadata(b)) {
        (Ok(a), Ok(b)) => a.uid() == b.uid() && a.gid() == b.gid(),
        _ => false,
    }
}

#[cfg(not(unix))]
fn same_owner(_: &Path, _: &Path) -> bool {
    true
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
    fn writes_a_document_in_a_folder_it_cannot_create_files_in() {
        use std::os::unix::fs::PermissionsExt;

        let dir = TempDir::new().unwrap();
        let folder = dir.path().join("read-only");
        fs::create_dir(&folder).unwrap();
        let path = folder.join("doc.md");
        fs::write(&path, "old").unwrap();
        fs::set_permissions(&folder, fs::Permissions::from_mode(0o555)).unwrap();
        let can_create = fs::write(folder.join("probe"), "").is_ok();
        let result = replace_file(&path, "new");
        fs::set_permissions(&folder, fs::Permissions::from_mode(0o755)).unwrap();
        if can_create {
            return; // root can create files anyway
        }
        result.unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "new");
        assert_eq!(fs::read_dir(&folder).unwrap().count(), 1);
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
