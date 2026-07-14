use crate::parser::token_parser::{TokenParser, TokenSnapshot};
use crate::token_usage::token_count_value;
use chrono::{DateTime, Local, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};

const LEDGER_VERSION: u32 = 1;
const LEDGER_FILE_NAME: &str = "codex-island-token-ledger-v1.json";

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
struct SessionTotals {
    input: u64,
    cached_input: u64,
    output: u64,
    reasoning: u64,
}

impl SessionTotals {
    fn total_tokens(&self) -> u64 {
        self.input + self.output
    }

    fn is_zero(&self) -> bool {
        self.input == 0 && self.cached_input == 0 && self.output == 0 && self.reasoning == 0
    }

    fn saturating_sub(&self, baseline: &SessionTotals) -> SessionTotals {
        SessionTotals {
            input: self.input.saturating_sub(baseline.input),
            cached_input: self.cached_input.saturating_sub(baseline.cached_input),
            output: self.output.saturating_sub(baseline.output),
            reasoning: self.reasoning.saturating_sub(baseline.reasoning),
        }
    }

    fn delta_from(&self, previous: &SessionTotals) -> SessionTotals {
        if self.total_tokens() < previous.total_tokens() {
            return self.clone();
        }

        self.saturating_sub(previous)
    }

    fn add_assign(&mut self, other: &SessionTotals) {
        self.input = self.input.saturating_add(other.input);
        self.cached_input = self.cached_input.saturating_add(other.cached_input);
        self.output = self.output.saturating_add(other.output);
        self.reasoning = self.reasoning.saturating_add(other.reasoning);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GlobalTokenUsageSnapshot {
    #[serde(rename = "type")]
    pub message_type: String,
    pub total_input: u64,
    pub total_cached_input: u64,
    pub total_output: u64,
    pub total_reasoning: u64,
    pub total_tokens: u64,
    pub session_count: usize,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DailyTokenUsageSnapshot {
    #[serde(rename = "type")]
    pub message_type: String,
    pub local_date: String,
    pub total_input: u64,
    pub total_cached_input: u64,
    pub total_output: u64,
    pub total_reasoning: u64,
    pub total_tokens: u64,
    pub session_count: usize,
    pub request_count: u64,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct PersistedTokenLedger {
    version: u32,
    global_sessions: HashMap<String, SessionTotals>,
    daily_date: String,
    daily_sessions: HashMap<String, SessionTotals>,
    daily_request_counts: HashMap<String, u64>,
}

#[derive(Debug, Clone)]
struct FileRuntimeState {
    session_id: String,
    last_totals: SessionTotals,
}

#[derive(Debug)]
pub struct TokenUsageAggregators {
    pub global: GlobalTokenAggregator,
    pub daily: DailyTokenAggregator,
    /// Per-session latest `TokenSnapshot` rebuilt from each history file's last
    /// `token_count` event. Published at watcher startup so IPC clients connecting after
    /// the initial publish still receive a current per-session token frame from the
    /// replay cache, instead of seeing all zeros until the next live codex turn.
    pub latest_snapshots: Vec<TokenSnapshot>,
    file_states: HashMap<String, FileRuntimeState>,
    ledger_path: Option<PathBuf>,
    dirty: bool,
}

impl TokenUsageAggregators {
    pub fn load_from_sessions_dir(sessions_dir: impl AsRef<Path>) -> Self {
        let sessions_dir = sessions_dir.as_ref();
        let ledger_path = sessions_dir
            .parent()
            .unwrap_or(sessions_dir)
            .join(LEDGER_FILE_NAME);
        Self::load_from_sessions_dir_for_date_and_ledger(
            sessions_dir,
            Local::now().date_naive(),
            Some(ledger_path),
        )
    }

    #[cfg(test)]
    fn load_from_sessions_dir_for_date(
        sessions_dir: impl AsRef<Path>,
        local_date: NaiveDate,
    ) -> Self {
        Self::load_from_sessions_dir_for_date_and_ledger(sessions_dir, local_date, None)
    }

    fn load_from_sessions_dir_for_date_and_ledger(
        sessions_dir: impl AsRef<Path>,
        local_date: NaiveDate,
        ledger_path: Option<PathBuf>,
    ) -> Self {
        let persisted = ledger_path
            .as_deref()
            .and_then(load_persisted_ledger)
            .unwrap_or_default();
        let local_date_string = local_date.format("%Y-%m-%d").to_string();
        let mut global = GlobalTokenAggregator {
            sessions: persisted.global_sessions,
        };
        let mut daily = DailyTokenAggregator::new(local_date);
        if persisted.daily_date == local_date_string {
            daily.sessions = persisted.daily_sessions;
            daily.request_counts = persisted.daily_request_counts;
        }
        let mut latest_snapshots = Vec::new();
        let mut file_states = HashMap::new();

        let mut session_files = collect_jsonl_files(sessions_dir.as_ref());
        if ledger_path.is_some() {
            if let Some(codex_home) = sessions_dir.as_ref().parent() {
                session_files.extend(collect_jsonl_files(&codex_home.join("archived_sessions")));
            }
        }

        for path in session_files {
            if let Some(scan) = scan_token_file(&path, local_date) {
                file_states.insert(
                    path.to_string_lossy().to_string(),
                    FileRuntimeState {
                        session_id: scan.session_id.clone(),
                        last_totals: scan.latest_totals.clone(),
                    },
                );

                global.merge_session(scan.session_id.clone(), scan.lifetime_totals);
                daily.merge_session(
                    scan.session_id.clone(),
                    scan.daily_totals,
                    scan.daily_request_count,
                );

                if let Some(payload) = scan.latest_token_payload {
                    let timestamp = scan.latest_token_timestamp.unwrap_or_else(Utc::now);
                    if let Some(snapshot) = TokenParser::snapshot_from_history(
                        &path,
                        Some(&scan.session_id),
                        &payload,
                        timestamp,
                    ) {
                        latest_snapshots.push(snapshot);
                    }
                }
            }
        }

        Self {
            global,
            daily,
            latest_snapshots,
            file_states,
            ledger_path,
            dirty: true,
        }
    }

    pub fn update_from_snapshot(
        &mut self,
        snapshot: &TokenSnapshot,
    ) -> (
        Option<GlobalTokenUsageSnapshot>,
        Option<DailyTokenUsageSnapshot>,
    ) {
        let file_key = snapshot.session_file.clone();
        if !self.file_states.contains_key(&file_key) {
            if let Some(scan) = scan_token_file(
                Path::new(&snapshot.session_file),
                snapshot.timestamp.with_timezone(&Local).date_naive(),
            ) {
                self.file_states.insert(
                    file_key.clone(),
                    FileRuntimeState {
                        session_id: scan.session_id.clone(),
                        last_totals: scan.latest_totals,
                    },
                );
                self.global
                    .merge_session(scan.session_id.clone(), scan.lifetime_totals);
                self.daily.merge_session(
                    scan.session_id,
                    scan.daily_totals,
                    scan.daily_request_count,
                );
                self.dirty = true;
                return (Some(self.global.snapshot()), Some(self.daily.snapshot()));
            }
            return (None, None);
        }

        if snapshot.turn_index == 0 {
            return (None, None);
        }

        let current = SessionTotals::from_snapshot(snapshot);
        let state = self
            .file_states
            .get_mut(&file_key)
            .expect("file state exists");
        let delta = current.delta_from(&state.last_totals);
        state.last_totals = current;

        if delta.is_zero() {
            return (None, None);
        }

        let session_id = state.session_id.clone();
        self.global.add_delta(&session_id, &delta);
        self.daily.add_delta(
            &session_id,
            &delta,
            snapshot.timestamp.with_timezone(&Local).date_naive(),
        );
        self.dirty = true;

        (Some(self.global.snapshot()), Some(self.daily.snapshot()))
    }

    pub fn flush_if_dirty(&mut self) -> std::io::Result<()> {
        if !self.dirty {
            return Ok(());
        }
        let Some(path) = &self.ledger_path else {
            self.dirty = false;
            return Ok(());
        };

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let persisted = PersistedTokenLedger {
            version: LEDGER_VERSION,
            global_sessions: self.global.sessions.clone(),
            daily_date: self.daily.local_date.format("%Y-%m-%d").to_string(),
            daily_sessions: self.daily.sessions.clone(),
            daily_request_counts: self.daily.request_counts.clone(),
        };
        let bytes = serde_json::to_vec(&persisted).map_err(std::io::Error::other)?;
        let temp_path = path.with_extension(format!("tmp-{}", std::process::id()));
        std::fs::write(&temp_path, bytes)?;
        std::fs::rename(temp_path, path)?;
        self.dirty = false;
        Ok(())
    }
}

impl SessionTotals {
    fn from_snapshot(snapshot: &TokenSnapshot) -> Self {
        Self {
            input: snapshot.total_input,
            cached_input: snapshot.total_cached_input,
            output: snapshot.total_output,
            reasoning: snapshot.total_reasoning,
        }
    }
}

fn load_persisted_ledger(path: &Path) -> Option<PersistedTokenLedger> {
    let data = std::fs::read(path).ok()?;
    let ledger: PersistedTokenLedger = serde_json::from_slice(&data).ok()?;
    (ledger.version == LEDGER_VERSION).then_some(ledger)
}

#[derive(Debug, Default)]
pub struct GlobalTokenAggregator {
    sessions: HashMap<String, SessionTotals>,
}

impl GlobalTokenAggregator {
    #[cfg(test)]
    pub fn load_from_sessions_dir(sessions_dir: impl AsRef<Path>) -> Self {
        let mut aggregator = Self::default();

        for path in collect_jsonl_files(sessions_dir.as_ref()) {
            if let Some(scan) = scan_token_file(&path, Local::now().date_naive()) {
                aggregator.merge_session(scan.session_id, scan.lifetime_totals);
            }
        }

        aggregator
    }

    #[cfg(test)]
    pub fn update_from_snapshot(
        &mut self,
        snapshot: &TokenSnapshot,
    ) -> Option<GlobalTokenUsageSnapshot> {
        let totals = SessionTotals {
            input: snapshot.total_input,
            cached_input: snapshot.total_cached_input,
            output: snapshot.total_output,
            reasoning: snapshot.total_reasoning,
        };

        if totals.is_zero() {
            return None;
        }

        self.sessions.insert(snapshot.session_id.clone(), totals);
        Some(self.snapshot())
    }

    fn add_delta(&mut self, session_id: &str, delta: &SessionTotals) {
        self.sessions
            .entry(session_id.to_string())
            .or_default()
            .add_assign(delta);
    }

    pub fn snapshot(&self) -> GlobalTokenUsageSnapshot {
        let mut total_input = 0;
        let mut total_cached_input = 0;
        let mut total_output = 0;
        let mut total_reasoning = 0;

        for totals in self.sessions.values() {
            total_input += totals.input;
            total_cached_input += totals.cached_input;
            total_output += totals.output;
            total_reasoning += totals.reasoning;
        }

        GlobalTokenUsageSnapshot {
            message_type: "global_token_usage".to_string(),
            total_input,
            total_cached_input,
            total_output,
            total_reasoning,
            total_tokens: total_input + total_output,
            session_count: self.sessions.len(),
            updated_at: Utc::now(),
        }
    }

    fn merge_session(&mut self, session_id: String, totals: SessionTotals) {
        if totals.is_zero() {
            return;
        }

        match self.sessions.get(&session_id) {
            Some(existing) if existing.total_tokens() > totals.total_tokens() => {}
            _ => {
                self.sessions.insert(session_id, totals);
            }
        }
    }
}

#[derive(Debug)]
pub struct DailyTokenAggregator {
    local_date: NaiveDate,
    sessions: HashMap<String, SessionTotals>,
    request_counts: HashMap<String, u64>,
}

impl Default for DailyTokenAggregator {
    fn default() -> Self {
        Self::new(Local::now().date_naive())
    }
}

impl DailyTokenAggregator {
    pub fn new(local_date: NaiveDate) -> Self {
        Self {
            local_date,
            sessions: HashMap::new(),
            request_counts: HashMap::new(),
        }
    }

    #[cfg(test)]
    pub fn update_from_snapshot(
        &mut self,
        snapshot: &TokenSnapshot,
    ) -> Option<DailyTokenUsageSnapshot> {
        let snapshot_date = snapshot.timestamp.with_timezone(&Local).date_naive();
        if snapshot_date < self.local_date {
            return None;
        }

        if snapshot_date > self.local_date {
            self.local_date = snapshot_date;
            self.sessions.clear();
            self.request_counts.clear();
        }

        let delta = SessionTotals {
            input: snapshot.delta_input,
            cached_input: snapshot.delta_cached_input,
            output: snapshot.delta_output,
            reasoning: snapshot.delta_reasoning,
        };

        if delta.is_zero() {
            return None;
        }
        self.add_delta(&snapshot.session_id, &delta, snapshot_date);
        Some(self.snapshot())
    }

    fn add_delta(&mut self, session_id: &str, delta: &SessionTotals, date: NaiveDate) {
        if date > self.local_date {
            self.local_date = date;
            self.sessions.clear();
            self.request_counts.clear();
        }
        if date != self.local_date || delta.is_zero() {
            return;
        }

        self.sessions
            .entry(session_id.to_string())
            .or_default()
            .add_assign(delta);
        *self
            .request_counts
            .entry(session_id.to_string())
            .or_default() += 1;
    }

    pub fn snapshot(&self) -> DailyTokenUsageSnapshot {
        let mut total_input = 0;
        let mut total_cached_input = 0;
        let mut total_output = 0;
        let mut total_reasoning = 0;

        for totals in self.sessions.values() {
            total_input += totals.input;
            total_cached_input += totals.cached_input;
            total_output += totals.output;
            total_reasoning += totals.reasoning;
        }

        DailyTokenUsageSnapshot {
            message_type: "daily_token_usage".to_string(),
            local_date: self.local_date.format("%Y-%m-%d").to_string(),
            total_input,
            total_cached_input,
            total_output,
            total_reasoning,
            total_tokens: total_input + total_output,
            session_count: self.sessions.len(),
            request_count: self.request_counts.values().sum(),
            updated_at: Utc::now(),
        }
    }

    fn merge_session(
        &mut self,
        session_id: String,
        daily_totals: SessionTotals,
        request_count: u64,
    ) {
        if daily_totals.is_zero() {
            return;
        }

        match self.sessions.get(&session_id) {
            Some(existing) if existing.total_tokens() > daily_totals.total_tokens() => {}
            _ => {
                self.sessions.insert(session_id.clone(), daily_totals);
            }
        }
        self.request_counts
            .entry(session_id)
            .and_modify(|existing| *existing = (*existing).max(request_count))
            .or_insert(request_count);
    }
}

#[derive(Debug)]
struct FileTokenScan {
    session_id: String,
    lifetime_totals: SessionTotals,
    daily_totals: SessionTotals,
    daily_request_count: u64,
    latest_totals: SessionTotals,
    /// Last `token_count` payload observed in the file, used to rebuild the session's
    /// latest `TokenSnapshot` for startup replay.
    latest_token_payload: Option<Value>,
    /// Timestamp of the last `token_count` event, used as the rebuilt snapshot's
    /// timestamp. Falls back to the file's modification time when the event payload
    /// lacks an RFC 3339 timestamp.
    latest_token_timestamp: Option<DateTime<Utc>>,
}

fn scan_token_file(path: &Path, local_date: NaiveDate) -> Option<FileTokenScan> {
    let file = std::fs::File::open(path).ok()?;
    let reader = BufReader::new(file);
    let fallback_date = file_modified_local_date(path);
    let fallback_timestamp = file_modified_utc(path);
    let replay_boundary = history_replay_boundary(path);

    let mut session_id = session_id_from_path(path);
    let mut identity_resolved = false;
    let mut latest_totals = None;
    let mut previous_totals = SessionTotals::default();
    let mut lifetime_totals = SessionTotals::default();
    let mut daily_totals = SessionTotals::default();
    let mut daily_request_count = 0;
    let mut latest_token_payload: Option<Value> = None;
    let mut latest_token_timestamp: Option<DateTime<Utc>> = None;

    for (line_index, line) in reader.lines().map_while(Result::ok).enumerate() {
        let Ok(parsed) = serde_json::from_str::<Value>(&line) else {
            continue;
        };

        if !identity_resolved {
            if let Some(extracted_session_id) = extract_session_id(&parsed) {
                session_id = Some(extracted_session_id);
                identity_resolved = true;
            }
        }

        let Some(payload) = parsed.get("payload") else {
            continue;
        };
        if parsed.get("type").and_then(|value| value.as_str()) != Some("event_msg")
            || payload.get("type").and_then(|value| value.as_str()) != Some("token_count")
        {
            continue;
        }

        let totals = SessionTotals {
            input: token_count_value(payload, "input_tokens").unwrap_or(0),
            cached_input: token_count_value(payload, "cached_input_tokens").unwrap_or(0),
            output: token_count_value(payload, "output_tokens").unwrap_or(0),
            reasoning: token_count_value(payload, "reasoning_tokens").unwrap_or(0),
        };
        let delta = totals.delta_from(&previous_totals);
        previous_totals = totals.clone();

        if !totals.is_zero() {
            latest_totals = Some(totals.clone());
            latest_token_payload = Some(payload.clone());
            let event_timestamp = parsed
                .get("timestamp")
                .and_then(Value::as_str)
                .and_then(parse_utc_timestamp)
                .or(fallback_timestamp);
            latest_token_timestamp = event_timestamp;
        }

        let event_date = parsed
            .get("timestamp")
            .and_then(Value::as_str)
            .and_then(local_date_from_timestamp)
            .or(fallback_date);

        let line_number = line_index + 1;
        let is_history_snapshot = replay_boundary
            .map(|boundary| line_number < boundary)
            .unwrap_or(false);
        if let Some(event_date) = event_date.filter(|_| !is_history_snapshot) {
            lifetime_totals.add_assign(&delta);
            if event_date == local_date && !delta.is_zero() {
                daily_totals.add_assign(&delta);
                daily_request_count += 1;
            }
        }
    }

    Some(FileTokenScan {
        session_id: session_id?,
        lifetime_totals,
        daily_totals,
        daily_request_count,
        latest_totals: latest_totals?,
        latest_token_payload,
        latest_token_timestamp,
    })
}

fn history_replay_boundary(path: &Path) -> Option<usize> {
    let file = std::fs::File::open(path).ok()?;
    let mut is_subagent = false;
    let mut metadata_classified = false;
    let mut first_inter_agent = None;
    let mut last_thread_settings = None;

    for (line_index, line) in BufReader::new(file)
        .lines()
        .map_while(Result::ok)
        .enumerate()
    {
        let Ok(parsed) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        if !metadata_classified
            && parsed.get("type").and_then(Value::as_str) == Some("session_meta")
        {
            is_subagent = is_subagent_metadata(&parsed);
            metadata_classified = true;
        }
        if parsed
            .get("type")
            .and_then(Value::as_str)
            .is_some_and(|event_type| event_type.starts_with("inter_agent_communication"))
            && first_inter_agent.is_none()
        {
            first_inter_agent = Some(line_index + 1);
        }
        if parsed.get("type").and_then(Value::as_str) == Some("event_msg")
            && parsed
                .get("payload")
                .and_then(|payload| payload.get("type"))
                .and_then(Value::as_str)
                == Some("thread_settings_applied")
        {
            last_thread_settings = Some(line_index + 1);
        }
    }

    is_subagent
        .then_some(first_inter_agent.or(last_thread_settings))
        .flatten()
}

fn is_subagent_metadata(parsed: &Value) -> bool {
    let payload = parsed.get("payload").unwrap_or(&Value::Null);
    payload
        .get("forked_from_id")
        .and_then(Value::as_str)
        .is_some()
        || payload
            .get("parent_thread_id")
            .and_then(Value::as_str)
            .is_some()
        || payload.get("thread_source").and_then(Value::as_str) == Some("subagent")
        || payload
            .get("source")
            .and_then(|source| source.get("subagent"))
            .is_some()
}

fn collect_jsonl_files(root: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    collect_jsonl_files_inner(root, &mut files);
    files
}

fn collect_jsonl_files_inner(dir: &Path, files: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_jsonl_files_inner(&path, files);
        } else if path.extension().and_then(|ext| ext.to_str()) == Some("jsonl") {
            files.push(path);
        }
    }
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

fn local_date_from_timestamp(timestamp: &str) -> Option<NaiveDate> {
    DateTime::parse_from_rfc3339(timestamp)
        .ok()
        .map(|date| date.with_timezone(&Local).date_naive())
}

fn file_modified_local_date(path: &Path) -> Option<NaiveDate> {
    let modified = std::fs::metadata(path).ok()?.modified().ok()?;
    let datetime: DateTime<Local> = modified.into();
    Some(datetime.date_naive())
}

fn parse_utc_timestamp(timestamp: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(timestamp)
        .ok()
        .map(|date| date.with_timezone(&Utc))
}

fn file_modified_utc(path: &Path) -> Option<DateTime<Utc>> {
    let modified = std::fs::metadata(path).ok()?.modified().ok()?;
    let datetime: DateTime<Utc> = modified.into();
    Some(datetime)
}

#[cfg(test)]
mod tests {
    use super::{DailyTokenAggregator, GlobalTokenAggregator, TokenUsageAggregators};
    use crate::parser::token_parser::TokenSnapshot;
    use chrono::{NaiveDate, TimeZone, Utc};
    use serde_json::json;
    use std::fs;
    use std::io::Write;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn scans_latest_token_count_per_session() {
        let root = temp_dir("scan");
        let day = root.join("2026/06/28");
        fs::create_dir_all(&day).unwrap();

        write_jsonl_lines(
            &day.join("rollout-2026-06-28T10-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "session-a"}}),
                token_count(100, 40, 10, 1),
                token_count(140, 50, 20, 2),
            ],
        );
        write_jsonl_lines(
            &day.join("rollout-2026-06-28T11-00-00-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl"),
            &[
                json!({"type": "event_msg", "payload": {"type": "token_count", "info": null}}),
                token_count(200, 100, 30, 3),
            ],
        );

        let snapshot = GlobalTokenAggregator::load_from_sessions_dir(&root).snapshot();
        let _ = fs::remove_dir_all(&root);

        assert_eq!(snapshot.session_count, 2);
        assert_eq!(snapshot.total_input, 340);
        assert_eq!(snapshot.total_cached_input, 150);
        assert_eq!(snapshot.total_output, 50);
        assert_eq!(snapshot.total_reasoning, 5);
        assert_eq!(snapshot.total_tokens, 390);
    }

    #[test]
    fn runtime_update_replaces_one_session_without_double_counting() {
        let mut aggregator = GlobalTokenAggregator::default();

        let first = snapshot("session-a", 100, 40, 10, 1);
        let second = snapshot("session-a", 200, 80, 25, 2);

        let global = aggregator.update_from_snapshot(&first).unwrap();
        assert_eq!(global.total_tokens, 110);
        assert_eq!(global.session_count, 1);

        let global = aggregator.update_from_snapshot(&second).unwrap();
        assert_eq!(global.total_tokens, 225);
        assert_eq!(global.session_count, 1);
    }

    #[test]
    fn runtime_update_ignores_placeholder_zero_token_count() {
        let mut aggregator = GlobalTokenAggregator::default();
        aggregator
            .update_from_snapshot(&snapshot("session-a", 100, 40, 10, 1))
            .unwrap();

        assert!(aggregator
            .update_from_snapshot(&snapshot("session-b", 0, 0, 0, 0))
            .is_none());
        assert_eq!(aggregator.snapshot().session_count, 1);
        assert_eq!(aggregator.snapshot().total_tokens, 110);
    }

    #[test]
    fn scans_daily_token_count_for_local_date() {
        let root = temp_dir("daily-scan");
        let day = root.join("2026/06/28");
        fs::create_dir_all(&day).unwrap();

        write_jsonl_lines(
            &day.join("rollout-2026-06-28T10-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "session-a"}}),
                token_count_at(100, 40, 10, 1, "2026-06-27T08:00:00Z"),
                token_count_at(150, 70, 25, 2, "2026-06-28T08:00:00Z"),
            ],
        );
        write_jsonl_lines(
            &day.join("rollout-2026-06-28T11-00-00-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "session-b"}}),
                token_count_at(200, 100, 30, 3, "2026-06-28T09:00:00Z"),
            ],
        );

        let aggregators = TokenUsageAggregators::load_from_sessions_dir_for_date(
            &root,
            NaiveDate::from_ymd_opt(2026, 6, 28).unwrap(),
        );
        let daily = aggregators.daily.snapshot();
        let _ = fs::remove_dir_all(&root);

        assert_eq!(daily.session_count, 2);
        assert_eq!(daily.total_input, 250);
        assert_eq!(daily.total_cached_input, 130);
        assert_eq!(daily.total_output, 45);
        assert_eq!(daily.total_tokens, 295);
        assert_eq!(daily.request_count, 2);
    }

    #[test]
    fn subagent_counts_own_usage_without_replaying_parent_history() {
        let root = temp_dir("subagent-history");
        let day = root.join("2026/06/28");
        fs::create_dir_all(&day).unwrap();

        write_jsonl_lines(
            &day.join("rollout-2026-06-28T10-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "root-session", "thread_source": "user"}}),
                token_count_at(100, 40, 10, 1, "2026-06-28T08:00:00Z"),
            ],
        );
        write_jsonl_lines(
            &day.join("rollout-2026-06-28T10-01-00-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {
                    "id": "child-session",
                    "forked_from_id": "root-session",
                    "thread_source": "subagent"
                }}),
                json!({"type": "session_meta", "payload": {"id": "root-session", "thread_source": "user"}}),
                token_count_at(100, 40, 10, 1, "2026-06-28T08:01:00Z"),
                json!({"type": "inter_agent_communication_metadata", "payload": {}}),
                token_count_at(180, 90, 25, 2, "2026-06-28T08:02:00Z"),
            ],
        );

        let aggregators = TokenUsageAggregators::load_from_sessions_dir_for_date(
            &root,
            NaiveDate::from_ymd_opt(2026, 6, 28).unwrap(),
        );
        let global = aggregators.global.snapshot();
        let daily = aggregators.daily.snapshot();
        let _ = fs::remove_dir_all(&root);

        assert_eq!(global.session_count, 2);
        assert_eq!(global.total_tokens, 205);
        assert_eq!(daily.session_count, 2);
        assert_eq!(daily.total_tokens, 205);
        assert_eq!(daily.request_count, 2);
        let child = aggregators
            .latest_snapshots
            .iter()
            .find(|snapshot| snapshot.session_id == "child-session")
            .expect("subagent remains available for active-session display");
        assert_eq!(child.total_input + child.total_output, 205);
    }

