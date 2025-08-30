# PdfScreenplayParsex

A PDF screenplay parser library written in Elixir that extracts and classifies screenplay elements from PDF files. It uses PyMuPDF (via pythonx and a supervised GenServer) for PDF text extraction with positional information and provides structured output of screenplay components.

## Installation

Add `pdf_screenplay_parsex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pdf_screenplay_parsex, "~> 0.1.0"}
  ]
end
```

## Usage as a Library

### Basic Text Extraction

Extract raw text and detect language from a PDF:

```elixir
# Read PDF file
pdf_binary = File.read!("screenplay.pdf")

# Extract text with language detection
{:ok, result} = PdfScreenplayParsex.parse_binary(pdf_binary)

# Access extracted content
IO.puts("Language: #{result.language}")
IO.puts("Total pages: #{result.total_pages}")
IO.puts("First page text: #{result.pages |> hd() |> Map.get("text")}")
```

### Structured Screenplay Parsing

Parse and classify screenplay elements:

```elixir
pdf_binary = File.read!("screenplay.pdf")

# Parse with full classification
{:ok, script} = PdfScreenplayParsex.parse_structured(pdf_binary)

# Access structured data
IO.puts("Title: #{script.title}")
IO.puts("Language: #{script.language}")
IO.puts("Total pages: #{script.total_pages}")

# Access elements by page
first_page = Enum.at(script.pages, 0)
scene_headings = Enum.filter(first_page.elements, &(&1.type == :scene_heading))
dialogue_lines = Enum.filter(first_page.elements, &(&1.type == :dialogue))

# Print all character names
character_names = 
  script.pages
  |> Enum.flat_map(fn page -> page.elements end)
  |> Enum.filter(fn element -> element.type == :character end)
  |> Enum.map(fn element -> element.text end)
  |> Enum.uniq()

IO.inspect(character_names)
```

### JSON Export

Convert parsed screenplay to JSON:

```elixir
pdf_binary = File.read!("screenplay.pdf")

# Parse to JSON (compact)
{:ok, json} = PdfScreenplayParsex.parse_to_json(pdf_binary)
File.write!("screenplay.json", json)

# Parse to JSON (pretty formatted)
{:ok, pretty_json} = PdfScreenplayParsex.parse_to_json(pdf_binary, pretty: true)
File.write!("screenplay_pretty.json", pretty_json)

# Convert existing script struct to JSON
{:ok, script} = PdfScreenplayParsex.parse_structured(pdf_binary)
{:ok, json} = PdfScreenplayParsex.script_to_json(script, pretty: true)
```

### Error Handling

The library provides comprehensive error handling:

```elixir
case PdfScreenplayParsex.parse_binary(pdf_binary) do
  {:ok, result} -> 
    # Process successful result
    IO.puts("Successfully parsed #{result.total_pages} pages")
    
  {:error, %PdfScreenplayParsex.Errors.ValidationError{} = error} ->
    # Handle validation errors (invalid PDF, size limits, etc.)
    IO.puts("Validation error: #{error.message}")
    
  {:error, %PdfScreenplayParsex.Errors.PDFError{} = error} ->
    # Handle PDF processing errors
    IO.puts("PDF processing error: #{error.message}")
    
  {:error, %PdfScreenplayParsex.Errors.PythonExecutionError{} = error} ->
    # Handle Python execution errors
    IO.puts("Python error: #{error.message}")
end
```

### Using in a Phoenix Application

#### Method 1: Automatic Startup (Recommended)

Add the library to your dependencies and it will start automatically:

```elixir
# mix.exs
def deps do
  [
    {:pdf_screenplay_parsex, "~> 0.1.0"}
  ]
end
```

The library's supervision tree will start automatically when your Phoenix application starts.

#### Method 2: Manual Supervision (If needed)

If you need more control, you can manually add it to your application's supervision tree:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ... your other children
      MyAppWeb.Endpoint,
      
      # Add the PdfScreenplayServer to your supervision tree
      {PdfScreenplayParsex.PdfScreenplayServer, name: PdfScreenplayParsex.PdfScreenplayServer}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

#### Using in Phoenix Controllers

```elixir
# lib/my_app_web/controllers/screenplay_controller.ex
defmodule MyAppWeb.ScreenplayController do
  use MyAppWeb, :controller

  def upload(conn, %{"screenplay" => %Plug.Upload{} = upload}) do
    case File.read(upload.path) do
      {:ok, pdf_binary} ->
        case PdfScreenplayParsex.parse_structured(pdf_binary) do
          {:ok, script} ->
            conn
            |> put_status(:ok)
            |> json(%{
              title: script.title,
              language: script.language,
              total_pages: script.total_pages,
              characters: extract_characters(script)
            })
            
          {:error, error} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to parse screenplay: #{inspect(error)}"})
        end
        
      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Could not read uploaded file"})
    end
  end

  defp extract_characters(script) do
    script.pages
    |> Enum.flat_map(fn page -> page.elements end)
    |> Enum.filter(fn element -> element.type == :character end)
    |> Enum.map(fn element -> element.text end)
    |> Enum.uniq()
  end
end
```

#### Using in Phoenix LiveView

```elixir
# lib/my_app_web/live/screenplay_live.ex
defmodule MyAppWeb.ScreenplayLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, screenplay: nil, parsing: false)}
  end

  def handle_event("parse_screenplay", %{"screenplay" => %{} = upload}, socket) do
    socket = assign(socket, parsing: true)
    
    # In a real app, you'd want to handle this async with a Task
    case PdfScreenplayParsex.parse_structured(upload.binary) do
      {:ok, script} ->
        {:noreply, 
         assign(socket, 
           screenplay: script, 
           parsing: false
         )}
         
      {:error, error} ->
        {:noreply, 
         socket
         |> put_flash(:error, "Failed to parse screenplay: #{inspect(error)}")
         |> assign(parsing: false)
        }
    end
  end
end
```


