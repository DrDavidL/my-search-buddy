use crate::indexer;
use anyhow::{Context, Result};
use globset::{GlobBuilder, GlobMatcher};
use regex::escape;
use std::cmp::Ordering;
use tantivy::collector::TopDocs;
use tantivy::query::{BooleanQuery, BoostQuery, Occur, Query, QueryParser, RegexQuery};
use tantivy::schema::{Field, TantivyDocument, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SearchDomain {
    Name,
    Content,
    Both,
}

impl Default for SearchDomain {
    fn default() -> Self {
        SearchDomain::Both
    }
}

#[derive(Debug, Clone)]
pub struct SearchQuery {
    pub term: String,
    pub search_in: SearchDomain,
    pub path_glob: Option<String>,
    pub limit: usize,
}

impl Default for SearchQuery {
    fn default() -> Self {
        SearchQuery {
            term: String::new(),
            search_in: SearchDomain::Both,
            path_glob: None,
            limit: 50,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct SearchHit {
    pub path: String,
    pub name: String,
    pub score: f32,
    pub modified_at: Option<i64>,
    pub size: Option<u64>,
}

pub fn search(query: SearchQuery) -> Result<Vec<SearchHit>> {
    let trimmed = query.term.trim();
    if trimmed.is_empty() {
        return Ok(Vec::new());
    }

    let index = indexer::index().context("index not initialized")?;
    let reader = indexer::reader().context("reader not available")?;
    let fields = indexer::fields()?;

    let mut search_fields = Vec::new();
    match query.search_in {
        SearchDomain::Name => search_fields.push(fields.name),
        SearchDomain::Content => search_fields.push(fields.content),
        SearchDomain::Both => {
            search_fields.push(fields.name);
            search_fields.push(fields.content);
        }
    }

    let mut parser = QueryParser::for_index(&index, search_fields.clone());
    if matches!(query.search_in, SearchDomain::Name | SearchDomain::Both) {
        parser.set_field_boost(fields.name, 2.0);
    }
    parser.set_conjunction_by_default();

    let parsed_query = parser
        .parse_query(trimmed)
        .with_context(|| format!("failed to parse search query: {}", trimmed))?;

    let mut subqueries: Vec<(Occur, Box<dyn Query>)> = Vec::new();
    let main_query: Box<dyn Query> =
        if matches!(query.search_in, SearchDomain::Name | SearchDomain::Both) {
            Box::new(BoostQuery::new(parsed_query, 1.5))
        } else {
            parsed_query
        };
    subqueries.push((Occur::Should, main_query));

    if matches!(query.search_in, SearchDomain::Name | SearchDomain::Both)
        && !trimmed.is_empty()
        && !trimmed.contains(char::is_whitespace)
    {
        let escaped = escape(trimmed);
        let pattern = format!("^{}.*", escaped);
        if let Ok(regex_query) = RegexQuery::from_pattern(&pattern, fields.name_raw) {
            let boosted = BoostQuery::new(Box::new(regex_query), 3.0);
            subqueries.push((Occur::Should, Box::new(boosted)));
        }
    }

    let combined: Box<dyn Query> = if subqueries.len() == 1 {
        subqueries.into_iter().next().unwrap().1
    } else {
        Box::new(BooleanQuery::new(subqueries))
    };

    let searcher = reader.searcher();
    let top_docs = searcher
        .search(&combined, &TopDocs::with_limit(query.limit.max(1)))
        .context("tantivy search execution failed")?;

    let glob_matcher = build_glob_matcher(query.path_glob.as_deref())?;

    let mut hits = Vec::with_capacity(top_docs.len());
    for (score, address) in top_docs {
        let doc = searcher
            .doc(address)
            .context("failed to fetch stored document")?;

        let path = field_text(&doc, fields.path)
            .unwrap_or_default()
            .to_string();
        if let Some(ref matcher) = glob_matcher {
            if !matcher.is_match(&path) {
                continue;
            }
        }

        let name = field_text(&doc, fields.name)
            .unwrap_or_default()
            .to_string();
        let modified_at = field_i64(&doc, fields.mtime);
        let size = field_u64(&doc, fields.size);

        hits.push(SearchHit {
            path,
            name,
            score,
            modified_at,
            size,
        });
    }

    hits.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(Ordering::Equal)
            .then_with(|| b.modified_at.unwrap_or(0).cmp(&a.modified_at.unwrap_or(0)))
    });

    Ok(hits)
}

fn build_glob_matcher(pattern: Option<&str>) -> Result<Option<GlobMatcher>> {
    let Some(raw) = pattern.map(str::trim).filter(|p| !p.is_empty()) else {
        return Ok(None);
    };

    let glob = GlobBuilder::new(raw)
        .case_insensitive(true)
        .build()
        .with_context(|| format!("invalid glob pattern: {}", raw))?;

    Ok(Some(glob.compile_matcher()))
}

fn field_text(doc: &TantivyDocument, field: Field) -> Option<&str> {
    doc.get_first(field).and_then(|value| value.as_str())
}

fn field_i64(doc: &TantivyDocument, field: Field) -> Option<i64> {
    doc.get_first(field).and_then(|value| value.as_i64())
}

fn field_u64(doc: &TantivyDocument, field: Field) -> Option<u64> {
    doc.get_first(field).and_then(|value| value.as_u64())
}

#[cfg(test)]
mod tests {
    use super::{search, SearchDomain, SearchQuery};
    use crate::scanner::FileMeta;
    use crate::{add_or_update_file, commit, init_index};
    use std::sync::atomic::{AtomicU64, Ordering};
    use tempfile::tempdir;

    static NEXT_INODE: AtomicU64 = AtomicU64::new(1);

    fn meta(path: &str, name: &str, ext: Option<&str>) -> FileMeta {
        let inode = NEXT_INODE.fetch_add(1, Ordering::Relaxed);
        FileMeta {
            path: path.into(),
            name: name.into(),
            ext: ext.map(|e| e.into()),
            modified_at: 100,
            size: 42,
            inode,
            dev: 1,
        }
    }

    #[test]
    fn searches_content_and_name() {
        let _guard = crate::TEST_MUTEX.lock().unwrap();
        let dir = tempdir().unwrap();
        init_index(dir.path().to_str().unwrap()).unwrap();

        let _ = add_or_update_file(
            meta(
                dir.path().join("docs/note.md").to_str().unwrap(),
                "note.md",
                Some("md"),
            ),
            Some("rust search prototype".into()),
            false,
        )
        .unwrap();
        let _ = add_or_update_file(
            meta(
                dir.path().join("src/main.rs").to_str().unwrap(),
                "main.rs",
                Some("rs"),
            ),
            Some("fn main() {}".into()),
            false,
        )
        .unwrap();
        commit().unwrap();

        let content_hits = search(SearchQuery {
            term: "rust".into(),
            search_in: SearchDomain::Content,
            path_glob: None,
            limit: 10,
        })
        .unwrap();
        assert_eq!(content_hits.len(), 1);
        assert!(content_hits[0].path.ends_with("docs/note.md"));

        let name_hits = search(SearchQuery {
            term: "main".into(),
            search_in: SearchDomain::Name,
            path_glob: None,
            limit: 10,
        })
        .unwrap();
        assert_eq!(name_hits.len(), 1);
        assert!(name_hits[0].path.ends_with("src/main.rs"));
    }

    #[test]
    fn applies_glob_filter() {
        let _guard = crate::TEST_MUTEX.lock().unwrap();
        let dir = tempdir().unwrap();
        init_index(dir.path().to_str().unwrap()).unwrap();

        let _ = add_or_update_file(
            meta(
                dir.path().join("readme.md").to_str().unwrap(),
                "readme.md",
                Some("md"),
            ),
            Some("introduction".into()),
            false,
        )
        .unwrap();
        let _ = add_or_update_file(
            meta(
                dir.path().join("docs/todo.txt").to_str().unwrap(),
                "todo.txt",
                Some("txt"),
            ),
            Some("introduction".into()),
            false,
        )
        .unwrap();
        commit().unwrap();

        let hits = search(SearchQuery {
            term: "introduction".into(),
            search_in: SearchDomain::Both,
            path_glob: Some("**/*.md".into()),
            limit: 10,
        })
        .unwrap();

        assert_eq!(hits.len(), 1);
        assert!(hits[0].path.ends_with("readme.md"));
    }
}
