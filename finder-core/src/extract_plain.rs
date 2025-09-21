use anyhow::{Context, Result};
use std::fs;
use std::io::Read;
use std::path::Path;

/// Read up to `size_limit` bytes from a plain-text file and return a UTF-8 string.
/// Returns `Ok(None)` when the file exceeds the limit.
pub fn read_plain_text<P: AsRef<Path>>(path: P, size_limit: usize) -> Result<Option<String>> {
    let path = path.as_ref();
    let metadata = fs::metadata(path).with_context(|| {
        format!(
            "failed to stat file for plain text extraction: {}",
            path.display()
        )
    })?;

    if metadata.len() > size_limit as u64 {
        return Ok(None);
    }

    let mut file = fs::File::open(path).with_context(|| {
        format!(
            "failed to open file for plain text extraction: {}",
            path.display()
        )
    })?;
    let mut buffer = Vec::with_capacity(metadata.len() as usize);
    file.by_ref()
        .take(size_limit as u64)
        .read_to_end(&mut buffer)
        .with_context(|| {
            format!(
                "failed reading file for plain text extraction: {}",
                path.display()
            )
        })?;

    if buffer.is_empty() {
        return Ok(Some(String::new()));
    }

    match String::from_utf8(buffer) {
        Ok(text) => Ok(Some(text)),
        Err(err) => {
            let lossy = err.into_bytes();
            Ok(Some(String::from_utf8_lossy(&lossy).into_owned()))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::read_plain_text;
    use std::char::REPLACEMENT_CHARACTER;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn reads_small_utf8_file() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("hello.txt");
        fs::write(&file_path, "hello world").unwrap();

        let text = read_plain_text(&file_path, 1024).unwrap();
        assert_eq!(text.as_deref(), Some("hello world"));
    }

    #[test]
    fn returns_none_when_too_large() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("large.txt");
        fs::write(&file_path, vec![b'x'; 10]).unwrap();

        let text = read_plain_text(&file_path, 5).unwrap();
        assert!(text.is_none());
    }

    #[test]
    fn falls_back_to_lossy_decoding() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("binary.bin");
        let bytes = vec![0xf0, 0x9f, 0x92, 0xa9, 0xff];
        fs::write(&file_path, &bytes).unwrap();

        let text = read_plain_text(&file_path, 1024).unwrap().unwrap();
        assert!(text.contains(REPLACEMENT_CHARACTER));
    }
}
