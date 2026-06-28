pub mod jsonl_watcher;
pub mod ws_client;

use crate::parser::RawEvent;
use tokio::sync::mpsc;

pub async fn start_all_watchers(sessions_dir: &str, event_tx: mpsc::Sender<RawEvent>) {
    let (jsonl_tx, mut jsonl_rx) = mpsc::channel(512);
    let (ws_tx, mut ws_rx) = mpsc::channel(128);

    let watcher = jsonl_watcher::JsonlWatcher::new(sessions_dir, jsonl_tx);
    tokio::spawn(async move {
        if let Err(error) = watcher.start().await {
            tracing::error!("JSONL watcher error: {error}");
        }
    });

    let ws = ws_client::WsClient::new(ws_client::WsConfig::from_env(), ws_tx);
    tokio::spawn(async move {
        ws.run_forever().await;
    });

    let jsonl_event_tx = event_tx.clone();
    tokio::spawn(async move {
        while let Some(line) = jsonl_rx.recv().await {
            if jsonl_event_tx
                .send(RawEvent::JsonlLine(line))
                .await
                .is_err()
            {
                break;
            }
        }
    });

    tokio::spawn(async move {
        while let Some(ws_event) = ws_rx.recv().await {
            if event_tx.send(RawEvent::WsMessage(ws_event)).await.is_err() {
                break;
            }
        }
    });
}
