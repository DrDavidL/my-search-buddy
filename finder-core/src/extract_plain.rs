use anyhow::{Context, Result};
use std::fs;
use std::io::Read;
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlainTextExtraction {
    pub content: Option<String>,
    pub bytes_read: usize,
    pub was_binary: bool,
}

/// Read up to `size_limit` bytes from a plain-text file, sniffing the first
/// `sniff_bytes` to short-circuit obvious binaries. Returns the extracted text
/// (when available), the number of bytes read, and whether the file was treated
/// as binary.
pub fn read_plain_text<P: AsRef<Path>>(
    path: P,
    size_limit: usize,
    sniff_bytes: usize,
) -> Result<PlainTextExtraction> {
    let path = path.as_ref();
    let metadata = fs::metadata(path).with_context(|| {
        format!(
            "failed to stat file for plain text extraction: {}",
            path.display()
        )
    })?;

    if metadata.len() > size_limit as u64 {
        return Ok(PlainTextExtraction {
            content: None,
            bytes_read: 0,
            was_binary: false,
        });
    }

    let mut file = fs::File::open(path).with_context(|| {
        format!(
            "failed to open file for plain text extraction: {}",
            path.display()
        )
    })?;

    let max_bytes = metadata.len().min(size_limit as u64) as usize;
    let mut buffer = Vec::with_capacity(max_bytes);

    if sniff_bytes > 0 && max_bytes > 0 {
        let sniff_len = sniff_bytes.min(max_bytes);
        let mut head = vec![0u8; sniff_len];
        let read = file.read(&mut head).with_context(|| {
            format!(
                "failed reading file head for plain text extraction: {}",
                path.display()
            )
        })?;
        head.truncate(read);

        if read == 0 {
            return Ok(PlainTextExtraction {
                content: Some(String::new()),
                bytes_read: 0,
                was_binary: false,
            });
        }

        buffer.extend_from_slice(&head);
        if looks_binary(&head) {
            return Ok(PlainTextExtraction {
                content: None,
                bytes_read: buffer.len(),
                was_binary: true,
            });
        }
    }

    if buffer.len() < max_bytes {
        file.by_ref()
            .take((max_bytes - buffer.len()) as u64)
            .read_to_end(&mut buffer)
            .with_context(|| {
                format!(
                    "failed reading file body for plain text extraction: {}",
                    path.display()
                )
            })?;
    }

    let bytes_read = buffer.len();
    if bytes_read == 0 {
        return Ok(PlainTextExtraction {
            content: Some(String::new()),
            bytes_read,
            was_binary: false,
        });
    }

    let content = match String::from_utf8(buffer) {
        Ok(text) => text,
        Err(err) => {
            let lossy = err.into_bytes();
            String::from_utf8_lossy(&lossy).into_owned()
        }
    };

    Ok(PlainTextExtraction {
        content: Some(content),
        bytes_read,
        was_binary: false,
    })
}

pub fn looks_binary(head: &[u8]) -> bool {
    if head.is_empty() {
        return false;
    }
    if head.iter().any(|&b| b == 0) {
        return true;
    }
    let non_printable = head
        .iter()
        .filter(|&&b| b < 9 || (b > 13 && b < 32))
        .count();
    (non_printable as f32 / head.len() as f32) > 0.10
}

#[cfg(test)]
mod tests {
    use super::{looks_binary, read_plain_text};
    use std::char::REPLACEMENT_CHARACTER;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn reads_small_utf8_file() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("hello.txt");
        fs::write(&file_path, "hello world").unwrap();

        let text = read_plain_text(&file_path, 1024, 4096).unwrap();
        assert_eq!(text.content.as_deref(), Some("hello world"));
        assert_eq!(text.bytes_read, "hello world".len());
        assert!(!text.was_binary);
    }

    #[test]
    fn returns_none_when_too_large() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("large.txt");
        fs::write(&file_path, vec![b'x'; 10]).unwrap();

        let text = read_plain_text(&file_path, 5, 4096).unwrap();
        assert!(text.content.is_none());
        assert_eq!(text.bytes_read, 0);
        assert!(!text.was_binary);
    }

    #[test]
    fn falls_back_to_lossy_decoding() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("binary.bin");
        let bytes = vec![0xf0, 0x9f, 0x92, 0xa9, 0xff];
        fs::write(&file_path, &bytes).unwrap();

        let text = read_plain_text(&file_path, 1024, 4096).unwrap();
        let extracted = text.content.unwrap();
        assert!(extracted.contains(REPLACEMENT_CHARACTER));
        assert_eq!(text.bytes_read, bytes.len());
        assert!(!text.was_binary);
    }

    #[test]
    fn detects_binary_via_sniff() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("bin.dat");
        fs::write(&file_path, b"\x00\x01\x02\x03rest").unwrap();

        let text = read_plain_text(&file_path, 1024, 8).unwrap();
        assert!(text.content.is_none());
        assert!(text.was_binary);
        assert_eq!(text.bytes_read, b"\x00\x01\x02\x03rest".len().min(8));
    }

    #[test]
    fn binary_heuristic_handles_printable_ascii() {
        assert!(!looks_binary(b"Hello, world!"));
        assert!(looks_binary(b"\x00bad"));
    }
}
