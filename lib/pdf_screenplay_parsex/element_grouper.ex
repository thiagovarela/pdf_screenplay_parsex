defmodule PdfScreenplayParsex.ElementGrouper do
  @moduledoc """
  Groups text elements based on vertical gaps between them.

  This module handles the conversion of raw PDF text items into TextElement structs
  and groups them based on configurable gap thresholds. Elements are grouped together
  when they have small vertical gaps between them, representing logical units like
  dialogue blocks or action paragraphs.
  """

  alias PdfScreenplayParsex.{TextElement, TextUtils}

  @doc """
  Groups elements on each page based on gaps between them.

  ## Parameters

    * `pages_with_elements` - A list of page maps with TextElement structs
    * `gap_threshold` - Minimum gap size to create a new group (defaults to 10)

  ## Returns

  Returns a list of pages, each containing:
    * `:page_number` - The page number
    * `:groups` - A list of element groups
    * `:page_width` - The width of the page
    * `:page_height` - The height of the page
  """
  @spec group_elements_by_gap(list(), number()) :: list()
  def group_elements_by_gap(pages_with_elements, gap_threshold \\ 10)
      when is_list(pages_with_elements) do
    pages_with_elements
    |> Enum.map(fn page ->
      groups = group_page_elements(page.elements, gap_threshold)

      %{
        page_number: page.page_number,
        groups: groups,
        page_width: page.page_width,
        page_height: page.page_height
      }
    end)
  end

  @doc """
  Converts a single page's text items to TextElements with gap calculations.

  ## Parameters

    * `page_data` - Map containing page information from PDF extraction

  ## Returns

  Returns a map with converted TextElements and page metadata.
  """
  @spec convert_page_to_text_elements(map()) :: map()
  def convert_page_to_text_elements(page_data) do
    page_num = page_data["page_number"]
    text_items = page_data["text_items"]
    page_width = page_data["width"]
    page_height = page_data["height"]

    # Convert to TextElements and calculate gaps (text_items are already in order)
    elements = convert_to_text_elements_with_gaps(text_items, page_width)

    %{
      page_number: page_num,
      elements: elements,
      page_width: page_width,
      page_height: page_height
    }
  end

  @doc """
  Converts text items to TextElements with gap calculations.

  ## Parameters

    * `text_items` - List of text item maps from PDF extraction
    * `page_width` - Width of the page for centering calculations

  ## Returns

  Returns a list of TextElement structs with gap information.
  """
  @spec convert_to_text_elements_with_gaps(list(), number()) :: list(TextElement.t())
  def convert_to_text_elements_with_gaps(text_items, page_width) do
    text_items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      gap_to_prev = TextUtils.calculate_gap_to_prev(text_items, index)
      gap_to_next = TextUtils.calculate_gap_to_next(text_items, index)
      centered = TextUtils.element_centered?(item, page_width)

      %TextElement{
        text: item["text"],
        x: item["x"],
        y: item["y"],
        width: item["width"],
        height: item["height"],
        font_size: item["font_size"],
        font_name: item["font"],
        gap_to_prev: gap_to_prev,
        gap_to_next: gap_to_next,
        centered: centered
      }
    end)
  end

  @doc """
  Filters out TextElements with empty or whitespace-only text.

  ## Parameters

    * `page` - Page map containing elements list

  ## Returns

  Returns the page map with filtered elements.
  """
  @spec filter_empty_text_elements(map()) :: map()
  def filter_empty_text_elements(page) do
    filtered_elements =
      page.elements
      |> Enum.filter(fn element ->
        # Keep elements that have non-empty text after trimming
        String.trim(element.text) != ""
      end)

    %{page | elements: filtered_elements}
  end

  @doc """
  Groups elements on a single page based on gap threshold.

  Elements are grouped together when the gap between them is smaller than
  the threshold. A large gap indicates the start of a new logical group.

  ## Parameters

    * `elements` - List of TextElement structs
    * `gap_threshold` - Minimum gap size to create a new group

  ## Returns

  Returns a list of element groups (list of lists).
  """
  @spec group_page_elements(list(TextElement.t()), number()) :: list(list(TextElement.t()))
  def group_page_elements(elements, gap_threshold) do
    elements
    |> Enum.reduce({[], []}, fn element, {groups, current_group} ->
      new_current_group = current_group ++ [element]

      # Check if this element has a significant gap to next (indicating end of group)
      if element.gap_to_next && element.gap_to_next >= gap_threshold do
        # End current group and start a new one
        {groups ++ [new_current_group], []}
      else
        # Continue building current group
        {groups, new_current_group}
      end
    end)
    |> case do
      # No remaining elements
      {groups, []} -> groups
      # Add final group
      {groups, remaining} -> groups ++ [remaining]
    end
  end

  @doc """
  Checks if following elements in a group have no gaps between them.

  This is used to validate character groups where dialogue elements
  should be gapless after the character name.

  ## Parameters

    * `group` - List of TextElement structs

  ## Returns

  Returns `true` if all following elements are gapless, `false` otherwise.
  """
  @spec has_gapless_following_elements?(list(TextElement.t())) :: boolean()
  def has_gapless_following_elements?(group) do
    group
    # Skip the first element (the character name)
    |> Enum.drop(1)
    |> Enum.all?(fn element ->
      # Check if gap_to_prev is 0 or very small (allowing for line height variations)
      # Increased tolerance to 3 to accommodate continuation markers (gap ~2.9)
      element.gap_to_prev == 0 || element.gap_to_prev <= 3
    end)
  end
end