## Data Structures

### Script Struct

```elixir
%PdfScreenplayParsex.Script{
  title: "SCREENPLAY TITLE",           # Extracted title
  author: nil,                         # Author (if detected)
  pages: [%PdfScreenplayParsex.Page{}], # List of pages
  full_text: "...",                    # Complete text content
  metadata: %{},                       # Additional metadata
  language: :english,                  # Detected language
  total_pages: 120                     # Total page count
}
```

### Page Struct

```elixir
%PdfScreenplayParsex.Page{
  number: 1,                           # Page number
  elements: [%PdfScreenplayParsex.TextElement{}], # Classified elements
  raw_elements: []                     # Raw text elements (if preserved)
}
```

### TextElement Struct

```elixir
%PdfScreenplayParsex.TextElement{
  text: "INT. COFFEE SHOP - DAY",      # Text content
  type: :scene_heading,                # Element type
  is_dual_dialogue: false,             # Dual dialogue flag
  x: 72.0,                            # X position
  y: 144.0,                           # Y position  
  width: 200.0,                       # Width
  height: 12.0,                       # Height
  font_size: 12.0,                    # Font size
  font_name: "Times-Roman",           # Font name
  gap_to_prev: 24.0,                  # Gap to previous element
  gap_to_next: 12.0,                  # Gap to next element
  centered: false                      # Centered flag
}
```

## Element Types

The classifier recognizes these screenplay elements:

- `:title`, `:author` - Title page elements
- `:scene_heading` - INT./EXT. scene locations  
- `:action` - Action lines and descriptions
- `:character` - Character names before dialogue
- `:dialogue` - Character dialogue text
- `:parenthetical` - Dialogue directions in parentheses
- `:transition` - Scene transitions (CUT TO:, FADE IN:, etc.)
- `:page_number` - Page numbering

## Common Development Commands

### Build & Compile
```bash
mix deps.get         # Install dependencies
mix compile          # Compile the project
```

### Testing
```bash
mix test             # Run all tests
mix test test/classification_test.exs  # Run specific test file
```

### Code Quality
```bash
mix format           # Format code according to .formatter.exs
mix credo            # Run static code analysis
```

### Parse PDF Files
```bash
# Text format (default)
mix parse_pdf screenplay.pdf output.txt

# JSON format
mix parse_pdf screenplay.pdf output.json --format json
mix parse_pdf screenplay.pdf output.json --format json-pretty

# Test with fixtures
mix parse_pdf "test/fixtures/Juno.pdf" juno_output.txt
```

## Architecture

### Core Processing Pipeline

1. **PDF Extraction** 
   - **PdfScreenplayServer GenServer** (`lib/pdf_screenplay_parsex/pdf_screenplay_server.ex`) - Supervised GenServer managing PyMuPDF operations
   - **PdfScreenplayExtract** (`lib/pdf_screenplay_parsex/pdf_screenplay_extract.ex`) - API layer delegating to GenServer
   - Uses PyMuPDF via pythonx for thread-safe PDF text extraction with positional data
   - Returns structured pages with text elements including x/y coordinates, fonts, sizes, and styling information

2. **Classification System**
   - **ScreenplayClassifier** (`screenplay_classifier.ex`) - Main orchestrator that processes pages through the classification pipeline
   - **ElementClassifier** (`element_classifier.ex`) - Classifies individual text elements by type (scene heading, character, dialogue, etc.)
   - **TitlePageClassifier** (`title_page_classifier.ex`) - Identifies and classifies title page elements
   - **DualDialogueClassifier** (`dual_dialogue_classifier.ex`) - Detects side-by-side dialogue formatting
   - **ElementGrouper** (`element_grouper.ex`) - Groups related elements together (e.g., character name with dialogue)
   - **ClassificationContext** (`classification_context.ex`) - Maintains state and context during classification

3. **Public API** (`lib/pdf_screenplay_parsex.ex`)
   - `parse_binary/1` - Extract raw text and language detection
   - `parse_structured/1` - Full classification returning Script struct
   - `parse_to_json/2` - JSON output with optional pretty formatting

### Element Types
The classifier recognizes standard screenplay elements:
- `:title`, `:author` - Title page elements
- `:scene_heading` - INT./EXT. scene locations
- `:action` - Action lines and descriptions
- `:character` - Character names before dialogue
- `:dialogue` - Character dialogue text
- `:parenthetical` - Dialogue directions in parentheses
- `:transition` - Scene transitions (CUT TO:, FADE IN:, etc.)
- `:page_number` - Page numbering

### Testing
Snapshot tests compare classifier output against expected fixture files for consistency. Test PDFs are in `test/fixtures/`.

## Dependencies
- **pythonx** - Python interop for PDF extraction via supervised GenServer
- **jason** - JSON encoding/decoding
- **credo** - Code analysis (dev/test only)

### Python Dependencies (automatically managed)
- **PyMuPDF** (1.26.4) - High-performance PDF text extraction
- **langdetect** (1.0.9) - Language detection for extracted text

## GenServer Architecture

The library uses a supervised GenServer (`PdfScreenplayServer`) for all Python operations, providing:

- **Thread Safety** - All Python operations happen in a single process, avoiding GIL issues
- **Fault Tolerance** - Python errors don't crash the main application
- **Resource Management** - Proper Python interpreter lifecycle management
- **Process Isolation** - PDF processing failures are contained
- **Automatic Startup** - GenServer starts automatically with your application

The GenServer handles Python dependency installation via `uv` and manages PyMuPDF operations for reliable, high-performance PDF extraction.
