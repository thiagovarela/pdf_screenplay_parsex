defmodule PdfScreenplayParsex.ClassificationContext do
  @moduledoc """
  Manages classification state and context during multi-pass screenplay analysis.

  This module encapsulates the state that needs to be maintained and passed between
  different phases of the classification process, including character positions,
  scene heading locations, and page metadata.
  """

  @type t :: %__MODULE__{
    page_width: number(),
    page_height: number(),
    page_number: integer(),
    established_char_x: number() | nil,
    scene_heading_x_positions: list(number()),
    character_x_position: number() | nil,
    is_title_page: boolean(),
    continuing_character: String.t() | nil,
    groups: list()
  }

  defstruct [
    :page_width,
    :page_height,
    :page_number,
    :established_char_x,
    :scene_heading_x_positions,
    :character_x_position,
    :is_title_page,
    :continuing_character,
    :groups
  ]

  @doc """
  Creates a new ClassificationContext from page data.

  ## Parameters

    * `page` - Page map containing dimensions and metadata
    * `established_char_x` - Character X position from previous pages (optional)

  ## Returns

  Returns a new ClassificationContext struct.
  """
  @spec new(map(), number() | nil) :: t()
  def new(page, established_char_x \\ nil) do
    %__MODULE__{
      page_width: page[:page_width] || page["page_width"],
      page_height: page[:page_height] || page["page_height"],
      page_number: page[:page_number] || page["page_number"],
      groups: page[:groups] || page["groups"] || [],
      established_char_x: established_char_x,
      scene_heading_x_positions: [],
      character_x_position: established_char_x,
      is_title_page: false
    }
  end

  @doc """
  Updates the context with new scene heading X positions.

  ## Parameters

    * `context` - ClassificationContext struct
    * `x_positions` - List of X positions to add

  ## Returns

  Returns updated ClassificationContext.
  """
  @spec add_scene_heading_positions(t(), list(number())) :: t()
  def add_scene_heading_positions(context, x_positions) do
    %{context | scene_heading_x_positions: context.scene_heading_x_positions ++ x_positions}
  end

  @doc """
  Updates the character X position in the context.

  ## Parameters

    * `context` - ClassificationContext struct
    * `x_position` - New character X position

  ## Returns

  Returns updated ClassificationContext.
  """
  @spec update_character_position(t(), number()) :: t()
  def update_character_position(context, x_position) do
    %{context | character_x_position: x_position}
  end

  @doc """
  Sets the continuing character name for page-to-page continuations.

  ## Parameters

    * `context` - ClassificationContext to update
    * `character_name` - Name of character continuing from previous page

  ## Returns

  Returns updated ClassificationContext.
  """
  @spec set_continuing_character(t(), String.t() | nil) :: t()
  def set_continuing_character(context, character_name) do
    %{context | continuing_character: character_name}
  end

  @doc """
  Marks the page as a title page.

  ## Parameters

    * `context` - ClassificationContext struct
    * `is_title_page` - Boolean indicating if this is a title page

  ## Returns

  Returns updated ClassificationContext.
  """
  @spec set_title_page(t(), boolean()) :: t()
  def set_title_page(context, is_title_page) do
    %{context | is_title_page: is_title_page}
  end

  @doc """
  Updates the groups in the context.

  ## Parameters

    * `context` - ClassificationContext struct
    * `groups` - New groups list

  ## Returns

  Returns updated ClassificationContext.
  """
  @spec update_groups(t(), list()) :: t()
  def update_groups(context, groups) do
    %{context | groups: groups}
  end

  @doc """
  Checks if character position is established (not nil).

  ## Parameters

    * `context` - ClassificationContext struct

  ## Returns

  Returns `true` if character position is established, `false` otherwise.
  """
  @spec character_position_established?(t()) :: boolean()
  def character_position_established?(context) do
    not is_nil(context.character_x_position)
  end

  @doc """
  Gets the character X position with a default fallback.

  ## Parameters

    * `context` - ClassificationContext struct
    * `default` - Default value if position is not established

  ## Returns

  Returns the character X position or default value.
  """
  @spec get_character_position(t(), any()) :: number() | any()
  def get_character_position(context, default \\ nil) do
    context.character_x_position || default
  end

  @doc """
  Extracts character X position from classified groups in the context.

  Searches through all groups to find the first character element
  and returns its X position.

  ## Parameters

    * `context` - ClassificationContext struct

  ## Returns

  Returns the X position of the first character found, or `nil`.
  """
  @spec extract_character_position_from_groups(t()) :: number() | nil
  def extract_character_position_from_groups(context) do
    context.groups
    |> Enum.find_value(fn group ->
      Enum.find_value(group, fn elem ->
        if Map.get(elem, :type) == :character do
          elem.x
        else
          nil
        end
      end)
    end)
  end

  @doc """
  Converts the context back to a page map format.

  ## Parameters

    * `context` - ClassificationContext struct

  ## Returns

  Returns a map in the original page format.
  """
  @spec to_page_map(t()) :: map()
  def to_page_map(context) do
    %{
      page_number: context.page_number,
      groups: context.groups,
      page_width: context.page_width,
      page_height: context.page_height
    }
  end
end
