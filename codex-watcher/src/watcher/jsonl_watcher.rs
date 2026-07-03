use crate::token_usage::{context_used_tokens, model_context_window, token_count_value};
use anyhow::{Context, Result};
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;
use std::io::{BufRead, BufReader as StdBufReader};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};
use tokio::fs::File;
use tokio::io::{AsyncBufReadExt, AsyncSeekExt, BufReader};
use tokio::sync::mpsc;
use tokio::time::{interval, MissedTickBehavior};
use tracing::{debug, info, warn};

#[derive(Debug, Clone, Serialize)]
pub struct RawJsonlLine {
    pub session_file: PathBuf,
    pub session_id: Option<String>,
    pub event_type: String,
    pub payload_type: Option<String>,
    pub parsed: Value,
}

#[derive(Debug, Clone)]
struct FileTailState {
    path: PathBuf,
    offset: u64,
    session_id: Option<String>,
}

pub struct JsonlWatcher {
    sessions_dir: PathBuf,
    tx: mpsc::Sender<RawJsonlLine>,
    tailing: HashMap<PathBuf, FileTailState>,
    active_file: Option<PathBuf>,
}

impl JsonlWatcher {
    pub fn new(sessions_dir: impl Into<PathBuf>, tx: mpsc::Sender<RawJsonlLine>) -> Self {
        let sessions_dir = sessions_dir.into();
        let sessions_dir = canonicalize_existing_path(&sessions_dir);

        Self {
            sessions_dir,
            tx,
            tailing: HashMap::new(),
            active_file: None,
        }
    }

    pub async fn start(mut self) -> Result<()> {
        self.scan_existing_sessions().await?;

        let (fs_tx, mut fs_rx) = mpsc::channel(256);
        let mut watcher = RecommendedWatcher::new(
            move |result: notify::Result<Event>| match result {
                Ok(event) => {
                    if let Err(error) = fs_tx.blocking_send(event) {
                        warn!("File watcher event receiver closed: {error}");
                    }
                }
                Err(error) => warn!("File watcher error: {error}"),
            },
            Config::default().with_poll_interval(Duration::from_millis(200)),
        )
        .context("create filesystem watcher")?;

        watcher
            .watch(&self.sessions_dir, RecursiveMode::Recursive)
            .with_context(|| format!("watch {}", self.sessions_dir.display()))?;
        info!("File watcher started on {}", self.sessions_dir.display());

        let mut poll_interval = interval(Duration::from_millis(500));
        poll_interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

        loop {
            tokio::select! {
                maybe_event = fs_rx.recv() => {
                    let Some(event) = maybe_event else {
                        break;
                    };
                    self.handle_fs_event(event).await;
                }
                _ = poll_interval.tick() => {
                    self.poll_session_files().await;
                }
            }
        }

        Ok(())
    }

    async fn scan_existing_sessions(&mut self) -> Result<()> {
        let cutoff = SystemTime::now()
            .checked_sub(Duration::from_secs(86_400))
            .unwrap_or(SystemTime::UNIX_EPOCH);

        let mut latest: Option<(PathBuf, SystemTime)> = None;

        for path in collect_jsonl_files(&self.sessions_dir)? {
            let Ok(metadata) = std::fs::metadata(&path) else {
                continue;
            };
            let Ok(modified) = metadata.modified() else {
                continue;
            };
            if modified < cutoff {
                continue;
            }

            let offset = metadata.len();
            info!(
                "Pre-positioning tail: {} at offset {offset}",
                path.display()
            );
            self.tailing.insert(
                path.clone(),
                FileTailState {
                    path: path.clone(),
                    offset,
                    session_id: session_id_from_path(&path),
                },
            );

            if latest
                .as_ref()
                .map(|(_, latest_modified)| modified > *latest_modified)
                .unwrap_or(true)
            {
                latest = Some((path.clone(), modified));
            }
        }

        if let Some((path, _)) = latest {
            info!("Active session file: {}", path.display());
            self.active_file = Some(path);
            self.seed_active_session().await;
        }

        Ok(())
    }

