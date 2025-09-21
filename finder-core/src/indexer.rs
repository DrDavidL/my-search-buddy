use crate::scanner::FileMeta;
use crate::schema::build_schema;
use anyhow::{anyhow, Context, Result};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex, RwLock};
use tantivy::collector::TopDocs;
use tantivy::directory::MmapDirectory;
use tantivy::merge_policy::LogMergePolicy;
use tantivy::query::TermQuery;
use tantivy::schema::{Field, IndexRecordOption, Schema, TantivyDocument, Value};
use tantivy::{DocAddress, Index, IndexReader, IndexWriter, Term};

const DEFAULT_WRITER_MEM_BYTES: usize = 384 * 1024 * 1024;
const DEFAULT_WRITER_THREADS: usize = 0; // will be replaced with num_cpus at runtime

#[derive(Debug, Clone, Copy)]
pub struct IndexSettings {
    pub writer_threads: usize,
    pub writer_heap_bytes: usize,
}

impl Default for IndexSettings {
    fn default() -> Self {
        Self {
            writer_threads: DEFAULT_WRITER_THREADS,
            writer_heap_bytes: DEFAULT_WRITER_MEM_BYTES,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IndexUpdate {
    Added,
    Updated,
    Skipped,
}

#[derive(Clone)]
pub(crate) struct IndexFields {
    pub path: Field,
    pub name: Field,
    pub name_raw: Field,
    pub ext: Field,
    pub identity: Field,
    pub mtime: Field,
    pub size: Field,
    pub inode: Field,
    pub dev: Field,
    pub content: Field,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IndexedDocument {
    pub path: String,
    pub mtime: i64,
    pub size: u64,
}

impl IndexedDocument {
    pub fn from_meta(meta: &FileMeta) -> Self {
        Self {
            path: meta.path.clone(),
            mtime: meta.modified_at,
            size: meta.size,
        }
    }

    pub fn matches_meta(&self, meta: &FileMeta) -> bool {
        self.mtime == meta.modified_at && self.size == meta.size && self.path == meta.path
    }
}

struct IndexHandle {
    index: Index,
    reader: IndexReader,
    writer: Mutex<IndexWriter>,
    fields: IndexFields,
}

static INDEX_STATE: Lazy<RwLock<Option<Arc<IndexHandle>>>> = Lazy::new(|| RwLock::new(None));
static INDEX_SETTINGS: Lazy<RwLock<IndexSettings>> =
    Lazy::new(|| RwLock::new(IndexSettings::default()));

pub fn configure(settings: IndexSettings) {
    let mut guard = INDEX_SETTINGS.write().unwrap();
    *guard = settings;
}

pub fn init_index(path: &str) -> Result<()> {
    let schema = build_schema();
    let path = Path::new(path);
    fs::create_dir_all(path)
        .with_context(|| format!("failed creating index directory: {}", path.display()))?;

    let directory = MmapDirectory::open(path)
        .with_context(|| format!("failed opening mmap directory: {}", path.display()))?;
    let index = Index::open_or_create(directory, schema.clone())
        .context("failed to open or create tantivy index")?;

    let reader = index.reader().context("failed to create tantivy reader")?;

    let settings = current_settings();
    let threads = if settings.writer_threads == 0 {
        num_cpus::get().max(1)
    } else {
        settings.writer_threads.max(1)
    };
    let writer = index
        .writer_with_num_threads(threads, settings.writer_heap_bytes.max(16 * 1024 * 1024))
        .context("failed to create tantivy writer")?;

    let mut merge_policy = LogMergePolicy::default();
    merge_policy.set_level_log_size(1.2);
    writer.set_merge_policy(Box::new(merge_policy));

    let fields = IndexFields {
        path: field(&schema, "path")?,
        name: field(&schema, "name")?,
        name_raw: field(&schema, "name_raw")?,
        ext: field(&schema, "ext")?,
        identity: field(&schema, "identity")?,
        mtime: field(&schema, "mtime")?,
        size: field(&schema, "size")?,
        inode: field(&schema, "inode")?,
        dev: field(&schema, "dev")?,
        content: field(&schema, "content")?,
    };

    let handle = Arc::new(IndexHandle {
        index,
        reader,
        writer: Mutex::new(writer),
        fields,
    });

    let mut guard = INDEX_STATE.write().unwrap();
    *guard = Some(handle);

    Ok(())
}

pub fn add_or_update_file(
    meta: FileMeta,
    content_opt: Option<String>,
    force_reindex: bool,
) -> Result<IndexUpdate> {
    let handle = index_handle()?;
    let identity = meta.identity();

    let mut update = IndexUpdate::Added;

    if !force_reindex {
        if let Some(existing) = find_existing(&handle, &identity)? {
            if existing.matches_meta(&meta) {
                return Ok(IndexUpdate::Skipped);
            }
            update = IndexUpdate::Updated;
        }
    }

    {
        let writer = handle.writer.lock().expect("index writer mutex poisoned");

        let identity_term = Term::from_field_text(handle.fields.identity, &identity);
        writer.delete_term(identity_term);

        let mut doc = TantivyDocument::new();
        doc.add_text(handle.fields.path, meta.path.clone());
        doc.add_text(handle.fields.name, meta.name.clone());
        doc.add_text(handle.fields.name_raw, meta.name);
        if let Some(ext) = meta.ext.clone() {
            doc.add_text(handle.fields.ext, ext);
        }
        doc.add_text(handle.fields.identity, identity);
        doc.add_i64(handle.fields.mtime, meta.modified_at);
        doc.add_u64(handle.fields.size, meta.size);
        doc.add_u64(handle.fields.inode, meta.inode);
        doc.add_u64(handle.fields.dev, meta.dev);
        if let Some(content) = content_opt {
            if !content.is_empty() {
                doc.add_text(handle.fields.content, content);
            }
        }

        writer
            .add_document(doc)
            .context("failed adding document to index")?;
    }

    Ok(update)
}

pub fn commit() -> Result<()> {
    let handle = index_handle()?;
    {
        let mut writer = handle.writer.lock().expect("index writer mutex poisoned");
        writer.commit().context("tantivy commit failed")?;
    }
    handle
        .reader
        .reload()
        .context("failed to reload index reader")?;
    Ok(())
}

pub fn close() {
    let mut guard = INDEX_STATE.write().unwrap();
    *guard = None;
}

fn index_handle() -> Result<Arc<IndexHandle>> {
    INDEX_STATE
        .read()
        .unwrap()
        .clone()
        .context("index not initialized")
}

fn field(schema: &Schema, name: &str) -> Result<Field> {
    schema
        .get_field(name)
        .with_context(|| format!("schema missing expected field: {}", name))
}

pub(crate) fn index() -> Result<Index> {
    Ok(index_handle()?.index.clone())
}

pub(crate) fn reader() -> Result<IndexReader> {
    Ok(index_handle()?.reader.clone())
}

pub(crate) fn fields() -> Result<IndexFields> {
    Ok(index_handle()?.fields.clone())
}

fn extract_indexed_document(
    doc: &TantivyDocument,
    fields: &IndexFields,
) -> Result<IndexedDocument> {
    let path = doc
        .get_first(fields.path)
        .and_then(|value| value.as_str())
        .ok_or_else(|| anyhow!("existing document missing path"))?
        .to_string();

    let mtime = doc
        .get_first(fields.mtime)
        .and_then(|value| value.as_i64())
        .ok_or_else(|| anyhow!("existing document missing mtime"))?;

    let size = doc
        .get_first(fields.size)
        .and_then(|value| value.as_u64())
        .ok_or_else(|| anyhow!("existing document missing size"))?;

    Ok(IndexedDocument { path, mtime, size })
}

fn find_existing(handle: &IndexHandle, identity: &str) -> Result<Option<IndexedDocument>> {
    let searcher = handle.reader.searcher();
    let term = Term::from_field_text(handle.fields.identity, identity);
    let query = TermQuery::new(term, IndexRecordOption::Basic);
    let top_docs = searcher
        .search(&query, &TopDocs::with_limit(1))
        .context("term query failed")?;

    let Some((_score, address)) = top_docs.into_iter().next() else {
        return Ok(None);
    };

    let doc: TantivyDocument = searcher
        .doc(address)
        .context("failed to fetch existing doc")?;

    let existing = extract_indexed_document(&doc, &handle.fields)?;
    Ok(Some(existing))
}

pub fn load_index_state() -> Result<HashMap<String, IndexedDocument>> {
    let handle = index_handle()?;
    let searcher = handle.reader.searcher();
    let mut state = HashMap::new();

    for (segment_ord, segment_reader) in searcher.segment_readers().iter().enumerate() {
        for doc_id in segment_reader.doc_ids_alive() {
            let address = DocAddress {
                segment_ord: segment_ord as u32,
                doc_id,
            };
            let doc: TantivyDocument = searcher.doc(address).with_context(|| {
                format!(
                    "failed to fetch existing doc for segment {} doc {}",
                    segment_ord, doc_id
                )
            })?;

            let identity = doc
                .get_first(handle.fields.identity)
                .and_then(|value| value.as_str())
                .ok_or_else(|| anyhow!("indexed document missing identity"))?
                .to_string();

            let metadata = extract_indexed_document(&doc, &handle.fields)?;
            state.insert(identity, metadata);
        }
    }

    Ok(state)
}

fn current_settings() -> IndexSettings {
    *INDEX_SETTINGS.read().unwrap()
}

#[cfg(test)]
mod tests {
    use super::{add_or_update_file, commit, init_index, IndexUpdate};
    use crate::scanner::FileMeta;
    use tempfile::tempdir;

    #[test]
    fn initializes_and_writes_documents() {
        let _guard = crate::TEST_MUTEX.lock().unwrap();
        let dir = tempdir().unwrap();
        init_index(dir.path().to_str().unwrap()).unwrap();

        let meta = FileMeta {
            path: dir.path().join("file.txt").to_string_lossy().to_string(),
            name: "file.txt".into(),
            ext: Some("txt".into()),
            modified_at: 123,
            size: 42,
            inode: 1,
            dev: 1,
        };

        assert!(matches!(
            add_or_update_file(meta, Some("hello world".into()), false).unwrap(),
            IndexUpdate::Added
        ));
        commit().unwrap();

        let reader = super::reader().unwrap();
        reader.reload().unwrap();
        let searcher = reader.searcher();
        assert_eq!(searcher.num_docs(), 1);
    }
}
