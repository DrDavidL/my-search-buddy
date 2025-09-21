use anyhow::Result;
use ignore::WalkBuilder;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FileMeta {
    pub path: String,
    pub name: String,
    pub ext: Option<String>,
    pub modified_at: i64,
    pub size: u64,
    pub inode: u64,
    pub dev: u64,
}

impl FileMeta {
    /// Unique identifier for the file, preferring inode/dev when available and
    /// falling back to the full path when running on filesystems without those.
    pub fn identity(&self) -> String {
        if self.inode != 0 || self.dev != 0 {
            format!("{}:{}", self.dev, self.inode)
        } else {
            format!("path:{}", self.path)
        }
    }
}

const SKIP_DIR_NAMES: &[&str] = &[".git", "Library", "node_modules", ".Trash"];

/// Scan the provided root directory, respecting ignore files, and return discovered file metadata.
pub fn scan_root<P: AsRef<Path>>(root: P) -> Result<Vec<FileMeta>> {
    let root = root.as_ref();
    let mut builder = WalkBuilder::new(root);
    builder.standard_filters(true);
    builder.filter_entry(|entry| {
        if entry.depth() == 0 {
            return true;
        }
        let name = entry.file_name().to_string_lossy();
        let is_dir = entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false);
        if is_dir {
            if SKIP_DIR_NAMES.contains(&name.as_ref()) {
                return false;
            }
            if name.starts_with('.') {
                return false;
            }
        }
        true
    });

    let walker = builder.build();

    let paths: Vec<PathBuf> = walker
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.file_type().map(|ft| ft.is_file()).unwrap_or(false))
        .map(|entry| entry.into_path())
        .collect();

    let mut entries: Vec<_> = paths
        .par_iter()
        .filter_map(|path| build_meta(path).ok())
        .collect();

    entries.par_sort_by(|a, b| a.path.cmp(&b.path));
    Ok(entries)
}

fn build_meta(path: &Path) -> Result<FileMeta> {
    let metadata = fs::symlink_metadata(path)?;

    let name = path
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let ext = path
        .extension()
        .map(|s| s.to_string_lossy().to_string())
        .filter(|s| !s.is_empty());

    let modified_at = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|dur| dur.as_secs() as i64)
        .unwrap_or_default();

    #[cfg(unix)]
    use std::os::unix::fs::MetadataExt;

    #[cfg(unix)]
    let (inode, dev) = (metadata.ino(), metadata.dev());

    #[cfg(not(unix))]
    let (inode, dev) = (0, 0);

    Ok(FileMeta {
        path: path.to_string_lossy().to_string(),
        name,
        ext,
        modified_at,
        size: metadata.len(),
        inode,
        dev,
    })
}

#[cfg(test)]
mod tests {
    use super::scan_root;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn collects_file_metadata() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::write(root.join("a.txt"), "hello").unwrap();
        fs::create_dir(root.join("sub")).unwrap();
        fs::write(root.join("sub/b.md"), "world").unwrap();

        let files = scan_root(root).unwrap();
        assert_eq!(files.len(), 2);
        let names: Vec<_> = files.iter().map(|f| f.name.as_str()).collect();
        assert!(names.contains(&"a.txt"));
        assert!(names.contains(&"b.md"));
    }
}
