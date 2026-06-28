use crate::parser::token_parser::TokenSnapshot;
use crate::token_usage::token_count_value;
use chrono::{DateTime, Utc};
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

#[derive(Debug, Default)]
pub struct GlobalTokenAggregator {
    sessions: HashMap<String, SessionTotals>,
}

impl GlobalTokenAggregator {
    pub fn load_from_sessions_dir(sessions_dir: impl AsRef<Path>) -> Self {
        let mut aggregator = Self::default();

        for path in collect_jsonl_files(sessions_dir.as_ref()) {
            if let Some((session_id, totals)) = latest_totals_from_file(&path) {
                aggregator.merge_session(session_id, totals);
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

fn latest_totals_from_file(path: &Path) -> Option<(String, SessionTotals)> {
    let file = std::fs::File::open(path).ok()?;
    let reader = BufReader::new(file);

    let mut session_id = session_id_from_path(path);
    let mut latest_totals = None;

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
            latest_totals = Some(totals);
        }
    }

    Some((session_id?, latest_totals?))
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

#[cfg(test)]
mod tests {
    use super::GlobalTokenAggregator;
    use crate::parser::token_parser::TokenSnapshot;
    use chrono::Utc;
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

    fn token_count(input: u64, cached: u64, output: u64, reasoning: u64) -> serde_json::Value {
        json!({
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
        })
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