    async fn seed_active_session(&mut self) {
        let Some(path) = self.active_file.clone() else {
            return;
        };

        let Ok((session_id, seed_lines)) = seed_latest_lines_from_file(&path) else {
            return;
        };

        if let Some(state) = self.tailing.get_mut(&path) {
            if session_id.is_some() {
                state.session_id = session_id;
            }
        }

        for seed_line in seed_lines {
            if let Err(error) = self.tx.send(seed_line.raw).await {
                warn!("Failed to send seeded JSONL event: {error}");
                break;
            }
        }
    }

    async fn handle_fs_event(&mut self, event: Event) {
        match event.kind {
            EventKind::Create(_) => {
                for path in jsonl_paths(event.paths) {
                    info!("New session file detected: {}", path.display());
                    self.active_file = Some(path.clone());
                    self.tailing.entry(path.clone()).or_insert(FileTailState {
                        path: path.clone(),
                        offset: 0,
                        session_id: session_id_from_path(&path),
                    });
                    self.tail_file(&path).await;
                }
            }
            EventKind::Modify(_) => {
                for path in jsonl_paths(event.paths) {
                    self.active_file = Some(path.clone());
                    if self.is_active_file(&path) {
                        self.tail_file(&path).await;
                    }
                }
            }
            _ => {}
        }
    }

    fn is_active_file(&self, path: &Path) -> bool {
        self.active_file.as_deref() == Some(path)
    }

    async fn poll_session_files(&mut self) {
        let cutoff = SystemTime::now()
            .checked_sub(Duration::from_secs(86_400))
            .unwrap_or(SystemTime::UNIX_EPOCH);

        let Ok(paths) = collect_jsonl_files(&self.sessions_dir) else {
            return;
        };

        for path in paths {
            let Ok(metadata) = std::fs::metadata(&path) else {
                continue;
            };
            let Ok(modified) = metadata.modified() else {
                continue;
            };
            if modified < cutoff {
                continue;
            }

            let len = metadata.len();
            let should_tail = match self.tailing.get(&path) {
                Some(state) => len != state.offset,
                None => true,
            };

            if !should_tail {
                continue;
            }

            if !self.tailing.contains_key(&path) {
                info!("Polling discovered session file: {}", path.display());
                self.tailing.insert(
                    path.clone(),
                    FileTailState {
                        path: path.clone(),
                        offset: 0,
                        session_id: session_id_from_path(&path),
                    },
                );
            }

            self.active_file = Some(path.clone());
            self.tail_file(&path).await;
        }
    }

    async fn tail_file(&mut self, path: &Path) {
        let state = self
            .tailing
            .entry(path.to_path_buf())
            .or_insert(FileTailState {
                path: path.to_path_buf(),
                offset: 0,
                session_id: session_id_from_path(path),
            });

        let Ok(metadata) = std::fs::metadata(&state.path) else {
            warn!("Cannot stat {}", state.path.display());
            return;
        };
        if metadata.len() < state.offset {
            debug!("File truncated, resetting tail: {}", state.path.display());
            state.offset = 0;
        }

        let mut file = match File::open(&state.path).await {
            Ok(file) => file,
            Err(error) => {
                warn!("Cannot open {}: {error}", state.path.display());
                return;
            }
        };

        if let Err(error) = file.seek(std::io::SeekFrom::Start(state.offset)).await {
            warn!("Seek failed for {}: {error}", state.path.display());
            return;
        }

        let mut reader = BufReader::new(file);
        let mut new_offset = state.offset;

        loop {
            let mut line = String::new();
            let bytes_read = match reader.read_line(&mut line).await {
                Ok(0) => break,
                Ok(bytes_read) => bytes_read,
                Err(error) => {
                    warn!("Read failed for {}: {error}", state.path.display());
                    break;
                }
            };

            if !line.ends_with('\n') {
                debug!(
                    "Waiting for complete JSONL line in {}",
                    state.path.display()
                );
                break;
            }

            new_offset += bytes_read as u64;
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            match serde_json::from_str::<Value>(trimmed) {
                Ok(parsed) => {
                    if let Some(session_id) = extract_session_id(&parsed) {
                        state.session_id = Some(session_id);
                    }

                    let Some(sanitized) = sanitize_jsonl_event(&parsed) else {
                        continue;
                    };

                    let raw = RawJsonlLine {
                        session_file: state.path.clone(),
                        session_id: state.session_id.clone(),
                        event_type: event_type(&sanitized).unwrap_or("unknown").to_string(),
                        payload_type: payload_type(&sanitized).map(ToOwned::to_owned),
                        parsed: sanitized,
                    };

                    if let Err(error) = self.tx.send(raw).await {
                        warn!("Failed to send JSONL event: {error}");
                        break;
                    }
                }
                Err(error) => debug!("Skip non-JSON line in {}: {error}", state.path.display()),
            }
        }

        state.offset = new_offset;
    }
}

