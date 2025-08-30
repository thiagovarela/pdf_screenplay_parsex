defmodule PdfScreenplayParsex.ElementClassifier do
  @moduledoc """
  Classifies individual text elements into screenplay element types.

  This module handles the multi-pass classification logic for identifying
  scene headings, characters, dialogue, actions, transitions, and other
  screenplay elements based on positioning, formatting, and text patterns.
  """

  alias PdfScreenplayParsex.{ClassificationContext, ElementGrouper, TextElement, TextUtils}

  @doc """
  First pass classification: identifies scene headings, transitions, characters, and page numbers.

  ## Parameters

    * `element` - TextElement to classify
    * `index` - Index of element in group
    * `group` - List of elements in the same group
    * `context` - ClassificationContext with page and state information
    * `screenplay_started` - Boolean indicating if screenplay content has begun

  ## Returns

  Returns the element with type classification added.
  """
  @spec classify_element_first_pass(TextElement.t(), integer(), list(), ClassificationContext.t(), boolean()) ::
          TextElement.t()
  def classify_element_first_pass(element, index, group, context, screenplay_started) do
    cond do
      # Page number: short text, numeric, left or right aligned, small height
      page_number?(element, context.page_width) ->
        Map.put(element, :type, :page_number)

      # Scene heading can only be the first element of a group
      index == 0 && scene_heading?(element) ->
        Map.put(element, :type, :scene_heading)

      # Transition: can be alone or with page numbers
      index == 0 && transition?(element) && transition_group_valid?(group) ->
        Map.put(element, :type, :transition)

      # Character: Only detect characters after screenplay content has started
      # This prevents title page elements from being incorrectly classified as characters
      # Allow detection for first element OR potential dual dialogue characters
      screenplay_started && 
      (index == 0 || potential_dual_dialogue_character?(element, index, group) || 
       Map.get(element, :potential_dual_dialogue_character, false)) && 
      character_first_pass?(element, group, context.established_char_x) ->
        Map.put(element, :type, :character)

      # Default - keep as unclassified TextElement
      true ->
        element
    end
  end

  @doc """
  Second pass classification: identifies subheadings, actions, and missed characters.

  ## Parameters

    * `element` - TextElement to classify
    * `group` - List of elements in the same group
    * `context` - ClassificationContext with scene heading and character positions

  ## Returns

  Returns the element with updated classification.
  """
  @spec classify_element_second_pass(TextElement.t(), list(), ClassificationContext.t()) :: TextElement.t()
  def classify_element_second_pass(element, group, context) do
    # Get element's index in the group
    element_index = Enum.find_index(group, fn e -> e == element end) || 0

    cond do
      # Fix character classification when grouped with non-dialogue elements
      should_fix_character_classification?(element, element_index, group) ->
        Map.put(element, :type, :centered)

      # Skip if already classified
      already_classified?(element) ->
        element

      # Character: second pass check for elements not caught in first pass (centering issues)
      second_pass_character?(element, element_index, group, context) ->
        Map.put(element, :type, :character)

      # Orphaned dialogue: dialogue at x~180 or centered, mixed case, sentence-like
      # Check this BEFORE action to catch dialogue that might look like action
      # IMPORTANT: Only classify as dialogue if there's a character in the group
      orphaned_dialogue?(element) && valid_dialogue_with_character?(element, group, context) ->
        Map.put(element, :type, :dialogue)

      # Action: left-aligned, sentence case, not scene heading or character
      action?(element) ->
        Map.put(element, :type, :action)

      # Subheading: alone in group OR with only page numbers, all caps, left-aligned or at scene heading position
      subheading_second_pass?(element, group, context) ->
        Map.put(element, :type, :subheading)

      # Centered text: elements that are marked as centered (like "THE END", "FADE IN", etc.)
      centered_text?(element) ->
        Map.put(element, :type, :centered)

      # Default - keep as is
      true ->
        element
    end
  end

  @doc """
  Third pass classification: identifies parentheticals and dialogue.

  ## Parameters

    * `element` - TextElement to classify
    * `group` - List of elements in the same group

  ## Returns

  Returns the element with final classification.
  """
  @spec classify_element_third_pass(TextElement.t(), list()) :: TextElement.t()
  def classify_element_third_pass(element, group) do
    # Get element's index in the group
    element_index = Enum.find_index(group, fn e -> e == element end) || 0

    cond do
      # Skip if already classified
      Map.has_key?(element, :type) && element.type != nil ->
        element

      # Parenthetical: immediately after character, contains parentheses
      element_index > 0 && parenthetical?(element, element_index, group) ->
        Map.put(element, :type, :parenthetical)

      # Dialogue: gapless element in a group with a character, not parenthetical
      element_index > 0 && dialogue?(element, element_index, group) ->
        Map.put(element, :type, :dialogue)

      # Default - keep as is
      true ->
        element
    end
  end

  # Helper functions for classify_element_second_pass complexity reduction

  @spec should_fix_character_classification?(TextElement.t(), non_neg_integer(), list()) :: boolean()
  defp should_fix_character_classification?(element, element_index, group) do
    # Don't fix dual dialogue characters
    is_dual_dialogue = Map.get(element, :potential_dual_dialogue_character, false) || 
                       Enum.any?(group, &Map.get(&1, :potential_dual_dialogue, false))
    
    element_index == 0 && Map.get(element, :type) == :character &&
      has_non_dialogue_raw_elements?(group) && not is_dual_dialogue
  end

  @spec already_classified?(TextElement.t()) :: boolean()
  defp already_classified?(element) do
    Map.has_key?(element, :type) && element.type != nil
  end

  @spec second_pass_character?(TextElement.t(), non_neg_integer(), list(), ClassificationContext.t()) :: boolean()
  defp second_pass_character?(element, element_index, group, context) do
    element_index == 0 && character_second_pass?(element, group, context.character_x_position)
  end

  @spec subheading_second_pass?(TextElement.t(), list(), ClassificationContext.t()) :: boolean()
  defp subheading_second_pass?(element, group, context) do
    (length(group) == 1 || group_has_only_page_numbers_besides_element?(group, element)) &&
      TextUtils.all_caps?(element) &&
      (at_scene_heading_x?(element, context.scene_heading_x_positions) ||
       (element.x >= 60 && element.x <= 140 && String.length(String.trim(element.text)) <= 20))
  end

  @spec centered_text?(TextElement.t()) :: boolean()
  defp centered_text?(element) do
    element.centered && TextUtils.all_caps?(element)
  end

  @spec orphaned_dialogue?(TextElement.t()) :: boolean()
  defp orphaned_dialogue?(element) do
    # Orphaned dialogue can be at dialogue position (x~180) or centered
    (dialogue_position?(element) || element.centered) && looks_like_dialogue?(element)
  end

  @spec valid_dialogue_with_character?(TextElement.t(), list(), ClassificationContext.t()) :: boolean()
  defp valid_dialogue_with_character?(element, group, context) do
    # Dialogue is only valid if there's a character in the same group
    has_character = Enum.any?(group, fn elem ->
      Map.get(elem, :type) == :character
    end)
    
    # Exception: continuation from previous page (character carries over)
    has_continuing_character = context.continuing_character != nil
    
    # Exception: continuation markers in text
    has_continuation_marker = element.text && String.match?(element.text, ~r/\(CONT'D\)|\(MORE\)|^\(/)
    
    has_character || has_continuing_character || has_continuation_marker
  end

  # Private functions for element type detection

  @spec scene_heading?(TextElement.t()) :: boolean()
  defp scene_heading?(%TextElement{text: text}) do
    # Scene heading regex patterns
    # Matches: INT., EXT., INT/EXT, I/E, INT - , EXT - , etc.
    scene_heading_pattern =
      ~r/^\s*(INT\.?|EXT\.?|INT\/EXT\.?|I\/E\.?|EST\.?|ESTABLISHING)[\s\.\-]/i

    Regex.match?(scene_heading_pattern, text)
  end

  @spec transition?(TextElement.t()) :: boolean()
  defp transition?(%TextElement{text: text, x: x}) do
    # Check text patterns first
    has_transition_text = transition_by_text_pattern?(text)

    if has_transition_text do
      # Transitions can be left-aligned (like FADE IN:) or right-aligned (like CUT TO:)
      # Left-aligned: x around 72-120
      # Right-aligned: x around 400+
      is_left_aligned = x >= 60 && x <= 140
      is_right_aligned = x >= 400

      is_left_aligned || is_right_aligned
    else
      false
    end
  end

  @spec transition_by_text_pattern?(String.t()) :: boolean()
  defp transition_by_text_pattern?(text) do
    # Trim whitespace for pattern matching
    trimmed_text = String.trim(text)

    # Standard transition patterns
    # Matches: CUT TO:, FADE IN:, FADE OUT:, FADE OUT, FADE OUT., DISSOLVE TO:, SMASH CUT TO:, etc.
    # Split into patterns that end with colons (no optional period) and those that don't
    transition_with_colon = ~r/^(CUT TO|FADE (IN|OUT|TO BLACK)|DISSOLVE TO|MATCH CUT|SMASH CUT( TO)?|WIPE TO|IRIS (IN|OUT)|TIME CUT|JUMP CUT):$/i
    transition_no_colon = ~r/^(FADE OUT|FADE IN)\.?$/i

    # Time-based transitions
    # Matches: LATER, CONTINUOUS, MOMENTS LATER, etc.
    time_transition =
      ~r/^(LATER|CONTINUOUS|MOMENTS? LATER|SAME|DAY|NIGHT|MORNING|AFTERNOON|EVENING|DAWN|DUSK)$/i

    # Visual/Color transitions
    # Matches: BURN TO [COLOR], DISSOLVE TO [COLOR], FADE TO [COLOR], etc.
    visual_transition = ~r/(BURN TO|FADE TO|DISSOLVE TO|CUT TO|SMASH TO)\s+[A-Z][A-Z\s]*\.?$/i

    Regex.match?(transition_with_colon, trimmed_text) || Regex.match?(transition_no_colon, trimmed_text) ||
      Regex.match?(time_transition, trimmed_text) || Regex.match?(visual_transition, trimmed_text)
  end

  @spec character_first_pass?(TextElement.t(), list(), number() | nil) :: boolean()
  defp character_first_pass?(%TextElement{x: x} = element, group, established_character_x) do
    # Removed unused variable
    
    cond do
      # Dual dialogue character - be very lenient
      Map.get(element, :potential_dual_dialogue_character, false) ->
        TextUtils.valid_character_name?(element.text) && in_character_range?(x)
      
      # No established position - use normal new character logic
      is_nil(established_character_x) ->
        in_character_range?(x) && TextUtils.valid_character_name?(element.text) &&
          has_valid_character_group_structure_for_new?(group)
      
      # Established position exists - check if element matches
      true ->
        at_character_position?(x, established_character_x) && TextUtils.valid_character_name?(element.text) &&
          has_valid_character_group_structure?(group)
    end
  end


  @spec character_second_pass?(TextElement.t(), list(), number() | nil) :: boolean()
  defp character_second_pass?(%TextElement{x: x} = element, group, character_x_position) do
    # Check if text matches character name pattern
    if TextUtils.valid_character_name?(element.text) do
      # Extract name part to check if it's all caps
      {name_part, _extension} = TextUtils.extract_character_name_and_extension(element.text)
      
      if TextUtils.all_caps_text?(name_part) do
        # Check position validity
        position_valid = cond do
          # If we have an established position, check if we're near it
          !is_nil(character_x_position) ->
            abs(x - character_x_position) <= 5
          
          # If no established position, check if we're in typical character range
          # Characters are typically between x=180 and x=280
          true ->
            x >= 180 && x <= 280
        end
        
        if position_valid do
          # If group has more than 1 element, following elements must be gapless
          if length(group) > 1 do
            ElementGrouper.has_gapless_following_elements?(group)
          else
            # Single element character names are allowed (though rare)
            true
          end
        else
          false
        end
      else
        false
      end
    else
      false
    end
  end

  @spec at_character_position?(number(), number()) :: boolean()
  defp at_character_position?(x, established_x) do
    # Allow tight tolerance for established position
    tight_match = abs(x - established_x) <= 5
    
    # Also allow standard screenplay character positions even if different from established
    # This handles cases where established position is from dual dialogue or unusual positioning
    standard_positions = [252.0, 180.0]  # Common character and dialogue positions
    standard_match = Enum.any?(standard_positions, fn pos -> abs(x - pos) <= 5 end)
    
    # Allow wider tolerance if positions are reasonably close (within 80px)
    reasonable_distance = abs(x - established_x) <= 80 && in_character_range?(x)
    
    tight_match || standard_match || reasonable_distance
  end

  @spec in_character_range?(number()) :: boolean()
  defp in_character_range?(x) do
    # Characters are typically positioned between x=180 and x=280 in screenplays
    # Extended range to x=400 to accommodate right-side dual dialogue
    x >= 180 && x <= 400
  end

  @spec transition_group_valid?(list()) :: boolean()
  defp transition_group_valid?(group) do
    # Transitions can be alone or with page numbers only
    case length(group) do
      1 -> true
      _ -> 
        # Check if all other elements are page numbers
        non_transition_elements = Enum.drop(group, 1)
        Enum.all?(non_transition_elements, fn elem ->
          # Check if it looks like a page number
          text = String.trim(elem.text || "")
          String.match?(text, ~r/^\d+\.?$/)
        end)
    end
  end

  @spec has_potential_dialogue_content?(list()) :: boolean()
  defp has_potential_dialogue_content?(group) do
    # Skip the first element (potential character) and check if there's dialogue-like content
    remaining_elements = Enum.drop(group, 1)
    
    # Look for elements that could be dialogue (mixed case, sentence-like text)
    Enum.any?(remaining_elements, fn elem ->
      text = String.trim(elem.text || "")
      # Dialogue is typically mixed case, has reasonable length, and looks like speech
      text != String.upcase(text) && 
        String.length(text) > 5 &&
        String.length(text) < 200 &&
        not String.starts_with?(String.upcase(text), "INT.") &&
        not String.starts_with?(String.upcase(text), "EXT.")
    end)
  end

  @spec potential_dual_dialogue_character?(TextElement.t(), integer(), list()) :: boolean()
  defp potential_dual_dialogue_character?(element, _index, group) do
    # Check if this could be a second character in a dual dialogue setup
    # Must be a valid character name and positioned significantly different from first element
    if TextUtils.valid_character_name?(element.text) do
      first_element = List.first(group)
      if first_element && first_element != element do
        # Check horizontal separation (potential dual dialogue)
        x_diff = abs(element.x - first_element.x)
        # Also check if first element could be a character
        x_diff > 150 && TextUtils.valid_character_name?(first_element.text) && 
        in_character_range?(element.x)
      else
        false
      end
    else
      false
    end
  end

  @spec has_valid_character_group_structure?(list()) :: boolean()
  defp has_valid_character_group_structure?(_group) do
    # For position-based detection, we're more lenient since position is already validated
    # We just need to ensure the first element could be a character name
    true
  end

  @spec has_valid_character_group_structure_for_new?(list()) :: boolean()
  defp has_valid_character_group_structure_for_new?(group) do
    # For new character detection, be more lenient to allow dual dialogue
    cond do
      length(group) == 1 -> true
      length(group) <= 3 -> ElementGrouper.has_gapless_following_elements?(group)  
      # For complex groups (potential dual dialogue), just check if there's dialogue-like content
      true -> has_potential_dialogue_content?(group)
    end
  end

  @spec at_scene_heading_x?(TextElement.t(), list(number())) :: boolean()
  defp at_scene_heading_x?(%TextElement{x: x}, scene_heading_x_positions) do
    # Allow small tolerance for X position matching (within 2 pixels)
    tolerance = 2

    Enum.any?(scene_heading_x_positions, fn scene_x ->
      abs(x - scene_x) <= tolerance
    end)
  end

  @spec page_number?(TextElement.t(), number()) :: boolean()
  defp page_number?(%TextElement{text: text, x: x, width: width, height: height}, page_width) do
    trimmed_text = String.trim(text)

    # Must be short (max 6 chars for longer page numbers)
    is_short = String.length(trimmed_text) <= 6

    # Must match page number pattern (digits with optional period and revision markers)
    # Examples: 1, 2., 15, 4.*, 12A, 5R, 8.*, 123
    is_numeric = Regex.match?(~r/^\d+\.?[A-Z*]*$/, trimmed_text)

    # Must be reasonably small height (increased threshold)
    is_small = height <= 20

    # Check alignment - must be left, right, or center aligned
    left_margin = x
    right_margin = page_width - (x + width)
    center_distance = abs((x + width / 2) - (page_width / 2))

    # More flexible alignment detection
    is_edge_aligned = left_margin < 120 || right_margin < 120 || center_distance < 50

    is_short && is_numeric && is_small && is_edge_aligned
  end

  @spec parenthetical?(TextElement.t(), integer(), list()) :: boolean()
  defp parenthetical?(%TextElement{text: text, x: x}, index, group) do
    trimmed_text = String.trim(text)
    # Parenthetical position: slightly indented from dialogue (200-250 range)
    is_parenthetical_position = x >= 200 && x <= 250
    
    # Parentheticals can exist in character groups OR continuation groups
    has_character_or_dialogue = has_character_in_group?(group) || has_dialogue_like_elements?(group)
    
    if has_character_or_dialogue || looks_like_parenthetical_text?(trimmed_text) do
      cond do
        # Complete parenthetical: enclosed in parentheses and properly positioned
        complete_parenthetical?(trimmed_text) && is_parenthetical_position ->
          true

        # Multi-line parenthetical start: starts with "(" but doesn't end with ")"
        multiline_parenthetical_start?(trimmed_text, text) ->
          has_closing_parenthetical?(group, index + 1)

        # Multi-line parenthetical continuation: continues from previous parenthetical
        true ->
          parenthetical_continuation?(group, index, text)
      end
    else
      false
    end
  end

  @spec has_character_in_group?(list()) :: boolean()
  defp has_character_in_group?(group) do
    Enum.any?(group, fn elem -> Map.get(elem, :type) == :character end)
  end

  @spec has_dialogue_like_elements?(list()) :: boolean()
  defp has_dialogue_like_elements?(group) do
    # Check if group has elements that look like dialogue (at x~180, mixed case)
    Enum.any?(group, fn elem ->
      text = String.trim(elem.text || "")
      elem.x >= 160 && elem.x <= 200 && text != String.upcase(text) && String.length(text) > 0
    end)
  end

  @spec looks_like_parenthetical_text?(String.t()) :: boolean()
  defp looks_like_parenthetical_text?(text) do
    # Check if text looks like a parenthetical directive
    text 
    |> String.starts_with?("(") 
    |> Kernel.and(String.ends_with?(text, ")"))
    |> Kernel.and(String.length(text) > 2)
    |> Kernel.and(String.length(text) < 50)  # Reasonable length for parenthetical
  end


  @spec complete_parenthetical?(String.t()) :: boolean()
  defp complete_parenthetical?(text) do
    String.starts_with?(text, "(") && String.ends_with?(text, ")")
  end

  @spec multiline_parenthetical_start?(String.t(), String.t()) :: boolean()
  defp multiline_parenthetical_start?(trimmed_text, full_text) do
    String.starts_with?(trimmed_text, "(") && !String.contains?(full_text, ")")
  end

  @spec has_closing_parenthetical?(list(), integer()) :: boolean()
  defp has_closing_parenthetical?(group, next_index) do
    next_element = Enum.at(group, next_index)
    next_element && String.contains?(next_element.text, ")")
  end

  @spec parenthetical_continuation?(list(), integer(), String.t()) :: boolean()
  defp parenthetical_continuation?(group, index, text) do
    if index <= 0 do
      false
    else
      prev_element = Enum.at(group, index - 1)
      prev_element &&
        Map.get(prev_element, :type) == :parenthetical &&
        !String.contains?(prev_element.text, ")") &&
        String.contains?(text, ")")
    end
  end

  @spec dialogue?(TextElement.t(), integer(), list()) :: boolean()
  defp dialogue?(%TextElement{} = element, index, group) do
    # Check if there's a character in this group
    has_character = Enum.any?(group, fn elem -> Map.get(elem, :type) == :character end)

    if has_character do
      # Element must be gapless (small gap to previous element)
      is_gapless = element.gap_to_prev == nil || element.gap_to_prev <= 2

      # Check for dialogue continuation: same x position as previous dialogue element
      if index > 0 do
        previous_element = Enum.at(group, index - 1)
        is_dialogue_continuation = 
          previous_element && 
          Map.get(previous_element, :type) == :dialogue &&
          abs(element.x - previous_element.x) <= 5 &&  # Same x position (within 5px tolerance)
          is_gapless

        if is_dialogue_continuation do
          true
        else
          # Original logic: check all elements between character and this one
          character_index = Enum.find_index(group, fn elem -> Map.get(elem, :type) == :character end)

          if character_index != nil && index > character_index do
            # All elements between character and current must be gapless
            elements_between = Enum.slice(group, (character_index + 1)..index)

            all_gapless =
              Enum.all?(elements_between, fn elem ->
                elem.gap_to_prev == nil || elem.gap_to_prev <= 2
              end)

            is_gapless && all_gapless
          else
            false
          end
        end
      else
        false
      end
    else
      false
    end
  end

  @spec action?(TextElement.t()) :: boolean()
  defp action?(%TextElement{text: text, x: x}) do
    # Action lines are left-aligned (x ≈ 72-140 points for various formats)
    is_left_aligned = x >= 60 && x <= 140

    # Not a scene heading pattern
    scene_heading_regex = ~r/^((?:\*{0,3}_?)?(?:(?:int|ext|est|i\/e)[. ]).+)|^(?:\.(?!\.+))(.+)/i
    not_scene_heading = not Regex.match?(scene_heading_regex, text)

    # Not a transition pattern (transitions are typically right-aligned or end with "TO:")
    transition_regex = ~r/(FADE|CUT|DISSOLVE|BURN|SMASH)\s+TO:?\s*$|TO:\s*$/i
    not_transition = not Regex.match?(transition_regex, text)

    # Not a standalone character name (character names should be centered and simple)
    # Action text can contain character names, but shouldn't BE a character name
    # Character names are typically centered, so left-aligned all-caps with punctuation is likely action
    is_simple_character_name =
      String.match?(text, ~r/^[A-Z][A-Z\s']*( [A-Z]+)*(\s+\([^)]+\))?$/) &&  # Stricter pattern, no special chars
        String.length(String.trim(text)) < 25 &&
        not String.contains?(text, ["--", ".", "!", "?", ":"])  # Action fragments have punctuation

    not_standalone_character = not is_simple_character_name

    # Must have some actual content (not just whitespace)
    has_content = String.trim(text) != ""

    # Not a page marker like "CONTINUED:"
    not_page_marker = not String.match?(text, ~r/^(CONTINUED|MORE|CONT'D):?\s*$/i)

    is_left_aligned && not_scene_heading && not_transition && not_standalone_character &&
      has_content && not_page_marker
  end

  @spec has_non_dialogue_raw_elements?(list()) :: boolean()
  defp has_non_dialogue_raw_elements?(group) do
    # Skip the first element (the potential character) and check the rest
    remaining_elements = Enum.drop(group, 1)

    # Filter out page numbers - they shouldn't affect character classification
    non_page_elements = Enum.reject(remaining_elements, fn elem ->
      elem_type = Map.get(elem, :type)
      text = String.trim(elem.text || "")

      # Remove page numbers from consideration
      elem_type == :page_number || String.match?(text, ~r/^\d+\.?$/)
    end)

    # If there are no non-page elements remaining, don't reclassify
    if Enum.empty?(non_page_elements) do
      false
    else
      # Check remaining elements for actual non-dialogue content
      Enum.any?(non_page_elements, fn elem ->
        elem_type = Map.get(elem, :type)

        case elem_type do
          nil ->
            # Unclassified - assume it could be dialogue unless clearly not
            text = String.trim(elem.text)

            cond do
              # Scene numbers: parentheses with numbers
              String.match?(text, ~r/^\(\d+\)$/) -> true

              # Very short text (< 3 chars) is likely not dialogue
              String.length(text) < 3 -> true

              # Default: assume unclassified text could be dialogue
              true -> false
            end

          :scene_number -> true
          :transition -> true
          :scene_heading -> true
          :action -> true
          :dialogue -> false
          :parenthetical -> false
          _ -> true  # Any other classified type is non-dialogue
        end
      end)
    end
  end

  # Helper functions for orphaned dialogue detection

  @spec dialogue_position?(TextElement.t()) :: boolean()
  defp dialogue_position?(%TextElement{x: x}) do
    # Dialogue is typically at x: 150-180 range
    x >= 140 && x <= 200
  end

  @spec looks_like_dialogue?(TextElement.t()) :: boolean()
  defp looks_like_dialogue?(%TextElement{text: text, x: x}) do
    trimmed = String.trim(text)

    # Not all caps (distinguishes from character names)
    not_all_caps = trimmed != String.upcase(trimmed)

    # Contains lowercase letters (dialogue characteristic)
    has_lowercase = String.match?(trimmed, ~r/[a-z]/)

    # Not too short (likely not a stage direction)
    reasonable_length = String.length(trimmed) > 3

    # Enhanced action detection - if at action position, be more strict about dialogue classification
    if x >= 60 && x <= 140 do
      # At action position - check for clear dialogue markers
      # Dialogue often has quotes, question marks, exclamations, or conversational patterns
      dialogue_markers = String.match?(trimmed, ~r/["'""]|[?!]|^(I|You|We|Let|Don't|Can't|Won't|Didn't|Isn't|Aren't)\s/i) ||
                         String.match?(trimmed, ~r/(said|asked|replied|answered|whispered|shouted|yelled)[\s,]/i) ||
                         String.starts_with?(trimmed, "(") # Parenthetical
      
      # Action patterns that should NOT be dialogue
      action_patterns = String.match?(trimmed, ~r/^(He|She|They|It|The|A|An)\s/i) ||
                       String.match?(trimmed, ~r/(slides|walks|runs|sits|stands|looks|turns|opens|closes|grabs|puts|takes|moves)\s/i) ||
                       String.match?(trimmed, ~r/\b(door|window|table|chair|book|car|house|room|light)\b/i)
      
      not_all_caps && has_lowercase && reasonable_length && dialogue_markers && not action_patterns
    else
      # At dialogue position - use original logic
      not_action_like = not String.match?(trimmed, ~r/^(He|She|They|It)\s/i)
      not_all_caps && has_lowercase && reasonable_length && not_action_like
    end
  end

  @spec group_has_only_page_numbers_besides_element?(list(), TextElement.t()) :: boolean()
  defp group_has_only_page_numbers_besides_element?(group, target_element) do
    other_elements = Enum.reject(group, fn elem -> elem == target_element end)

    Enum.all?(other_elements, fn elem ->
      Map.get(elem, :type) == :page_number
    end)
  end
end