    #[test]
    fn daily_request_count_ignores_duplicate_cumulative_frames() {
        let root = temp_dir("daily-request-count");
        let day = root.join("2026/06/28");
        fs::create_dir_all(&day).unwrap();
        write_jsonl_lines(
            &day.join("rollout-2026-06-28T10-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "session-a"}}),
                token_count_at(100, 40, 10, 1, "2026-06-28T08:00:00Z"),
                token_count_at(100, 40, 10, 1, "2026-06-28T08:00:01Z"),
                token_count_at(150, 70, 25, 2, "2026-06-28T08:00:02Z"),
            ],
        );

        let daily = TokenUsageAggregators::load_from_sessions_dir_for_date(
            &root,
            NaiveDate::from_ymd_opt(2026, 6, 28).unwrap(),
        )
        .daily
        .snapshot();
        let _ = fs::remove_dir_all(&root);

        assert_eq!(daily.total_tokens, 175);
        assert_eq!(daily.request_count, 2);
    }

    #[test]
    fn persisted_ledger_survives_session_file_deletion() {
        let root = temp_dir("persisted-deletion");
        let sessions = root.join("sessions/2026/06/28");
        fs::create_dir_all(&sessions).unwrap();
        let session_file =
            sessions.join("rollout-2026-06-28T10-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl");
        write_jsonl_lines(
            &session_file,
            &[
                json!({"type": "session_meta", "payload": {"id": "session-a"}}),
                token_count(150, 70, 25, 2),
            ],
        );

        let sessions_root = root.join("sessions");
        let mut first = TokenUsageAggregators::load_from_sessions_dir(&sessions_root);
        assert_eq!(first.global.snapshot().total_tokens, 175);
        first.flush_if_dirty().unwrap();

        fs::remove_file(session_file).unwrap();
        let second = TokenUsageAggregators::load_from_sessions_dir(&sessions_root);

        assert_eq!(second.global.snapshot().total_input, 150);
        assert_eq!(second.global.snapshot().total_cached_input, 70);
        assert_eq!(second.global.snapshot().total_output, 25);
        assert_eq!(second.global.snapshot().total_tokens, 175);
        assert_eq!(second.global.snapshot().session_count, 1);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn latest_snapshots_rebuild_each_session_latest_token_count() {
        let root = temp_dir("latest-snapshots");
        let day = root.join("2026/06/28");
        fs::create_dir_all(&day).unwrap();

        write_jsonl_lines(
            &day.join("rollout-2026-06-28T10-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "session-a"}}),
                token_count_at(100, 40, 10, 1, "2026-06-28T08:00:00Z"),
                token_count_at(150, 70, 25, 2, "2026-06-28T08:30:00Z"),
            ],
        );
        write_jsonl_lines(
            &day.join("rollout-2026-06-28T11-00-00-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "session-b"}}),
                token_count_at(200, 100, 30, 3, "2026-06-28T09:00:00Z"),
            ],
        );

        let aggregators = TokenUsageAggregators::load_from_sessions_dir_for_date(
            &root,
            NaiveDate::from_ymd_opt(2026, 6, 28).unwrap(),
        );
        let _ = fs::remove_dir_all(&root);

        let snapshots = &aggregators.latest_snapshots;
        assert_eq!(snapshots.len(), 2);

        let session_a = snapshots
            .iter()
            .find(|snapshot| snapshot.session_id == "session-a")
            .expect("session-a rebuilt");
        // The rebuild reflects the latest cumulative totals, not the earlier row.
        assert_eq!(session_a.total_input, 150);
        assert_eq!(session_a.total_cached_input, 70);
        assert_eq!(session_a.total_output, 25);
        assert_eq!(session_a.total_input + session_a.total_output, 175);
        // Deltas are zeroed: this is a seeded baseline, not a live incremental turn.
        assert_eq!(session_a.delta_input, 0);
        assert_eq!(session_a.delta_output, 0);
        assert_eq!(session_a.turn_index, 0);
        assert_eq!(
            session_a.timestamp,
            Utc.with_ymd_and_hms(2026, 6, 28, 8, 30, 0).unwrap()
        );

        let session_b = snapshots
            .iter()
            .find(|snapshot| snapshot.session_id == "session-b")
            .expect("session-b rebuilt");
        assert_eq!(session_b.total_input, 200);
        assert_eq!(session_b.total_output, 30);
        assert_eq!(session_b.total_input + session_b.total_output, 230);
        assert_eq!(session_b.turn_index, 0);
    }

    #[test]
    fn latest_snapshots_omits_files_without_token_counts() {
        let root = temp_dir("latest-snapshots-empty");
        let day = root.join("2026/06/28");
        fs::create_dir_all(&day).unwrap();

        // A session file with metadata only and a zero-totals token_count row should not
        // contribute a rebuilt snapshot (scan_token_file drops files whose latest totals
        // are zero, and snapshot_from_history rejects zero payloads).
        write_jsonl_lines(
            &day.join("rollout-2026-06-28T12-00-00-cccccccc-cccc-cccc-cccc-cccccccccccc.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "session-c"}}),
                token_count(0, 0, 0, 0),
            ],
        );

        let aggregators = TokenUsageAggregators::load_from_sessions_dir_for_date(
            &root,
            NaiveDate::from_ymd_opt(2026, 6, 28).unwrap(),
        );
        let _ = fs::remove_dir_all(&root);

        assert!(aggregators.latest_snapshots.is_empty());
    }

    #[test]
    fn daily_scan_excludes_sessions_without_today_tokens() {
        let root = temp_dir("daily-exclude");
        let day = root.join("2026/06/27");
        fs::create_dir_all(&day).unwrap();

        write_jsonl_lines(
            &day.join("rollout-2026-06-27T10-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"),
            &[
                json!({"type": "session_meta", "payload": {"id": "session-a"}}),
                token_count_at(100, 40, 10, 1, "2026-06-27T08:00:00Z"),
            ],
        );

        let daily = TokenUsageAggregators::load_from_sessions_dir_for_date(
            &root,
            NaiveDate::from_ymd_opt(2026, 6, 28).unwrap(),
        )
        .daily
        .snapshot();
        let _ = fs::remove_dir_all(&root);

        assert_eq!(daily.session_count, 0);
        assert_eq!(daily.total_tokens, 0);
    }

    #[test]
    fn daily_runtime_update_resets_on_next_local_day() {
        let mut aggregator =
            DailyTokenAggregator::new(NaiveDate::from_ymd_opt(2026, 6, 28).unwrap());

        let first = snapshot_at(
            "session-a",
            100,
            40,
            10,
            1,
            100,
            40,
            10,
            1,
            Utc.with_ymd_and_hms(2026, 6, 28, 8, 0, 0).unwrap(),
        );
        let next_day = snapshot_at(
            "session-a",
            130,
            50,
            20,
            2,
            30,
            10,
            10,
            1,
            Utc.with_ymd_and_hms(2026, 6, 29, 8, 0, 0).unwrap(),
        );

        assert_eq!(
            aggregator
                .update_from_snapshot(&first)
                .unwrap()
                .total_tokens,
            110
        );
        let daily = aggregator.update_from_snapshot(&next_day).unwrap();

        assert_eq!(daily.local_date, "2026-06-29");
        assert_eq!(daily.total_tokens, 40);
    }

    fn token_count(input: u64, cached: u64, output: u64, reasoning: u64) -> serde_json::Value {
        token_count_value(input, cached, output, reasoning, None)
    }

    fn token_count_at(
        input: u64,
        cached: u64,
        output: u64,
        reasoning: u64,
        timestamp: &str,
    ) -> serde_json::Value {
        token_count_value(input, cached, output, reasoning, Some(timestamp))
    }

    fn token_count_value(
        input: u64,
        cached: u64,
        output: u64,
        reasoning: u64,
        timestamp: Option<&str>,
    ) -> serde_json::Value {
        let mut value = json!({
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "info": {
                    "total_token_usage": {
                        "input_tokens": input,
                        "cached_input_tokens": cached,
                        "output_tokens": output,
                        "reasoning_output_tokens": reasoning,
                        "total_tokens": input + output
                    }
                }
            }
        });

        if let Some(timestamp) = timestamp {
            value["timestamp"] = json!(timestamp);
        }

        value
    }

