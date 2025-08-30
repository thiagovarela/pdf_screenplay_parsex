defmodule PdfScreenplayParsex.PdfScreenplayServer do
  @moduledoc """
  GenServer for managing the Python interpreter and pdfplumber operations.

  This module ensures all Python operations happen in a single process,
  avoiding issues with Python's Global Interpreter Lock (GIL) and providing
  thread-safe access to the Python interpreter.
  """

  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the PdfScreenplayServer GenServer.
  """
  def start_link(opts \\ []) do
    opts = Keyword.validate!(opts, name: __MODULE__)
    GenServer.start_link(__MODULE__, [], name: opts[:name])
  end

  @doc """
  Extracts text with positions from a PDF binary.

  ## Parameters
    * `binary` - PDF file as binary data

  ## Returns
    * `{:ok, result}` - Success with extraction results
    * `{:error, reason}` - Error with reason
  """
  def extract_text_with_positions(binary) when is_binary(binary) do
    GenServer.call(__MODULE__, {:extract_text_with_positions, binary}, :infinity)
  end

  @doc """
  Extracts plain text from a PDF binary.

  ## Parameters
    * `binary` - PDF file as binary data

  ## Returns
    * `{:ok, text}` - Success with extracted text
    * `{:error, reason}` - Error with reason
  """
  def extract_text(binary) when is_binary(binary) do
    GenServer.call(__MODULE__, {:extract_text, binary}, :infinity)
  end

  # Server Callbacks

  @impl true
  def init([]) do
    Logger.info("Initializing PdfScreenplayServer and Python interpreter...")

    try do
      # Initialize pythonx with pdfplumber dependency
      :ok = init_python()
      Logger.info("Python interpreter initialized successfully")
      {:ok, %{initialized: true}}
    rescue
      e in RuntimeError ->
        if e.message =~ ~r/Python interpreter has already been initialized/ do
          Logger.info("Python interpreter was already initialized")
          {:ok, %{initialized: true}}
        else
          Logger.error("Failed to initialize Python interpreter: #{inspect(e)}")
          {:stop, {:python_init_failed, e}}
        end

      e ->
        Logger.error("Unexpected error initializing Python: #{inspect(e)}")
        {:stop, {:python_init_failed, e}}
    end
  end

  @impl true
  def handle_call({:extract_text_with_positions, binary}, _from, state) do
    result =
      safe_python_call(fn ->
        do_extract_text_with_positions(binary)
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:extract_text, binary}, _from, state) do
    result =
      safe_python_call(fn ->
        do_extract_text(binary)
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call(request, _from, state) do
    Logger.warning("Received unknown request: #{inspect(request)}")
    {:reply, {:error, :unknown_request}, state}
  end

  # Private Functions

  defp init_python do
    Pythonx.uv_init("""
    [project]
    name = "pdf_screenplay_parsex"
    version = "0.1.0"
    requires-python = ">=3.11"
    dependencies = [
      "PyMuPDF==1.26.4",
      "langdetect==1.0.9"
    ]
    """)
  end

  defp safe_python_call(func) do
    try do
      func.()
    rescue
      e in Pythonx.Error ->
        Logger.error("Python error: #{inspect(e)}")
        {:error, e}

      e ->
        Logger.error("Unexpected error in Python call: #{inspect(e)}")
        {:error, e}
    end
  end

  defp do_extract_text_with_positions(binary) do
    python_code = """
    import pymupdf
    import io
    from langdetect import detect
    import traceback

    try:
        # Open PDF from binary data
        pdf_bytes = io.BytesIO(pdf_bytes)
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

    {result, _} = Pythonx.eval(python_code, %{"pdf_bytes" => binary})
    decoded_result = Pythonx.decode(result)

    # Convert the result to our expected format
    case decoded_result do
      %{"success" => true} ->
        {:ok,
         %PdfScreenplayParsex.PositionalExtractionResult{
           pages: decoded_result["pages"],
           language: decoded_result["language"],
           total_text: decoded_result["total_text"]
         }}

      %{"success" => false} ->
        {:error, 
         %{
           message: "PDF extraction failed in Python",
           python_error: decoded_result["error"],
           python_traceback: decoded_result["traceback"]
         }}

      _ ->
        {:ok,
         %PdfScreenplayParsex.PositionalExtractionResult{
           pages: decoded_result["pages"],
           language: decoded_result["language"],
           total_text: decoded_result["total_text"]
         }}
    end
  end

  defp do_extract_text(binary) do
    python_code = """
    import pymupdf
    import io

    try:
        # Open PDF from binary data
        pdf_bytes = io.BytesIO(pdf_bytes)
        doc = pymupdf.open(stream=pdf_bytes, filetype="pdf")

        full_text = ""
        for page in doc:
            page_text = page.get_text()
            if page_text:
                full_text += page_text + "\\n"

        doc.close()
        result = {"success": True, "text": full_text}

    except Exception as e:
        result = {"success": False, "error": str(e)}

    result
    """

    {result, _} = Pythonx.eval(python_code, %{"pdf_bytes" => binary})
    decoded_result = Pythonx.decode(result)
    
    case decoded_result do
      %{"success" => true} -> {:ok, decoded_result["text"]}
      %{"success" => false} -> {:error, decoded_result["error"]}
      _ -> {:ok, decoded_result}
    end
  end
end
