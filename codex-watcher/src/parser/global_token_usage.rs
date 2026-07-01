use crate::parser::token_parser::TokenSnapshot;
use crate::token_usage::token_count_value;
use chrono::{DateTime, Local, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
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
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug)]
pub struct TokenUsageAggregators {
    pub global: GlobalTokenAggregator,
    pub daily: DailyTokenAggregator,
}

impl TokenUsageAggregators {
    pub fn load_from_sessions_dir(sessions_dir: impl AsRef<Path>) -> Self {
        Self::load_from_sessions_dir_for_date(sessions_dir, Local::now().date_naive())
    }

    fn load_from_sessions_dir_for_date(
        sessions_dir: impl AsRef<Path>,
        local_date: NaiveDate,
    ) -> Self {
        let mut global = GlobalTokenAggregator::default();
        let mut daily = DailyTokenAggregator::new(local_date);

        for path in collect_jsonl_files(sessions_dir.as_ref()) {
            if let Some(scan) = scan_token_file(&path, local_date) {
                global.merge_session(scan.session_id.clone(), scan.latest_totals);

                if let Some(latest_today) = scan.latest_today_totals {
                    daily.merge_session(
                        scan.session_id,
                        latest_today.saturating_sub(&scan.daily_baseline),
                        scan.daily_baseline,
                    );
                }
            }
        }

        Self { global, daily }
    }

    pub fn update_from_snapshot(
        &mut self,
        snapshot: &TokenSnapshot,
    ) -> (
        Option<GlobalTokenUsageSnapshot>,
        Option<DailyTokenUsageSnapshot>,
    ) {
        (
            self.global.update_from_snapshot(snapshot),
            self.daily.update_from_snapshot(snapshot),
        )
    }
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
                aggregator.merge_session(scan.session_id, scan.latest_totals);
            }
        }

        aggregator
    }

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
    baselines: HashMap<String, SessionTotals>,
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
            baselines: HashMap::new(),
        }
    }

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
            self.baselines.clear();
        }

        let current = SessionTotals {
            input: snapshot.total_input,
            cached_input: snapshot.total_cached_input,
            output: snapshot.total_output,
            reasoning: snapshot.total_reasoning,
        };

        if current.is_zero() {
            return None;
        }

        let baseline = self
            .baselines
            .entry(snapshot.session_id.clone())
            .or_insert_with(|| {
                current.saturating_sub(&SessionTotals {
                    input: snapshot.delta_input,
                    cached_input: snapshot.delta_cached_input,
                    output: snapshot.delta_output,
                    reasoning: snapshot.delta_reasoning,
                })
            })
            .clone();
        let daily_totals = current.saturating_sub(&baseline);

        if daily_totals.is_zero() {
            return None;
        }

        self.sessions
            .insert(snapshot.session_id.clone(), daily_totals);
        Some(self.snapshot())
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
            updated_at: Utc::now(),
        }
    }

    fn merge_session(
        &mut self,
        session_id: String,
        daily_totals: SessionTotals,
        baseline: SessionTotals,
    ) {
        self.baselines
            .entry(session_id.clone())
            .and_modify(|existing| {
                if existing.total_tokens() < baseline.total_tokens() {
                    *existing = baseline.clone();
                }
            })
            .or_insert(baseline);

        if daily_totals.is_zero() {
            return;
        }

        match self.sessions.get(&session_id) {
            Some(existing) if existing.total_tokens() > daily_totals.total_tokens() => {}
            _ => {
                self.sessions.insert(session_id, daily_totals);
            }
        }
    }
}

#[derive(Debug)]
struct FileTokenScan {
    session_id: String,
    latest_totals: SessionTotals,
    daily_baseline: SessionTotals,
    latest_today_totals: Option<SessionTotals>,
}

fn scan_token_file(path: &Path, local_date: NaiveDate) -> Option<FileTokenScan> {
    let file = std::fs::File::open(path).ok()?;
    let reader = BufReader::new(file);
    let fallback_date = file_modified_local_date(path);

    let mut session_id = session_id_from_path(path);
    let mut latest_totals = None;
    let mut daily_baseline = SessionTotals::default();
    let mut latest_today_totals = None;

    for line in reader.lines().map_while(Result::ok) {
        let Ok(parsed) = serde_json::from_str::<Value>(&line) else {
            continue;
        };

        if let Some(extracted_session_id) = extract_session_id(&parsed) {
            session_id = Some(extracted_session_id);
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

        if !totals.is_zero() {
            latest_totals = Some(totals.clone());
        }

        let event_date = parsed
            .get("timestamp")
            .and_then(Value::as_str)
            .and_then(local_date_from_timestamp)
            .or(fallback_date);

        if let Some(event_date) = event_date {
            if event_date < local_date {
                daily_baseline = totals;
            } else if event_date == local_date {
                latest_today_totals = Some(totals);
            }
        }
    }

    Some(FileTokenScan {
        session_id: session_id?,
        latest_totals: latest_totals?,
        daily_baseline,
        latest_today_totals,
    })
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
