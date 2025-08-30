defmodule PdfScreenplayParsex.TextUtils do
  @moduledoc """
  Text processing utilities for screenplay parsing.

  This module provides common text manipulation and validation functions
  used throughout the screenplay classification process.
  """

  alias PdfScreenplayParsex.TextElement

  @doc """
  Calculates the vertical gap between the current element and the previous element.

  ## Parameters

    * `text_items` - List of text items from PDF extraction
    * `index` - Index of the current element

  ## Returns

  Returns the gap in points, or `nil` if this is the first element.
  """
  @spec calculate_gap_to_prev(list(), non_neg_integer()) :: float() | nil
  def calculate_gap_to_prev(_text_items, 0), do: nil

  def calculate_gap_to_prev(text_items, index) when index > 0 do
    current_item = Enum.at(text_items, index)
    prev_item = Enum.at(text_items, index - 1)

    current_y = current_item["y"]
    prev_bottom = prev_item["y"] + prev_item["height"]

    # Gap is the vertical distance from bottom of previous element to top of current element
    gap = current_y - prev_bottom

    # Return gap if positive (actual gap), otherwise 0 (overlapping or touching)
    max(0, gap)
  end

  @doc """
  Calculates the vertical gap between the current element and the next element.

  ## Parameters

    * `text_items` - List of text items from PDF extraction
    * `index` - Index of the current element

  ## Returns

  Returns the gap in points, or `nil` if this is the last element.
  """
  @spec calculate_gap_to_next(list(), non_neg_integer()) :: float() | nil
  def calculate_gap_to_next(text_items, index) when index >= length(text_items) - 1, do: nil

  def calculate_gap_to_next(text_items, index) do
    current_item = Enum.at(text_items, index)
    next_item = Enum.at(text_items, index + 1)

    current_bottom = current_item["y"] + current_item["height"]
    next_y = next_item["y"]

    # Gap is the vertical distance from bottom of current element to top of next element
    gap = next_y - current_bottom

    # Return gap if positive (actual gap), otherwise 0 (overlapping or touching)
    max(0, gap)
  end

  @doc """
  Determines if an element is centered based on its position and the page width.

  ## Parameters

    * `item` - Text item map with x, width properties
    * `page_width` - Width of the page in points

  ## Returns

  Returns `true` if the element is considered centered, `false` otherwise.
  """
  @spec element_centered?(map(), number()) :: boolean()
  def element_centered?(item, page_width) do
    x = item["x"]
    element_center = x + item["width"] / 2
    page_center = page_width / 2
    
    # Consider an element centered if its center is within tolerance of the page center
    # Base tolerance is 20 points, but we'll be more flexible for certain cases
    base_tolerance = 20
    distance_from_center = abs(element_center - page_center)
    
    # For elements that might be titles (x >= 280), use a more generous tolerance
    # This handles cases like Interstellar where the title is at x=292
    tolerance = if x >= 280 && x <= 320, do: 35, else: base_tolerance
    
    # Must be geometrically centered first
    if distance_from_center > tolerance do
      false
    else
      # For elements that are geometrically centered, apply exclusions more carefully
      
      # Exclude dialogue positions that are clearly not meant to be centered
      # x=180 dialogue position should not be considered centered unless very precisely centered
      dialogue_exclusion = (x >= 170 && x <= 190) && distance_from_center > 8
      
      # For character positions (x=240-270), be more nuanced:
      # - If distance is small (≤18pt), allow centering (could be titles)
      # - If distance is larger (>18pt), it's probably a character name
      char_position_exclusion = (x >= 240 && x <= 270) && distance_from_center > 18
      
      # Allow centering unless excluded
      not (char_position_exclusion || dialogue_exclusion)
    end
  end

  @doc """
  Extracts character name and extension from character text.

  Handles various extension formats:
  - Parentheses: "JUNO (V.O.)", "CHARACTER (CONT'D)"
  - Space-separated: "JUNO V.O.", "CHARACTER CONT'D"

  ## Parameters

    * `text` - The character text to parse

  ## Returns

  Returns `{name_part, extension}` tuple. Extension is `nil` if none found.

  ## Examples

      iex> TextUtils.extract_character_name_and_extension("JUNO (V.O.)")
      {"JUNO", "(V.O.)"}

      iex> TextUtils.extract_character_name_and_extension("JUNO V.O.")
      {"JUNO", "V.O."}

      iex> TextUtils.extract_character_name_and_extension("JUNO")
      {"JUNO", nil}
  """
  @spec extract_character_name_and_extension(String.t()) :: {String.t(), String.t() | nil}
  def extract_character_name_and_extension(text) do
    # First try to match character name with extension in parentheses
    # Extensions like (CONT'D), (O.S.), (V.O.), (OFF), etc.
    case Regex.run(~r/^(.+?)\s*(\([^)]+\))\s*$/, text) do
      [_, name_part, extension] ->
        {String.trim(name_part), String.trim(extension)}
      _ ->
        # Try to match character name with extension without parentheses
        # Extensions like V.O., O.S., CONT'D, OFF, etc.
        case Regex.run(~r/^(.+?)\s+((?:V\.O\.|O\.S\.|CONT\'D|OFF|ON|FILTER|PHONE|RADIO|INTERCOM|ECHO|REVERB)\.?)$/, text) do
          [_, name_part, extension] ->
            {String.trim(name_part), String.trim(extension)}
          _ ->
            # No extension found, return entire text as name
            {String.trim(text), nil}
        end
    end
  end

  @doc """
  Checks if text is all uppercase (ignoring punctuation and numbers).

  ## Parameters

    * `text` - The text to check

  ## Returns

  Returns `true` if all letters in the text are uppercase, `false` otherwise.
  """
  @spec all_caps_text?(String.t()) :: boolean()
  def all_caps_text?(text) do
    # Remove punctuation and numbers, check if remaining letters are all uppercase
    letters_only = String.replace(text, ~r/[^a-zA-Z]/, "")

    # Must have at least some letters and all must be uppercase
    String.length(letters_only) > 0 && letters_only == String.upcase(letters_only)
  end

  @doc """
  Checks if text is all caps for TextElement (ignoring punctuation and numbers).

  ## Parameters

    * `element` - TextElement struct

  ## Returns

  Returns `true` if all letters in the element text are uppercase, `false` otherwise.
  """
  @spec all_caps?(TextElement.t()) :: boolean()
  def all_caps?(%TextElement{text: text}) do
    all_caps_text?(text)
  end

  @doc """
  Validates if text matches valid character name patterns.

  Checks for:
  - One or more uppercase words separated by spaces
  - Optional extensions like V.O., O.S., CONT'D
  - Extensions in parentheses: (V.O.), (CONT'D)

  ## Parameters

    * `text` - The text to validate

  ## Returns

  Returns `true` if text matches character name patterns, `false` otherwise.

  ## Examples

      iex> TextUtils.valid_character_name?("JUNO")
      true

      iex> TextUtils.valid_character_name?("BRICK STEEL")
      true

      iex> TextUtils.valid_character_name?("JUNO (V.O.)")
      true

      iex> TextUtils.valid_character_name?("juno")
      false
  """
  @spec valid_character_name?(String.t()) :: boolean()
  def valid_character_name?(text) do
    trimmed = String.trim(text)
    
    # Exclude screenplay formatting elements
    if String.match?(trimmed, ~r/^(THE END|FADE IN|FADE OUT|CUT TO|DISSOLVE TO)$/i) do
      false
    else
      # Regex pattern covers:
      # - One or more uppercase words separated by spaces: JUNO, BRICK STEEL, WHISPERED VOICE
      # - Numbered characters: GIRL #1, BOY #2, SOLDIER #3
      # - Titles with periods: MRS. SMITH, DR. JONES, MS. BROWN
      # - Hyphenated names: ONE-ARMED OLD MAN, EX-HUSBAND, TWENTY-SOMETHING GIRL
      # - Possessive names: FATHER'S VOICE, MOTHER'S VOICE, CHILD'S VOICE
      # - Slash-separated names: COMMERCIAL/RADIO, TV/RADIO, ANNOUNCER/VOICE
      # - Mixed-case surnames: MRS. McCANN, DR. MacDONALD, O'BRIEN
      # - Extensions like V.O., O.S., CONT'D: JUNO V.O., CHARACTER O.S.
      # - Extensions in parentheses: JUNO (V.O.), STEEL (CONT'D)
      # - Multiple parenthetical extensions: PENNYWISE (O.C.) (CONT'D)
      character_regex = ~r/^[A-Z]+\.?(?:[A-Za-z\s#0-9\.\-'\/]+[A-Za-z0-9])?(?:\s+[A-Z]\.(?:[A-Z]\.)*)*(?:\s*\([^)]+\))*\s*$/
      Regex.match?(character_regex, trimmed)
    end
  end

  @doc """
  Checks if text looks like a date.

  ## Parameters

    * `text` - The text to check

  ## Returns

  Returns `true` if text matches date patterns, `false` otherwise.
  """
  @spec looks_like_date?(String.t()) :: boolean()
  def looks_like_date?(text) do
    # Don't match if it looks like an address
    if String.match?(text, ~r/(street|st|avenue|ave|road|rd|drive|dr|lane|ln|way|court|ct|place|pl)\.?$/i) do
      false
    else
      date_patterns = [
        ~r/^\d{1,2}\/\d{1,2}\/\d{2,4}$/,  # MM/DD/YYYY or MM/DD/YY
        ~r/^\d{1,2}-\d{1,2}-\d{2,4}$/,   # MM-DD-YYYY or MM-DD-YY
        ~r/(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+\d{4}/i,
        ~r/^(draft|revision|rev).*\d/i  # Draft date
      ]

      Enum.any?(date_patterns, fn pattern ->
        String.match?(text, pattern)
      end)
    end
  end

  @doc """
  Checks if text looks like contact information.

  ## Parameters

    * `text` - The text to check

  ## Returns

  Returns `true` if text matches contact patterns, `false` otherwise.
  """
  @spec looks_like_contact?(String.t()) :: boolean()
  def looks_like_contact?(text) do
    contact_patterns = [
      ~r/\d{3}[-.]?\d{3}[-.]?\d{4}/,  # Phone numbers
      ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,  # Email
      ~r/\d+\s+[\w\s]+\s+(street|st|avenue|ave|road|rd|drive|dr|lane|ln|way|court|ct|place|pl)/i,  # Address
      ~r/(los angeles|new york|hollywood|chicago|atlanta|austin|ca|ny|california|florida|texas)/i  # Cities/States
    ]

    Enum.any?(contact_patterns, fn pattern ->
      String.match?(text, pattern)
    end)
  end

  @doc """
  Checks if text looks like copyright information.

  ## Parameters

    * `text` - The text to check

  ## Returns

  Returns `true` if text matches copyright patterns, `false` otherwise.
  """
  @spec looks_like_copyright?(String.t()) :: boolean()
  def looks_like_copyright?(text) do
    copyright_patterns = [
      ~r/copyright|©|\(c\)|all rights reserved|proprietary/i,
      ~r/wga|writers guild/i
    ]

    Enum.any?(copyright_patterns, fn pattern ->
      String.match?(text, pattern)
    end)
  end

  @doc """
  Checks if text is a page marker that shouldn't be classified as dialogue.

  ## Parameters

    * `text` - The text to check

  ## Returns

  Returns `true` if text is a page marker, `false` otherwise.
  """
  @spec page_marker?(String.t()) :: boolean()
  def page_marker?(text) do
    trimmed = String.trim(text)

    # Page markers typically contain colons and are formatting/continuity markers
    String.contains?(trimmed, ":") &&
    (String.contains?(String.upcase(trimmed), "CONTINUED") ||
     String.contains?(String.upcase(trimmed), "MORE") ||
     Regex.match?(~r/^(FADE|CUT|DISSOLVE|SMASH).*(TO|IN|OUT):/i, trimmed))
  end

  @doc """
  Checks if group contains author markers like "written by", "screenplay by".

  ## Parameters

    * `group` - List of TextElement structs

  ## Returns

  Returns `true` if group contains author markers, `false` otherwise.
  """
  @spec has_author_marker?(list(TextElement.t())) :: boolean()
  def has_author_marker?(group) do
    author_markers = ~r/(written by|screenplay by|authored by|created by|original screenplay by|^screenplay$|^by$)/i

    Enum.any?(group, fn elem ->
      String.match?(elem.text, author_markers)
    end)
  end

  @doc """
  Checks if group contains source markers.

  ## Parameters

    * `group` - List of TextElement structs

  ## Returns

  Returns `true` if group contains source markers, `false` otherwise.
  """
  @spec has_source_marker?(list(TextElement.t())) :: boolean()
  def has_source_marker?(group) do
    source_markers = ~r/(based on|inspired by|adapted from|from the novel|from the story|story by|novel by)/i

    Enum.any?(group, fn elem ->
      String.match?(elem.text, source_markers)
    end)
  end
end
