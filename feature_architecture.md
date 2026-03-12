# Feature Architecture: Tools & Document Import

## Overview
Add OpenAI web search + code interpreter tool calling, and document import (PDF, DOCX, PPTX, CSV, XLSX).

## Data Model Changes

### Message.swift
Add new fields:
- `annotations: Data?` — JSON-encoded array of annotation objects (url_citation, file_citation)
- `toolCalls: Data?` — JSON-encoded array of tool call info (web_search_call, code_interpreter_call)
- `fileAttachments: Data?` — JSON-encoded array of { filename, fileSize, fileType, fileId }

### New: FileAttachment struct (Codable, Sendable)
- `id: UUID`
- `filename: String`
- `fileSize: Int64`
- `fileType: String` (pdf, docx, pptx, csv, xlsx)
- `fileId: String?` (OpenAI file ID after upload)
- `uploadStatus: UploadStatus` (pending, uploading, uploaded, failed)

### New: URLCitation struct (Codable, Sendable)
- `url: String`
- `title: String`
- `startIndex: Int`
- `endIndex: Int`

### New: ToolCallInfo struct (Codable, Sendable)
- `type: ToolCallType` (webSearch, codeInterpreter)
- `status: ToolCallStatus` (inProgress, searching/interpreting, completed)
- `code: String?` (for code interpreter)
- `results: [String]?` (for code interpreter)

## OpenAIService Changes

### streamChat()
- Add `tools` parameter to request body:
  ```json
  "tools": [
    { "type": "web_search" },
    { "type": "code_interpreter", "container": { "type": "auto" } }
  ]
  ```
- Add `input_file` support in buildInputArray for file attachments

### New SSE Events to Handle
- `response.web_search_call.in_progress` → yield .webSearchStarted
- `response.web_search_call.searching` → yield .webSearchSearching
- `response.web_search_call.completed` → yield .webSearchCompleted
- `response.code_interpreter_call.in_progress` → yield .codeInterpreterStarted
- `response.code_interpreter_call.interpreting` → yield .codeInterpreterInterpreting
- `response.code_interpreter_call_code.delta` → yield .codeInterpreterCodeDelta(String)
- `response.code_interpreter_call_code.done` → yield .codeInterpreterCodeDone(String)
- `response.code_interpreter_call.completed` → yield .codeInterpreterCompleted
- `response.output_text.annotation.added` → yield .annotationAdded(annotation)

### New: uploadFile()
- POST to /v1/files with purpose=user_data
- Returns file_id

## StreamEvent Extensions
Add new cases:
- `.webSearchStarted`
- `.webSearchSearching`
- `.webSearchCompleted`
- `.codeInterpreterStarted`
- `.codeInterpreterInterpreting`
- `.codeInterpreterCodeDelta(String)`
- `.codeInterpreterCodeDone(String)`
- `.codeInterpreterCompleted`
- `.annotationAdded(AnnotationData)`

## UI Components

### WebSearchIndicator
- Animated search icon during web search
- "Searching the web..." text
- Appears in streaming bubble when web search is active

### CitationLinksView
- Horizontal scrollable row of citation chips
- Each chip: favicon + title, tappable to open URL
- Appears below assistant message text when annotations present

### CodeInterpreterView
- Collapsible code block showing the Python code
- Execution status indicator
- Output display area

### DocumentPickerButton
- SF Symbol: "doc.badge.plus"
- Opens UIDocumentPickerViewController
- Supports: PDF, DOCX, PPTX, CSV, XLSX

### FileAttachmentPreview
- Compact card: file icon + filename + size
- Upload progress indicator
- Shown in input area (like image preview) and in user message bubble

## ChatViewModel Changes
- Add `currentToolState` property for streaming UI
- Add `selectedFileAttachments: [FileAttachment]` for pending uploads
- Handle new StreamEvent cases
- Upload files before sending message
- Store annotations and tool calls on finalized messages

## Integration Flow

### Web Search Flow
1. User sends message → tools included in API request
2. Model decides to search → SSE: web_search_call events
3. UI shows search indicator in streaming bubble
4. Search completes → text with annotations streams in
5. Message finalized → annotations stored → CitationLinksView shown

### Code Interpreter Flow
1. User sends message → tools included in API request
2. Model decides to run code → SSE: code_interpreter_call events
3. UI shows code being written in streaming bubble
4. Code executes → results stream in
5. Message finalized → code + results stored → CodeInterpreterView shown

### Document Import Flow
1. User taps document button → file picker opens
2. User selects file(s) → FileAttachment created with pending status
3. Preview shown in input area
4. User sends message → files uploaded to OpenAI first
5. file_ids included in API request as input_file items
6. File attachment preview shown in user message bubble
