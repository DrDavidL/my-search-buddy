use std::env;
use std::error::Error;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use finder_core::{
    add_or_update_file, commit, init_index, read_plain_text, scan_root, search, IndexUpdate,
    SearchDomain, SearchQuery,
};

const DEFAULT_INDEX_DIR: &str = "/tmp/finder-index";
const DEFAULT_COMMIT_THRESHOLD: usize = 1000;
const DEFAULT_COMMIT_INTERVAL_MS: u64 = 2_000;
const DEFAULT_MAX_BYTES: u64 = 1_572_864;
const DEFAULT_LIMIT: usize = 50;
const DEFAULT_SKIP_EXT: &str = ".pkg,.dmg,.app";
const BENCH_RUNS: usize = 5;

#[derive(Debug)]
struct Args {
    index_dir: PathBuf,
    roots: Vec<PathBuf>,
    queries: Vec<String>,
    glob: Option<String>,
    commit_every: usize,
    commit_ms: u64,
    limit: usize,
    reindex: bool,
    writer_threads: Option<usize>,
    writer_mem_mb: usize,
    max_bytes: u64,
    skip_exts: Vec<String>,
    scope: SearchDomain,
}

impl Default for Args {
    fn default() -> Self {
        Self {
            index_dir: PathBuf::from(DEFAULT_INDEX_DIR),
            roots: Vec::new(),
            queries: Vec::new(),
            glob: None,
            commit_every: DEFAULT_COMMIT_THRESHOLD,
            commit_ms: DEFAULT_COMMIT_INTERVAL_MS,
            limit: DEFAULT_LIMIT,
            reindex: false,
            writer_threads: None,
            writer_mem_mb: 384,
            max_bytes: DEFAULT_MAX_BYTES,
            skip_exts: parse_exts(DEFAULT_SKIP_EXT),
            scope: SearchDomain::Both,
        }
    }
}

impl Args {
    fn parse() -> Result<Self, String> {
        let mut args = env::args_os();
        let _program = args.next();
        let mut config = Args::default();

        while let Some(arg) = args.next() {
            let arg_str = arg.to_string_lossy();
            match arg_str.as_ref() {
                "--help" | "-h" => {
                    print_usage();
                    std::process::exit(0);
                }
                "--index-dir" => {
                    let value = next_value(&mut args, "--index-dir")?;
                    config.index_dir = PathBuf::from(value);
                }
                "--root" => {
                    let value = next_value(&mut args, "--root")?;
                    config.roots.push(PathBuf::from(value));
                }
                "--q" => {
                    let value = next_value(&mut args, "--q")?;
                    config.queries.push(value.to_string_lossy().to_string());
                }
                "--glob" => {
                    let value = next_value(&mut args, "--glob")?;
                    config.glob = Some(value.to_string_lossy().to_string());
                }
                "--commit-every" => {
                    let value = next_value(&mut args, "--commit-every")?;
                    config.commit_every = parse_usize(&value, "--commit-every")?;
                }
                "--commit-ms" => {
                    let value = next_value(&mut args, "--commit-ms")?;
                    config.commit_ms = parse_u64(&value, "--commit-ms")?;
                }
                "--limit" => {
                    let value = next_value(&mut args, "--limit")?;
                    config.limit = parse_usize(&value, "--limit")?;
                }
                "--reindex" => {
                    config.reindex = true;
                }
                "--threads" => {
                    let value = next_value(&mut args, "--threads")?;
                    let parsed = parse_usize(&value, "--threads")?;
                    config.writer_threads = Some(parsed);
                }
                "--writer-mem-mb" => {
                    let value = next_value(&mut args, "--writer-mem-mb")?;
                    config.writer_mem_mb = parse_usize(&value, "--writer-mem-mb")?;
                }
                "--max-bytes" => {
                    let value = next_value(&mut args, "--max-bytes")?;
                    config.max_bytes = parse_u64(&value, "--max-bytes")?;
                }
                "--skip-ext" => {
                    let value = next_value(&mut args, "--skip-ext")?;
                    config.skip_exts = parse_exts(&value.to_string_lossy());
                }
                "--scope" => {
                    let value = next_value(&mut args, "--scope")?;
                    config.scope = parse_scope(&value.to_string_lossy())?;
                }
                unknown => {
                    return Err(format!("unknown argument: {}", unknown));
                }
            }
        }

        if config.roots.is_empty() {
            return Err("at least one --root must be provided".into());
        }

        if config.commit_every == 0 {
            return Err("--commit-every must be greater than 0".into());
        }

        if config.commit_ms == 0 {
            return Err("--commit-ms must be greater than 0".into());
        }

        Ok(config)
    }
}

fn next_value(args: &mut impl Iterator<Item = OsString>, flag: &str) -> Result<OsString, String> {
    args.next()
        .ok_or_else(|| format!("missing value for {}", flag))
}

