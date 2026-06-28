use serde_json::Value;

pub(crate) fn token_count_value(payload: &Value, internal_key: &str) -> Option<u64> {
    let usage_key = match internal_key {
        "reasoning_tokens" => "reasoning_output_tokens",
        key => key,
    };

    number_field(payload, internal_key)
        .or_else(|| number_field(payload, usage_key))
        .or_else(|| total_usage(payload).and_then(|usage| number_field(usage, usage_key)))
        .or_else(|| total_usage(payload).and_then(|usage| number_field(usage, internal_key)))
}

fn total_usage(payload: &Value) -> Option<&Value> {
    payload
        .get("info")
        .and_then(|info| info.get("total_token_usage"))
}

fn number_field(value: &Value, key: &str) -> Option<u64> {
    value.get(key).and_then(|value| value.as_u64())
}

#[cfg(test)]
mod tests {
    use super::token_count_value;
    use serde_json::json;

    #[test]
    fn reads_direct_token_count_fields() {
        let payload = json!({
            "input_tokens": 10,
            "cached_input_tokens": 5,
            "output_tokens": 2,
            "reasoning_tokens": 1,
        });

        assert_eq!(token_count_value(&payload, "input_tokens"), Some(10));
        assert_eq!(token_count_value(&payload, "cached_input_tokens"), Some(5));
        assert_eq!(token_count_value(&payload, "output_tokens"), Some(2));
        assert_eq!(token_count_value(&payload, "reasoning_tokens"), Some(1));
    }

    #[test]
    fn reads_real_codex_total_token_usage_fields() {
        let payload = json!({
            "info": {
                "total_token_usage": {
                    "input_tokens": 120,
                    "cached_input_tokens": 40,
                    "output_tokens": 12,
                    "reasoning_output_tokens": 3,
                    "total_tokens": 132
                },
                "last_token_usage": {
                    "input_tokens": 50,
                    "cached_input_tokens": 20,
                    "output_tokens": 5,
                    "reasoning_output_tokens": 1,
                    "total_tokens": 55
                }
            },
            "rate_limits": {
                "primary": {}
            }
        });

        assert_eq!(token_count_value(&payload, "input_tokens"), Some(120));
        assert_eq!(token_count_value(&payload, "cached_input_tokens"), Some(40));
        assert_eq!(token_count_value(&payload, "output_tokens"), Some(12));
        assert_eq!(token_count_value(&payload, "reasoning_tokens"), Some(3));
    }
}