    #[allow(clippy::too_many_arguments)]
    fn snapshot_at(
        session_id: &str,
        input: u64,
        cached: u64,
        output: u64,
        reasoning: u64,
        delta_input: u64,
        delta_cached: u64,
        delta_output: u64,
        delta_reasoning: u64,
        timestamp: chrono::DateTime<Utc>,
    ) -> TokenSnapshot {
        TokenSnapshot {
            timestamp,
            delta_input,
            delta_cached_input: delta_cached,
            delta_uncached_input: delta_input.saturating_sub(delta_cached),
            delta_output,
            delta_reasoning,
            ..snapshot(session_id, input, cached, output, reasoning)
        }
    }

    fn snapshot(
        session_id: &str,
        input: u64,
        cached: u64,
        output: u64,
        reasoning: u64,
    ) -> TokenSnapshot {
        TokenSnapshot {
            session_id: session_id.to_string(),
            session_file: "/tmp/test.jsonl".to_string(),
            delta_input: input,
            delta_cached_input: cached,
            delta_uncached_input: input.saturating_sub(cached),
            delta_output: output,
            delta_reasoning: reasoning,
            total_input: input,
            total_cached_input: cached,
            total_uncached_input: input.saturating_sub(cached),
            total_output: output,
            total_reasoning: reasoning,
            context_used: input + output,
            context_window: None,
            cache_hit_rate: 0.0,
            timestamp: Utc::now(),
            turn_index: 1,
        }
    }

    fn temp_dir(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "codex-island-global-token-{label}-{}-{nanos}",
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
