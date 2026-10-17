/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use std::fs;
use std::path::Path;

use anyhow::Context;
use anyhow::Result;

/// Writes `contents` to `path` through a hidden temporary file next to it,
/// renamed into place, so that a document running at the same time (see
/// `--jobs`) reads either the old or the new contents, never a half-written
/// file. Keeps the permissions of an existing file and writes through a
/// symlink, like [`fs::write`].
pub(crate) fn replace_file(path: &Path, contents: impl AsRef<[u8]>) -> Result<()> {
    let target = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
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
