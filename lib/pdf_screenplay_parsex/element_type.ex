defmodule PdfScreenplayParsex.ElementType do
  @moduledoc """
  Classification functions for screenplay elements.
  """

  alias PdfScreenplayParsex.TextElement
  alias PdfScreenplayParsex.TextUtils

  @doc """
  Classifies if an element is a title based on position, formatting, and context.
  """
  def title?(%TextElement{centered: centered} = element, _index, group, context) do
    # Must be centered
    # Must be relatively short (title-like)
    # Group should be simple (title + maybe subtitle)
    # Should be all caps, title case, or clearly title-like
    # Must be on first page only (page_number = 0)
    # More restrictive to avoid conflicts with new specific title page elements
    centered &&
      String.length(String.trim(element.text)) <= 50 &&
      length(group) <= 3 &&
      title_like_text?(element.text) &&
      Map.get(context, :page_number, 0) == 0 &&
      # Don't classify as title if it matches other specific title page patterns
      !TextUtils.author_marker?(element.text) &&
      !TextUtils.source_marker?(element.text) &&
      !TextUtils.source_names?(element.text) &&
      # Don't classify as title if we recently saw an author marker (this should be author)
      !Map.get(context, :recent_author_marker, false)
  end

  @doc """
  Classifies if an element is a scene heading based on pattern and context.
  """
  def scene_heading?(element, _index, _group, _context) do
    # Scene headings identified purely by content pattern - most reliable approach
    # Position-based rules can fail across different screenplay formats
    TextUtils.scene_heading?(element.text)
  end

  @doc """
  Classifies if an element is a character name based on position, formatting, and context.
  """
  def character?(element, index, group, context) do
    # Must be in character position range (use context if available)
    # Must look like a character name
    # If not first in group, previous element should have large gap (new logical section)
    # Characters can only be classified after screenplay has started OR on early pages (opening/prologue)
    screenplay_started = Map.get(context, :screenplay_started, false)
    page_number = Map.get(context, :page_number, 0)
    is_early_page = page_number <= 2  # Allow characters on pages 0, 1, 2 for opening content

    # Check if this could be a character based on position and text
    is_character_like =
      character_position?(element, context) &&
      TextUtils.character?(element.text) &&
      (screenplay_started || is_early_page)

    if is_character_like do
      if index == 0 do
        # First in group - check if valid character group structure
        valid_character_group?(group)
      else
        # Not first in group - check if it starts a new logical section
        # (large gap from previous element or different x position suggesting new column)
        prev_element = Enum.at(group, index - 1)

        # Character should have significant gap from previous (new paragraph/section)
        # or be at a different x position (dialogue vs character positioning)
        gap_to_prev = Map.get(element, :gap_to_prev, 0)

        (gap_to_prev > 15.0) ||  # Significant vertical gap
        (prev_element && abs(element.x - prev_element.x) > 50)  # Different horizontal position
      end
    else
      false
    end
  end

  @doc """
  Classifies if an element is a transition based on pattern and context.
  """
  def transition?(element, index, _group, _context) do
    # Must be first element in group
    # Must match transition pattern using TextUtils
    # Usually positioned towards the right margin
    index == 0 &&
      TextUtils.transition?(element.text) &&
      transition_position?(element)
  end

  @doc """
  Classifies if an element is a page number based on pattern and context.
  """
  def page_number?(element, _index, _group, _context) do
    # Page numbers are typically:
    # - Positioned at top or bottom margins
    # - Contain only numbers or simple number patterns
    # - Can be in any position within their group (not necessarily first)
    page_number_pattern?(element.text) &&
      page_number_position?(element)
  end

  @doc """
  Classifies if an element is a scene number based on pattern and context.
  """
  def scene_number?(element, _index, _group, _context) do
    # Scene numbers are typically:
    # - Positioned at left or right margins (not top/bottom)
    # - Contain numbers, often with periods or dashes
    # - Don't require being first in group since they can appear independently
    scene_number_pattern?(element.text) &&
      scene_number_position?(element)
  end

  @doc """
  Classifies if an element is a parenthetical based on pattern and context.
  """
  def parenthetical?(element, index, group, context) do
    # Parentheticals are:
    # - Wrapped in parentheses (text pattern)
    # - Preceded by a character element in the same group
    # - Positioned in dialogue area (similar to dialogue positioning)
    # Note: Parentheticals can appear in opening scenes/prologues before formal scene headings
    TextUtils.parenthetical?(element.text) &&
      preceded_by_character?(index, group) &&
      parenthetical_position?(element, context)
  end

  @doc """
  Classifies if an element is a continuation marker based on pattern and context.
  """
  def continuation?(element, _index, _group, _context) do
    # Continuation markers are:
    # - Wrapped in parentheses
    # - Contain specific continuation text patterns
    # - Usually positioned at character or dialogue positions
    TextUtils.continuation?(element.text)
  end

  @doc """
  Classifies if an element is a subheading based on pattern and context.
  """
  def subheading?(element, _index, _group, context) do
    # Subheadings are:
    # - All caps text
    # - Short text (≤20 characters)
    # - Positioned at scene heading position or left-aligned
    # - Can only be classified after screenplay has started
    screenplay_started = Map.get(context, :screenplay_started, false)
    screenplay_started &&
      TextUtils.subheading?(element.text) &&
      subheading_position?(element, context)
  end

  @doc """
  Classifies if an element is action text based on position and context.
  """
  def action?(element, _index, _group, context) do
    # Actions are text that:
    # - Start at the same x position as scene headings (left margin)
    # - Are not transitions or scene headings themselves
    # - Can only be classified after screenplay has started
    screenplay_started = Map.get(context, :screenplay_started, false)

    screenplay_started &&
      action_position?(element, context) &&
      not TextUtils.transition?(element.text) &&
      not TextUtils.scene_heading?(element.text)
  end

  @doc """
  Classifies if an element is dialogue based on position and context.
  """
  def dialogue?(element, _index, _group, context) do
    # Dialogue is positioned:
    # - After the scene heading x position (further right)
    # - Before the character x position (further left)
    # - Can only be classified after character position is ACTUALLY established
    # AND only after screenplay has started OR on early pages (opening/prologue)
    screenplay_started = Map.get(context, :screenplay_started, false)
    page_number = Map.get(context, :page_number, 0)
    is_early_page = page_number <= 2  # Allow dialogue on pages 0, 1, 2 for opening content

    # CRITICAL: Only classify as dialogue if we've actually seen a character
    # This prevents misclassifying character names as dialogue
    character_x = Map.get(context, :character_x_position)

    (screenplay_started || is_early_page) &&
      character_x != nil &&  # Must have actually established character position
      dialogue_position?(element, context)
  end

  @doc """
  Classifies if an element is an author marker based on pattern and context.
  """
  def author_marker?(element, _index, _group, context) do
    # Author markers appear on title pages (page 0)
    # Include "Written", "by", author names
    Map.get(context, :page_number, 0) == 0 &&
      element.centered &&
      TextUtils.author_marker?(element.text)
  end

  @doc """
  Classifies if an element is an author name based on title page position logic.
  """
  def author?(element, element_index, group, context) do
    # Authors appear on title pages (page 0)
    # Logic: ONLY if immediately following an author marker keyword like "By"
    on_title_page = Map.get(context, :page_number, 0) == 0

    on_title_page &&
      element.centered &&
      # Only accept as author if directly following "by" or similar
      (previous_is_author_marker?(element_index, group) ||
       (Map.get(context, :recent_author_marker, false) && is_author_name_text?(element.text)))
  end

  @doc """
  Classifies if an element is a source marker based on pattern and context.
  """
  def source_marker?(element, _index, _group, context) do
    # Source markers appear on title pages (page 0)
    # Include "Based on the novel", "by", source references
    Map.get(context, :page_number, 0) == 0 &&
      element.centered &&
      TextUtils.source_marker?(element.text)
  end

  @doc """
  Classifies if an element is source names based on pattern and context.
  """
  def source_names?(element, _index, _group, context) do
    # Source names appear on title pages (page 0)
    # Include draft info, dates, version numbers
    Map.get(context, :page_number, 0) == 0 &&
      element.centered &&
      TextUtils.source_names?(element.text)
  end

  @doc """
  Classifies if an element is a source credit (Story by, etc.) based on pattern and context.
  """
  def source?(element, _index, _group, context) do
    # Source credits appear on title pages (page 0)
    # Include "Story by", "Original screenplay by", etc.
    Map.get(context, :page_number, 0) == 0 &&
      element.centered &&
      TextUtils.source_credit?(element.text)
  end

  @doc """
  Classifies if an element is notes based on pattern and context.
  """
  def notes?(element, _index, _group, context) do
    # Notes can appear on title pages (page 0) or as header notes on any page
    # Include production company info, copyright, contact info
    # Also classify as notes if it's at the very top of page (y < 40)
    # Page numbers will be reclassified later if they match page number patterns
    page_number = Map.get(context, :page_number, 0)

    (page_number == 0 && TextUtils.notes?(element.text)) ||
    element.y < 40  # Header area - page numbers will override this later
  end

  # Helper functions

  defp title_case?(text) do
    # Simple title case check: first letter of each word is capitalized
    words = String.split(text, " ")

    Enum.all?(words, fn word ->
      case String.first(word) do
        nil -> true
        first_char -> first_char == String.upcase(first_char)
      end
    end)
  end

  defp title_like_text?(text) do
    # Text that looks like a main title (more restrictive than other title page elements)
    trimmed_lower = String.trim(text) |> String.downcase()

    (TextUtils.all_caps_text?(text) || title_case?(text)) &&
    # Reasonable word count for titles (using proper word count that handles spaced letters)
    proper_word_count(text) <= 6 &&
    trimmed_lower not in ["by", "written", "based on the novel"]
  end

  # Count actual words, handling cases where letters are spaced out
  defp proper_word_count(text) do
    # Split on spaces
    parts = String.split(String.trim(text), " ")

    # Check if we have mostly single letters (indicating spaced-out text)
    single_letter_count = Enum.count(parts, fn part -> String.length(part) == 1 end)

    if single_letter_count >= length(parts) * 0.7 do
      # Likely spaced letters, collapse them into words
      # Remove empty strings and join single letters, then split on multiple spaces
      text
      |> String.replace(~r/(\b\w)\s+(?=\w\b)/, "\\1")  # Remove spaces between single letters
      |> String.replace(~r/\s{2,}/, " ")  # Collapse multiple spaces to single space
      |> String.split(" ")
      |> Enum.reject(&(&1 == ""))
      |> length()
    else
      # Normal text, count words normally
      parts
      |> Enum.reject(&(&1 == ""))
      |> length()
    end
  end

  defp character_position?(%TextElement{x: x}, context) do
    case Map.get(context, :character_x_position) do
      nil ->
        # No established character position, use default range
        x >= 180 && x <= 400

      established_x ->
        # Use established character position with some tolerance
        abs(x - established_x) <= 1
    end
  end

  defp left_margin?(x) do
    # More permissive left margin for different PDF formatting
    # Original: x <= 110, expanded to handle varying formats
    x <= 140
  end


  defp transition_position?(%TextElement{x: x}) do
    # Transitions are typically positioned towards the right margin
    # Usually around x >= 400 for standard screenplay format
    x <= 180 || x >= 400
  end

  defp page_number_pattern?(text) do
    # Page numbers are typically just numbers, possibly with periods or dashes
    # Examples: "1", "12", "1.", "-12-", "Page 1"
    trimmed = String.trim(text)
    
    Regex.match?(~r/^(?:page\s+)?\d+\.?$|^-?\d+-?$/i, trimmed) ||
    # Simple number patterns
    Regex.match?(~r/^\d{1,3}$/, trimmed)
  end

  defp page_number_position?(%TextElement{y: y}) do
    # Page numbers are usually at top (y < 100) or bottom (y > 700) of page
    y < 100 || y > 700
  end

  defp scene_number_pattern?(text) do
    # Scene numbers are typically numbers with optional formatting
    # Examples: "1", "1A", "12.", "1-2", "A1"
    trimmed = String.trim(text)
    
    # Pattern for scene numbers: optional letter + number + optional letter/punctuation
    Regex.match?(~r/^[A-Z]?\d+[A-Z]?\.?$|^\d+[A-Z]?-\d*$/, trimmed)
  end

  defp scene_number_position?(%TextElement{x: x, y: y}) do
    # Scene numbers can be positioned at left margin or right margin
    # But not at top/bottom page margins (that's page numbers)
    # Left margin: x < 100 (far left) but not at top/bottom
    # Right margin: x >= 500 (far right) but not at top/bottom
    (x < 100 || x >= 500) && y >= 100 && y <= 700
  end

  defp valid_character_group?(group) do
    case length(group) do
      # Single element character (valid)
      1 ->
        true

      # Multiple elements - check if following elements could be dialogue/parentheticals
      _ ->
        # Following elements should have small gaps (gapless or nearly gapless)
        following_elements = Enum.drop(group, 1)

        Enum.all?(following_elements, fn elem ->
          elem.gap_to_prev == nil || elem.gap_to_prev <= 3.0
        end)
    end
  end



  defp action_position?(%TextElement{x: x}, context) do
    case Map.get(context, :scene_heading_x_position) do
      nil ->
        # No established scene heading position, use default left margin
        left_margin?(x)

      established_x ->
        # Use established scene heading position with some tolerance
        abs(x - established_x) <= 1
    end
  end


  defp dialogue_position?(%TextElement{x: x}, context) do
    scene_heading_x = Map.get(context, :scene_heading_x_position)
    character_x = Map.get(context, :character_x_position)
    dialogue_x = Map.get(context, :dialogue_x_position)

    case {scene_heading_x, character_x, dialogue_x} do
      {nil, _, _} -> false  # No scene heading position established
      {_, nil, _} -> false  # No character position established
      {sh_x, char_x, nil} ->
        # No established dialogue position - use range between scene heading and character
        x > sh_x && x < char_x
      {_sh_x, _char_x, established_dialogue_x} ->
        # Use established dialogue position with tight tolerance
        abs(x - established_dialogue_x) <= 1
    end
  end

  defp preceded_by_character?(index, group) do
    # Check if there's a character element before this index in the same group
    if index > 0 do
      preceding_elements = Enum.take(group, index)
      Enum.any?(preceding_elements, fn elem ->
        # Check if already classified as character OR looks like character
        Map.get(elem, :type) == :character ||
        (elem.x >= 180 && elem.x <= 400 && TextUtils.character?(elem.text))
      end)
    else
      false
    end
  end

  defp parenthetical_position?(%TextElement{x: x}, _context) do
    # Parentheticals are typically positioned in the dialogue area
    # They can appear at various x positions depending on the screenplay format
    # Generally between left margin and character position
    x >= 180 && x <= 280
  end

  defp subheading_position?(%TextElement{x: x}, context) do
    case Map.get(context, :scene_heading_x_position) do
      nil ->
        # No established scene heading position, use default left margin
        left_margin?(x)

      established_x ->
        # At scene heading position OR left-aligned (more lenient tolerance)
        abs(x - established_x) <= 5 || left_margin?(x)
    end
  end

  # Helper function to check if previous element is an author marker
  defp previous_is_author_marker?(element_index, group) do
    if element_index > 0 do
      previous_element = Enum.at(group, element_index - 1)
      if previous_element do
        previous_text = String.trim(previous_element.text) |> String.downcase()
        previous_text in ["by", "written", "written by", "screenplay by", "teleplay by", "story by"]
      else
        false
      end
    else
      false
    end
  end

  # Helper function to check if text looks like an author name
  defp is_author_name_text?(text) do
    trimmed = String.trim(text)

    # Author names are typically:
    # - Title case or all caps
    # - Contains common name patterns
    # - Not screenplay markers or source material references
    # - Reasonable length for a name
    words = String.split(trimmed, " ")
    word_count = length(words)

    word_count >= 1 && word_count <= 4 &&
    String.length(trimmed) <= 50 &&
    # Not screenplay terminology
    not String.contains?(String.downcase(trimmed), "based on") &&
    not String.contains?(String.downcase(trimmed), "novel") &&
    not String.contains?(String.downcase(trimmed), "draft") &&
    not String.contains?(String.downcase(trimmed), "version") &&
    # Contains letters (not just numbers/symbols)
    String.match?(trimmed, ~r/[A-Za-z]/)
  end

  # Legacy functions (kept for compatibility)
  def title_element?(_element, _context), do: false
  def subheading?(_element, _context), do: false
  def centered?(_element, _context), do: false
  def action?(_element, _context), do: false
  def dialogue?(_element, _context), do: false
end
