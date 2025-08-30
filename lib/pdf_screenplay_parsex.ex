defmodule PdfScreenplayParsex do
  defmodule TextElement do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [
      :text,
      :type,
      :is_dual_dialogue,
      :x,
      :y,
      :width,
      :height,
      :font_size,
      :font_name,
      :gap_to_prev,
      :gap_to_next,
      :centered
    ]
  end

  defmodule PositionalExtractionResult do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [:pages, :language, :total_text]
  end

  defmodule Page do
    @moduledoc "Represents a single page of a screenplay with classified elements"
    @derive Jason.Encoder
    defstruct [:number, :elements, :raw_elements]
  end

  defmodule Script do
    @moduledoc "Complete screenplay structure"
    @derive Jason.Encoder
    defstruct [:title, :author, :pages, :full_text, :metadata, :language, :total_pages]
  end

  alias PdfScreenplayParsex.{
    Errors,
    Page,
    PdfScreenplayExtract,
    ScreenplayClassifier,
    Script
  }

  @moduledoc """
  A library for parsing PDF screenplay files.

  This module extracts text from PDF screenplays and detects the language
  of the extracted content using PDF text extraction and language detection.

  All public functions include comprehensive input validation and error handling.
  """

  # Configuration constants
  @max_pdf_size_mb 100
  @max_pdf_size_bytes @max_pdf_size_mb * 1024 * 1024
  @min_pdf_size_bytes 1024
  # "%PDF"
  @pdf_header <<37, 80, 68, 70>>

  @doc """
  Parses a PDF screenplay from binary data.

  Extracts text from all pages of the PDF and detects the language of the content.

  ## Parameters

    * `binary` - The PDF file as binary data

  ## Returns

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.

  The result is a map containing:
    * `:pages` - A map of page numbers (0-indexed) to extracted text content
    * `:language` - The detected language as an atom (e.g., `:english`, `:spanish`)
    * `:total_pages` - The total number of pages processed

  ## Examples

      # Parse a PDF screenplay
      pdf_binary = File.read!("screenplay.pdf")
      {:ok, result} = PdfScreenplayParsex.parse_binary(pdf_binary)

      # Access extracted text by page
      first_page_text = result.pages[0]

      # Check detected language
      result.language #=> :english

      # Get total pages
      result.total_pages #=> 10

  """
  def parse_binary(binary) when is_binary(binary) do
    Errors.with_error_handling(
      fn ->
        # Validate input
        case validate_pdf_binary(binary) do
          :ok ->
            extract_and_process(binary)

          {:error, error} ->
            raise error
        end
      end,
      %{operation: "parse_binary", size: byte_size(binary)}
    )
  end

  def parse_binary(invalid_input) do
    {:error,
     %Errors.ValidationError{
       message: "Input must be binary data",
       field: :binary,
       value: invalid_input,
       constraint: :type
     }}
  end

  def parse_screenplay(binary) when is_binary(binary) do
    parse_binary(binary)
  end

  @doc """
  Parses a PDF screenplay from binary data and returns structured screenplay elements.

  Similar to `parse_binary/1` but returns classified screenplay elements organized
  by type and position, following proper screenplay formatting conventions.

  ## Parameters

    * `binary` - The PDF file as binary data

  ## Returns

  Returns `{:ok, script}` on success or `{:error, reason}` on failure.

  The script is a `%Script{}` struct containing:
    * `:title` - Extracted title information from the first page
    * `:pages` - A list of `%Page{}` structs with classified elements
    * `:metadata` - Additional screenplay metadata
    * `:language` - The detected language as an atom
    * `:total_pages` - The total number of pages processed

  ## Examples

      # Parse a PDF screenplay with element classification
      pdf_binary = File.read!("screenplay.pdf")
      {:ok, script} = PdfScreenplayParsex.parse_structured(pdf_binary)

      # Access classified elements by page
      first_page = Enum.at(script.pages, 0)
      scene_headings = Enum.filter(first_page.elements, &(&1.type == :scene_heading))

      # Check script metadata
      script.title #=> "MY SCREENPLAY TITLE"
      script.language #=> :english

  """
  def parse_structured(binary) when is_binary(binary) do
    Errors.with_error_handling(
      fn ->
        # Validate input
        case validate_pdf_binary(binary) do
          :ok ->
            classify_and_structure(binary)

          {:error, error} ->
            raise error
        end
      end,
      %{operation: "parse_structured", size: byte_size(binary)}
    )
  end

  def parse_structured(invalid_input) do
    {:error,
     %Errors.ValidationError{
       message: "Input must be binary data",
       field: :binary,
       value: invalid_input,
       constraint: :type
     }}
  end

  @doc """
  Parses a screenplay PDF and returns JSON string with structured data.

  Similar to `parse_structured/1` but returns a JSON-encoded string instead of Elixir structs.
  Useful for API responses, file exports, or integration with other systems.

  ## Parameters

    * `binary` - The PDF file as binary data (required)
    * `options` - Optional keyword list with formatting options:
      * `:pretty` - Boolean, whether to format JSON with indentation (default: false)

  ## Returns

  Returns `{:ok, json_string}` on success or `{:error, reason}` on failure.

  ## Examples

      # Basic usage
      {:ok, json} = PdfScreenplayParsex.parse_to_json(pdf_binary)

      # Pretty formatted JSON
      {:ok, pretty_json} = PdfScreenplayParsex.parse_to_json(pdf_binary, pretty: true)

      # Save to file
      {:ok, json} = PdfScreenplayParsex.parse_to_json(pdf_binary)
      File.write!("screenplay.json", json)

  """
  @spec parse_to_json(binary(), keyword()) :: {:ok, String.t()} | {:error, Exception.t()}
  def parse_to_json(binary, options \\ []) when is_binary(binary) do
    case parse_structured(binary) do
      {:ok, script} ->
        try do
          json_string =
            if Keyword.get(options, :pretty, false) do
              Jason.encode!(script, pretty: true)
            else
              Jason.encode!(script)
            end

          {:ok, json_string}
        rescue
          error -> {:error, error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Converts an existing Script struct to JSON string.

  Useful when you already have a parsed script and want to convert it to JSON
  without re-parsing the original PDF.

  ## Parameters

    * `script` - A `%Script{}` struct from `parse_structured/1`
    * `options` - Optional keyword list with formatting options:
      * `:pretty` - Boolean, whether to format JSON with indentation (default: false)

  ## Returns

  Returns `{:ok, json_string}` on success or `{:error, reason}` on failure.

  ## Examples

      {:ok, script} = PdfScreenplayParsex.parse_structured(pdf_binary)
      {:ok, json} = PdfScreenplayParsex.script_to_json(script)

      # Pretty formatted
      {:ok, pretty_json} = PdfScreenplayParsex.script_to_json(script, pretty: true)

  """
  @spec script_to_json(Script.t(), keyword()) :: {:ok, String.t()} | {:error, Exception.t()}
  def script_to_json(script, options \\ [])

  def script_to_json(%Script{} = script, options) do
    try do
      json_string =
        if Keyword.get(options, :pretty, false) do
          Jason.encode!(script, pretty: true)
        else
          Jason.encode!(script)
        end

      {:ok, json_string}
    rescue
      error -> {:error, error}
    end
  end

  def script_to_json(invalid_input, _options) do
    {:error,
     %Errors.ValidationError{
       message: "Input must be a Script struct",
       field: :script,
       value: invalid_input,
       constraint: :type
     }}
  end

  # Extract title from the first page's title elements
  defp extract_title(pages) when is_list(pages) do
    case Enum.at(pages, 0) do
      %Page{elements: elements} ->
        # Find all elements with :title type from the classifier
        title_texts =
          elements
          |> Enum.filter(fn element -> Map.get(element, :type) == :title end)
          |> Enum.map(fn element -> String.trim(element.text) end)
          |> Enum.reject(&(&1 == ""))

        case title_texts do
          [] -> nil
          titles -> Enum.join(titles, "\n")
        end

      _ ->
        nil
    end
  end

  defp extract_title(_), do: nil

  # Private functions for input validation and processing

  @spec validate_pdf_binary(binary()) :: :ok | {:error, Errors.ValidationError.t()}
  defp validate_pdf_binary(binary) do
    validators = [
      {:required},
      {:type, :binary},
      {:min_size, @min_pdf_size_bytes},
      {:max_size, @max_pdf_size_bytes},
      &validate_pdf_header/1
    ]

    Errors.validate(binary, validators, :binary)
  end

  @spec validate_pdf_header(binary()) :: true | {:error, String.t()}
  defp validate_pdf_header(binary) when byte_size(binary) < 4 do
    {:error, "File too small to be a valid PDF"}
  end

  defp validate_pdf_header(binary) do
    case binary do
      <<@pdf_header, _rest::binary>> -> true
      _ -> {:error, "Invalid PDF header - file does not appear to be a PDF"}
    end
  end

  @spec extract_and_process(binary()) :: map()
  defp extract_and_process(binary) do
    case PdfScreenplayExtract.extract_text_with_positions(binary) do
      {:ok,
       %PositionalExtractionResult{pages: pages, language: language_str, total_text: total_text}} ->
        language_atom = String.to_atom(language_str)

        %{
          pages: pages,
          language: language_atom,
          total_pages: length(pages),
          full_text: total_text
        }

      {:error, reason} ->
        raise %Errors.PDFError{
          message: "Failed to extract text from PDF",
          type: :extraction_failed,
          details: %{reason: reason}
        }

      other ->
        raise %Errors.PDFError{
          message: "Unexpected response from PDF extractor",
          type: :unexpected_response,
          details: %{response: other}
        }
    end
  end

  @spec classify_and_structure(binary()) :: Script.t()
  defp classify_and_structure(binary) do
    # First extract the raw text to capture full_text
    case PdfScreenplayExtract.extract_text_with_positions(binary) do
      {:ok,
       %PositionalExtractionResult{pages: _pages, language: language_str, total_text: total_text}} ->
        language_atom = String.to_atom(language_str)

        # Now classify the screenplay
        case ScreenplayClassifier.classify_screenplay(binary) do
          {:ok, classified_pages} ->
            # Convert classified pages to Script format
            structured_pages =
              classified_pages
              |> Enum.map(fn page ->
                # Flatten groups to get all elements
                all_elements = List.flatten(Map.get(page, :groups, []))

                %Page{
                  number: Map.get(page, :page_number, 0),
                  elements: all_elements,
                  # Raw elements not preserved in current classifier
                  raw_elements: []
                }
              end)

            # Extract title from first page
            title = extract_title(structured_pages)

            %Script{
              title: title,
              pages: structured_pages,
              full_text: total_text,
              metadata: %{},
              language: language_atom,
              total_pages: length(structured_pages)
            }

          {:error, reason} ->
            raise %Errors.ClassificationError{
              message: "Failed to classify screenplay elements",
              context: %{reason: reason}
            }
        end

      {:error, reason} ->
        raise %Errors.PDFError{
          message: "Failed to extract text from PDF",
          type: :extraction_failed,
          details: %{reason: reason}
        }
    end
  end

  @doc """
  Formats a parsed screenplay script into a readable text format.

  Takes a Script struct and returns a formatted string representation
  of all the screenplay elements organized by pages.

  ## Parameters
    * `script` - A %Script{} struct from parse_structured/1

  ## Returns
    A formatted string with all screenplay elements

  ## Examples

      iex> {:ok, script} = PdfScreenplayParsex.parse_structured(pdf_binary)
      iex> output = PdfScreenplayParsex.dump_content(script)
      iex> File.write!("output.txt", output)
  """
  def dump_content(%{} = result) when is_map(result) and not is_struct(result) do
    header = """
    SCREENPLAY ELEMENTSPARSING RESULTS
    ==========================

    Language: #{result.language}
    Total Pages: #{result.total_pages}

    """

    pages_content =
      result.pages
      |> Enum.map_join("\n\n" <> String.duplicate("=", 50) <> "\n\n", fn page ->
        page_header = "PAGE #{page["page_number"]}\n" <> String.duplicate("-", 20) <> "\n"

        page_body =
          page["text_items"]
          |> Enum.map_join(
            "\n",
            &(&1["text"] <> " y: " <> to_string(&1["y"]) <> " x: " <> to_string(&1["x"]))
          )

        page_header <> page_body
      end)

    header <> pages_content
  end
end
