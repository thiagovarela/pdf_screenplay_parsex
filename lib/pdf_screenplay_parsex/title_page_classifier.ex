defmodule PdfScreenplayParsex.TitlePageClassifier do
  @moduledoc """
  Handles classification of title page elements.

  This module is responsible for identifying and classifying elements specific
  to screenplay title pages, including titles, author information, source material,
  contact information, dates, and copyright notices.
  """

  alias PdfScreenplayParsex.TextUtils

  @doc """
  Reclassifies title elements on the first page after initial screenplay classification.

  This function finds the boundary between title page content and screenplay content,
  then reclassifies everything before that boundary as title page elements.

  ## Parameters

    * `pages` - List of classified pages

  ## Returns

  Returns updated pages list with title elements properly classified.
  """
  @spec reclassify_title_elements(list()) :: list()
  def reclassify_title_elements(pages) do
    case pages do
      [first_page | rest] ->
        # Find the first scene heading or transition in the groups
        title_boundary_index = find_title_boundary(first_page.groups)

        cond do
          title_boundary_index && title_boundary_index > 0 ->
            # Only reclassify if there are groups before the screenplay content
            # Reclassify elements before the boundary as title elements
            reclassified_groups = reclassify_first_page_groups(first_page.groups, title_boundary_index)
            updated_first_page = %{first_page | groups: reclassified_groups}
            [updated_first_page | rest]

          title_boundary_index == 0 ->
            # Screenplay content starts immediately, no title page elements to reclassify
            pages

          true ->
          # No screenplay elements found, treat entire first page as title page
          reclassified_groups = reclassify_all_as_title(first_page.groups)
          updated_first_page = %{first_page | groups: reclassified_groups}
          [updated_first_page | rest]
        end

      [] ->
        []
    end
  end

  @doc """
  Detects if a page is likely a title page based on content patterns.

  ## Parameters

    * `page` - Page map with groups

  ## Returns

  Returns `true` if the page appears to be a title page, `false` otherwise.
  """
  @spec title_page?(map()) :: boolean()
  def title_page?(page) do
    # Title pages typically contain centered text and lack scene headings or INT/EXT patterns
    # Check if page contains scene headings or screenplay content patterns
    has_scene_heading = Enum.any?(page.groups, fn group ->
      Enum.any?(group, fn element ->
        text = String.trim(element.text)
        String.starts_with?(text, ["INT.", "EXT.", "FADE IN", "FADE OUT"])
      end)
    end)

    # If it has scene headings, it's not a title page
    not has_scene_heading
  end

  # Private functions

  @spec find_title_boundary(list()) :: integer() | nil
  defp find_title_boundary(groups) do
    groups
    |> Enum.with_index()
    |> Enum.find(fn {group, _index} ->
      Enum.any?(group, fn element ->
        Map.get(element, :type) in [:scene_heading, :transition]
      end)
    end)
    |> case do
      {_group, index} -> index
      nil -> nil
    end
  end

  @spec reclassify_first_page_groups(list(), integer()) :: list()
  defp reclassify_first_page_groups(groups, boundary_index) do
    {title_groups, screenplay_groups} = Enum.split(groups, boundary_index)

    # Reclassify title groups
    reclassified_title_groups =
      title_groups
      |> Enum.with_index()
      |> Enum.map(fn {group, index} ->
        reclassify_title_group(group, index, title_groups)
      end)

    # Keep screenplay groups as-is
    reclassified_title_groups ++ screenplay_groups
  end

  @spec reclassify_all_as_title(list()) :: list()
  defp reclassify_all_as_title(groups) do
    groups
    |> Enum.with_index()
    |> Enum.map(fn {group, index} ->
      reclassify_title_group(group, index, groups)
    end)
  end

  @spec reclassify_title_group(list(), integer(), list()) :: list()
  defp reclassify_title_group(group, index, all_title_groups) do
    # Check if any element in the group is already classified as transition or scene_heading
    # If so, don't reclassify - this preserves screenplay elements that appear early
    has_screenplay_element = Enum.any?(group, fn elem ->
      Map.get(elem, :type) in [:transition, :scene_heading]
    end)

    if has_screenplay_element do
      # Keep the group as-is, don't reclassify screenplay elements
      group
    else
      cond do
        # First group: likely the title
        index == 0 && all_centered?(group) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :title) end)

        # Special case: "By [author]" immediately after title (common pattern)
        # This should be treated as author information, not source
        index == 1 && all_centered?(group) && length(group) == 1 && 
        String.match?(List.first(group).text, ~r/^by\s+.+/i) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :author_names) end)

        # Author marker groups (can appear anywhere)
        all_centered?(group) && TextUtils.has_author_marker?(group) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :author_marker) end)

        # Draft date (even if centered) - check this VERY early
        all_centered?(group) && has_date_content?(group) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :draft_date) end)

        # Notes (quotes, even if centered)
        all_centered?(group) && has_quote_content?(group) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :notes) end)

        # Notes (anything after draft_date) - must come before ALL other checks
        all_centered?(group) && has_draft_date_in_previous_any?(all_title_groups, index) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :notes) end)

        # Source marker groups (inspired by, based on, etc.)
        all_centered?(group) && TextUtils.has_source_marker?(group) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :source_marker) end)

        # Source names (following source marker and looks like source material)
        all_centered?(group) && has_source_marker_in_previous_any?(all_title_groups, index) && looks_like_source_material?(group) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :source_names) end)

        # Author names (following author marker, but not after source marker)
        all_centered?(group) && has_author_marker_in_previous_any?(all_title_groups, index) && not has_source_marker_in_previous_any?(all_title_groups, index) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :author_names) end)

        # Source names (following source marker)
        all_centered?(group) && has_source_marker_in_previous_any?(all_title_groups, index) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :source_names) end)

        # Remaining centered groups are source continuation
        all_centered?(group) ->
          group |> Enum.map(fn elem -> Map.put(elem, :type, :source_continuation) end)

        # Non-centered groups: date, contact, copyright, notes
        true ->
          classify_non_centered_title_elements(group, index, all_title_groups)
      end
    end
  end

  @spec all_centered?(list()) :: boolean()
  defp all_centered?(group) do
    Enum.all?(group, fn elem -> elem.centered end)
  end


  @spec has_author_marker_in_previous_any?(list(), integer()) :: boolean()
  defp has_author_marker_in_previous_any?(all_groups, current_index) do
    all_groups
    |> Enum.take(current_index)  # Take all groups before current
    |> Enum.any?(&TextUtils.has_author_marker?/1)
  end

  @spec has_source_marker_in_previous_any?(list(), integer()) :: boolean()
  defp has_source_marker_in_previous_any?(all_groups, current_index) do
    all_groups
    |> Enum.take(current_index)  # Take all groups before current
    |> Enum.any?(&TextUtils.has_source_marker?/1)
  end

  @spec looks_like_author_names?(list()) :: boolean()
  defp looks_like_author_names?(group) do
    # Check if group contains typical author name patterns
    Enum.any?(group, fn elem ->
      text = String.trim(elem.text)
      # Author names typically have capital letters and may contain "&" connectors
      String.match?(text, ~r/^[A-Z][a-zA-Z\s&]+$/) && String.length(text) > 1 && String.length(text) < 50
    end)
  end

  @spec looks_like_source_material?(list()) :: boolean()
  defp looks_like_source_material?(group) do
    # Check if group contains patterns typical of source material references
    Enum.any?(group, fn elem ->
      text = String.trim(elem.text)
      # Source material typically mentions films, books, stories, plays
      String.match?(text, ~r/(film|movie|book|story|novel|play|short story)/i) ||
      # Or has ALL CAPS titles like movie/book titles
      (String.match?(text, ~r/^[A-Z\s,]+$/) && String.length(text) > 5 && String.length(text) < 100)
    end)
  end

  @spec classify_non_centered_title_elements(list(), integer(), list()) :: list()
  defp classify_non_centered_title_elements(group, index, all_groups) do
    # First check if this group has author or source markers
    cond do
      TextUtils.has_author_marker?(group) ->
        group |> Enum.map(fn elem -> Map.put(elem, :type, :author_marker) end)
      
      TextUtils.has_source_marker?(group) ->
        group |> Enum.map(fn elem -> Map.put(elem, :type, :source_marker) end)
      
      # Source names (following source marker, but only if it looks like source material)
      has_source_marker_in_previous_any?(all_groups, index) && looks_like_source_material?(group) ->
        group |> Enum.map(fn elem -> Map.put(elem, :type, :source_names) end)

      # Author names (following author marker in any previous group, and not source material)
      looks_like_author_names?(group) && has_author_marker_in_previous_any?(all_groups, index) && 
      not has_source_marker_in_previous_any?(all_groups, index) ->
        group |> Enum.map(fn elem -> Map.put(elem, :type, :author_names) end)
      
      true ->
        # Individual element classification
        group |> Enum.map(fn elem ->
          cond do
            # Date patterns
            TextUtils.looks_like_date?(elem.text) ->
              Map.put(elem, :type, :draft_date)

            # Contact info patterns (address, phone, email)
            TextUtils.looks_like_contact?(elem.text) ->
              Map.put(elem, :type, :contact)

            # Copyright patterns
            TextUtils.looks_like_copyright?(elem.text) ->
              Map.put(elem, :type, :copyright)

            # Everything else is notes/metadata
            true ->
              Map.put(elem, :type, :notes)
          end
        end)
    end
  end

  @spec has_date_content?(list()) :: boolean()
  defp has_date_content?(group) do
    Enum.any?(group, fn elem ->
      TextUtils.looks_like_date?(elem.text)
    end)
  end

  @spec has_quote_content?(list()) :: boolean()
  defp has_quote_content?(group) do
    Enum.any?(group, fn elem ->
      String.contains?(elem.text, "\"") || String.match?(elem.text, ~r/^["""].+["""]$/)
    end)
  end

  @spec has_draft_date_in_previous_any?(list(), integer()) :: boolean()
  defp has_draft_date_in_previous_any?(all_groups, current_index) do
    all_groups
    |> Enum.take(current_index)  # Take all groups before current
    |> Enum.any?(fn group ->
      Enum.any?(group, fn elem ->
        Map.get(elem, :type) == :draft_date
      end)
    end)
  end

end
