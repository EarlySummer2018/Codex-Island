use crate::parser::RawEvent;
use crate::token_usage::token_count_value;
use crate::watcher::jsonl_watcher::RawJsonlLine;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;
use tracing::debug;

#[derive(Debug, Clone, Default)]
struct TokenAccumulator {
    input_tokens: u64,
    cached_input_tokens: u64,
    output_tokens: u64,
    reasoning_tokens: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TokenSnapshot {
    pub session_id: String,
    pub session_file: String,

    pub delta_input: u64,
    pub delta_cached_input: u64,
    pub delta_uncached_input: u64,
    pub delta_output: u64,
    pub delta_reasoning: u64,

    pub total_input: u64,
    pub total_cached_input: u64,
    pub total_uncached_input: u64,
    pub total_output: u64,
    pub total_reasoning: u64,

    pub cache_hit_rate: f64,
    pub timestamp: DateTime<Utc>,
    pub turn_index: u32,
}

impl TokenSnapshot {
    pub fn cache_hit_percent(&self) -> String {
        format!("{:.1}%", self.cache_hit_rate * 100.0)
    }

    pub fn total_tokens(&self) -> u64 {
        self.total_input + self.total_output
    }

    pub fn estimated_saving_ratio(&self) -> f64 {
        if self.delta_input == 0 {
            return 0.0;
        }

        let saved = self.delta_cached_input as f64 * 0.9;
        saved / self.delta_input as f64
    }
}

#[derive(Debug, Default)]
pub struct TokenParser {
    accumulators: HashMap<String, TokenAccumulator>,
    turn_indices: HashMap<String, u32>,
}

impl TokenParser {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn process_event(&mut self, event: &RawEvent) -> Option<TokenSnapshot> {
        let RawEvent::JsonlLine(line) = event else {
            return None;
        };

        self.process_line(line)
    }

    pub fn process_line(&mut self, line: &RawJsonlLine) -> Option<TokenSnapshot> {
        if line.payload_type.as_deref() != Some("token_count") {
            return None;
        }

        self.process_parsed(&line.session_file, line.session_id.as_deref(), &line.parsed)
    }

    pub fn process_parsed(
        &mut self,
        session_file: &Path,
        session_id: Option<&str>,
        parsed: &Value,
    ) -> Option<TokenSnapshot> {
        let event_type = parsed
            .get("payload")
            .and_then(|payload| payload.get("type"))
            .and_then(|value| value.as_str())?;

        if event_type != "token_count" {
            return None;
        }

        let payload = parsed.get("payload")?;
        let file_key = session_file.to_string_lossy().to_string();
        let current = TokenAccumulator {
            input_tokens: token_count_value(payload, "input_tokens").unwrap_or(0),
            cached_input_tokens: token_count_value(payload, "cached_input_tokens").unwrap_or(0),
            output_tokens: token_count_value(payload, "output_tokens").unwrap_or(0),
            reasoning_tokens: token_count_value(payload, "reasoning_tokens").unwrap_or(0),
        };

        debug!(
            "token_count raw: input={} cached={} output={} reasoning={}",
            current.input_tokens,
            current.cached_input_tokens,
            current.output_tokens,
            current.reasoning_tokens
        );

        let previous = self
            .accumulators
            .get(&file_key)
            .cloned()
            .unwrap_or_default();

        let delta_input = current.input_tokens.saturating_sub(previous.input_tokens);
        let delta_cached_input = current
            .cached_input_tokens
            .saturating_sub(previous.cached_input_tokens);
        let delta_output = current.output_tokens.saturating_sub(previous.output_tokens);
        let delta_reasoning = current
            .reasoning_tokens
            .saturating_sub(previous.reasoning_tokens);
        let delta_uncached_input = delta_input.saturating_sub(delta_cached_input);

        let turn_index = {
            let index = self.turn_indices.entry(file_key.clone()).or_insert(0);
            *index += 1;
            *index
        };

        let cache_hit_rate = if current.input_tokens > 0 {
            current.cached_input_tokens as f64 / current.input_tokens as f64
        } else {
            0.0
        };

        self.accumulators.insert(file_key.clone(), current.clone());

        let snapshot = TokenSnapshot {
            session_id: session_id.unwrap_or("unknown").to_string(),
            session_file: file_key,
            delta_input,
            delta_cached_input,
            delta_uncached_input,
            delta_output,
            delta_reasoning,
            total_input: current.input_tokens,
            total_cached_input: current.cached_input_tokens,
            total_uncached_input: current
                .input_tokens
                .saturating_sub(current.cached_input_tokens),
            total_output: current.output_tokens,
            total_reasoning: current.reasoning_tokens,
            cache_hit_rate,
            timestamp: Utc::now(),
            turn_index,
        };

        debug!(
            "TokenSnapshot: turn={} delta_input={} delta_cached={} delta_uncached={} delta_output={} cache={:.1}%",
            snapshot.turn_index,
            snapshot.delta_input,
            snapshot.delta_cached_input,
            snapshot.delta_uncached_input,
            snapshot.delta_output,
            snapshot.cache_hit_rate * 100.0
        );

        Some(snapshot)
    }

    pub fn clear_session(&mut self, session_file: &str) {
        self.accumulators.remove(session_file);
        self.turn_indices.remove(session_file);
    }
}

#[cfg(test)]
mod tests {
    use super::TokenParser;
    use crate::watcher::jsonl_watcher::RawJsonlLine;
    use serde_json::{json, Value};
    use std::path::PathBuf;

