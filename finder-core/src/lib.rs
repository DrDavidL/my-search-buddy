mod extract_plain;
mod indexer;
mod query;
mod scanner;
mod schema;

pub use crate::query::{SearchDomain, SearchHit, SearchQuery};
pub use crate::scanner::{scan_root, FileMeta};
pub use crate::schema::build_schema;
pub use extract_plain::read_plain_text;
pub use indexer::{configure as configure_indexer, IndexSettings, IndexUpdate};

#[cfg(test)]
use once_cell::sync::Lazy;
#[cfg(test)]
use std::sync::Mutex;

#[cfg(test)]
pub(crate) static TEST_MUTEX: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

use anyhow::Result;

pub fn init_index(path: &str) -> Result<()> {
    indexer::init_index(path)
}

pub fn add_or_update_file(
    meta: FileMeta,
    content_opt: Option<String>,
    force_reindex: bool,
) -> Result<IndexUpdate> {
    indexer::add_or_update_file(meta, content_opt, force_reindex)
}

pub fn commit() -> Result<()> {
    indexer::commit()
}

pub fn search(q: SearchQuery) -> Result<Vec<SearchHit>> {
    query::search(q)
}
