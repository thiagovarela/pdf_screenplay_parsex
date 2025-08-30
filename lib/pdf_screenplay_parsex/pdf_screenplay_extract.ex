defmodule PdfScreenplayParsex.PdfScreenplayExtract do
  @moduledoc """
  Handles PDF text extraction using PyMuPDF via Pythonx.

  This module provides enhanced error handling and validation for Python execution,
  including timeout handling, dependency validation, and structured error reporting.
  """

  alias PdfScreenplayParsex.{Errors, PositionalExtractionResult}

  # Python execution timeout in milliseconds (2 minutes)
  @python_timeout 120_000

  def extract_text_from_binary(binary) do
    extract_text_with_positions(binary)
  end

  def extract_text_with_positions(binary) do
    Errors.with_error_handling(fn ->
      # Validate Python dependencies first
      case validate_python_dependencies() do
        :ok -> execute_python_extraction(binary)
        {:error, error} -> raise error
      end
    end, %{operation: "extract_text_with_positions", binary_size: byte_size(binary)})
  end

  # Private functions

  @spec validate_python_dependencies() :: :ok | {:error, Errors.PythonExecutionError.t()}
  defp validate_python_dependencies do
    validation_code = """
    import sys
    missing_modules = []

    try:
        import pymupdf
    except ImportError:
        missing_modules.append("pymupdf")

    try:
        import langdetect
    except ImportError:
        missing_modules.append("langdetect")

    {
        "missing_modules": missing_modules,
        "python_version": sys.version
    }
    """

    try do
      {result, _globals} = Pythonx.eval(validation_code, %{})
      decoded_result = Pythonx.decode(result)

      case decoded_result["missing_modules"] do
        [] -> :ok
        missing ->
          {:error, %Errors.PythonExecutionError{
            message: "Missing required Python modules: #{Enum.join(missing, ", ")}",
            python_error: "ImportError",
            code_snippet: "import #{Enum.join(missing, ", ")}"
          }}
      end
    rescue
      error ->
        {:error, %Errors.PythonExecutionError{
          message: "Failed to validate Python dependencies",
          python_error: inspect(error),
          code_snippet: validation_code
        }}
    end
  end

  @spec execute_python_extraction(binary()) :: PositionalExtractionResult.t()
  defp execute_python_extraction(binary) do
    python_code = build_extraction_code()

    try do
      # Execute with timeout
      task = Task.async(fn ->
        Pythonx.eval(python_code, %{"pdf_binary" => binary})
      end)

      case Task.yield(task, @python_timeout) || Task.shutdown(task) do
        {:ok, {result, _globals}} ->
          decoded_result = Pythonx.decode(result)

          # Check if Python execution was successful
          case decoded_result do
            %{"success" => true} ->
              %PositionalExtractionResult{
                pages: decoded_result["pages"],
                language: decoded_result["language"],
                total_text: decoded_result["total_text"]
              }

            %{"success" => false} ->
              raise %Errors.PythonExecutionError{
                message: "PDF extraction failed in Python",
                python_error: decoded_result["error"],
                python_traceback: decoded_result["traceback"]
              }

            _ ->
              %PositionalExtractionResult{
                pages: decoded_result["pages"],
                language: decoded_result["language"],
                total_text: decoded_result["total_text"]
              }
          end

        nil ->
          raise %Errors.PythonExecutionError{
            message: "Python execution timed out after #{@python_timeout}ms",
            python_error: "TimeoutError",
            code_snippet: String.slice(python_code, 0, 200) <> "..."
          }
      end
    rescue
      error in [Errors.PythonExecutionError] ->
        reraise error, __STACKTRACE__

      error ->
        python_error = extract_python_error(error)

        reraise %Errors.PythonExecutionError{
          message: "PDF extraction failed during Python execution",
          python_error: python_error[:message],
          python_traceback: python_error[:traceback],
          code_snippet: String.slice(python_code, 0, 200) <> "..."
        }, __STACKTRACE__
    end
  end

  @spec build_extraction_code() :: String.t()
  defp build_extraction_code do
    """
    import pymupdf
    import io
    from langdetect import detect
    import traceback

    try:
        # Open PDF from binary data
        pdf_bytes = io.BytesIO(pdf_binary)
        doc = pymupdf.open(stream=pdf_bytes, filetype="pdf")

        # Extract text from all pages with positioning
        pages = []
        total_text = ""

        for page_num, page in enumerate(doc, 1):
            try:
                # Get basic text content
                page_text = page.get_text()
                total_text += page_text + "\\n"

                # Get detailed text information with positioning
                text_dict = page.get_text("dict")

                # Extract text items with positioning
                text_items = []
                page_width = page.rect.width
                page_height = page.rect.height

                for block in text_dict["blocks"]:
                    if "lines" in block:  # Text block
                        for line in block["lines"]:
                            if not line["spans"]:
                                continue
                            span = line["spans"][0]
                            if len(line["spans"]) > 1:
                                text = " ".join([text["text"] for text in line["spans"]])
                            else:
                                text = span["text"]
                                if text.strip() == "":
                                    continue
                            bbox = span["bbox"]

                            # Detect if Y coordinates need normalization
                            # If bbox[1] (bottom) > bbox[3] (top), coordinates are already normalized
                            # If bbox[3] (top) > bbox[1] (bottom), we need to normalize
                            y_coord = bbox[1] if bbox[1] < bbox[3] else page_height - bbox[3]

                            text_items.append({
                                "text": text,
                                "x": bbox[0],  # Left x coordinate
                                "y": y_coord,  # Normalized y coordinate (0=top)
                                "width": bbox[2] - bbox[0],  # Width of text
                                "height": bbox[3] - bbox[1],  # Height of text
                                "font_size": span["size"],  # Font size
                                "font": span["font"],  # Font name
                                "flags": span["flags"],  # Font flags (bold, italic, etc.)
                                "color": span["color"]  # Text color
                            })

                pages.append({
                    'page_number': page_num,
                    'text': page_text,
                    'width': page_width,
                    'height': page_height,
                    'text_items': text_items
                })
            except Exception as page_error:
                # Log page-specific errors but continue processing
                print(f"Warning: Error processing page {page_num}: {page_error}")
                continue

        doc.close()

        # Detect language and convert to full name
        try:
            lang_code = detect(total_text) if total_text.strip() else "en"
            # Convert common language codes to full names
            language_map = {
                "en": "english",
                "es": "spanish",
                "fr": "french",
                "de": "german",
                "it": "italian",
                "pt": "portuguese",
                "ru": "russian",
                "zh": "chinese",
                "ja": "japanese",
                "ko": "korean"
            }
            language = language_map.get(lang_code, lang_code)
        except Exception as lang_error:
            print(f"Warning: Language detection failed: {lang_error}")
            language = "english"

        result = {
            "success": True,
            "pages": pages,
            "language": language,
            "total_text": total_text
        }

    except Exception as e:
        result = {
            "success": False,
            "error": str(e),
            "traceback": traceback.format_exc(),
            "error_type": type(e).__name__
        }

    result
    """
  end

  @spec extract_python_error(any()) :: %{message: String.t(), traceback: String.t() | nil}
  defp extract_python_error(error) do
    error_message = cond do
      is_binary(error) -> error
      is_exception(error) -> Exception.message(error)
      true -> inspect(error)
    end

    %{
      message: error_message,
      traceback: nil  # Could be enhanced to extract actual Python tracebacks
    }
  end
end