    fn token_value(input: u64, cached: u64, output: u64, reasoning: u64) -> Value {
        json!({
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "input_tokens": input,
                "cached_input_tokens": cached,
                "output_tokens": output,
                "reasoning_tokens": reasoning
            }
        })
    }

    fn real_codex_token_value(input: u64, cached: u64, output: u64, reasoning: u64) -> Value {
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
                    },
                    "last_token_usage": {
                        "input_tokens": 1,
                        "cached_input_tokens": 1,
                        "output_tokens": 1,
                        "reasoning_output_tokens": 0,
                        "total_tokens": 2
                    }
                }
            }
        })
    }

    fn token_line(input: u64, cached: u64, output: u64, reasoning: u64) -> RawJsonlLine {
        RawJsonlLine {
            session_file: PathBuf::from("/tmp/rollout-test.jsonl"),
            session_id: Some("sess-1".to_string()),
            event_type: "event_msg".to_string(),
            payload_type: Some("token_count".to_string()),
            parsed: token_value(input, cached, output, reasoning),
        }
    }

    fn real_codex_token_line(input: u64, cached: u64, output: u64, reasoning: u64) -> RawJsonlLine {
        RawJsonlLine {
            session_file: PathBuf::from("/tmp/rollout-real-test.jsonl"),
            session_id: Some("sess-1".to_string()),
            event_type: "event_msg".to_string(),
            payload_type: Some("token_count".to_string()),
            parsed: real_codex_token_value(input, cached, output, reasoning),
        }
    }

    #[test]
    fn first_event_uses_full_value_as_delta() {
        let mut parser = TokenParser::new();
        let snapshot = parser.process_line(&token_line(1200, 800, 50, 0)).unwrap();

        assert_eq!(snapshot.delta_input, 1200);
        assert_eq!(snapshot.delta_cached_input, 800);
        assert_eq!(snapshot.delta_uncached_input, 400);
        assert_eq!(snapshot.delta_output, 50);
        assert_eq!(snapshot.turn_index, 1);
    }

    #[test]
    fn calculates_delta_between_token_count_events() {
        let mut parser = TokenParser::new();
        parser.process_line(&token_line(1200, 800, 50, 0));

        let snapshot = parser
            .process_line(&token_line(2800, 1600, 320, 10))
            .unwrap();

        assert_eq!(snapshot.delta_input, 1600);
        assert_eq!(snapshot.delta_cached_input, 800);
        assert_eq!(snapshot.delta_uncached_input, 800);
        assert_eq!(snapshot.delta_output, 270);
        assert_eq!(snapshot.delta_reasoning, 10);
        assert_eq!(snapshot.turn_index, 2);
    }

    #[test]
    fn parses_real_codex_nested_token_count_events() {
        let mut parser = TokenParser::new();

        let snapshot = parser
            .process_line(&real_codex_token_line(37129849, 36520192, 113761, 31644))
            .unwrap();

        assert_eq!(snapshot.total_input, 37129849);
        assert_eq!(snapshot.total_cached_input, 36520192);
        assert_eq!(snapshot.total_output, 113761);
        assert_eq!(snapshot.total_reasoning, 31644);
        assert_eq!(snapshot.delta_output, 113761);
        assert_eq!(snapshot.turn_index, 1);
    }

    #[test]
    fn computes_cache_hit_rate_from_totals() {
        let mut parser = TokenParser::new();
        let snapshot = parser.process_line(&token_line(1000, 750, 100, 0)).unwrap();

        assert!((snapshot.cache_hit_rate - 0.75).abs() < 0.001);
        assert_eq!(snapshot.cache_hit_percent(), "75.0%");
    }

    #[test]
    fn ignores_non_token_events() {
        let mut parser = TokenParser::new();
        let line = RawJsonlLine {
            session_file: PathBuf::from("/tmp/rollout-test.jsonl"),
            session_id: Some("sess-1".to_string()),
            event_type: "event_msg".to_string(),
            payload_type: Some("user_message".to_string()),
            parsed: json!({
                "type": "event_msg",
                "payload": { "type": "user_message" }
            }),
        };

        assert!(parser.process_line(&line).is_none());
    }

    #[test]
    fn never_emits_negative_delta_when_counts_reset() {
        let mut parser = TokenParser::new();
        parser.process_line(&token_line(5000, 3000, 200, 40));

        let snapshot = parser.process_line(&token_line(100, 0, 10, 0)).unwrap();

        assert_eq!(snapshot.delta_input, 0);
        assert_eq!(snapshot.delta_cached_input, 0);
        assert_eq!(snapshot.delta_uncached_input, 0);
        assert_eq!(snapshot.delta_output, 0);
        assert_eq!(snapshot.delta_reasoning, 0);
        assert_eq!(snapshot.total_input, 100);
    }

    #[test]
    fn clear_session_resets_delta_baseline() {
        let mut parser = TokenParser::new();
        let line = token_line(100, 50, 10, 0);
        parser.process_line(&line);
        parser.clear_session("/tmp/rollout-test.jsonl");

        let snapshot = parser.process_line(&line).unwrap();

        assert_eq!(snapshot.delta_input, 100);
        assert_eq!(snapshot.turn_index, 1);
    }
}