fn collect_jsonl_files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    collect_jsonl_files_inner(root, &mut files)?;
    Ok(files)
}

fn collect_jsonl_files_inner(dir: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    if !dir.exists() {
        return Ok(());
    }

    for entry in std::fs::read_dir(dir).with_context(|| format!("read {}", dir.display()))? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_jsonl_files_inner(&path, files)?;
        } else if is_jsonl_path(&path) {
            files.push(canonicalize_existing_path(&path));
        }
    }

    Ok(())
}

fn jsonl_paths(paths: Vec<PathBuf>) -> impl Iterator<Item = PathBuf> {
    paths.into_iter().filter_map(|path| {
        if is_jsonl_path(&path) {
            Some(canonicalize_existing_path(&path))
        } else {
            None
        }
    })
}

fn is_jsonl_path(path: &Path) -> bool {
    path.extension().and_then(|ext| ext.to_str()) == Some("jsonl")
}

fn canonicalize_existing_path(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

fn session_id_from_path(path: &Path) -> Option<String> {
    let stem = path.file_stem()?.to_str()?;
    let parts: Vec<&str> = stem.split('-').collect();

    if parts.len() >= 5 {
        for start in (0..=parts.len() - 5).rev() {
            let candidate = &parts[start..start + 5];
            if candidate
                .iter()
                .zip([8, 4, 4, 4, 12])
                .all(|(part, length)| {
                    part.len() == length
                        && part.chars().all(|character| character.is_ascii_hexdigit())
                })
            {
                return Some(candidate.join("-"));
            }
        }
    }

    stem.rsplit('-')
        .next()
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn extract_session_id(parsed: &Value) -> Option<String> {
    match parsed.get("type").and_then(|value| value.as_str()) {
        Some("session_init") => parsed
            .get("payload")
            .and_then(|payload| payload.get("session_id"))
            .and_then(|value| value.as_str())
            .map(ToOwned::to_owned),
        Some("session_meta") => parsed
            .get("payload")
            .and_then(|payload| payload.get("id"))
            .and_then(|value| value.as_str())
            .map(ToOwned::to_owned),
        _ => None,
    }
}

fn sanitize_jsonl_event(parsed: &Value) -> Option<Value> {
    let top_type = parsed.get("type").and_then(|value| value.as_str())?;
    let timestamp = parsed.get("timestamp").cloned();

    match top_type {
        "session_init" => {
            let payload = parsed.get("payload").unwrap_or(&Value::Null);
            Some(json_object(
                top_type,
                timestamp,
                vec![
                    ("session_id", payload.get("session_id").cloned()),
                    ("model", payload.get("model").cloned()),
                ],
            ))
        }
        "session_meta" => {
            let payload = parsed.get("payload").unwrap_or(&Value::Null);
            Some(json_object(
                top_type,
                timestamp,
                vec![
                    ("id", payload.get("id").cloned()),
                    ("cwd", payload.get("cwd").cloned()),
                    ("cli_version", payload.get("cli_version").cloned()),
                ],
            ))
        }
        "event_msg" => sanitize_event_msg(parsed, timestamp),
        "response_item" => sanitize_response_item(parsed, timestamp),
        _ => None,
    }
}

fn sanitize_response_item(parsed: &Value, timestamp: Option<Value>) -> Option<Value> {
    let payload = parsed.get("payload")?;
    let payload_type = payload.get("type").and_then(|value| value.as_str())?;

    match payload_type {
        "function_call" | "custom_tool_call" => Some(json_object(
            "response_item",
            timestamp,
            vec![
                ("type", Some(Value::String("tool_call".to_string()))),
                ("tool", payload.get("name").cloned()),
            ],
        )),
        _ => None,
    }
}

fn sanitize_event_msg(parsed: &Value, timestamp: Option<Value>) -> Option<Value> {
    let payload = parsed.get("payload")?;
    let payload_type = payload.get("type").and_then(|value| value.as_str())?;

    let fields = match payload_type {
        "token_count" => vec![
            ("type", Some(Value::String(payload_type.to_string()))),
            (
                "input_tokens",
                token_count_json_value(payload, "input_tokens"),
            ),
            (
                "cached_input_tokens",
                token_count_json_value(payload, "cached_input_tokens"),
            ),
            (
                "output_tokens",
                token_count_json_value(payload, "output_tokens"),
            ),
            (
                "reasoning_tokens",
                token_count_json_value(payload, "reasoning_tokens"),
            ),
            ("context_used", token_context_used_json_value(payload)),
            ("context_window", token_context_window_json_value(payload)),
        ],
        "task_started" | "task_complete" => {
            vec![("type", Some(Value::String(payload_type.to_string())))]
        }
        "agent_message" => vec![
            ("type", Some(Value::String(payload_type.to_string()))),
            ("phase", payload.get("phase").cloned()),
        ],
        "user_message" | "assistant_message_start" | "assistant_message_stop" | "tool_approval" => {
            vec![
                ("type", Some(Value::String(payload_type.to_string()))),
                ("approved", payload.get("approved").cloned()),
            ]
        }
        "tool_call" | "awaiting_approval" => vec![
            ("type", Some(Value::String(payload_type.to_string()))),
            ("tool", payload.get("tool").cloned()),
            ("command", payload.get("command").cloned()),
        ],
        "error" | "turn_error" | "stream_error" => {
            vec![("type", Some(Value::String(payload_type.to_string())))]
        }
        // Deltas often contain assistant text. Token deltas are tracked through token_count.
        "assistant_message_delta" => return None,
        _ => return None,
    };

    Some(json_object("event_msg", timestamp, fields))
}

fn token_count_json_value(payload: &Value, internal_key: &str) -> Option<Value> {
    token_count_value(payload, internal_key)
        .map(serde_json::Number::from)
        .map(Value::Number)
}

fn token_context_used_json_value(payload: &Value) -> Option<Value> {
    context_used_tokens(payload)
        .map(serde_json::Number::from)
        .map(Value::Number)
}

fn token_context_window_json_value(payload: &Value) -> Option<Value> {
    model_context_window(payload)
        .map(serde_json::Number::from)
        .map(Value::Number)
}

fn json_object(
    top_type: &str,
    timestamp: Option<Value>,
    fields: Vec<(&str, Option<Value>)>,
) -> Value {
    let mut root = serde_json::Map::new();
    root.insert("type".to_string(), Value::String(top_type.to_string()));
    if let Some(timestamp) = timestamp {
        root.insert("timestamp".to_string(), timestamp);
    }

    let mut payload = serde_json::Map::new();
    for (key, value) in fields {
        if let Some(value) = value {
            payload.insert(key.to_string(), value);
        }
    }
    if !payload.is_empty() {
        root.insert("payload".to_string(), Value::Object(payload));
    }

    Value::Object(root)
}

fn event_type(parsed: &Value) -> Option<&str> {
    parsed.get("type").and_then(|value| value.as_str())
}

fn payload_type(parsed: &Value) -> Option<&str> {
    parsed
        .get("payload")
        .and_then(|payload| payload.get("type"))
        .and_then(|value| value.as_str())
}

#[derive(Debug, Clone)]
struct SeedLine {
    line_number: usize,
    raw: RawJsonlLine,
}

fn seed_latest_lines_from_file(path: &Path) -> Result<(Option<String>, Vec<SeedLine>)> {
    let file = std::fs::File::open(path).with_context(|| format!("open {}", path.display()))?;
    let reader = StdBufReader::new(file);

    let mut session_id = session_id_from_path(path);
    let mut last_token_count: Option<SeedLine> = None;
    let mut last_state_event: Option<SeedLine> = None;

    for (index, line) in reader.lines().enumerate() {
        let Ok(line) = line else {
            continue;
        };
        if line.trim().is_empty() {
            continue;
        }

        let Ok(parsed) = serde_json::from_str::<Value>(&line) else {
            continue;
        };

        if let Some(extracted_session_id) = extract_session_id(&parsed) {
            session_id = Some(extracted_session_id);
        }

        let Some(sanitized) = sanitize_jsonl_event(&parsed) else {
            continue;
        };

        let Some(payload_type) = payload_type(&sanitized).map(ToOwned::to_owned) else {
            continue;
        };

        let raw = RawJsonlLine {
            session_file: path.to_path_buf(),
            session_id: session_id.clone(),
            event_type: event_type(&sanitized).unwrap_or("unknown").to_string(),
            payload_type: Some(payload_type.clone()),
            parsed: sanitized,
        };

        let seed_line = SeedLine {
            line_number: index + 1,
            raw,
        };

        if payload_type == "token_count" {
            last_token_count = Some(seed_line.clone());
        }

        if is_state_seed_payload_type(&payload_type) {
            last_state_event = Some(seed_line);
        }
    }

    let mut seed_lines = Vec::new();
    if let Some(line) = last_token_count {
        seed_lines.push(line);
    }
    if let Some(line) = last_state_event {
        if seed_lines
            .iter()
            .all(|seed_line| seed_line.line_number != line.line_number)
        {
            seed_lines.push(line);
        }
    }
    seed_lines.sort_by_key(|line| line.line_number);

    Ok((session_id, seed_lines))
}

fn is_state_seed_payload_type(payload_type: &str) -> bool {
    matches!(
        payload_type,
        "task_started"
            | "task_complete"
            | "user_message"
            | "agent_message"
            | "tool_call"
            | "token_count"
            | "assistant_message_stop"
            | "awaiting_approval"
            | "tool_approval"
            | "error"
            | "turn_error"
            | "stream_error"
    )
}

#[cfg(test)]
mod tests {
    use super::{
        extract_session_id, sanitize_jsonl_event, seed_latest_lines_from_file, session_id_from_path,
    };
    use serde_json::json;
    use std::fs;
    use std::io::Write;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEMP_JSONL_COUNTER: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn extracts_session_init_session_id() {
        let value = json!({
            "type": "session_init",
            "payload": { "session_id": "abc-123" }
        });

        assert_eq!(extract_session_id(&value).as_deref(), Some("abc-123"));
    }

    #[test]
    fn extracts_desktop_session_meta_id() {
        let value = json!({
            "type": "session_meta",
            "payload": { "id": "desktop-456" }
        });

        assert_eq!(extract_session_id(&value).as_deref(), Some("desktop-456"));
    }

    #[test]
    fn derives_session_id_from_rollout_filename() {
        let path = PathBuf::from(
            "/tmp/rollout-2026-06-28T17-05-03-019f0d79-a330-7352-97a3-9032d7b038db.jsonl",
        );

        assert_eq!(
            session_id_from_path(&path).as_deref(),
            Some("019f0d79-a330-7352-97a3-9032d7b038db")
        );
    }

    #[test]
    fn drops_assistant_text_deltas() {
        let value = json!({
            "type": "event_msg",
            "payload": {
                "type": "assistant_message_delta",
                "content": "private assistant text"
            }
        });

        assert!(sanitize_jsonl_event(&value).is_none());
    }

    #[test]
    fn keeps_only_token_count_fields() {
        let value = json!({
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "input_tokens": 10,
                "cached_input_tokens": 5,
                "output_tokens": 2,
                "reasoning_tokens": 1,
                "content": "should not leak"
            }
        });

        let sanitized = sanitize_jsonl_event(&value).unwrap();
        assert_eq!(sanitized["payload"]["type"], "token_count");
        assert_eq!(sanitized["payload"]["input_tokens"], 10);
        assert!(sanitized["payload"].get("content").is_none());
    }

    #[test]
    fn normalizes_real_codex_token_count_fields() {
        let value = json!({
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "info": {
                    "total_token_usage": {
                        "input_tokens": 120,
                        "cached_input_tokens": 40,
                        "output_tokens": 12,
                        "reasoning_output_tokens": 3,
                        "total_tokens": 132
                    },
                    "last_token_usage": {
                        "input_tokens": 20,
                        "cached_input_tokens": 10,
                        "output_tokens": 4,
                        "reasoning_output_tokens": 1,
                        "total_tokens": 24
                    }
                },
                "model_context_window": 258400,
                "rate_limits": {
                    "primary": {
                        "used_percent": 12.5
                    }
                }
            }
        });

        let sanitized = sanitize_jsonl_event(&value).unwrap();

        assert_eq!(sanitized["payload"]["type"], "token_count");
        assert_eq!(sanitized["payload"]["input_tokens"], 120);
        assert_eq!(sanitized["payload"]["cached_input_tokens"], 40);
        assert_eq!(sanitized["payload"]["output_tokens"], 12);
        assert_eq!(sanitized["payload"]["reasoning_tokens"], 3);
        assert_eq!(sanitized["payload"]["context_used"], 24);
        assert_eq!(sanitized["payload"]["context_window"], 258400);
        assert!(sanitized["payload"].get("info").is_none());
        assert!(sanitized["payload"].get("rate_limits").is_none());
    }

    #[test]
    fn keeps_task_lifecycle_events_without_private_content() {
        let started = sanitize_jsonl_event(&json!({
            "type": "event_msg",
            "payload": {
                "type": "task_started",
                "private": "drop"
            }
        }))
        .unwrap();
        let complete = sanitize_jsonl_event(&json!({
            "type": "event_msg",
            "payload": {
                "type": "task_complete",
                "message": "drop"
            }
        }))
        .unwrap();

        assert_eq!(started["payload"]["type"], "task_started");
        assert_eq!(complete["payload"]["type"], "task_complete");
        assert!(started["payload"].get("private").is_none());
        assert!(complete["payload"].get("message").is_none());
    }

    #[test]
    fn keeps_agent_message_phase_without_text() {
        let value = json!({
            "type": "event_msg",
            "payload": {
                "type": "agent_message",
                "phase": "final_answer",
                "message": "private assistant text"
            }
        });

        let sanitized = sanitize_jsonl_event(&value).unwrap();

        assert_eq!(sanitized["payload"]["type"], "agent_message");
        assert_eq!(sanitized["payload"]["phase"], "final_answer");
        assert!(sanitized["payload"].get("message").is_none());
    }

    #[test]
    fn keeps_tool_call_name_without_arguments() {
        let value = json!({
            "type": "response_item",
            "payload": {
                "type": "function_call",
                "name": "exec_command",
                "arguments": "{\"cmd\":\"private\"}"
            }
        });

        let sanitized = sanitize_jsonl_event(&value).unwrap();

        assert_eq!(sanitized["payload"]["type"], "tool_call");
        assert_eq!(sanitized["payload"]["tool"], "exec_command");
        assert!(sanitized["payload"].get("arguments").is_none());
    }

    #[test]
    fn seeds_latest_token_count_and_terminal_state() {
        let path =
            temp_jsonl_path("rollout-2026-06-28T17-05-03-019f0d79-a330-7352-97a3-9032d7b038db");
        write_jsonl_lines(
            &path,
            &[
                json!({
                    "type": "session_init",
                    "payload": { "session_id": "seed-session", "model": "test" }
                }),
                json!({
                    "type": "event_msg",
                    "payload": {
                        "type": "token_count",
                        "info": {
                            "total_token_usage": {
                                "input_tokens": 100,
                                "cached_input_tokens": 50,
                                "output_tokens": 8,
                                "reasoning_output_tokens": 1,
                                "total_tokens": 108
                            }
                        }
                    }
                }),
                json!({
                    "type": "event_msg",
                    "payload": {
                        "type": "agent_message",
                        "phase": "final_answer",
                        "message": "private"
                    }
                }),
                json!({
                    "type": "event_msg",
                    "payload": {
                        "type": "token_count",
                        "info": {
                            "total_token_usage": {
                                "input_tokens": 150,
                                "cached_input_tokens": 90,
                                "output_tokens": 21,
                                "reasoning_output_tokens": 3,
                                "total_tokens": 171
                            }
                        }
                    }
                }),
                json!({
                    "type": "event_msg",
                    "payload": { "type": "task_complete", "message": "private" }
                }),
            ],
        );

        let (session_id, seed_lines) = seed_latest_lines_from_file(&path).unwrap();
        let _ = fs::remove_file(&path);

        assert_eq!(session_id.as_deref(), Some("seed-session"));
        assert_eq!(seed_lines.len(), 2);
        assert_eq!(
            seed_lines[0].raw.payload_type.as_deref(),
            Some("token_count")
        );
        assert_eq!(seed_lines[0].raw.parsed["payload"]["input_tokens"], 150);
        assert_eq!(seed_lines[0].raw.parsed["payload"]["output_tokens"], 21);
        assert_eq!(
            seed_lines[1].raw.payload_type.as_deref(),
            Some("task_complete")
        );
    }

    #[test]
    fn seeds_filename_session_id_when_metadata_is_absent() {
        let path =
            temp_jsonl_path("rollout-2026-06-28T17-05-03-019f0d79-a330-7352-97a3-9032d7b038db");
        write_jsonl_lines(
            &path,
            &[json!({
                "type": "event_msg",
                "payload": { "type": "task_started" }
            })],
        );

        let (session_id, seed_lines) = seed_latest_lines_from_file(&path).unwrap();
        let _ = fs::remove_file(&path);

        assert_eq!(
            session_id.as_deref(),
            Some("019f0d79-a330-7352-97a3-9032d7b038db")
        );
        assert_eq!(
            seed_lines[0].raw.session_id.as_deref(),
            Some("019f0d79-a330-7352-97a3-9032d7b038db")
        );
    }

    #[test]
    fn keeps_error_type_without_private_message() {
        let value = json!({
            "type": "event_msg",
            "payload": {
                "type": "turn_error",
                "message": "private failure text"
            }
        });

        let sanitized = sanitize_jsonl_event(&value).unwrap();
        assert_eq!(sanitized["payload"]["type"], "turn_error");
        assert!(sanitized["payload"].get("message").is_none());
    }

    fn temp_jsonl_path(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let counter = TEMP_JSONL_COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!(
            "codex-island-{label}-{}-{nanos}-{counter}.jsonl",
            std::process::id()
        ))
    }

    fn write_jsonl_lines(path: &PathBuf, lines: &[serde_json::Value]) {
        let mut file = fs::File::create(path).unwrap();
        for line in lines {
            writeln!(file, "{line}").unwrap();
        }
    }
}
