defmodule PdfScreenplayParsex.Grouper do
  @moduledoc """
  Utility functions for grouping screenplay elements.
  """

  alias PdfScreenplayParsex.TextElement

  @doc """
  Calculates the vertical gap between the current element and the previous element.

  ## Parameters

    * `elements` - List of text items or TextElements
    * `index` - Index of the current element

  ## Returns

  Returns the gap in points, or raises for invalid input.
  """
  @spec calculate_gap_to_prev!(list(), non_neg_integer()) :: float()
  def calculate_gap_to_prev!([], _index),
    do: raise(ArgumentError, "elements list cannot be empty")

  def calculate_gap_to_prev!(_elements, 0), do: 0.0

  def calculate_gap_to_prev!(elements, index) when index > 0 and index < length(elements) do
    current_item = Enum.at(elements, index)
    prev_item = Enum.at(elements, index - 1)

    {current_y, prev_y, prev_height} = extract_position_data(current_item, prev_item)

    prev_bottom = prev_y + prev_height
    gap = current_y - prev_bottom

    max(0.0, gap)
  end

  def calculate_gap_to_prev!(_elements, index),
    do: raise(ArgumentError, "index #{index} out of bounds")

  # Helper function to extract position data from either text items or TextElements
  defp extract_position_data(current_item, prev_item) do
    case {current_item, prev_item} do
      # Both are TextElements
      {%TextElement{y: current_y}, %TextElement{y: prev_y, height: prev_height}} ->
        {current_y, prev_y, prev_height}

      # Both are text item maps
      {%{"y" => current_y}, %{"y" => prev_y, "height" => prev_height}} ->
        {current_y, prev_y, prev_height}

      # Mixed types - not supported
      _ ->
        raise ArgumentError, "elements must be either all TextElements or all text item maps"
    end
  end

  @doc """
  Calculates the vertical gap between the current element and the next element.

  ## Parameters

    * `elements` - List of text items or TextElements
    * `index` - Index of the current element

  ## Returns

  Returns the gap in points, or raises for invalid input.
  """
  @spec calculate_gap_to_next!(list(), non_neg_integer()) :: float()
  def calculate_gap_to_next!([], _index),
    do: raise(ArgumentError, "elements list cannot be empty")

  def calculate_gap_to_next!(elements, index) when index >= length(elements) - 1, do: 0.0

  def calculate_gap_to_next!(elements, index) when index >= 0 and index < length(elements) - 1 do
    current_item = Enum.at(elements, index)
    next_item = Enum.at(elements, index + 1)

    {current_y, current_height, next_y} = extract_next_position_data(current_item, next_item)

    current_bottom = current_y + current_height
    gap = next_y - current_bottom

    max(0.0, gap)
  end

  def calculate_gap_to_next!(_elements, index),
    do: raise(ArgumentError, "index #{index} out of bounds")

  # Helper function to extract position data for next gap calculation
  defp extract_next_position_data(current_item, next_item) do
    case {current_item, next_item} do
      # Both are TextElements
      {%TextElement{y: current_y, height: current_height}, %TextElement{y: next_y}} ->
        {current_y, current_height, next_y}

      # Both are text item maps
      {%{"y" => current_y, "height" => current_height}, %{"y" => next_y}} ->
        {current_y, current_height, next_y}

      # Mixed types - not supported
      _ ->
        raise ArgumentError, "elements must be either all TextElements or all text item maps"
    end
  end

  @doc """
  Groups elements based on gap thresholds between them.

  Elements are grouped together when the gap between them is smaller than
  the threshold. A large gap indicates the start of a new logical group.

  ## Parameters

    * `elements` - List of TextElement structs
    * `gap_threshold` - Minimum gap size to create a new group (defaults to 10)

  ## Returns

  Returns a list of element groups (list of lists).
  """
  @spec group_by_gap?(list(TextElement.t()), number()) :: list(list(TextElement.t()))
  def group_by_gap?(elements, gap_threshold \\ 10)

  def group_by_gap?(elements, gap_threshold)
      when is_list(elements) and is_number(gap_threshold) do
    if Enum.empty?(elements) do
      []
    else
      elements
      |> Enum.chunk_while(
        [],
        fn element, acc ->
          new_acc = acc ++ [element]

          # Check if this element has a significant gap to next (indicating end of group)
          if element.gap_to_next && element.gap_to_next >= gap_threshold do
            # End current group and start a new one
            {:cont, new_acc, []}
          else
            # Continue building current group
            {:cont, new_acc}
          end
        end,
        fn
          # Handle any remaining elements in the final group
          [] -> {:cont, []}
          remaining -> {:cont, remaining, []}
        end
      )
      # Remove any empty groups
      |> Enum.reject(&Enum.empty?/1)
    end
  end

  def group_by_gap?(invalid_input, _gap_threshold),
    do: raise(ArgumentError, "elements must be a list, got: #{inspect(invalid_input)}")

  @doc """
  Determines if an element is centered based on its position and the page width.

  ## Parameters

    * `element` - TextElement or text item map
    * `page_width` - Width of the page in points

  ## Returns

  Returns `true` if the element is considered centered, `false` otherwise.
  """
  @spec centered?(TextElement.t() | map(), number()) :: boolean()
  def centered?(element, page_width) when is_number(page_width) and page_width > 0 do
    {x, width} = extract_centering_data(element)

    element_center = x + width / 2
    page_center = page_width / 2

    # Base tolerance is 20 points
    base_tolerance = 20
    distance_from_center = abs(element_center - page_center)

    # For elements that might be titles (x >= 280), use a more generous tolerance
    tolerance = if x >= 280 && x <= 320, do: 35, else: base_tolerance

    # Must be geometrically centered first
    if distance_from_center > tolerance do
      false
    else
      # Apply exclusions for elements that shouldn't be considered centered
      # even if they're geometrically close to center

      # Exclude dialogue positions that are clearly not meant to be centered
      dialogue_exclusion = x >= 170 && x <= 190 && distance_from_center > 8

      # For character positions, be more nuanced
      char_position_exclusion = x >= 240 && x <= 270 && distance_from_center > 18

      # Allow centering unless excluded
      not (char_position_exclusion || dialogue_exclusion)
    end
  end

  def centered?(_element, page_width),
    do: raise(ArgumentError, "page_width must be a positive number, got: #{inspect(page_width)}")

  # Helper function to extract position data for centering calculation
  defp extract_centering_data(element) do
    case element do
      %TextElement{x: x, width: width} ->
        {x, width}

      %{"x" => x, "width" => width} ->
        {x, width}

      _ ->
        raise ArgumentError,
              "element must be a TextElement or text item map with x and width fields"
    end
  end

  @doc """
  Converts raw text items to TextElements with gap calculations and centering information.

  ## Parameters

    * `text_items` - List of text item maps from PDF extraction
    * `page_width` - Width of the page for centering calculations (optional, defaults to 612)

  ## Returns

  Returns a list of TextElement structs with gap and centering information.
  """
  @spec build_text_elements(list(map()), number()) :: list(TextElement.t())
  def build_text_elements(text_items, page_width \\ 612)

  def build_text_elements(text_items, page_width)
      when is_list(text_items) and is_number(page_width) do
    text_items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      gap_to_prev = if index > 0, do: calculate_gap_to_prev!(text_items, index), else: nil

      gap_to_next =
        if index < length(text_items) - 1,
          do: calculate_gap_to_next!(text_items, index),
          else: nil

      is_centered = centered?(item, page_width)

      %TextElement{
        text: Map.get(item, "text", ""),
        x: Map.get(item, "x", 0),
        y: Map.get(item, "y", 0),
        width: Map.get(item, "width", 0),
        height: Map.get(item, "height", 0),
        font_size: Map.get(item, "font_size"),
        font_name: Map.get(item, "font"),
        gap_to_prev: gap_to_prev,
        gap_to_next: gap_to_next,
        centered: is_centered,
        type: nil,
        is_dual_dialogue: false
      }
    end)
  end

  def build_text_elements(invalid_input, _page_width),
    do: raise(ArgumentError, "text_items must be a list, got: #{inspect(invalid_input)}")
end
