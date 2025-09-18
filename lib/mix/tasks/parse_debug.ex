defmodule Mix.Tasks.ParseDebug do
  @moduledoc """
  Parse a PDF screenplay file with debug output showing detailed classification results.

  ## Usage

      mix parse_debug <pdf_file> <output_file>

  ## Examples

      # Parse with debug output
      mix parse_debug screenplay.pdf output.txt
      mix parse_debug "test/fixtures/en/IT.pdf" it_debug_output.txt

  ## What this does

  1. Parses the PDF using the standard PDF parser
  2. Runs the result through the classifier pipeline
  3. Outputs classified elements in a human-readable text format
  4. Shows element types, positions, and text content

  """
  use Mix.Task

  @shortdoc "Parse PDF screenplay with debug output"

  def run(args) do
    case args do
      [pdf_file, output_file] ->
        parse_debug(pdf_file, output_file)

      _ ->
        IO.puts("Usage: mix parse_debug <pdf_file> <output_file>")
        System.halt(1)
    end
  end

  defp parse_debug(pdf_file, output_file) do
    # Start required applications
    Application.ensure_all_started(:pdf_screenplay_parsex)
    
    # Start the GenServer for PDF processing
    {:ok, _pid} = PdfScreenplayParsex.PdfScreenplayServer.start_link()

    case File.read(pdf_file) do
      {:ok, binary} ->
        IO.puts("Parsing PDF file with debug output: #{pdf_file}")

        # Step 1: Parse the PDF
        case PdfScreenplayParsex.parse_binary(binary) do
          {:ok, parse_result} ->
            # Step 2: Run through V2 classifier
            case PdfScreenplayParsex.Classifier.classify_screenplay(parse_result) do
              {:ok, classified_pages} ->
                # Step 3: Convert to debug text output
                text_output = format_debug_results(classified_pages)
                
                case File.write(output_file, text_output) do
                  :ok ->
                    IO.puts("Debug classification results saved to: #{output_file}")
                    print_summary(classified_pages)

                  {:error, reason} ->
                    IO.puts("Error writing to output file: #{reason}")
                    System.halt(1)
                end

              {:error, reason} ->
                IO.puts("Error in classification: #{inspect(reason)}")
                System.halt(1)
            end

          {:error, reason} ->
            IO.puts("Error parsing PDF: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("Error reading PDF file '#{pdf_file}': #{reason}")
        System.halt(1)
    end
  end

  defp format_debug_results(classified_pages) do
    output = ["=== DEBUG CLASSIFIER RESULTS ===\n"]
    
    for {page, page_index} <- Enum.with_index(classified_pages) do
      page_output = format_page(page, page_index)
      [output | page_output]
    end
    |> List.flatten()
    |> Enum.join("")
  end

  defp format_page(page, page_index) do
    page_header = "\n--- PAGE #{page_index + 1} (#{page.page_width}x#{page.page_height}) ---\n"
    
    elements_output = 
      page.groups
      |> Enum.flat_map(& &1)
      |> Enum.map(&format_element/1)
      |> Enum.join("")
    
    if String.length(elements_output) > 0 do
      [page_header, elements_output]
    else
      []
    end
  end

  defp format_element(element) do
    type_str = case element.type do
      nil -> "UNCLASSIFIED"
      type -> type |> to_string() |> String.upcase()
    end
    
    # Format position info
    position = "x:#{Float.round(element.x, 1)}, y:#{Float.round(element.y, 1)}"
    
    # Add centering info if available
    centered_info = if element.centered, do: " [CENTERED]", else: ""
    
    # Clean up text for display
    clean_text = element.text |> String.trim() |> String.slice(0, 100)
    clean_text = if String.length(element.text) > 100, do: clean_text <> "...", else: clean_text
    
    "#{type_str}#{centered_info} (#{position}): #{clean_text}\n"
  end

  defp print_summary(classified_pages) do
    # Collect all elements
    all_elements = 
      classified_pages
      |> Enum.flat_map(fn page -> 
        page.groups
        |> Enum.flat_map(& &1)
      end)

    # Count by type
    counts = 
      all_elements
      |> Enum.reduce(%{}, fn element, acc ->
        type = element.type || :unclassified
        Map.update(acc, type, 1, &(&1 + 1))
      end)

    total_elements = length(all_elements)
    classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
    classification_ratio = length(classified_elements) / total_elements * 100

    IO.puts("\n=== SUMMARY ===")
    IO.puts("Total pages: #{length(classified_pages)}")
    IO.puts("Total elements: #{total_elements}")
    IO.puts("Classified elements: #{length(classified_elements)}")
    IO.puts("Classification ratio: #{Float.round(classification_ratio, 1)}%")
    IO.puts("\nElement counts:")
    
    # Sort by count descending
    counts
    |> Enum.sort_by(fn {_type, count} -> count end, :desc)
    |> Enum.each(fn {type, count} ->
      type_name = type |> to_string() |> String.replace("_", " ") |> String.capitalize()
      IO.puts("  #{type_name}: #{count}")
    end)
    
    IO.puts("")
  end
end