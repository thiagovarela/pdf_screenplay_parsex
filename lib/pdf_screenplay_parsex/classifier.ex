defmodule PdfScreenplayParsex.Classifier do
  @moduledoc """
  Clean, focused classifier for screenplay elements.

  V2 implementation with simplified pipeline focusing on:
  - Title classification
  - Scene heading classification
  - Character classification
  - Action classification
  - Dialogue classification
  - Parenthetical classification
  - Continuation classification
  - Subheading classification
  - Transition classification
  - Page number classification
  - Scene number classification
  - Second pass: Dual dialogue detection and reclassification
  """

  alias PdfScreenplayParsex.{TextElement, Grouper, ElementType}

  defstruct [
    :page_width,
    :page_height,
    :page_number,
    :established_char_x,
    :scene_heading_x_position,
    :character_x_position,
    :is_title_page,
    :continuing_character,
    :groups
  ]

  @doc """
  Main classification pipeline. Takes parsed binary data and returns classified pages.

  ## Pipeline:
  1. Receives result from parse_binary_data
  2. Builds TextElements using Grouper
  3. Groups elements by gaps
  4. Classifies elements (first pass only)
  5. Returns structured pages

  ## Parameters
    * `parse_result` - Result from PdfScreenplayParsex.parse_binary/1

  ## Returns
    List of page maps with classified element groups
  """
  @spec classify_screenplay(map()) :: {:ok, list(map())} | {:error, term()}
  def classify_screenplay(%{pages: pages} = _parse_result) do
    try do
      # First, build all text elements and groups to analyze screenplay structure
      all_pages_with_groups =
        pages
        |> Enum.with_index()
        |> Enum.map(fn {page, index} ->
          # Step 1: Build TextElements with gap calculations
          text_elements = Grouper.build_text_elements(Map.get(page, "text_items", []), Map.get(page, "width", 612))

          # Step 2: Group elements by gaps
          element_groups = Grouper.group_by_gap?(text_elements)

          {index, element_groups}
        end)

      # Find the screenplay boundary across all pages (looking at text patterns, not classifications)
      screenplay_boundary = find_screenplay_boundary(all_pages_with_groups)

      # Initialize global context that persists across all pages
      initial_global_context = %{
        scene_heading_x_position: nil,
        character_x_position: nil,
        dialogue_x_position: nil,
        is_title_page: nil,
        first_scene_heading_y: nil,
        scene_heading_found: false,
        screenplay_boundary: screenplay_boundary
      }

      {classified_pages, _final_context} =
        all_pages_with_groups
        |> Enum.reduce({[], initial_global_context}, fn {page_index, element_groups},
                                                        {acc_pages, global_context} ->
          original_page = Enum.at(pages, page_index)
          {processed_page, updated_context} = process_page_with_groups(
            original_page, element_groups, page_index, global_context
          )
          final_page = Map.put(processed_page, :page_number, page_index)
          {[final_page | acc_pages], updated_context}
        end)

      {:ok, Enum.reverse(classified_pages)}
    rescue
      error -> {:error, error}
    end
  end

  def classify_screenplay(invalid_input) do
    {:error, "Expected map with :pages key, got: #{inspect(invalid_input)}"}
  end

  # Process a single page with pre-built groups
  @spec process_page_with_groups(map(), list(list(TextElement.t())), integer(), map()) :: {map(), map()}
  defp process_page_with_groups(page, element_groups, page_index, global_context) do
    page_width = Map.get(page, "width", 612)

    # Step 3: Merge global context with page-specific context
    page_context =
      Map.merge(global_context, %{
        page_width: page_width,
        page_height: Map.get(page, "height", 792),
        page_number: page_index
      })

    # Step 4: Classify elements in each group with context tracking
    {classified_groups, final_context} =
      element_groups
      |> Enum.with_index()
      |> Enum.reduce({[], page_context}, fn {group, group_index}, {acc_groups, context} ->
        {classified_group, updated_context} = classify_group_with_context(
          group, group_index, page_index, context
        )
        {[classified_group | acc_groups], updated_context}
      end)

    classified_groups =
      classified_groups
      |> Enum.reverse()
      |> Enum.reject(&Enum.empty?/1)

    # Step 5: Second pass - detect and reclassify dual dialogue and subheadings
    # Add screenplay_started flag based on page/group position
    screenplay_started = screenplay_started?(global_context, page_index, 0, 0)
    context_with_screenplay_started = Map.put(final_context, :screenplay_started, screenplay_started)
    second_pass_groups = second_pass_classification(classified_groups, context_with_screenplay_started)

    # Step 6: Final pass - classify any remaining unclassified elements as action
    final_classified_groups = final_pass_classification(second_pass_groups, context_with_screenplay_started)

    page_result = %{
      groups: final_classified_groups,
      page_width: page_width,
      page_height: Map.get(page, "height", 792)
    }

    # Return both the page result and the updated global context
    updated_global_context =
      Map.take(final_context, [
        :scene_heading_x_position,
        :character_x_position,
        :dialogue_x_position,
        :is_title_page,
        :scene_heading_found,
        :screenplay_boundary
      ])

    {page_result, updated_global_context}
  end

  # Classify all elements in a group with context tracking
  @spec classify_group_with_context(list(TextElement.t()), integer(), integer(), map()) ::
          {list(TextElement.t()), map()}
  defp classify_group_with_context(group, group_index, page_index, context) when is_list(group) do
    {classified_elements, updated_context} =
      group
      |> Enum.with_index()
      |> Enum.reduce({[], context}, fn {element, element_index}, {acc_elements, ctx} ->
        {classified_element, updated_ctx} =
          classify_element_with_context(element, element_index, group, group_index, page_index, ctx)

        {[classified_element | acc_elements], updated_ctx}
      end)

    {Enum.reverse(classified_elements), updated_context}
  end

  # Classify a single element with context tracking
  @spec classify_element_with_context(TextElement.t(), integer(), list(TextElement.t()), integer(), integer(), map()) ::
          {TextElement.t(), map()}
  defp classify_element_with_context(element, element_index, group, group_index, page_index, context) do
    # Check if screenplay has started at this position
    screenplay_started = screenplay_started?(context, page_index, group_index, element_index)
    context_with_screenplay_flag = Map.put(context, :screenplay_started, screenplay_started)
    cond do
      # Title: centered text on early pages
      ElementType.title?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :title}, context}

      # Author marker: "Written", "by", author names on title page
      ElementType.author_marker?(element, element_index, group, context_with_screenplay_flag) ->
        updated_context = Map.put(context, :recent_author_marker, true)
        {%{element | type: :author_marker}, updated_context}

      # Author: actual author names following author markers
      ElementType.author?(element, element_index, group, context_with_screenplay_flag) ->
        # Clear the recent_author_marker flag after using it
        updated_context = Map.put(context, :recent_author_marker, false)
        {%{element | type: :author}, updated_context}

      # Source credits: "Story by", "Original screenplay by", etc.
      ElementType.source?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :source}, context}

      # Source marker: "Based on the novel", "by", source references on title page
      ElementType.source_marker?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :source_marker}, context}

      # Source names: draft info, dates, version numbers on title page
      ElementType.source_names?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :source_names}, context}

      # Page number: number patterns at top/bottom margins (check before notes)
      ElementType.page_number?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :page_number}, context}

      # Notes: production company info, copyright, contact info
      ElementType.notes?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :notes}, context}

      # Scene heading: first element, matches scene heading pattern
      ElementType.scene_heading?(element, element_index, group, context_with_screenplay_flag) ->
        updated_context = update_scene_heading_context(element, context)
        {%{element | type: :scene_heading}, updated_context}

      # Character: matches character patterns and positioning
      ElementType.character?(element, element_index, group, context_with_screenplay_flag) ->
        updated_context = update_character_context(element, context)
        {%{element | type: :character}, updated_context}

      # Action: text at scene heading position that's not transitions or scene headings
      ElementType.action?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :action}, context}

      # Parenthetical: wrapped in parentheses, preceded by character, at dialogue position
      # Check this BEFORE dialogue since parentheticals are more specific
      ElementType.parenthetical?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :parenthetical}, context}

      # Dialogue: text positioned between scene heading and character x positions
      ElementType.dialogue?(element, element_index, group, context_with_screenplay_flag) ->
        updated_context = update_dialogue_context(element, context)
        {%{element | type: :dialogue}, updated_context}

      # Continuation: markers like (MORE), (CONT'D), (CONTINUED)
      ElementType.continuation?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :continuation}, context}

      # Subheading: all caps, short, at scene heading or left position
      ElementType.subheading?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :subheading}, context}

      # Transition: matches transition patterns and positioning
      ElementType.transition?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :transition}, context}

      # Scene number: number patterns at left/right margins (check before page numbers)
      ElementType.scene_number?(element, element_index, group, context_with_screenplay_flag) ->
        {%{element | type: :scene_number}, context}

      # Default: keep unclassified for now (will be handled in final pass)
      true ->
        {element, context}
    end
  end

  # Update context when a scene heading is found
  @spec update_scene_heading_context(TextElement.t(), map()) :: map()
  defp update_scene_heading_context(%TextElement{x: x, y: y}, context) do
    updated_context =
      case Map.get(context, :scene_heading_x_position) do
        nil -> Map.put(context, :scene_heading_x_position, x)
        # Keep existing position
        _ -> context
      end

    # Mark that we've found a scene heading
    updated_context = Map.put(updated_context, :scene_heading_found, true)

    # Track the y-coordinate of the first scene heading globally
    case Map.get(updated_context, :first_scene_heading_y) do
      nil -> Map.put(updated_context, :first_scene_heading_y, y)
      # Keep existing first scene heading y
      _ -> updated_context
    end
  end

  # Update context when a character is found
  @spec update_character_context(TextElement.t(), map()) :: map()
  defp update_character_context(%TextElement{x: x}, context) do
    case Map.get(context, :character_x_position) do
      nil -> Map.put(context, :character_x_position, x)
      # Keep existing position
      _ -> context
    end
  end

  # Update context when dialogue is found
  @spec update_dialogue_context(TextElement.t(), map()) :: map()
  defp update_dialogue_context(%TextElement{x: x}, context) do
    case Map.get(context, :dialogue_x_position) do
      nil -> Map.put(context, :dialogue_x_position, x)
      # Keep existing position
      _ -> context
    end
  end

  # Second pass: detect and reclassify dual dialogue, subheadings, and titles
  @spec second_pass_classification(list(list(TextElement.t())), map()) ::
          list(list(TextElement.t()))
  defp second_pass_classification(groups, context) do
    groups
    |> Enum.map(&process_group_for_titles(&1, context))
    |> Enum.map(&process_group_for_dual_dialogue(&1, context))
    |> Enum.map(&process_group_for_subheadings(&1, context))
  end

  # Process a single group to retroactively identify titles based on author markers
  @spec process_group_for_titles(list(TextElement.t()), map()) :: list(TextElement.t())
  defp process_group_for_titles(group, context) do
    # Only process on title page (page 0)
    if Map.get(context, :page_number, 0) == 0 do
      # Find author markers in this group
      author_marker_indices =
        group
        |> Enum.with_index()
        |> Enum.filter(fn {elem, _idx} ->
          elem.type == :author_marker ||
          (elem.type == :title && String.downcase(String.trim(elem.text)) == "screenplay")
        end)
        |> Enum.map(fn {_elem, idx} -> idx end)

      if length(author_marker_indices) > 0 do
        # If we found author markers, look back for potential titles
        first_marker_index = Enum.min(author_marker_indices)

        group
        |> Enum.with_index()
        |> Enum.map(fn {elem, idx} ->
          cond do
            # Before the first author marker, centered, capitalized text should be title
            idx < first_marker_index &&
            (elem.type == :character || is_nil(elem.type) ||
             (elem.type == :title && String.downcase(String.trim(elem.text)) == "screenplay")) &&
            elem.centered &&
            (PdfScreenplayParsex.TextUtils.all_caps_text?(elem.text) ||
             title_case?(elem.text)) &&
            String.downcase(String.trim(elem.text)) != "screenplay" ->
              %{elem | type: :title}

            # "Screenplay" by itself should be author_marker, not title
            elem.type == :title && String.downcase(String.trim(elem.text)) == "screenplay" ->
              %{elem | type: :author_marker}

            true ->
              elem
          end
        end)
      else
        group
      end
    else
      group
    end
  end

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

  # Process a single group to detect dual dialogue patterns
  @spec process_group_for_dual_dialogue(list(TextElement.t()), map()) :: list(TextElement.t())
  defp process_group_for_dual_dialogue(group, context) do
    # Only process dual dialogue if screenplay has started
    screenplay_started = Map.get(context, :screenplay_started, false)

    if screenplay_started do
      # Look for dual dialogue pattern:
      # 1. Two potential character names at different x positions (left ~180-200, right ~380-420)
      # 2. Following elements at corresponding dialogue positions (left ~108, right ~333)

      potential_left_chars =
        Enum.with_index(group)
        |> Enum.filter(fn {elem, _idx} ->
          is_nil(elem.type) &&
            elem.x >= 150 && elem.x <= 220 &&
            PdfScreenplayParsex.TextUtils.character?(elem.text)
        end)

      potential_right_chars =
        Enum.with_index(group)
        |> Enum.filter(fn {elem, _idx} ->
          is_nil(elem.type) &&
            elem.x >= 350 && elem.x <= 450 &&
            PdfScreenplayParsex.TextUtils.character?(elem.text)
        end)

      if length(potential_left_chars) > 0 && length(potential_right_chars) > 0 do
        reclassify_dual_dialogue_group(group, potential_left_chars, potential_right_chars)
      else
        group
      end
    else
      # Don't process dual dialogue if no scene heading found yet
      group
    end
  end

  # Reclassify elements in a dual dialogue group
  @spec reclassify_dual_dialogue_group(
          list(TextElement.t()),
          list({TextElement.t(), integer()}),
          list({TextElement.t(), integer()})
        ) :: list(TextElement.t())
  defp reclassify_dual_dialogue_group(group, left_chars, right_chars) do
    group
    |> Enum.with_index()
    |> Enum.map(fn {elem, idx} ->
      cond do
        # Left character
        Enum.any?(left_chars, fn {_char_elem, char_idx} -> char_idx == idx end) ->
          %{elem | type: :character}

        # Right character
        Enum.any?(right_chars, fn {_char_elem, char_idx} -> char_idx == idx end) ->
          %{elem | type: :character}

        # Left dialogue (unclassified or action at left dialogue position)
        (is_nil(elem.type) || elem.type == :action) && elem.x >= 80 && elem.x <= 140 ->
          %{elem | type: :dialogue}

        # Right dialogue (unclassified at right dialogue position)
        is_nil(elem.type) && elem.x >= 300 && elem.x <= 370 ->
          %{elem | type: :dialogue}

        # Keep existing classification
        true ->
          elem
      end
    end)
  end

  # Process a single group to detect subheadings in second pass
  @spec process_group_for_subheadings(list(TextElement.t()), map()) :: list(TextElement.t())
  defp process_group_for_subheadings(group, context) do
    # Check each unclassified element for subheading patterns
    group
    |> Enum.map(fn elem ->
      if is_nil(elem.type) && PdfScreenplayParsex.TextUtils.subheading?(elem.text) &&
           subheading_position_check?(elem, context) do
        %{elem | type: :subheading}
      else
        elem
      end
    end)
  end

  # Check subheading position (similar to ElementType but without scene_heading_found requirement)
  defp subheading_position_check?(%TextElement{x: x}, context) do
    case Map.get(context, :scene_heading_x_position) do
      nil ->
        # No established scene heading position, use default left margin
        x <= 110

      established_x ->
        # At scene heading position OR left-aligned (more lenient tolerance)
        abs(x - established_x) <= 5 || x <= 110
    end
  end

  # Final pass: classify any remaining unclassified elements as action (respecting scene heading requirement)
  @spec final_pass_classification(list(list(TextElement.t())), map()) ::
          list(list(TextElement.t()))
  defp final_pass_classification(groups, context) do
    scene_heading_found = Map.get(context, :scene_heading_found, false)

    groups
    |> Enum.map(&classify_remaining_as_action(&1, scene_heading_found))
  end

  # Classify any unclassified elements in a group as action (only after scene heading found)
  @spec classify_remaining_as_action(list(TextElement.t()), boolean()) :: list(TextElement.t())
  defp classify_remaining_as_action(group, scene_heading_found) do
    group
    |> Enum.map(fn elem ->
      if is_nil(elem.type) && scene_heading_found do
        %{elem | type: :action}
      else
        elem
      end
    end)
  end

  # Helper functions for title page detection and scene boundary management


  # Finds the boundary between title page content and screenplay content.
  # Returns the group index of the first scene heading or transition found,
  # or nil if no screenplay content is found.
  @spec find_screenplay_boundary(list({integer(), list(list(TextElement.t()))})) :: {integer(), integer(), integer()} | nil
  defp find_screenplay_boundary(all_pages_with_groups) when is_list(all_pages_with_groups) do
    all_pages_with_groups
    |> Enum.reduce_while(nil, fn {page_index, page_groups}, _acc ->
      case find_boundary_in_page(page_groups, page_index) do
        nil -> {:cont, nil}
        boundary -> {:halt, boundary}
      end
    end)
  end

  @spec find_boundary_in_page(list(list(TextElement.t())), integer()) :: {integer(), integer(), integer()} | nil
  defp find_boundary_in_page(page_groups, page_index) when is_list(page_groups) do
    page_groups
    |> Enum.with_index()
    |> Enum.find_value(fn {group, group_index} ->
      case find_boundary_in_group(group) do
        nil -> nil
        element_index -> {page_index, group_index, element_index}
      end
    end)
  end

  @spec find_boundary_in_group(list(TextElement.t())) :: integer() | nil
  defp find_boundary_in_group(group) when is_list(group) do
    group
    |> Enum.with_index()
    |> Enum.find_value(fn {element, element_index} ->
      if screenplay_boundary_element?(element) do
        element_index
      else
        nil
      end
    end)
  end

  @spec screenplay_boundary_element?(TextElement.t()) :: boolean()
  defp screenplay_boundary_element?(%TextElement{type: type, text: text}) do
    # Check both classification (if already set) and text patterns
    cond do
      type in [:scene_heading, :transition] -> true
      is_nil(type) -> screenplay_text_pattern?(text)  # Check text patterns for unclassified elements
      true -> false
    end
  end

  @spec screenplay_text_pattern?(String.t()) :: boolean()
  defp screenplay_text_pattern?(text) when is_binary(text) do
    clean_text = String.trim(text)
    String.starts_with?(clean_text, ["INT.", "EXT.", "FADE IN", "FADE OUT"]) ||
      PdfScreenplayParsex.TextUtils.scene_heading?(clean_text) ||
      PdfScreenplayParsex.TextUtils.transition?(clean_text)
  end

  defp screenplay_text_pattern?(_), do: false

  # Checks if screenplay content has started based on the current context and element position.
  # This replaces the simple Y-position check with a more comprehensive approach
  # that considers page boundaries and actual screenplay structure.
  @spec screenplay_started?(map(), integer(), integer(), integer()) :: boolean()
  defp screenplay_started?(context, current_page, current_group, current_element) do
    case Map.get(context, :screenplay_boundary) do
      nil -> false  # No screenplay boundary found yet
      {boundary_page, boundary_group, boundary_element} ->
        cond do
          current_page > boundary_page -> true
          current_page == boundary_page && current_group > boundary_group -> true
          current_page == boundary_page && current_group == boundary_group && current_element >= boundary_element -> true
          true -> false
        end
    end
  end
end
