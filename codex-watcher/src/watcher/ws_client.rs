use anyhow::Result;
use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use serde_json::{json, Value};
use tokio::sync::mpsc;
use tokio::time::{sleep, Duration};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, info};

#[derive(Debug, Clone)]
pub struct WsConfig {
    pub host: String,
    pub port: u16,
    pub retry_interval: Duration,
}

impl WsConfig {
    pub fn from_env() -> Self {
        let mut config = Self::default();

        if let Ok(host) = std::env::var("CODEX_APP_SERVER_HOST") {
            config.host = host;
        }
        if let Ok(port) = std::env::var("CODEX_APP_SERVER_PORT") {
            if let Ok(port) = port.parse::<u16>() {
                config.port = port;
            }
        }

        config
    }
}

impl Default for WsConfig {
    fn default() -> Self {
        Self {
            host: "127.0.0.1".to_string(),
            port: 4500,
            retry_interval: Duration::from_secs(3),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct WsStateEvent {
    pub method: String,
    pub params: Value,
}

pub struct WsClient {
    config: WsConfig,
    tx: mpsc::Sender<WsStateEvent>,
}

impl WsClient {
    pub fn new(config: WsConfig, tx: mpsc::Sender<WsStateEvent>) -> Self {
        Self { config, tx }
    }

    pub async fn run_forever(self) {
        let url = format!("ws://{}:{}", self.config.host, self.config.port);
        info!("Connecting to Codex App-Server at {url}");

        loop {
            match self.connect_once(&url).await {
                Ok(()) => info!(
                    "WebSocket connection closed cleanly, reconnecting in {:?}",
                    self.config.retry_interval
                ),
                Err(error) => debug!(
                    "WebSocket connection error: {error}, retrying in {:?}",
                    self.config.retry_interval
                ),
            }

            sleep(self.config.retry_interval).await;
        }
    }

    async fn connect_once(&self, url: &str) -> Result<()> {
        let (ws_stream, _) = connect_async(url).await?;
        info!("WebSocket connected to Codex App-Server");

        let (mut write, mut read) = ws_stream.split();

        let init_msg = json!({
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": {
                "clientInfo": {
                    "name": "codex-island",
                    "title": "Codex Island",
                    "version": "0.1.0"
                },
                "capabilities": {
                    "experimentalApi": true
                }
            }
        });
        write.send(Message::Text(init_msg.to_string())).await?;

        let initialized = json!({
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": {}
        });
        write.send(Message::Text(initialized.to_string())).await?;

        while let Some(message) = read.next().await {
            match message? {
                Message::Text(text) => self.handle_ws_message(&text).await,
                Message::Close(_) => break,
                _ => {}
            }
        }

        Ok(())
    }

    async fn handle_ws_message(&self, text: &str) {
        let Ok(value) = serde_json::from_str::<Value>(text) else {
            return;
        };

        if value.get("id").is_some() {
            return;
        }

        let method = value
            .get("method")
            .and_then(|method| method.as_str())
            .unwrap_or("")
            .to_string();

        if !is_interesting_method(&method) {
            return;
        }

        debug!("WebSocket event: {method}");
        let event = WsStateEvent {
            method,
            params: value.get("params").cloned().unwrap_or(Value::Null),
        };
        let _ = self.tx.send(event).await;
    }
}

fn is_interesting_method(method: &str) -> bool {
    matches!(
        method,
        "thread/status/changed"
            | "turn/started"
            | "turn/completed"
            | "turn/start"
            | "turn/stop"
            | "item/started"
            | "item/completed"
            | "item/tool/requestUserInput"
            | "item/requestUserInput"
            | "item/commandExecution/requestApproval"
            | "item/fileChange/requestApproval"
            | "tool/approval/request"
    )
}

#[cfg(test)]
mod tests {
    use super::{is_interesting_method, WsClient, WsConfig};
    use futures_util::{SinkExt, StreamExt};
    use serde_json::json;
    use tokio::net::TcpListener;
    use tokio::sync::mpsc;
    use tokio::time::{timeout, Duration};
    use tokio_tungstenite::{accept_async, tungstenite::Message};

    #[test]
    fn recognizes_thread_turn_item_and_approval_notifications() {
        assert!(is_interesting_method("thread/status/changed"));
        assert!(is_interesting_method("turn/started"));
        assert!(is_interesting_method("turn/completed"));
        assert!(is_interesting_method("item/started"));
        assert!(is_interesting_method("item/completed"));
        assert!(is_interesting_method("item/commandExecution/requestApproval"));
        assert!(is_interesting_method("item/fileChange/requestApproval"));
        assert!(is_interesting_method("item/tool/requestUserInput"));
        assert!(is_interesting_method("item/requestUserInput"));
        assert!(!is_interesting_method("unrelated/event"));
    }

    #[tokio::test]
    async fn forwards_interesting_notifications_from_websocket() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();

        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut socket = accept_async(stream).await.unwrap();

            let _initialize = socket.next().await.unwrap().unwrap();
            let _initialized = socket.next().await.unwrap().unwrap();

            socket
                .send(Message::Text(
                    json!({
                        "jsonrpc": "2.0",
                        "method": "thread/status/changed",
                        "params": {
                            "threadId": "thread-1",
                            "status": {
                                "type": "active",
                                "activeFlags": ["waitingOnApproval"]
                            }
                        }
                    })
                    .to_string(),
                ))
                .await
                .unwrap();
            socket.close(None).await.unwrap();
        });

        let (tx, mut rx) = mpsc::channel(1);
        let client = WsClient::new(
            WsConfig {
                host: "127.0.0.1".to_string(),
                port,
                retry_interval: Duration::from_millis(10),
            },
            tx,
        );

        client
            .connect_once(&format!("ws://127.0.0.1:{port}"))
            .await
            .unwrap();

        let event = timeout(Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(event.method, "thread/status/changed");
        assert_eq!(event.params["threadId"], "thread-1");
        assert_eq!(event.params["status"]["type"], "active");

        server.await.unwrap();
    }
}
