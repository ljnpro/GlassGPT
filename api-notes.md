# OpenAI Responses API - Streaming Events Reference

## Key SSE Event Types for Text Chat

### Text Output
- `response.output_text.delta` → `{ delta, content_index, item_id, output_index, sequence_number, type }`
- `response.output_text.done` → `{ content_index, item_id, logprobs, output_index, sequence_number, text, type }`

### Reasoning/Thinking
- `response.reasoning_summary_text.delta` → `{ delta, item_id, output_index, sequence_number, ... }`
- `response.reasoning_summary_text.done` → completed reasoning summary
- `response.reasoning.delta` → raw reasoning text delta (if available)

### Lifecycle
- `response.created` → response object created
- `response.in_progress` → response generation started
- `response.output_item.added` → new output item added
- `response.content_part.added` → new content part added
- `response.content_part.done` → content part finalized
- `response.output_item.done` → output item finalized
- `response.completed` → full response complete (contains full response object)
- `response.failed` → response generation failed
- `response.incomplete` → response ended incomplete

## Input Format (EasyInputMessage)
- `content`: string or array of content objects
- `role`: "user" | "assistant" | "developer" | "system"
- For text-only: content can be just a string
- For multimodal: content is array of `{ type: "input_text", text: "..." }` and `{ type: "input_image", image_url: "..." }`

## Non-streaming Response
- `output_text`: string with the full text output
- `output`: array of output items
- `status`: "completed" | "failed" | "incomplete"

## Key: The `delta` field in text delta events is the actual text chunk
