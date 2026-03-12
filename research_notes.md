# Research Notes: OpenAI Tools

## Web Search Tool

### Request Format
```json
{
  "model": "gpt-5",
  "tools": [
    { "type": "web_search" }
  ],
  "input": "What was a positive news story from today?"
}
```

- Tool type: `web_search` (GA) or `web_search_preview` (earlier version)
- Model can choose to search or not based on input
- Supports domain filtering with `filters` parameter
- Supports user location (country, city, region, timezone)

### Response Format
Two output items:
1. `web_search_call` - contains search call ID and action:
   - `search` - web search (includes `queries`)
   - `open_page` - page opened (reasoning models)
   - `find_in_page` - search within page (reasoning models)
2. `message` - contains:
   - `message.content[0].text` - the text result
   - `message.content[0].annotations` - cited URLs with `url_citation` objects containing URL, title, location

### Citation Format
- Inline citations in text
- `url_citation` annotation: { url, title, start_index, end_index }
- Must display citations as clickable links in UI

### Streaming
- SSE events include `web_search_call.in_progress`, `web_search_call.searching`, `web_search_call.completed`
- Then normal text delta events with annotations

### Important Notes
- Not supported with gpt-5 minimal reasoning or gpt-4.1-nano
- 128k context window limit
- GPT-5.4 and GPT-5.4 Pro should both support it

## Code Interpreter Tool

### Request Format
```json
{
  "model": "gpt-5.4",
  "tools": [
    {
      "type": "code_interpreter",
      "container": { "type": "auto", "memory_limit": "4g" }
    }
  ],
  "input": "Solve this equation: 3x + 11 = 14"
}
```

### Key Concepts
- Requires a **container** (sandboxed VM for running Python)
- Auto mode: pass `container: { type: "auto" }` - auto-creates or reuses container
- Container expires after 20 min of inactivity
- Memory tiers: 1g (default), 4g, 16g, 64g
- Model knows it as "python tool"

### Response Format
- `code_interpreter_call` output item with:
  - `id`, `container_id`
  - `code` - the Python code written
  - `results` - array of execution results
- `message` output with text and possible `container_file_citation` annotations

### File Handling
- Files in model input auto-uploaded to container
- Model can create files (plots, CSVs, etc.)
- Generated files cited via `container_file_citation` annotations
- Supports: CSV, DOCX, PDF, PPTX, XLSX, images, code files, etc.

### Streaming Events
- `code_interpreter_call.in_progress`
- `code_interpreter_call.interpreting` (code being written/run)
- `code_interpreter_call.completed`

### Important for Our App
- Since code_interpreter requires containers (server-side), it's more complex
- We need to handle container creation and file upload
- For MVP: could just enable the tool and display code + results
- File citations need download handling via containers API

## Streaming Events Summary

### Web Search Lifecycle
```
response.output_item.added (web_search_call)
web_search_call.in_progress → web_search_call.searching → web_search_call.completed
output_item.done
→ Then message with text + url_citation annotations
```

### Code Interpreter Lifecycle
```
response.output_item.added (code_interpreter_call)
code_interpreter_call.in_progress → code_interpreter_call.interpreting
code_interpreter_call_code.delta × N → code_interpreter_call_code.done
code_interpreter_call.completed → output_item.done
→ Then message with text + possible container_file_citation annotations
```

### Key Annotation Types
- `url_citation`: { url, title, start_index, end_index } — from web search
- `container_file_citation`: { container_id, file_id, filename } — from code interpreter

## Document Parsing Strategy (iOS Native)

### Approach: Use OpenAI File Inputs
OpenAI Responses API supports file inputs directly:
- PDF, DOCX, PPTX, CSV, XLSX all supported
- Files can be uploaded to OpenAI and referenced by file_id
- Or sent as base64 in the input
- Code interpreter can also process files

### iOS File Picking
- Use `UIDocumentPickerViewController` for file selection
- Supported UTTypes: PDF, DOCX, PPTX, CSV, XLSX
- Read file data, convert to base64, send to API

### OpenAI File Input API
- Files sent as `input_file` items in Responses API
- Three ways: Base64, file_id (via /v1/files), or external URL
- **PDF**: extracts text + page images (vision models)
- **DOCX, PPTX, TXT, code**: text extraction only
- **XLSX, CSV, TSV**: spreadsheet augmentation (first 1000 rows + metadata)
- Max 50MB per file, 50MB total per request
- Upload purpose: `user_data`

### Implementation Plan
1. Add document picker button (next to image picker)
2. Use UIDocumentPickerViewController with UTTypes for PDF, DOCX, PPTX, CSV, XLSX
3. Read file data -> upload to OpenAI /v1/files with purpose=user_data
4. Include file_id as input_file in the Responses API request
5. Display file attachment preview in chat bubble (icon + filename + size)
6. For the API request, use: { type: "input_file", file_id: "..." }

### Simplification Decision
Since OpenAI handles all parsing server-side, we DON'T need local parsing.
Just upload the raw file and let OpenAI extract content.
This means: pick file -> upload -> send file_id -> done.
