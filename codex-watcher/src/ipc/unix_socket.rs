use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::Value;
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
    token: Option<String>,
    global_token: Option<String>,
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

        if value.get("total_input").is_some() && value.get("delta_output").is_some() {
            self.token = Some(message.to_string());
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
        if let Some(token) = &self.token {
            messages.push(token.clone());
        }
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
