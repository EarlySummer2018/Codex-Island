use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use tokio::io::AsyncWriteExt;
use tokio::net::UnixListener;
use tokio::sync::broadcast;
use tracing::{debug, info, warn};

#[derive(Clone)]
pub struct IpcServer {
    tx: broadcast::Sender<String>,
    replay: Arc<Mutex<ReplayCache>>,
}

#[derive(Debug, Default)]
struct ReplayCache {
    state: Option<String>,
    /// Latest per-session `TokenSnapshot`, keyed by `session_id`. Kept as a map rather
    /// than a single slot so a freshly connected IPC client receives every session's
    /// current token frame from the replay cache, not just whichever one happened to be
    /// published last. Without this, the capsule shows all zeros at startup until the
    /// user asks codex another question and a live token_count event repopulates the
    /// single-slot cache.
    tokens: HashMap<String, String>,
    global_token: Option<String>,
    daily_token: Option<String>,
}

impl ReplayCache {
    fn update(&mut self, message: &str) {
        let Ok(value) = serde_json::from_str::<Value>(message) else {
            return;
        };

        if value.get("type").and_then(|value| value.as_str()) == Some("global_token_usage") {
            self.global_token = Some(message.to_string());
            return;
        }

        if value.get("type").and_then(|value| value.as_str()) == Some("daily_token_usage") {
            self.daily_token = Some(message.to_string());
            return;
        }

        if value.get("total_input").is_some() && value.get("delta_output").is_some() {
            if let Some(session_id) = value.get("session_id").and_then(|value| value.as_str()) {
                self.tokens
                    .insert(session_id.to_string(), message.to_string());
            }
            return;
        }

        if value.get("state").is_some() && value.get("session_id").is_some() {
            self.state = Some(message.to_string());
        }
    }

    fn messages(&self) -> Vec<String> {
        let mut messages = Vec::new();
        if let Some(global_token) = &self.global_token {
            messages.push(global_token.clone());
        }
        if let Some(daily_token) = &self.daily_token {
            messages.push(daily_token.clone());
        }
        messages.extend(self.tokens.values().cloned());
        if let Some(state) = &self.state {
            messages.push(state.clone());
        }
        messages
    }
}

impl IpcServer {
    pub async fn start(socket_path: impl Into<PathBuf>) -> Result<Self> {
        let socket_path = socket_path.into();
        cleanup_socket(&socket_path).await?;

        if let Some(parent) = socket_path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .with_context(|| format!("create socket directory {}", parent.display()))?;
        }

        let listener = UnixListener::bind(&socket_path)
            .with_context(|| format!("bind Unix socket {}", socket_path.display()))?;
        let (tx, _) = broadcast::channel::<String>(1024);
        let accept_tx = tx.clone();
        let replay = Arc::new(Mutex::new(ReplayCache::default()));
        let accept_replay = replay.clone();

        tokio::spawn(async move {
            info!("IPC Unix socket listening on {}", socket_path.display());
            loop {
                match listener.accept().await {
                    Ok((stream, _addr)) => {
                        let mut rx = accept_tx.subscribe();
                        let replay_messages = accept_replay
                            .lock()
                            .map(|cache| cache.messages())
                            .unwrap_or_default();
                        tokio::spawn(async move {
                            let mut stream = stream;
                            for message in replay_messages {
                                if stream.write_all(message.as_bytes()).await.is_err() {
                                    return;
                                }
                                if stream.write_all(b"\n").await.is_err() {
                                    return;
                                }
                            }

                            while let Ok(message) = rx.recv().await {
                                if stream.write_all(message.as_bytes()).await.is_err() {
                                    break;
                                }
                                if stream.write_all(b"\n").await.is_err() {
                                    break;
                                }
                            }
                        });
                    }
                    Err(error) => warn!("IPC accept error: {error}"),
                }
            }
        });

