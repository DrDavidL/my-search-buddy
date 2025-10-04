use crate::query::{SearchDomain, SearchQuery};
use crate::{add_or_update_file, close_index, commit, init_index, search, FileMeta, IndexUpdate};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;

#[repr(C)]
pub struct FCFileMeta {
    pub path: *const c_char,
    pub name: *const c_char,
    pub ext: *const c_char,
    pub mtime: i64,
    pub size: u64,
    pub inode: u64,
    pub dev: u64,
}

#[repr(C)]
pub struct FCQuery {
    pub q: *const c_char,
    pub glob: *const c_char,
    pub scope: c_int,
    pub limit: c_int,
}

#[repr(C)]
pub struct FCHit {
    pub path: *mut c_char,
    pub name: *mut c_char,
    pub mtime: i64,
    pub size: u64,
    pub score: f32,
}

#[repr(C)]
pub struct FCResults {
    pub hits: *mut FCHit,
    pub count: c_int,
}

#[no_mangle]
pub extern "C" fn fc_init_index(path: *const c_char) -> bool {
    let Some(path_str) = to_string(path) else {
        eprintln!("[ffi] fc_init_index called with null path");
        return false;
    };

    match init_index(&path_str) {
        Ok(()) => true,
        Err(err) => {
            eprintln!("[ffi] init_index failed: {err}");
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn fc_close_index() {
    close_index();
}

#[no_mangle]
pub extern "C" fn fc_add_or_update(meta: *const FCFileMeta, content: *const c_char) -> bool {
    let Some(file_meta) = file_meta_from_ffi(meta) else {
        eprintln!("[ffi] fc_add_or_update received invalid meta");
        return false;
    };
    let content_opt = to_string(content);

    match add_or_update_file(file_meta, content_opt, false) {
        Ok(IndexUpdate::Added | IndexUpdate::Updated | IndexUpdate::Skipped) => true,
        Err(err) => {
            eprintln!("[ffi] add_or_update_file failed: {err}");
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn fc_should_reindex(meta: *const FCFileMeta) -> bool {
    let Some(file_meta) = file_meta_from_ffi(meta) else {
        eprintln!("[ffi] fc_should_reindex received invalid meta");
        return false;
    };

    match crate::should_reindex(&file_meta) {
        Ok(should) => should,
        Err(err) => {
            eprintln!("[ffi] should_reindex failed: {err}");
            true
        }
    }
}

#[no_mangle]
pub extern "C" fn fc_commit_and_refresh() -> bool {
    match commit() {
        Ok(()) => true,
        Err(err) => {
            eprintln!("[ffi] commit failed: {err}");
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn fc_search(query: *const FCQuery) -> FCResults {
    let Some(query_ref) = (unsafe { query.as_ref() }) else {
        eprintln!("[ffi] fc_search received null query pointer");
        return FCResults {
            hits: ptr::null_mut(),
            count: 0,
        };
    };

    let term = to_string(query_ref.q).unwrap_or_default();
    let glob = to_string(query_ref.glob);
    let scope = match query_ref.scope {
        0 => SearchDomain::Name,
        1 => SearchDomain::Content,
        2 => SearchDomain::Both,
        _ => SearchDomain::Both,
    };
    let limit = if query_ref.limit <= 0 {
        50
    } else {
        query_ref.limit as usize
    };

    let search_query = SearchQuery {
        term,
        search_in: scope,
        path_glob: glob,
        limit,
    };

    let hits = match search(search_query) {
        Ok(results) => results,
        Err(err) => {
            eprintln!("[ffi] search failed: {err}");
            return FCResults {
                hits: ptr::null_mut(),
                count: 0,
            };
        }
    };

    if hits.is_empty() {
        return FCResults {
            hits: ptr::null_mut(),
            count: 0,
        };
    }

    let mut ffi_hits = Vec::with_capacity(hits.len());

    for hit in hits {
        match (CString::new(hit.path), CString::new(hit.name)) {
            (Ok(path_cstr), Ok(name_cstr)) => {
                let path_ptr = path_cstr.into_raw();
                let name_ptr = name_cstr.into_raw();
                ffi_hits.push(FCHit {
                    path: path_ptr,
                    name: name_ptr,
                    mtime: hit.modified_at.unwrap_or(0),
                    size: hit.size.unwrap_or(0),
                    score: hit.score,
                });
            }
            _ => {
                eprintln!("[ffi] encountered string with interior NUL; skipping hit");
            }
        }
    }

    if ffi_hits.is_empty() {
        return FCResults {
            hits: ptr::null_mut(),
            count: 0,
        };
    }

    let mut boxed = ffi_hits.into_boxed_slice();
    let count = boxed.len() as c_int;
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);

    FCResults { hits: ptr, count }
}

#[no_mangle]
pub extern "C" fn fc_free_results(results: *mut FCResults) {
    if results.is_null() {
        return;
    }

    let results_ref = unsafe { &mut *results };

    // Guard against double-free by checking both conditions
    if results_ref.hits.is_null() || results_ref.count <= 0 {
        results_ref.hits = ptr::null_mut();
        results_ref.count = 0;
        return;
    }

    let count = results_ref.count as usize;
    let hits_ptr = results_ref.hits;

    // Immediately null out to prevent double-free
    results_ref.hits = ptr::null_mut();
    results_ref.count = 0;

    // Now safely free the memory
    let slice_ptr = ptr::slice_from_raw_parts_mut(hits_ptr, count);
    let boxed: Box<[FCHit]> = unsafe { Box::from_raw(slice_ptr) };

    for hit in boxed.into_vec() {
        if !hit.path.is_null() {
            unsafe {
                drop(CString::from_raw(hit.path));
            }
        }
        if !hit.name.is_null() {
            unsafe {
                drop(CString::from_raw(hit.name));
            }
        }
    }
}

fn to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        None
    } else {
        unsafe { Some(CStr::from_ptr(ptr).to_string_lossy().into_owned()) }
    }
}

fn file_meta_from_ffi(meta: *const FCFileMeta) -> Option<FileMeta> {
    let meta_ref = unsafe { meta.as_ref() }?;

    let path = to_string(meta_ref.path)?;
    let name = to_string(meta_ref.name)?;
    let ext = to_string(meta_ref.ext).and_then(|s| if s.is_empty() { None } else { Some(s) });

    Some(FileMeta {
        path,
        name,
        ext,
        modified_at: meta_ref.mtime,
        size: meta_ref.size,
        inode: meta_ref.inode,
        dev: meta_ref.dev,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::TEST_MUTEX;
    use std::ffi::CString;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn ffi_roundtrip_search() {
        let _guard = TEST_MUTEX.lock().unwrap();

        let dir = tempdir().unwrap();
        let index_dir = CString::new(dir.path().to_str().unwrap()).unwrap();
        assert!(fc_init_index(index_dir.as_ptr()));

        let file_path = dir.path().join("hello.txt");
        fs::write(&file_path, "hello world").unwrap();

        let path_c = CString::new(file_path.to_str().unwrap()).unwrap();
        let name_c = CString::new("hello.txt").unwrap();
        let ext_c = CString::new("txt").unwrap();
        let content_c = CString::new("hello world").unwrap();

        let meta = FCFileMeta {
            path: path_c.as_ptr(),
            name: name_c.as_ptr(),
            ext: ext_c.as_ptr(),
            mtime: 0,
            size: 11,
            inode: 0,
            dev: 0,
        };

        assert!(fc_add_or_update(&meta, content_c.as_ptr()));
        assert!(fc_commit_and_refresh());

        let query_c = CString::new("hello").unwrap();
        let query = FCQuery {
            q: query_c.as_ptr(),
            glob: std::ptr::null(),
            scope: 2,
            limit: 10,
        };

        let mut results = fc_search(&query as *const _);
        assert!(results.count > 0);

        let hits = unsafe { std::slice::from_raw_parts(results.hits, results.count as usize) };
        let first = &hits[0];
        let hit_path = unsafe { CStr::from_ptr(first.path) }.to_str().unwrap();
        let hit_name = unsafe { CStr::from_ptr(first.name) }.to_str().unwrap();
        assert_eq!(hit_path, file_path.to_str().unwrap());
        assert_eq!(hit_name, "hello.txt");

        fc_free_results(&mut results as *mut _);
        fc_close_index();
    }
}