fn parse_usize(value: &OsString, flag: &str) -> Result<usize, String> {
    value
        .to_string_lossy()
        .parse::<usize>()
        .map_err(|_| format!("{} expects an integer", flag))
}

fn parse_u64(value: &OsString, flag: &str) -> Result<u64, String> {
    value
        .to_string_lossy()
        .parse::<u64>()
        .map_err(|_| format!("{} expects an integer", flag))
}

fn parse_exts(list: &str) -> Vec<String> {
    list.split(',')
        .map(|item| item.trim().trim_start_matches('.').to_lowercase())
        .filter(|s| !s.is_empty())
        .collect()
}

fn parse_scope(value: &str) -> Result<SearchDomain, String> {
    match value.to_lowercase().as_str() {
        "name" => Ok(SearchDomain::Name),
        "content" => Ok(SearchDomain::Content),
        "both" => Ok(SearchDomain::Both),
        other => Err(format!("invalid scope: {}", other)),
    }
}

fn print_usage() {
    eprintln!("finder-core smoke test");
    eprintln!("\nUsage:");
    eprintln!("  cargo run -p finder-core --bin smoke -- --root <path> [options]\n");
    eprintln!("Options:");
    eprintln!("  --index-dir <path>        Index directory (default: /tmp/finder-index)");
    eprintln!("  --root <path>             Root folder to scan (repeatable)");
    eprintln!("  --q <query>               Query to benchmark (repeatable)");
    eprintln!("  --glob <pattern>          Optional glob filter");
    eprintln!("  --threads <N>             Tantivy writer threads (default num_cpus)");
    eprintln!("  --writer-mem-mb <MB>      Tantivy writer memory in MB (default 384)");
    eprintln!("  --commit-every <N>        Commit every N documents (default 1000)");
    eprintln!("  --commit-ms <T>           Commit every T milliseconds (default 2000)");
    eprintln!("  --max-bytes <B>           Skip files larger than this (default 1572864)");
    eprintln!(
        "  --skip-ext <list>         Comma-separated extensions to skip (default .pkg,.dmg,.app)"
    );
    eprintln!("  --scope <name|content|both>  Default scope for bare queries (default both)");
    eprintln!("  --limit <N>               Max hits per query (default 50)");
    eprintln!("  --reindex                 Remove index directory before indexing");
    eprintln!("  --help                    Show this message");
}

#[derive(Default)]
struct Stats {
    files_seen: usize,
    added: usize,
    updated: usize,
    skipped_dedup: usize,
    skipped_large: usize,
    skipped_ext: usize,
    skipped_zero: usize,
    bytes_read: usize,
    commits: usize,
}

fn main() -> Result<(), Box<dyn Error>> {
    let args = Args::parse().unwrap_or_else(|err| {
        eprintln!("error: {err}");
        eprintln!("Use --help to see available options.");
        std::process::exit(1);
    });

    run(args).map_err(|err| {
        eprintln!("error: {err}");
        err
    })
}

