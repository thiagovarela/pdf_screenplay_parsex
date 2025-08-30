defmodule PdfScreenplayParsex.ScreenplayClassifier do
  @moduledoc """
  Refactored screenplay classifier using modular architecture.

  This classifier converts PDF text items to TextElements with enhanced gap calculations
  and multi-pass element classification. It now uses specialized modules for different
  aspects of the classification process.
  """

  alias PdfScreenplayParsex.{
    ClassificationContext,
    DualDialogueClassifier,
    ElementClassifier,
    ElementGrouper,
    Errors,
    TextElement,
    TitlePageClassifier
  }

  @doc """
  Classifies a screenplay from binary data into TextElements with gap calculations and element classification.

  ## Parameters

    * `binary` - The PDF file as binary data
    * `gap_threshold` - Minimum gap size to create a new group (defaults to 10)

  ## Returns

  Returns `{:ok, classified_pages}` on success or `{:error, reason}` on failure.

  The classified_pages is a list of pages, each containing:
    * `:page_number` - The page number
    * `:groups` - A list of element groups with classifications
    * `:page_width` - The width of the page
    * `:page_height` - The height of the page
  """
  @spec classify_screenplay(binary(), pos_integer()) :: {:ok, list()} | {:error, Exception.t()}
  def classify_screenplay(binary, gap_threshold \\ 10) when is_binary(binary) do
    Errors.with_error_handling(fn ->
      execute_classification_pipeline(binary, gap_threshold)
    end, %{operation: "classify_screenplay", binary_size: byte_size(binary)})
  end

  @doc """
  Groups elements by gap threshold using the ElementGrouper module.

  ## Parameters

    * `pages_with_elements` - List of page maps with TextElement structs
    * `gap_threshold` - Minimum gap size to create a new group

  ## Returns

  Returns grouped pages ready for classification.
  """
  @spec group_elements_by_gap(list(), number()) :: list()
  def group_elements_by_gap(pages_with_elements, gap_threshold \\ 10) do
    ElementGrouper.group_elements_by_gap(pages_with_elements, gap_threshold)
  end

  @doc """
  Formats classified pages into a readable text format.

  Takes a list of classified pages (already grouped and classified) and returns
  a formatted string representation with element types and properties.

  ## Parameters
    * `classified_pages` - A list of page maps from classify_screenplay/1

  ## Returns
    A formatted string with all TextElements organized in groups with classifications

  ## Examples

      iex> {:ok, pages} = PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)
      iex> output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(pages)
      iex> File.write!("output.txt", output)
  """
  def dump_content(classified_pages) when is_list(classified_pages) do
    # Default to text-compact mode with blank lines between groups
    classified_pages
    |> Enum.flat_map(fn %{groups: groups} -> groups end)
    |> Enum.map(fn group ->
      group
      |> Enum.map(&format_text_element_compact/1)
      |> Enum.join("\n")
    end)
    |> Enum.join("\n\n")
  end

  @doc """
  Dumps content in detailed format with full page structure.
  """
  @spec dump_content_detailed(list()) :: String.t()
  def dump_content_detailed(classified_pages) when is_list(classified_pages) do
    header = """
    SCREENPLAY CLASSIFIER RESULTS
    =============================

    Total Pages: #{length(classified_pages)}

    """

    pages_content =
      classified_pages
      |> Enum.map_join("\n\n" <> String.duplicate("=", 50) <> "\n\n", &format_page_with_groups/1)

    header <> pages_content
  end

  # Private functions

  @spec execute_classification_pipeline(binary(), pos_integer()) :: list()
  defp execute_classification_pipeline(binary, gap_threshold) do
    binary
    |> parse_binary_data()
    |> convert_to_text_elements()
    |> filter_empty_elements()
    |> group_elements(gap_threshold)
    |> classify_all_pages()
    |> reclassify_title_page()
  end

  @spec parse_binary_data(binary()) :: map()
  defp parse_binary_data(binary) do
    case PdfScreenplayParsex.parse_binary(binary) do
      {:ok, result} -> result
      {:error, %Errors.ValidationError{} = error} -> raise error
      {:error, %Errors.PDFError{} = error} -> raise error
      {:error, reason} ->
        raise %Errors.PDFError{
          message: "Failed to parse PDF binary data",
          type: :parsing_failed,
          details: %{reason: reason}
        }
    end
  end

  @spec convert_to_text_elements(map()) :: list()
  defp convert_to_text_elements(result) do
    result.pages
    |> Enum.map(&ElementGrouper.convert_page_to_text_elements/1)
  end

  @spec filter_empty_elements(list()) :: list()
  defp filter_empty_elements(pages_with_elements) do
    pages_with_elements
    |> Enum.map(&ElementGrouper.filter_empty_text_elements/1)
  end

  @spec group_elements(list(), pos_integer()) :: list()
  defp group_elements(pages_with_filtered_elements, gap_threshold) do
    ElementGrouper.group_elements_by_gap(pages_with_filtered_elements, gap_threshold)
  end

  @spec classify_all_pages(list()) :: list()
  defp classify_all_pages(grouped_pages) do
    # Use reduce to carry character position, continuation info, and last element between pages
    {classified_pages, _final_char_position, _final_continuation, _final_last_element} =
      grouped_pages
      |> Enum.reduce({[], nil, nil, nil}, fn page, {acc_pages, established_char_x, continuing_char, last_element_from_prev_page} ->
        context = ClassificationContext.new(page, established_char_x)
                 |> ClassificationContext.set_continuing_character(continuing_char)
        
        classified_page = classify_single_page_with_dialogue_context(context, last_element_from_prev_page)

        # Extract character position from this page to carry forward
        new_char_x = ClassificationContext.extract_character_position_from_groups(classified_page) || established_char_x

        # Check for (MORE) continuation at end of page
        new_continuing_char = extract_continuing_character(classified_page)

        # Get the last element from this page to carry forward
        last_element_current_page = extract_last_element_from_page(classified_page)

        updated_page = ClassificationContext.to_page_map(classified_page)
        {acc_pages ++ [updated_page], new_char_x, new_continuing_char, last_element_current_page}
      end)

    classified_pages
  end

  @spec classify_single_page_with_dialogue_context(ClassificationContext.t(), map() | nil) :: ClassificationContext.t()
  defp classify_single_page_with_dialogue_context(context, last_element_from_prev_page) do
    context
    |> set_title_page_flag()
    |> perform_continuation_pass()
    |> perform_dual_dialogue_pre_pass()
    |> perform_first_pass()
    |> perform_second_pass()
    |> perform_third_pass_with_dialogue_context(last_element_from_prev_page)
    |> perform_consistency_pass()
    |> perform_dual_dialogue_pass()
  end

  @spec extract_last_element_from_page(ClassificationContext.t()) :: map() | nil
  defp extract_last_element_from_page(context) do
    # Get the last element from the last group on this page
    if length(context.groups) > 0 do
      last_group = List.last(context.groups)
      if length(last_group) > 0 do
        List.last(last_group)
      else
        nil
      end
    else
      nil
    end
  end

  @spec perform_third_pass_with_dialogue_context(ClassificationContext.t(), map() | nil) :: ClassificationContext.t()
  defp perform_third_pass_with_dialogue_context(context, last_element_from_prev_page) do
    # Process groups with cross-group dialogue continuation context
    {third_pass_groups, _final_last_element} =
      context.groups
      |> Enum.reduce({[], last_element_from_prev_page}, fn group, {processed_groups, last_element_from_prev} ->
        # Process current group with context from previous group
        processed_group =
          group
          |> Enum.with_index()
          |> Enum.reduce([], fn {element, index}, acc ->
            classified_element = 
              cond do
                # Check for cross-group dialogue continuation for first element
                index == 0 && last_element_from_prev && is_cross_group_dialogue_continuation?(element, last_element_from_prev) ->
                  Map.put(element, :type, :dialogue)
                
                # Check for consecutive dialogue continuation within the same group
                index > 0 && is_consecutive_dialogue_continuation?(element, acc) ->
                  Map.put(element, :type, :dialogue)
                
                # Normal third pass classification
                true ->
                  ElementClassifier.classify_element_third_pass(element, group)
              end
            
            acc ++ [classified_element]
          end)
        
        # Get the last element for the next group
        last_element = List.last(processed_group)
        
        {processed_groups ++ [processed_group], last_element}
      end)

    ClassificationContext.update_groups(context, third_pass_groups)
  end


  @spec set_title_page_flag(ClassificationContext.t()) :: ClassificationContext.t()
  defp set_title_page_flag(context) do
    # If char position exists, screenplay content already started
    is_title_page = context.established_char_x == nil &&
                   TitlePageClassifier.title_page?(ClassificationContext.to_page_map(context))

    ClassificationContext.set_title_page(context, is_title_page)
  end

  @spec perform_first_pass(ClassificationContext.t()) :: ClassificationContext.t()
  defp perform_first_pass(context) do
    screenplay_started = not context.is_title_page

    {classified_groups, scene_heading_positions, character_position} =
      context.groups
      |> Enum.reduce({[], [], context.established_char_x}, fn group, {acc_groups, scene_positions, char_position} ->
        classified_group = classify_group_first_pass(group, context, char_position, screenplay_started)

        # Collect X positions of scene headings
        new_scene_positions = extract_scene_heading_positions(classified_group)

        # Update character X position from this group
        new_char_position = extract_character_position_from_group(classified_group) || char_position

        {acc_groups ++ [classified_group], scene_positions ++ new_scene_positions, new_char_position}
      end)

    context
    |> ClassificationContext.update_groups(classified_groups)
    |> ClassificationContext.add_scene_heading_positions(scene_heading_positions)
    |> ClassificationContext.update_character_position(character_position)
  end

  @spec perform_second_pass(ClassificationContext.t()) :: ClassificationContext.t()
  defp perform_second_pass(context) do
    second_pass_groups =
      context.groups
      |> Enum.map(fn group ->
        group
        |> Enum.map(fn element ->
          ElementClassifier.classify_element_second_pass(element, group, context)
        end)
      end)

    ClassificationContext.update_groups(context, second_pass_groups)
  end

  @spec is_cross_group_dialogue_continuation?(map(), map()) :: boolean()
  defp is_cross_group_dialogue_continuation?(current_element, last_element_from_prev) do
    # Check if current element could be dialogue continuation from previous group
    last_element_is_dialogue = Map.get(last_element_from_prev, :type) == :dialogue
    last_element_is_character = Map.get(last_element_from_prev, :type) == :character
    last_element_is_parenthetical = Map.get(last_element_from_prev, :type) == :parenthetical
    is_unclassified = Map.get(current_element, :type) == nil
    has_dialogue_characteristics = not String.match?(current_element.text, ~r/^[A-Z\s]+$/) # Not all caps like scene headings
    small_gap = current_element.gap_to_prev == nil || current_element.gap_to_prev <= 2
    
    # For dialogue continuation: same x-position as previous dialogue
    dialogue_continuation = last_element_is_dialogue && 
                           abs(current_element.x - last_element_from_prev.x) <= 5 &&
                           is_unclassified && 
                           has_dialogue_characteristics && 
                           small_gap
    
    # For dialogue after character: positioned at typical dialogue x-position (160-195 range)
    dialogue_after_character = last_element_is_character &&
                              current_element.x >= 160 && 
                              current_element.x <= 195 &&
                              is_unclassified &&
                              has_dialogue_characteristics &&
                              small_gap
    
    # For dialogue after parenthetical: positioned at typical dialogue x-position (160-195 range)
    dialogue_after_parenthetical = last_element_is_parenthetical &&
                                  current_element.x >= 160 && 
                                  current_element.x <= 195 &&
                                  is_unclassified &&
                                  has_dialogue_characteristics &&
                                  small_gap
    
    result = dialogue_continuation || dialogue_after_character || dialogue_after_parenthetical
    
    result
  end

  @spec is_consecutive_dialogue_continuation?(map(), list()) :: boolean()
  defp is_consecutive_dialogue_continuation?(current_element, processed_elements) do
    # Check if current element continues dialogue from immediately previous element in the same group
    if length(processed_elements) > 0 do
      previous_element = List.last(processed_elements)
      previous_is_dialogue = Map.get(previous_element, :type) == :dialogue
      same_x_position = abs(current_element.x - previous_element.x) <= 5
      is_unclassified = Map.get(current_element, :type) == nil
      has_dialogue_characteristics = not String.match?(current_element.text, ~r/^[A-Z\s]+$/)
      small_gap = current_element.gap_to_prev == nil || current_element.gap_to_prev <= 2
      
      previous_is_dialogue && same_x_position && is_unclassified && has_dialogue_characteristics && small_gap
    else
      false
    end
  end

  @spec perform_continuation_pass(ClassificationContext.t()) :: ClassificationContext.t()
  defp perform_continuation_pass(context) do
    if context.continuing_character do
      # Handle page continuation - insert continuing character at start of first group
      updated_groups = handle_character_continuation(context.groups, context.continuing_character)
      ClassificationContext.update_groups(context, updated_groups)
    else
      context
    end
  end

  @spec perform_dual_dialogue_pre_pass(ClassificationContext.t()) :: ClassificationContext.t()
  defp perform_dual_dialogue_pre_pass(context) do
    # Pre-process groups to identify potential dual dialogue
    pre_processed_groups = 
      context.groups
      |> Enum.map(fn group ->
        if dual_dialogue_pre_detection?(group) do
          # Mark elements as potential dual dialogue
          mark_potential_dual_dialogue_elements(group)
        else
          group
        end
      end)
    
    ClassificationContext.update_groups(context, pre_processed_groups)
  end

  @spec perform_consistency_pass(ClassificationContext.t()) :: ClassificationContext.t()
  defp perform_consistency_pass(context) do
    # Ensure consistent classification within groups
    consistent_groups = 
      context.groups
      |> Enum.map(&ensure_group_consistency/1)
    
    ClassificationContext.update_groups(context, consistent_groups)
  end

  @spec perform_dual_dialogue_pass(ClassificationContext.t()) :: ClassificationContext.t()
  defp perform_dual_dialogue_pass(context) do
    final_groups = DualDialogueClassifier.mark_dual_dialogue(context.groups)
    ClassificationContext.update_groups(context, final_groups)
  end

  @spec classify_group_first_pass(list(), ClassificationContext.t(), number() | nil, boolean()) :: list()
  defp classify_group_first_pass(group, context, _established_char_x, screenplay_started) do
    group
    |> Enum.with_index()
    |> Enum.map(fn {element, index} ->
      ElementClassifier.classify_element_first_pass(element, index, group, context, screenplay_started)
    end)
  end

  @spec extract_scene_heading_positions(list()) :: list(number())
  defp extract_scene_heading_positions(group) do
    group
    |> Enum.filter(fn elem -> Map.get(elem, :type) == :scene_heading end)
    |> Enum.map(fn elem -> elem.x end)
  end

  @spec extract_character_position_from_group(list()) :: number() | nil
  defp extract_character_position_from_group(group) do
    group
    |> Enum.find_value(fn elem ->
      if Map.get(elem, :type) == :character do
        elem.x
      else
        nil
      end
    end)
  end

  @spec reclassify_title_page(list()) :: list()
  defp reclassify_title_page(pages) do
    TitlePageClassifier.reclassify_title_elements(pages)
  end

  @spec dual_dialogue_pre_detection?(list()) :: boolean()
  defp dual_dialogue_pre_detection?(group) do
    # Look for potential dual dialogue patterns
    potential_characters = 
      group
      |> Enum.filter(fn elem ->
        # Look for elements that could be character names
        text = String.trim(elem.text || "")
        PdfScreenplayParsex.TextUtils.valid_character_name?(text) && 
          elem.x >= 180 && elem.x <= 400  # Extended character range
      end)

    # Check if we have 2 potential characters with significant separation
    if length(potential_characters) == 2 do
      [char1, char2] = potential_characters
      x_separation = abs(char1.x - char2.x)
      
      # Significant horizontal separation suggests dual dialogue
      x_separation > 150 && 
        length(group) > 2 &&  # Must have dialogue content
        has_dialogue_like_content?(group, potential_characters)
    else
      false
    end
  end

  @spec has_dialogue_like_content?(list(), list()) :: boolean()
  defp has_dialogue_like_content?(group, potential_characters) do
    # Remove potential characters and check remaining elements
    character_texts = MapSet.new(potential_characters, & &1.text)
    remaining_elements = 
      group
      |> Enum.reject(fn elem -> MapSet.member?(character_texts, elem.text) end)
    
    # Check if remaining elements look like dialogue
    Enum.any?(remaining_elements, fn elem ->
      text = String.trim(elem.text || "")
      # Dialogue characteristics: mixed case, reasonable length
      text != String.upcase(text) && 
        String.length(text) > 3 && 
        String.length(text) < 200
    end)
  end

  @spec mark_potential_dual_dialogue_elements(list()) :: list()
  defp mark_potential_dual_dialogue_elements(group) do
    group
    |> Enum.map(fn elem ->
      # Mark potential characters in dual dialogue groups
      text = String.trim(elem.text || "")
      if PdfScreenplayParsex.TextUtils.valid_character_name?(text) && elem.x >= 180 && elem.x <= 400 do
        Map.put(elem, :potential_dual_dialogue_character, true)
      else
        Map.put(elem, :potential_dual_dialogue, true)
      end
    end)
  end

  @spec extract_continuing_character(ClassificationContext.t()) :: String.t() | nil
  defp extract_continuing_character(context) do
    # Look for (MORE) markers at the end of the page
    last_group = List.last(context.groups)
    
    if last_group do
      # Check if last group ends with (MORE)
      more_element = Enum.find(last_group, fn elem ->
        text = String.trim(elem.text || "")
        text == "(MORE)"
      end)
      
      if more_element do
        # Find the character that has (MORE) - should be in previous groups
        find_character_before_more(context.groups)
      else
        nil
      end
    else
      nil
    end
  end

  @spec find_character_before_more(list()) :: String.t() | nil
  defp find_character_before_more(groups) do
    # Search backwards through groups to find the most recent character
    groups
    |> Enum.reverse()
    |> Enum.find_value(fn group ->
      # Look for character elements in this group
      Enum.find_value(group, fn elem ->
        if Map.get(elem, :type) == :character do
          # Extract base character name (remove CONT'D if present)
          text = String.trim(elem.text || "")
          extract_base_character_name(text)
        else
          nil
        end
      end)
    end)
  end

  @spec extract_base_character_name(String.t()) :: String.t()
  defp extract_base_character_name(character_text) do
    # Remove (CONT'D) and similar continuations to get base name
    character_text
    |> String.replace(~r/\s*\(CONT'D\).*$/, "")
    |> String.replace(~r/\s*\(CONT\).*$/, "")
    |> String.trim()
  end

  @spec handle_character_continuation(list(), String.t()) :: list()
  defp handle_character_continuation([], _continuing_character), do: []
  
  defp handle_character_continuation([first_group | rest_groups], continuing_character) do
    # Check if first group starts with orphaned dialogue
    if orphaned_dialogue_group?(first_group) do
      # Create a character element for the continuation
      character_element = create_continuing_character_element(continuing_character, first_group)
      updated_first_group = [character_element | first_group]
      [updated_first_group | rest_groups]
    else
      [first_group | rest_groups]
    end
  end

  @spec orphaned_dialogue_group?(list()) :: boolean()
  defp orphaned_dialogue_group?(group) do
    # Check if this group starts with unclassified elements that look like dialogue
    case List.first(group) do
      nil -> false
      first_element ->
        # Group starts with dialogue if:
        # 1. First element is at dialogue position (x around 180)
        # 2. Text is mixed case (not all caps)
        # 3. No character element in the group
        at_dialogue_position?(first_element) &&
          mixed_case_text?(first_element.text) &&
          not has_character_element?(group)
    end
  end

  @spec at_dialogue_position?(map()) :: boolean()
  defp at_dialogue_position?(element) do
    # Dialogue is typically at x=180 (±20 points tolerance)
    element.x >= 160 && element.x <= 200
  end

  @spec mixed_case_text?(String.t()) :: boolean()
  defp mixed_case_text?(text) do
    trimmed = String.trim(text)
    trimmed != String.upcase(trimmed) && String.length(trimmed) > 0
  end

  @spec has_character_element?(list()) :: boolean()
  defp has_character_element?(group) do
    Enum.any?(group, fn elem -> Map.get(elem, :type) == :character end)
  end

  @spec create_continuing_character_element(String.t(), list()) :: PdfScreenplayParsex.TextElement.t()
  defp create_continuing_character_element(character_name, first_group) do
    # Create a character element based on the first dialogue element
    first_element = List.first(first_group)
    
    %PdfScreenplayParsex.TextElement{
      text: "#{character_name} (CONT'D)",
      x: 252.0,  # Standard character position
      y: first_element.y - 12,  # Position slightly above first dialogue
      width: String.length(character_name) * 6,  # Approximate width
      height: 12,
      font_size: 12,
      font_name: "Arial",
      gap_to_prev: nil,
      gap_to_next: 0,
      centered: false,
      type: :character
    }
  end

  @spec ensure_group_consistency(list()) :: list()
  defp ensure_group_consistency(group) do
    # Check if group has a character or is a dialogue group
    has_character = Enum.any?(group, fn elem -> Map.get(elem, :type) == :character end)
    has_dialogue = Enum.any?(group, fn elem -> Map.get(elem, :type) == :dialogue end)
    
    if has_character || has_dialogue do
      # Classify unclassified dialogue-like elements in character/dialogue groups
      Enum.map(group, fn elem ->
        if should_be_dialogue?(elem, group) do
          Map.put(elem, :type, :dialogue)
        else
          elem
        end
      end)
    else
      group
    end
  end

  @spec should_be_dialogue?(map(), list()) :: boolean()
  defp should_be_dialogue?(elem, group) do
    # Element should be dialogue if:
    # 1. Not already classified (or classified as something we can override)
    # 2. At dialogue position (x ~180)
    # 3. Mixed case text (not all caps)
    # 4. In a group with character or existing dialogue
    # 5. Not a parenthetical
    
    current_type = Map.get(elem, :type)
    can_reclassify = current_type == nil || current_type == :unclassified
    
    if can_reclassify do
      text = String.trim(elem.text || "")
      at_dialogue_pos = elem.x >= 160 && elem.x <= 200
      is_mixed_case = text != String.upcase(text) && String.length(text) > 0
      not_parenthetical = not (String.starts_with?(text, "(") && String.ends_with?(text, ")"))
      
      has_character_or_dialogue = 
        Enum.any?(group, fn g_elem -> 
          type = Map.get(g_elem, :type)
          type == :character || type == :dialogue
        end)
      
      at_dialogue_pos && is_mixed_case && not_parenthetical && has_character_or_dialogue
    else
      false
    end
  end

  # Format a single page with its grouped elements
  defp format_page_with_groups(%{page_number: page_num, groups: groups}) do
    page_header = "PAGE #{page_num}\n" <> String.duplicate("-", 20) <> "\n"

    groups_content =
      groups
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {group, group_num} ->
        group_header = "GROUP #{group_num}:\n"

        group_elements =
          group
          |> Enum.map_join("\n", &format_text_element/1)

        group_header <> group_elements
      end)

    page_header <> groups_content
  end

  # Format a single TextElement with its properties (without gap-based blank lines)
  defp format_text_element(%TextElement{} = element) do
    gap_prev = if element.gap_to_prev, do: "#{element.gap_to_prev}", else: "nil"
    gap_next = if element.gap_to_next, do: "#{element.gap_to_next}", else: "nil"
    centered = if element.centered, do: "true", else: "false"
    type = Map.get(element, :type, :unclassified)
    is_dual = if Map.get(element, :is_dual_dialogue), do: " (DUAL)", else: ""

    "[#{type}#{is_dual}] #{element.text} | x: #{element.x} | y: #{element.y} | gap_to_prev: #{gap_prev} | gap_to_next: #{gap_next} | centered: #{centered}"
  end

  # Format a single TextElement in compact mode showing only [type] text
  defp format_text_element_compact(%TextElement{} = element) do
    type = Map.get(element, :type, :unclassified)
    is_dual = if Map.get(element, :is_dual_dialogue), do: " (DUAL)", else: ""
    "[#{type}#{is_dual}] #{element.text}"
  end
end
