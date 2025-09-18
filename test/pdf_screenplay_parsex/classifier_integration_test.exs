defmodule PdfScreenplayParsex.ClassifierIntegrationTest do
  use ExUnit.Case, async: false

  alias PdfScreenplayParsex.Classifier

  @moduletag timeout: 30_000

  describe "V2 Classifier Integration with IT.pdf" do
    test "processes IT.pdf through complete V2 pipeline" do
      # Read the IT.pdf file
      pdf_path = Path.join([__DIR__, "..", "fixtures", "en", "IT.pdf"])
      assert File.exists?(pdf_path), "IT.pdf file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)

      # Step 1: Parse the PDF using the main parser
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)

      # Verify the parse result structure
      assert %{pages: pages, language: language, total_pages: total_pages} = parse_result
      assert is_list(pages)
      assert language == :english
      assert total_pages > 0
      assert length(pages) == total_pages

      # Step 2: Run through V2 classifier
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      # Verify the classified result structure
      assert is_list(classified_pages)
      assert length(classified_pages) == total_pages

      # Verify each page has the expected structure
      for page <- classified_pages do
        assert Map.has_key?(page, :groups)
        assert Map.has_key?(page, :page_width)
        assert Map.has_key?(page, :page_height)
        assert Map.has_key?(page, :page_number)

        assert is_list(page.groups)
        assert is_number(page.page_width)
        assert is_number(page.page_height)
        assert is_integer(page.page_number)
      end

      # Step 3: Analyze the first page for expected elements
      first_page = List.first(classified_pages)
      assert first_page.page_number == 0

      # Get all elements from all groups on first page
      all_first_page_elements =
        first_page.groups
        |> Enum.flat_map(& &1)
        |> Enum.reject(&is_nil(&1.type))

      # Should have some classified elements
      assert length(all_first_page_elements) > 0

      # Check for title elements on first page (IT screenplay should have title)
      title_elements = Enum.filter(all_first_page_elements, &(&1.type == :title))

      if length(title_elements) > 0 do
        title_element = List.first(title_elements)
        assert title_element.centered == true

        assert String.contains?(String.upcase(title_element.text), "IT") or
                 String.contains?(title_element.text, "IT")
      end

      # Step 4: Look for scene headings across all pages
      all_elements =
        classified_pages
        |> Enum.flat_map(fn page ->
          page.groups
          |> Enum.flat_map(& &1)
        end)

      scene_headings = Enum.filter(all_elements, &(&1.type == :scene_heading))

      # Should have scene headings in a screenplay
      assert length(scene_headings) > 0

      # Verify scene heading patterns
      for scene_heading <- Enum.take(scene_headings, 3) do
        text = String.trim(scene_heading.text)

        assert String.match?(text, ~r/^(INT|EXT)/i),
               "Scene heading should start with INT or EXT: #{text}"
      end

      # Step 5: Look for character names
      characters = Enum.filter(all_elements, &(&1.type == :character))

      # Should have character names in a screenplay
      assert length(characters) > 0

      # Step 5.5: Look for transitions
      transitions = Enum.filter(all_elements, &(&1.type == :transition))

      # Step 5.7: Look for page numbers
      page_numbers = Enum.filter(all_elements, &(&1.type == :page_number))

      # Step 5.8: Look for scene numbers
      scene_numbers = Enum.filter(all_elements, &(&1.type == :scene_number))

      # Verify character positioning
      for character <- Enum.take(characters, 5) do
        # Characters should be positioned in the character range
        assert character.x >= 180 and character.x <= 400,
               "Character x position should be between 180-400: #{character.x}"

        # Verify character has text content
        text = String.trim(character.text)
        assert String.length(text) > 0, "Character should have text content"
      end

      # Step 6: Verify element distribution
      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      _unclassified_elements = Enum.filter(all_elements, &is_nil(&1.type))

      classification_ratio = length(classified_elements) / length(all_elements)

      # Should classify a reasonable percentage of elements
      assert classification_ratio > 0.01,
             "Should classify at least 1% of elements, got #{Float.round(classification_ratio * 100, 1)}%"

      # Print summary for manual verification
      IO.puts("\n=== V2 Classifier Integration Test Results ===")
      IO.puts("Total pages: #{total_pages}")
      IO.puts("Total elements: #{length(all_elements)}")
      IO.puts("Classified elements: #{length(classified_elements)}")
      IO.puts("Classification ratio: #{Float.round(classification_ratio * 100, 1)}%")
      IO.puts("Scene headings found: #{length(scene_headings)}")
      IO.puts("Characters found: #{length(characters)}")
      IO.puts("Transitions found: #{length(transitions)}")
      IO.puts("Page numbers found: #{length(page_numbers)}")
      IO.puts("Scene numbers found: #{length(scene_numbers)}")
      IO.puts("Title elements found: #{length(title_elements)}")

      # Print first few classified elements for inspection
      IO.puts("\n=== First 10 Classified Elements ===")

      classified_elements
      |> Enum.take(10)
      |> Enum.with_index(1)
      |> Enum.each(fn {element, index} ->
        IO.puts("#{index}. [#{element.type}] #{String.slice(element.text, 0, 50)}...")
      end)

      IO.puts("===============================================\n")
    end

    test "achieves expected element count distribution for IT.pdf" do
      # This test asserts the exact element counts we achieved during development
      # to ensure classification consistency and catch regressions

      pdf_path = Path.join([__DIR__, "..", "fixtures", "en", "IT.pdf"])
      assert File.exists?(pdf_path), "IT.pdf file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)

      # Parse and classify
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

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

      # Assert exact counts that we achieved during development
      assert total_elements == 4981, "Expected 4981 total elements, got #{total_elements}"

      assert length(classified_elements) == 4981,
             "Expected all elements classified, got #{length(classified_elements)}"

      assert Float.round(classification_ratio, 1) == 100.0,
             "Expected 100.0% classification ratio, got #{Float.round(classification_ratio, 1)}%"

      # Assert specific element type counts (updated after fixing scene heading detection)
      expected_counts = %{
        # Reduced because more are now correctly classified as scene_heading
        action: 1994,
        # Adjusted after adding index check to scene_heading
        dialogue: 1673,
        character: 937,
        # Increased from 161 - now catches headings without hyphens
        scene_heading: 189,
        page_number: 132,
        parenthetical: 35,
        transition: 7,
        author_marker: 3,
        continuation: 3,
        title: 1,
        # Increased after improved detection
        subheading: 2,
        source_marker: 1,
        source_names: 1,
        notes: 1
      }

      for {type, expected_count} <- expected_counts do
        actual_count = Map.get(counts, type, 0)

        assert actual_count == expected_count,
               "Expected #{expected_count} #{type} elements, got #{actual_count}"
      end

      # Ensure no unclassified elements remain
      unclassified_count = Map.get(counts, :unclassified, 0)

      assert unclassified_count == 0,
             "Expected 0 unclassified elements, got #{unclassified_count}"

      # Print verification summary
      IO.puts("\n=== Element Count Verification ===")
      IO.puts("✓ Total elements: #{total_elements}")
      IO.puts("✓ Classification ratio: #{Float.round(classification_ratio, 1)}%")
      IO.puts("✓ All expected element counts match")

      # Print sorted counts for verification
      counts
      |> Enum.sort_by(fn {_type, count} -> count end, :desc)
      |> Enum.each(fn {type, count} ->
        IO.puts("  #{String.capitalize(to_string(type))}: #{count}")
      end)

      IO.puts("=====================================\n")
    end

    test "V2 Classifier Integration with Interstellar-Final.pdf achieves expected element count distribution" do
      # Read the PDF and parse it with V2 classifier
      pdf_path = "test/fixtures/en/Interstellar-Final.pdf"
      assert File.exists?(pdf_path), "Interstellar-Final.pdf file not found at #{pdf_path}"

      # Read the PDF binary
      pdf_binary = File.read!(pdf_path)

      # Parse the PDF using the main parser
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)

      # Classify with V2 classifier
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      # Extract all elements from all pages
      all_elements =
        classified_pages
        |> Enum.flat_map(fn page ->
          page.groups
          |> Enum.flat_map(&Function.identity/1)
        end)

      # Calculate statistics
      total_elements = length(all_elements)
      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      _unclassified_elements = Enum.filter(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / total_elements * 100

      # Count elements by type
      counts =
        all_elements
        |> Enum.reduce(%{}, fn element, acc ->
          type = element.type || :unclassified
          Map.update(acc, type, 1, &(&1 + 1))
        end)

      # Print test results
      IO.puts("\n=== V2 Classifier Integration Test Results (Interstellar) ===")
      IO.puts("Total pages: #{length(classified_pages)}")
      IO.puts("Total elements: #{total_elements}")
      IO.puts("Classified elements: #{length(classified_elements)}")
      IO.puts("Classification ratio: #{Float.round(classification_ratio, 1)}%")
      IO.puts("Scene headings found: #{Map.get(counts, :scene_heading, 0)}")
      IO.puts("Characters found: #{Map.get(counts, :character, 0)}")
      IO.puts("Transitions found: #{Map.get(counts, :transition, 0)}")
      IO.puts("Page numbers found: #{Map.get(counts, :page_number, 0)}")
      IO.puts("Scene numbers found: #{Map.get(counts, :scene_number, 0)}")
      IO.puts("Title elements found: #{Map.get(counts, :title, 0)}")

      # Show first 10 classified elements with truncated text
      IO.puts("\n=== First 10 Classified Elements ===")

      classified_elements
      |> Enum.take(10)
      |> Enum.with_index(1)
      |> Enum.each(fn {elem, idx} ->
        truncated_text = String.slice(elem.text || "", 0, 15) <> "..."
        IO.puts("#{idx}. [#{elem.type}] #{truncated_text}")
      end)

      IO.puts("===============================================\n")

      # Basic assertions
      assert total_elements == 5574, "Expected 5574 total elements, got #{total_elements}"

      assert length(classified_elements) == 5567,
             "Expected 5567 classified elements, got #{length(classified_elements)}"

      assert Float.round(classification_ratio, 1) == 99.9,
             "Expected 99.9% classification ratio, got #{Float.round(classification_ratio, 1)}%"

      # Assert specific element type counts (updated after fixing scene heading detection)
      expected_counts = %{
        dialogue: 2313,
        # Reduced by 1 - one more scene heading detected
        action: 1389,
        character: 1126,
        # Increased from 357 - now catches headings without hyphens
        scene_heading: 358,
        parenthetical: 213,
        page_number: 155,
        unclassified: 7,  # was 8, one more element now classified
        continuation: 8,
        transition: 2,
        title: 1
      }

      # Print element count verification
      IO.puts("=== Element Count Verification (Interstellar) ===")

      for {type, expected_count} <- expected_counts do
        actual_count = Map.get(counts, type, 0)

        assert actual_count == expected_count,
               "Expected #{expected_count} #{type} elements, got #{actual_count}"

        IO.puts("✓ #{String.capitalize(to_string(type))}: #{actual_count}")
      end

      IO.puts("=====================================\n")
    end

    test "V2 Classifier Integration with Alien Covenant.pdf achieves expected element count distribution" do
      # Read the PDF and parse it with V2 classifier
      pdf_path = "test/fixtures/en/Alien Covenant.pdf"
      assert File.exists?(pdf_path), "Alien Covenant.pdf file not found at #{pdf_path}"

      # Read the PDF binary
      pdf_binary = File.read!(pdf_path)

      # Parse the PDF using the main parser
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)

      # Classify with V2 classifier
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      # Extract all elements from all pages
      all_elements =
        classified_pages
        |> Enum.flat_map(fn page ->
          page.groups
          |> Enum.flat_map(&Function.identity/1)
        end)

      # Calculate statistics
      total_elements = length(all_elements)
      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      _unclassified_elements = Enum.filter(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / total_elements * 100

      # Count elements by type
      counts =
        all_elements
        |> Enum.reduce(%{}, fn element, acc ->
          type = element.type || :unclassified
          Map.update(acc, type, 1, &(&1 + 1))
        end)

      # Print test results
      IO.puts("\n=== V2 Classifier Integration Test Results (Alien Covenant) ===")
      IO.puts("Total pages: #{length(classified_pages)}")
      IO.puts("Total elements: #{total_elements}")
      IO.puts("Classified elements: #{length(classified_elements)}")
      IO.puts("Classification ratio: #{Float.round(classification_ratio, 1)}%")
      IO.puts("Scene headings found: #{Map.get(counts, :scene_heading, 0)}")
      IO.puts("Characters found: #{Map.get(counts, :character, 0)}")
      IO.puts("Transitions found: #{Map.get(counts, :transition, 0)}")
      IO.puts("Page numbers found: #{Map.get(counts, :page_number, 0)}")
      IO.puts("Scene numbers found: #{Map.get(counts, :scene_number, 0)}")
      IO.puts("Title elements found: #{Map.get(counts, :title, 0)}")

      # Show first 10 classified elements with truncated text
      IO.puts("\n=== First 10 Classified Elements ===")

      classified_elements
      |> Enum.take(10)
      |> Enum.with_index(1)
      |> Enum.each(fn {elem, idx} ->
        truncated_text = String.slice(elem.text || "", 0, 15) <> "..."
        IO.puts("#{idx}. [#{elem.type}] #{truncated_text}")
      end)

      IO.puts("===============================================\n")

      # Basic assertions
      assert total_elements == 4383, "Expected 4383 total elements, got #{total_elements}"

      assert length(classified_elements) == 4382,
             "Expected 4382 classified elements, got #{length(classified_elements)}"

      assert Float.round(classification_ratio, 1) == 100.0,
             "Expected 100.0% classification ratio, got #{Float.round(classification_ratio, 1)}%"

      # Assert specific element type counts (baseline from current implementation)
      expected_counts = %{
        action: 2009,  # was 2012, 3 fewer due to improved classification
        dialogue: 1365,
        character: 656,  # was 653, improved character detection finds 3 more
        scene_heading: 158,
        page_number: 118,
        parenthetical: 62,
        author_marker: 2,  # was 1, improved detection finds 1 more
        continuation: 3,
        title: 6,  # was 7, improved title detection is more accurate
        unclassified: 1,
        source_marker: 1
      }

      # Print element count verification
      IO.puts("=== Element Count Verification (Alien Covenant) ===")

      for {type, expected_count} <- expected_counts do
        actual_count = Map.get(counts, type, 0)

        assert actual_count == expected_count,
               "Expected #{expected_count} #{type} elements, got #{actual_count}"

        IO.puts("✓ #{String.capitalize(to_string(type))}: #{actual_count}")
      end

      IO.puts("=====================================\n")
    end

    test "V2 Classifier Integration with John Wick.pdf achieves expected element count distribution" do
      # Read the PDF and parse it with V2 classifier
      pdf_path = "test/fixtures/en/John Wick.pdf"
      assert File.exists?(pdf_path), "John Wick.pdf file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      all_elements =
        classified_pages
        |> Enum.flat_map(fn page -> page.groups |> Enum.flat_map(&Function.identity/1) end)

      total_elements = length(all_elements)
      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / total_elements * 100

      counts =
        all_elements
        |> Enum.reduce(%{}, fn element, acc ->
          type = element.type || :unclassified
          Map.update(acc, type, 1, &(&1 + 1))
        end)

      # Basic assertions
      assert total_elements == 3477, "Expected 3477 total elements, got #{total_elements}"

      assert length(classified_elements) == 3476,
             "Expected 3476 classified elements, got #{length(classified_elements)}"

      assert Float.round(classification_ratio, 1) == 100.0,
             "Expected 100.0% classification ratio, got #{Float.round(classification_ratio, 1)}%"

      # Assert specific element type counts
      expected_counts = %{
        action: 1743,
        dialogue: 757,
        character: 454,
        scene_heading: 251,
        parenthetical: 158,
        page_number: 99,
        transition: 6,
        continuation: 3,
        author_marker: 1,
        title: 1,
        unclassified: 1,
        subheading: 1,
        notes: 1
      }

      for {type, expected_count} <- expected_counts do
        actual_count = Map.get(counts, type, 0)

        assert actual_count == expected_count,
               "Expected #{expected_count} #{type} elements, got #{actual_count}"
      end

      IO.puts("\n=== John Wick Classification Results ===")

      IO.puts(
        "✓ Total elements: #{total_elements}, Classification: #{Float.round(classification_ratio, 1)}%"
      )

      IO.puts("=====================================\n")
    end

    test "V2 Classifier Integration with Juno.pdf achieves expected element count distribution" do
      # Read the PDF and parse it with V2 classifier
      pdf_path = "test/fixtures/en/Juno.pdf"
      assert File.exists?(pdf_path), "Juno.pdf file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      all_elements =
        classified_pages
        |> Enum.flat_map(fn page -> page.groups |> Enum.flat_map(&Function.identity/1) end)

      total_elements = length(all_elements)
      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / total_elements * 100

      counts =
        all_elements
        |> Enum.reduce(%{}, fn element, acc ->
          type = element.type || :unclassified
          Map.update(acc, type, 1, &(&1 + 1))
        end)

      # Basic assertions
      assert total_elements == 4460, "Expected 4460 total elements, got #{total_elements}"

      assert length(classified_elements) == 4451,
             "Expected 4451 classified elements, got #{length(classified_elements)}"

      assert Float.round(classification_ratio, 1) == 99.8,
             "Expected 99.8% classification ratio, got #{Float.round(classification_ratio, 1)}%"

      # Assert specific element type counts (updated after classification improvements)
      expected_counts = %{
        dialogue: 1845,
        # Reduced further - more elements reclassified as characters
        action: 914,  # was 1023, improved character detection reduces action count
        character: 859,  # was 850, improved character detection finds 9 more
        # New! Previously misclassified as action
        scene_number: 227,
        page_number: 180,
        scene_heading: 117,
        continuation: 93,
        parenthetical: 84,
        subheading: 25,
        unclassified: 9,
        transition: 4,
        title: 2,
        notes: 101,  # was 1, y < 40 detection finds many more notes
        author_marker: 0
      }

      for {type, expected_count} <- expected_counts do
        actual_count = Map.get(counts, type, 0)

        assert actual_count == expected_count,
               "Expected #{expected_count} #{type} elements, got #{actual_count}"
      end

      IO.puts("\n=== Juno Classification Results ===")

      IO.puts(
        "✓ Total elements: #{total_elements}, Classification: #{Float.round(classification_ratio, 1)}%"
      )

      IO.puts("=====================================\n")
    end

    test "V2 Classifier Integration with A Star Is Born.pdf achieves expected element count distribution" do
      # This PDF previously had low classification due to margin detection issues
      # Now achieves excellent classification after fixing left margin threshold
      pdf_path = "test/fixtures/en/A Star Is Born.pdf"
      assert File.exists?(pdf_path), "A Star Is Born.pdf file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      all_elements =
        classified_pages
        |> Enum.flat_map(fn page -> page.groups |> Enum.flat_map(&Function.identity/1) end)

      total_elements = length(all_elements)
      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / total_elements * 100

      counts =
        all_elements
        |> Enum.reduce(%{}, fn element, acc ->
          type = element.type || :unclassified
          Map.update(acc, type, 1, &(&1 + 1))
        end)

      # Basic assertions (after fixing margin detection)
      assert total_elements == 5805, "Expected 5805 total elements, got #{total_elements}"

      assert length(classified_elements) == 5793,
             "Expected 5793 classified elements, got #{length(classified_elements)}"

      assert Float.round(classification_ratio, 1) == 99.8,
             "Expected 99.8% classification ratio, got #{Float.round(classification_ratio, 1)}%"

      # Assert specific element type counts (after margin detection fix)
      expected_counts = %{
        # Updated from debug output
        action: 3812,
        # Updated from debug output
        dialogue: 1281,
        parenthetical: 248,
        page_number: 136,
        # Updated from debug output
        continuation: 107,
        # Now properly detected!
        scene_heading: 113,
        # Updated from debug output - improved character detection
        character: 79,  # was 77, finds 2 more characters
        # Updated: reduced by improved classification
        unclassified: 12,  # was 14, 2 more elements now classified
        transition: 11,
        source_marker: 2,
        notes: 2,
        # Added: title is now properly classified
        title: 1,
        author_marker: 1
      }

      for {type, expected_count} <- expected_counts do
        actual_count = Map.get(counts, type, 0)

        assert actual_count == expected_count,
               "Expected #{expected_count} #{type} elements, got #{actual_count}"
      end

      IO.puts("\n=== A Star Is Born Classification Results (Fixed!) ===")

      IO.puts(
        "✅ Total elements: #{total_elements}, Classification: #{Float.round(classification_ratio, 1)}% (Excellent - margin detection fixed)"
      )

      IO.puts("=====================================\n")
    end

    test "handles errors gracefully with invalid input" do
      # Test with invalid input
      assert {:error, _reason} = Classifier.classify_screenplay(%{invalid: "data"})
      assert {:error, _reason} = Classifier.classify_screenplay("not a map")
      assert {:error, _reason} = Classifier.classify_screenplay(nil)
    end

    test "processes empty pages correctly" do
      # Test with empty pages
      empty_parse_result = %{
        pages: [],
        language: :english,
        total_pages: 0
      }

      {:ok, result} = Classifier.classify_screenplay(empty_parse_result)
      assert result == []
    end
  end

  describe "Batman Begins Classification" do
    test "processes Batman Begins through complete classification pipeline" do
      # Read the Batman Begins PDF file
      pdf_path = Path.join([__DIR__, "..", "fixtures", "en", "batman-begins-2005-screenplay.pdf"])
      assert File.exists?(pdf_path), "Batman Begins PDF file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)

      # Step 1: Parse the PDF using the main parser
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)

      # Verify the parse result structure
      assert %{pages: pages, language: language, total_pages: total_pages} = parse_result
      assert is_list(pages)
      assert language == :english
      assert total_pages > 0
      assert length(pages) == total_pages

      # Step 2: Run through classifier
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      # Verify the classified result structure
      assert is_list(classified_pages)
      assert length(classified_pages) == total_pages

      # Count elements by type
      all_elements =
        classified_pages
        |> Enum.flat_map(fn page ->
          page.groups
          |> Enum.flat_map(& &1)
        end)

      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      total_elements = length(all_elements)
      classification_ratio = length(classified_elements) / total_elements * 100

      # Count by type
      counts =
        all_elements
        |> Enum.reduce(%{}, fn element, acc ->
          type = element.type || :unclassified
          Map.update(acc, type, 1, &(&1 + 1))
        end)

      # Basic assertions for Batman Begins
      assert total_elements == 6109, "Expected 6109 total elements, got #{total_elements}"

      assert length(classified_elements) == 6109,
             "Expected 6109 classified elements, got #{length(classified_elements)}"

      assert Float.round(classification_ratio, 1) == 100.0,
             "Expected 100.0% classification ratio, got #{Float.round(classification_ratio, 1)}%"

      # Assert specific element type counts (updated after classification improvements)
      expected_counts = %{
        action: 1866,  # was 1960, improved character detection reduced misclassified action
        dialogue: 1803,
        character: 966,
        scene_number: 547,
        scene_heading: 320,
        page_number: 242,
        parenthetical: 167,
        continuation: 95,
        transition: 6,
        title: 1,
        author: 1,
        author_marker: 1
      }

      for {type, expected_count} <- expected_counts do
        actual_count = Map.get(counts, type, 0)

        assert actual_count == expected_count,
               "Expected #{expected_count} #{type} elements, got #{actual_count}"
      end

      # Verify title page classification specifically
      first_page = hd(classified_pages)

      first_page_elements =
        first_page.groups
        |> Enum.flat_map(& &1)
        # First 3 elements
        |> Enum.take(3)

      # Verify the specific title page pattern we fixed
      assert length(first_page_elements) >= 3, "Expected at least 3 elements on first page"

      [first_elem, second_elem, third_elem] = first_page_elements

      # Verify the exact classification we wanted
      assert first_elem.type == :title, "First element should be TITLE, got #{first_elem.type}"

      assert first_elem.text == "BATMAN BEGINS",
             "First element should be 'BATMAN BEGINS', got '#{first_elem.text}'"

      assert second_elem.type == :author_marker,
             "Second element should be AUTHOR_MARKER, got #{second_elem.type}"

      assert second_elem.text == "By", "Second element should be 'By', got '#{second_elem.text}'"

      assert third_elem.type == :author, "Third element should be AUTHOR, got #{third_elem.type}"

      assert third_elem.text == "DAVID GOYER",
             "Third element should be 'DAVID GOYER', got '#{third_elem.text}'"

      IO.puts("\n=== Batman Begins Classification Results ===")

      IO.puts(
        "✅ Total elements: #{total_elements}, Classification: #{Float.round(classification_ratio, 1)}%"
      )

      IO.puts("✅ Scene headings: #{Map.get(counts, :scene_heading, 0)} (improved from 0)")
      IO.puts("✅ Title page pattern: TITLE → AUTHOR_MARKER → AUTHOR")
      IO.puts("=====================================\n")
    end
  end

  describe "Additional PDF Fixtures" do
    test "processes The Irishman through classification pipeline" do
      pdf_path = Path.join([__DIR__, "..", "fixtures", "en", "the-irishman-script-pdf.pdf"])
      assert File.exists?(pdf_path), "The Irishman PDF file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      all_elements =
        classified_pages |> Enum.flat_map(fn page -> page.groups |> Enum.flat_map(& &1) end)

      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / length(all_elements) * 100

      counts =
        all_elements
        |> Enum.reduce(%{}, fn element, acc ->
          type = element.type || :unclassified
          Map.update(acc, type, 1, &(&1 + 1))
        end)

      assert length(all_elements) == 5779
      assert Float.round(classification_ratio, 1) == 100.0
      assert Map.get(counts, :scene_heading, 0) == 296

      IO.puts("\n=== The Irishman Classification Results ===")

      IO.puts(
        "✅ Total elements: #{length(all_elements)}, Classification: #{Float.round(classification_ratio, 1)}%"
      )

      IO.puts("=====================================\n")
    end

    test "processes Empathy Man through classification pipeline" do
      pdf_path = Path.join([__DIR__, "..", "fixtures", "en", "Empathy_Man_FINAL.pdf"])
      assert File.exists?(pdf_path), "Empathy Man PDF file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      all_elements =
        classified_pages |> Enum.flat_map(fn page -> page.groups |> Enum.flat_map(& &1) end)

      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / length(all_elements) * 100

      assert classification_ratio > 90.0

      IO.puts("\n=== Empathy Man Classification Results ===")

      IO.puts(
        "✅ Total elements: #{length(all_elements)}, Classification: #{Float.round(classification_ratio, 1)}%"
      )

      IO.puts("=====================================\n")
    end

    test "processes Caught By The Roots through classification pipeline" do
      pdf_path =
        Path.join([
          __DIR__,
          "..",
          "fixtures",
          "en",
          "Caught By The Roots(Female-led)_Danny King_Screenplay.pdf"
        ])

      assert File.exists?(pdf_path), "Caught By The Roots PDF file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      all_elements =
        classified_pages |> Enum.flat_map(fn page -> page.groups |> Enum.flat_map(& &1) end)

      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / length(all_elements) * 100

      assert classification_ratio > 90.0

      IO.puts("\n=== Caught By The Roots Classification Results ===")

      IO.puts(
        "✅ Total elements: #{length(all_elements)}, Classification: #{Float.round(classification_ratio, 1)}%"
      )

      IO.puts("=====================================\n")
    end

    test "processes Africa-Tolev through classification pipeline" do
      pdf_path = Path.join([__DIR__, "..", "fixtures", "en", "Africa-Tolev.pdf"])
      assert File.exists?(pdf_path), "Africa-Tolev PDF file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      all_elements =
        classified_pages |> Enum.flat_map(fn page -> page.groups |> Enum.flat_map(& &1) end)

      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / length(all_elements) * 100

      assert classification_ratio > 90.0

      IO.puts("\n=== Africa-Tolev Classification Results ===")

      IO.puts(
        "✅ Total elements: #{length(all_elements)}, Classification: #{Float.round(classification_ratio, 1)}%"
      )

      IO.puts("=====================================\n")
    end

    test "processes Slices of Death through classification pipeline" do
      pdf_path =
        Path.join([__DIR__, "..", "fixtures", "en", "xxxSLICES-OF-DEATHbyAdamNadworniak.pdf"])

      assert File.exists?(pdf_path), "Slices of Death PDF file not found at #{pdf_path}"

      pdf_binary = File.read!(pdf_path)
      {:ok, parse_result} = PdfScreenplayParsex.parse_binary(pdf_binary)
      {:ok, classified_pages} = Classifier.classify_screenplay(parse_result)

      all_elements =
        classified_pages |> Enum.flat_map(fn page -> page.groups |> Enum.flat_map(& &1) end)

      classified_elements = Enum.reject(all_elements, &is_nil(&1.type))
      classification_ratio = length(classified_elements) / length(all_elements) * 100

      assert classification_ratio > 90.0

      IO.puts("\n=== Slices of Death Classification Results ===")

      IO.puts(
        "✅ Total elements: #{length(all_elements)}, Classification: #{Float.round(classification_ratio, 1)}%"
      )

      IO.puts("=====================================\n")
    end
  end
end
