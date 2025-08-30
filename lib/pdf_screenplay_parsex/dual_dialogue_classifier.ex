defmodule PdfScreenplayParsex.DualDialogueClassifier do
  @moduledoc """
  Detects and classifies dual dialogue sequences in screenplay text.

  Dual dialogue occurs when two characters speak simultaneously, typically
  formatted side-by-side on the page. This module identifies such patterns
  and marks the relevant elements appropriately.
  """

  alias PdfScreenplayParsex.TextUtils

  @doc """
  Marks dual dialogue sequences in grouped elements.

  ## Parameters

    * `groups` - List of element groups to process

  ## Returns

  Returns updated groups with dual dialogue elements marked.
  """
  @spec mark_dual_dialogue(list()) :: list()
  def mark_dual_dialogue(groups) when is_list(groups) do
    groups
    |> Enum.map(fn group ->
      if dual_dialogue_within_group?(group) do
        # Mark elements in dual dialogue
        classify_dual_dialogue_elements(group)
      else
        group
      end
    end)
  end

  @doc """
  Checks if a group contains dual dialogue based on character positioning.

  ## Parameters

    * `group` - List of elements to check

  ## Returns

  Returns `true` if the group contains dual dialogue, `false` otherwise.
  """
  @spec dual_dialogue_within_group?(list()) :: boolean()
  def dual_dialogue_within_group?(group) do

    # Elements that could potentially be reclassified as dual dialogue
    # This includes unclassified elements, actions, dialogue, and already-classified characters
    reclassifiable_elements =
      group
      |> Enum.filter(fn elem ->
        current_type = Map.get(elem, :type)
        current_type == nil || current_type == :unclassified || current_type == :action || current_type == :character || current_type == :dialogue
      end)

    # Look for potential character names (regex match + ALL CAPS + reasonable width)
    potential_characters =
      reclassifiable_elements
      |> Enum.filter(fn elem ->
        current_type = Map.get(elem, :type)
        
        # If already classified as character, it's a potential dual dialogue character
        if current_type == :character do
          true
        else
          # Use TextUtils validation for better character name detection
          text = String.trim(elem.text)
          TextUtils.valid_character_name?(text) &&
            elem.width <= 200 &&
            String.length(text) <= 30
        end
      end)

    # Check if we have exactly 2 characters with significant horizontal separation
    length(potential_characters) == 2 &&
      has_significant_separation?(potential_characters)
  end

  @doc """
  Checks if characters have significant horizontal separation for dual dialogue.

  ## Parameters

    * `characters` - List of potential character elements

  ## Returns

  Returns `true` if characters are separated enough to be dual dialogue, `false` otherwise.
  """
  @spec has_significant_separation?(list()) :: boolean()
  def has_significant_separation?(characters) do
    x_positions = Enum.map(characters, fn elem -> elem.x end)
    min_x = Enum.min(x_positions)
    max_x = Enum.max(x_positions)

    # Require at least 150px separation for dual dialogue (more flexible than 180px)
    max_x - min_x >= 150
  end

  @doc """
  Classifies elements within a dual dialogue group using adaptive positioning.

  ## Parameters

    * `group` - List of elements in the dual dialogue group

  ## Returns

  Returns updated elements with dual dialogue classifications.
  """
  @spec classify_dual_dialogue_elements(list()) :: list()
  def classify_dual_dialogue_elements(group) do
    # Identify which are character names and which are dialogue
    Enum.map(group, fn elem ->
      current_type = Map.get(elem, :type)

      # Reclassify unclassified elements, actions, and already-classified elements for dual dialogue
      if current_type == nil || current_type == :unclassified || current_type == :action || current_type == :character || current_type == :dialogue do
        text = String.trim(elem.text)

        cond do
          # Character names: use consistent validation with main classifier
          TextUtils.valid_character_name?(text) &&
            elem.width <= 200 &&
              String.length(text) <= 30 ->
            elem
            |> Map.put(:type, :character)
            |> Map.put(:is_dual_dialogue, true)

          # Skip page markers and other non-dialogue text
          TextUtils.page_marker?(text) ->
            elem  # Keep as unclassified

          # Everything else in dual dialogue group is dialogue
          true ->
            elem
            |> Map.put(:type, :dialogue)
            |> Map.put(:is_dual_dialogue, true)
        end
      else
        # Keep existing classifications but mark as dual
        Map.put(elem, :is_dual_dialogue, true)
      end
    end)
  end
end
