defmodule Mix.Tasks.ParsePdf do
  @moduledoc """
  Parse a PDF screenplay file and output classified elements.

  ## Usage

      mix parse_pdf <pdf_file> <output_file> [options]

  ## Options

    * `--format text` (default) - Output as human-readable text format
    * `--format json` - Output as JSON format  
    * `--format json-pretty` - Output as pretty-formatted JSON
    * `--format structured` - Output as structured Script format (JSON)

  ## Examples

      # Text format (default)
      mix parse_pdf screenplay.pdf output.txt
      mix parse_pdf "test/fixtures/Juno.pdf" juno_output.txt

      # JSON format
      mix parse_pdf screenplay.pdf output.json --format json
      mix parse_pdf screenplay.pdf output.json --format json-pretty
      
      # Structured Script JSON (includes full metadata)
      mix parse_pdf screenplay.pdf script.json --format structured

  """
  use Mix.Task

  @shortdoc "Parse PDF screenplay and classify elements"

  def run(args) do
    {options, remaining_args, _} = 
      OptionParser.parse(args, 
        strict: [format: :string],
        aliases: [f: :format]
      )

    format = Keyword.get(options, :format, "text")

    case remaining_args do
      [pdf_file, output_file] ->
        parse_pdf(pdf_file, output_file, format)

      _ ->
        IO.puts("Usage: mix parse_pdf <pdf_file> <output_file> [--format text|json|json-pretty|structured]")
        System.halt(1)
    end
  end

  defp parse_pdf(pdf_file, output_file, format) do
    # Start required applications
    Application.ensure_all_started(:pdf_screenplay_parsex)
    
    # Start the GenServer for PDF processing
    {:ok, _pid} = PdfScreenplayParsex.PdfScreenplayServer.start_link()

    case File.read(pdf_file) do
      {:ok, binary} ->
        IO.puts("Parsing PDF file: #{pdf_file}")
        IO.puts("Output format: #{format}")

        output_content = case format do
          "text" ->
            # Use structured parsing then convert back to groups format for proper text spacing
            case PdfScreenplayParsex.parse_structured(binary) do
              {:ok, script} ->
                # Convert to text using a dedicated function that preserves spacing
                {:ok, PdfScreenplayParsex.script_to_text(script)}

              {:error, reason} ->
                {:error, reason}
            end

          "json" ->
            # Compact JSON format
            case PdfScreenplayParsex.parse_to_json(binary) do
              {:ok, json} -> {:ok, json}
              {:error, reason} -> {:error, reason}
            end

          "json-pretty" ->
            # Pretty formatted JSON
            case PdfScreenplayParsex.parse_to_json(binary, pretty: true) do
              {:ok, json} -> {:ok, json}
              {:error, reason} -> {:error, reason}
            end

          "structured" ->
            # Structured Script format as pretty JSON (same as json-pretty but clearer intent)
            case PdfScreenplayParsex.parse_to_json(binary, pretty: true) do
              {:ok, json} -> {:ok, json}
              {:error, reason} -> {:error, reason}
            end

          _ ->
            {:error, "Unsupported format: #{format}. Use: text, json, json-pretty, or structured"}
        end

        case output_content do
          {:ok, content} ->
            case File.write(output_file, content) do
              :ok ->
                IO.puts("Results saved to: #{output_file}")

              {:error, reason} ->
                IO.puts("Error writing to output file: #{reason}")
                System.halt(1)
            end

          {:error, reason} ->
            error_message = format_error(reason)
            IO.puts("Error parsing PDF: #{error_message}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("Error reading PDF file '#{pdf_file}': #{reason}")
        System.halt(1)
    end
  end

  # Helper function to format error messages
  defp format_error(%PdfScreenplayParsex.Errors.ValidationError{message: message}), do: message
  defp format_error(%PdfScreenplayParsex.Errors.PDFError{message: message}), do: message
  defp format_error(%PdfScreenplayParsex.Errors.ClassificationError{message: message}), do: message
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