        Ok(Self { tx, replay })
    }

    pub fn publish<T>(&self, event: &T)
    where
        T: Serialize,
    {
        match serde_json::to_string(event) {
            Ok(message) => {
                if let Ok(mut replay) = self.replay.lock() {
                    replay.update(&message);
                }
                if let Err(error) = self.tx.send(message) {
                    debug!("No IPC clients received event: {error}");
                }
            }
            Err(error) => warn!("Failed to serialize IPC event: {error}"),
        }
    }
}

pub async fn cleanup_socket(socket_path: &Path) -> Result<()> {
    match tokio::fs::remove_file(socket_path).await {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => {
            Err(error).with_context(|| format!("remove stale socket {}", socket_path.display()))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ReplayCache;

    #[test]
    fn replay_cache_keeps_state_session_token_and_global_token() {
        let mut cache = ReplayCache::default();

        cache.update(
            r#"{"type":"global_token_usage","total_input":300,"total_cached_input":140,"total_output":37,"total_reasoning":3,"total_tokens":337,"session_count":2,"updated_at":"2026-06-28T08:00:00Z"}"#,
        );
        cache.update(
            r#"{"type":"daily_token_usage","local_date":"2026-06-28","total_input":120,"total_cached_input":40,"total_output":20,"total_reasoning":2,"total_tokens":140,"session_count":1,"updated_at":"2026-06-28T08:00:00Z"}"#,
        );
        cache.update(
            r#"{"session_id":"session-a","session_file":"/tmp/a.jsonl","delta_input":20,"delta_cached_input":10,"delta_uncached_input":10,"delta_output":7,"delta_reasoning":1,"total_input":80,"total_cached_input":20,"total_uncached_input":60,"total_output":7,"total_reasoning":1,"cache_hit_rate":0.25,"timestamp":"2026-06-28T08:00:00Z","turn_index":1}"#,
        );
        cache.update(
            r#"{"session_id":"session-a","state":"streaming","timestamp":"2026-06-28T08:00:00Z","await_reason":null}"#,
        );

        let messages = cache.messages();

        assert_eq!(messages.len(), 4);
        assert!(messages[0].contains(r#""type":"global_token_usage""#));
        assert!(messages[1].contains(r#""type":"daily_token_usage""#));
        assert!(messages[2].contains(r#""delta_output":7"#));
        assert!(messages[3].contains(r#""state":"streaming""#));
    }

    #[test]
    fn replay_cache_keeps_latest_token_per_session() {
        let mut cache = ReplayCache::default();

        // Two distinct sessions: each must be retained independently so a freshly
        // connected client receives both sessions' current token frames.
        cache.update(
            r#"{"session_id":"session-a","session_file":"/tmp/a.jsonl","delta_input":0,"delta_output":0,"total_input":80,"total_output":7,"timestamp":"2026-06-28T08:00:00Z","turn_index":0}"#,
        );
        cache.update(
            r#"{"session_id":"session-b","session_file":"/tmp/b.jsonl","delta_input":0,"delta_output":0,"total_input":200,"total_output":30,"timestamp":"2026-06-28T09:00:00Z","turn_index":0}"#,
        );
        // A later frame for session-a replaces only the session-a slot, leaving
        // session-b intact.
        cache.update(
            r#"{"session_id":"session-a","session_file":"/tmp/a.jsonl","delta_input":0,"delta_output":0,"total_input":150,"total_output":25,"timestamp":"2026-06-28T08:30:00Z","turn_index":0}"#,
        );

        let messages = cache.messages();

        assert_eq!(messages.len(), 2);
        let session_a = messages
            .iter()
            .find(|message| message.contains(r#""session_id":"session-a""#))
            .expect("session-a retained");
        let session_b = messages
            .iter()
            .find(|message| message.contains(r#""session_id":"session-b""#))
            .expect("session-b retained");
        // session-a holds the latest (superseding) totals, not the earlier row.
        assert!(session_a.contains(r#""total_input":150"#));
        assert!(session_b.contains(r#""total_input":200"#));
    }
}
