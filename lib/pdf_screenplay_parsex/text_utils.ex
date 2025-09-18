defmodule PdfScreenplayParsex.TextUtils do
  @moduledoc """
  Utility functions for testing screenplay parsing functionality.
  """

  def scene_heading?(text) do
    # Scene headings start with INT/EXT and have location info
    # Can have optional time of day after a hyphen, but hyphen is not required
    # Examples: "INT. HOUSE", "EXT. SPACE", "INT. KITCHEN - NIGHT"
    regex = ~r/^(INT|EXT|INT\/EXT|EXT\/INT)\.?\s+.+$/
    Regex.match?(regex, text)
  end

  def character?(text) do
    # Character names are all caps, don't end with colons, and may have extensions
    trimmed = String.trim(text)
    regex = ~r/^[A-Z][^():]*?(\s*\(.*?\))?$/
    Regex.match?(regex, trimmed) && not String.ends_with?(trimmed, ":")
  end

  def transition?(text) do
    regex =
      ~r/^(FADE IN:|FADE OUT\.|CUT TO:|DISSOLVE TO:|MATCH CUT TO:|SMASH CUT TO:|JUMP CUT TO:|CROSS CUT TO:|INTERCUT:|BURN TO:|BURN TO PINK:|INTERCUT WITH:|MONTAGE:|END MONTAGE|BACK TO:|FLASHBACK:|END FLASHBACK|FREEZE FRAME|THE END)$/i

    Regex.match?(regex, text)
  end

  def subheading?(text) do
    # Subheadings are all caps, short text (≤20 chars), not scene headings or transitions
    # Common subheadings: "OPEN ON:", "LATER", "CONTINUOUS", time markers, etc.
    trimmed = String.trim(text)
    
    all_caps_text?(trimmed) &&
    String.length(trimmed) <= 20 &&
    not scene_heading?(text) &&
    not transition?(text) &&
    not continuation?(text) &&
    # Allow specific screenplay subheadings that might look like character names
    (not character?(text) || screenplay_subheading_pattern?(trimmed))
  end

  defp screenplay_subheading_pattern?(text) do
    # Common screenplay subheading patterns
    Regex.match?(~r/^(OPEN ON|FADE IN|FADE OUT|LATER|CONTINUOUS|MEANWHILE|ELSEWHERE|SUDDENLY|MOMENTS LATER|THE NEXT DAY|NEXT DAY|THAT NIGHT|MORNING|AFTERNOON|EVENING|NIGHT|DAWN|DUSK|AFTERWARDS|FIVE MINUTES LATER):?$/i, text) ||
    # Time/date patterns
    Regex.match?(~r/^(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+\d{4}$/i, text) ||
    # Other common patterns
    Regex.match?(~r/^(TITLE CARD|SUPER|INSERT|CLOSE UP):?$/i, text)
  end

  def parenthetical?(text) do
    # Parentheticals are wrapped in parentheses and contain stage directions
    # Examples: "(angrily)", "(to himself)", "(beat)", "(pause)"
    # Note: Continuation markers like "(CONT'D)" are handled separately
    trimmed = String.trim(text)
    regex = ~r/^\(.*\)$/
    Regex.match?(regex, trimmed) && not continuation?(text)
  end

  def continuation?(text) do
    # Continuation markers indicate dialogue or action continues
    # Examples: "(MORE)", "(CONT'D)", "(CONTINUED)", "(CONT)", "(MORE TO COME)"
    trimmed = String.trim(text) |> String.upcase()
    regex = ~r/^\((MORE|CONT'D|CONTINUED|CONT|MORE TO COME)\)$/
    Regex.match?(regex, trimmed)
  end

  def all_caps_text?(text) when is_binary(text) do
    cleaned_text = String.trim(text)
    cleaned_text == String.upcase(cleaned_text) && 
    String.length(cleaned_text) > 0 &&
    String.match?(cleaned_text, ~r/[A-Z]/)
  end

  def all_caps_text?(_), do: false

  def author_marker?(text) do
    # Author markers: "Written", "by", author names on title page
    trimmed = String.trim(text) |> String.downcase()

    # Use regex to match various authorship patterns
    Regex.match?(~r/^(written|by|written by|screenplay by|teleplay by|story by)$/i, trimmed)
  end

  def source_marker?(text) do
    # Source markers: "Based on the novel", source material references
    # NOT including "Story by" which is a source credit
    trimmed = String.trim(text) |> String.downcase()

    String.contains?(trimmed, "based on") ||
    String.contains?(trimmed, "adapted from") ||
    String.contains?(trimmed, "inspired by")
  end

  def source_credit?(text) do
    # Source credits: "Story by", "Original screenplay by", etc.
    # These indicate story/writing credits (not adaptation sources)
    # Matches full text like "Story by KTM" or just "Story by"
    trimmed = String.trim(text)

    Regex.match?(~r/^(story by|original screenplay by|characters by|original story by)/i, trimmed)
  end

  def source_names?(text) do
    # Source names: draft information, version numbers, dates
    trimmed = String.trim(text)
    
    # Draft patterns: "STUDIO DRAFT", "FIRST DRAFT", dates, version info
    Regex.match?(~r/(DRAFT|VERSION|REVISION|FINAL)/i, trimmed) ||
    Regex.match?(~r/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/, trimmed) ||  # Date patterns
    Regex.match?(~r/(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+\d{1,2},?\s+\d{4}/i, trimmed)
  end

  def notes?(text) do
    # Notes: production company info, copyright, contact info
    trimmed = String.trim(text)
    
    # Production company patterns
    String.contains?(trimmed, "Bros") ||
    String.contains?(trimmed, "Pictures") ||
    String.contains?(trimmed, "Productions") ||
    String.contains?(trimmed, "Entertainment") ||
    String.contains?(trimmed, "Studios") ||
    String.contains?(trimmed, "Films") ||
    # Copyright and contact patterns
    String.contains?(trimmed, "©") ||
    String.contains?(trimmed, "Copyright") ||
    String.contains?(trimmed, "@")
  end

end