fn run(args: Args) -> Result<(), Box<dyn Error>> {
    if args.reindex && args.index_dir.exists() {
        println!(
            "[INFO] removing existing index dir {}",
            args.index_dir.display()
        );
        fs::remove_dir_all(&args.index_dir)?;
    }

    let writer_threads = args
        .writer_threads
        .unwrap_or_else(|| num_cpus::get().max(1));
    finder_core::configure_indexer(finder_core::IndexSettings {
        writer_threads,
        writer_heap_bytes: args.writer_mem_mb.saturating_mul(1024 * 1024),
    });

    init_index(path_to_str(&args.index_dir)?)?;

    let start = Instant::now();
    let mut stats = Stats::default();
    let mut docs_since_commit = 0usize;
    let mut last_commit = Instant::now();

    println!(
        "[CONFIG] threads={} writer_mem_mb={} commit_every={} commit_ms={} max_bytes={} skip_ext={:?} limit={} scope={:?}",
        writer_threads,
        args.writer_mem_mb,
        args.commit_every,
        args.commit_ms,
        args.max_bytes,
        args.skip_exts,
        args.limit,
        args.scope
    );

    for root in &args.roots {
        let scan_start = Instant::now();
        let metas = scan_root(root)?;
        println!(
            "[INFO] scan completed for {}: {} files ({} s)",
            root.display(),
            metas.len(),
            format_seconds(scan_start.elapsed())
        );

        for meta in metas {
            stats.files_seen += 1;

            if meta.size == 0 {
                stats.skipped_zero += 1;
                continue;
            }

            if meta.size > args.max_bytes {
                stats.skipped_large += 1;
                continue;
            }

            if should_skip_ext(&meta.path, &args.skip_exts) {
                stats.skipped_ext += 1;
                continue;
            }

            let content_opt = if meta.size <= args.max_bytes {
                let limit = args.max_bytes.min(usize::MAX as u64) as usize;
                match read_plain_text(Path::new(&meta.path), limit) {
                    Ok(opt) => {
                        if let Some(ref content) = opt {
                            stats.bytes_read += content.len();
                        }
                        opt
                    }
                    Err(err) => {
                        eprintln!("[WARN] failed to read {}: {err}", meta.path);
                        None
                    }
                }
            } else {
                None
            };

            match add_or_update_file(meta, content_opt, args.reindex)? {
                IndexUpdate::Added => stats.added += 1,
                IndexUpdate::Updated => stats.updated += 1,
                IndexUpdate::Skipped => stats.skipped_dedup += 1,
            }

            docs_since_commit += 1;
            if docs_since_commit >= args.commit_every
                || last_commit.elapsed() >= Duration::from_millis(args.commit_ms)
            {
                commit()?;
                stats.commits += 1;
                docs_since_commit = 0;
                last_commit = Instant::now();
            }
        }
    }

    if docs_since_commit > 0 {
        commit()?;
        stats.commits += 1;
    }

    let total_elapsed = start.elapsed();
    println!(
        "[INFO] files={} added={} updated={} skipped_dedup={} skipped_large={} skipped_ext={} skipped_zero={} bytes_read={}KB commits={} total={} s throughput={:.1} docs/min",
        stats.files_seen,
        stats.added,
        stats.updated,
        stats.skipped_dedup,
        stats.skipped_large,
        stats.skipped_ext,
        stats.skipped_zero,
        stats.bytes_read / 1024,
        stats.commits,
        format_seconds(total_elapsed),
        docs_per_minute(&stats, total_elapsed)
    );

    if args.queries.is_empty() {
        return Ok(());
    }

    println!("[INFO] running query benchmarks (limit {})", args.limit);
    for query in &args.queries {
        let (domain, term) = parse_query(query, args.scope);
        let search_query = SearchQuery {
            term: term.clone(),
            search_in: domain,
            path_glob: args.glob.clone(),
            limit: args.limit,
        };

        let mut durations = Vec::with_capacity(BENCH_RUNS);
        let mut last_results = Vec::new();

        for _ in 0..BENCH_RUNS {
            let query_start = Instant::now();
            let results = search(search_query.clone())?;
            let elapsed = query_start.elapsed();
            durations.push(elapsed);
            if last_results.is_empty() {
                last_results = results;
            }
        }

        durations.sort();
        let p50 = percentile(&durations, 0.50);
        let p95 = percentile(&durations, 0.95);
        let hit_count = last_results.len();

        println!(
            "query=\"{}\" hits={} p50={}ms p95={}ms",
            query, hit_count, p50, p95
        );

        for hit in last_results.iter().take(5) {
            println!("  • {} — {}", hit.name, hit.path);
        }
    }

    Ok(())
}

fn parse_query(raw: &str, default_scope: SearchDomain) -> (SearchDomain, String) {
    if let Some(rest) = raw.strip_prefix("name:") {
        (SearchDomain::Name, rest.trim().to_string())
    } else if let Some(rest) = raw.strip_prefix("content:") {
        (SearchDomain::Content, rest.trim().to_string())
    } else if let Some(rest) = raw.strip_prefix("both:") {
        (SearchDomain::Both, rest.trim().to_string())
    } else {
        (default_scope, raw.trim().to_string())
    }
}

fn percentile(durations: &[Duration], percentile: f64) -> u128 {
    if durations.is_empty() {
        return 0;
    }
    let mut samples: Vec<u128> = durations.iter().map(|d| d.as_micros()).collect();
    samples.sort_unstable();
    let rank = percentile.clamp(0.0, 1.0) * (samples.len() as f64 - 1.0);
    let lower = rank.floor() as usize;
    let upper = rank.ceil() as usize;
    if lower == upper {
        return samples[lower] / 1000;
    }
    let weight = rank - lower as f64;
    let interpolated = samples[lower] as f64 * (1.0 - weight) + samples[upper] as f64 * weight;
    (interpolated / 1000.0) as u128
}

fn format_seconds(duration: Duration) -> String {
    format!("{:.2}", duration.as_secs_f64())
}

fn path_to_str(path: &Path) -> Result<&str, Box<dyn Error>> {
    path.to_str()
        .ok_or_else(|| "path is not valid UTF-8".into())
}

fn should_skip_ext(path: &str, skip_exts: &[String]) -> bool {
    if skip_exts.is_empty() {
        return false;
    }
    Path::new(path)
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| skip_exts.contains(&ext.to_lowercase()))
        .unwrap_or(false)
}

fn docs_per_minute(stats: &Stats, elapsed: Duration) -> f64 {
    if elapsed.as_secs_f64() == 0.0 {
        return 0.0;
    }
    let indexed = (stats.added + stats.updated) as f64;
    (indexed * 60.0) / elapsed.as_secs_f64()
}
