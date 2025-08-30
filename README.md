# PDF Parser

## Project Overview

This is a PDF screenplay parser library written in Elixir that extracts and classifies screenplay elements from PDF files. It uses Python libraries (via pythonx) for PDF text extraction with positional information and provides structured output of screenplay components.

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

1. **PDF Extraction** (`lib/pdf_screenplay_parsex/pdf_screenplay_extract.ex`)
   - Uses Python's pdfplumber via pythonx to extract text with positional data
   - Returns structured pages with text elements including x/y coordinates, fonts, sizes

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
- **pythonx** - Python interop for PDF extraction
- **jason** - JSON encoding/decoding
- **credo** - Code analysis (dev/test only)
