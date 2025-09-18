defmodule PdfScreenplayParsex.ElementTypeTest do
  use ExUnit.Case, async: true

  alias PdfScreenplayParsex.{TextElement, ElementType}

  describe "title?/4" do
    test "identifies valid title on first page" do
      element = %TextElement{
        text: "MY SCREENPLAY",
        centered: true,
        x: 300,
        y: 200
      }
      
      context = %{page_number: 0}  # First page
      
      assert ElementType.title?(element, 0, [element], context)
    end

    test "rejects title on second page" do
      element = %TextElement{
        text: "MY SCREENPLAY",
        centered: true,
        x: 300,
        y: 200
      }
      
      context = %{page_number: 1}  # Second page
      
      refute ElementType.title?(element, 0, [element], context)
    end

    test "rejects title on later pages" do
      element = %TextElement{
        text: "MY SCREENPLAY",
        centered: true,
        x: 300,
        y: 200
      }
      
      context = %{page_number: 5}  # Later page
      
      refute ElementType.title?(element, 0, [element], context)
    end

    test "rejects non-centered text even on first page" do
      element = %TextElement{
        text: "MY SCREENPLAY",
        centered: false,
        x: 100,
        y: 200
      }
      
      context = %{page_number: 0}  # First page
      
      refute ElementType.title?(element, 0, [element], context)
    end
  end

  describe "transition?/4" do
    test "identifies valid transitions with correct positioning" do
      # Valid transition pattern at right margin position
      element = %TextElement{
        text: "FADE OUT.",
        # Right margin position
        x: 450,
        y: 100
      }

      context = %{}

      assert ElementType.transition?(element, 0, [element], context)
    end

    test "rejects transition pattern at wrong position" do
      # Valid transition pattern but wrong position (left margin)
      element = %TextElement{
        text: "FADE OUT.",
        # Left margin position
        x: 200,
        y: 100
      }

      context = %{}

      refute ElementType.transition?(element, 0, [element], context)
    end

    test "rejects non-transition text at correct position" do
      # Wrong pattern but correct position
      element = %TextElement{
        text: "GEORGE",
        # Right margin position
        x: 450,
        y: 100
      }

      context = %{}

      refute ElementType.transition?(element, 0, [element], context)
    end

    test "rejects transition if not first element in group" do
      element1 = %TextElement{text: "Some text", x: 100, y: 100}
      element2 = %TextElement{text: "FADE OUT.", x: 450, y: 110}

      context = %{}

      # Second element in group should not be classified as transition
      refute ElementType.transition?(element2, 1, [element1, element2], context)
    end

    test "identifies various transition types" do
      transitions = [
        "FADE IN:",
        "FADE OUT.",
        "CUT TO:",
        "DISSOLVE TO:",
        "THE END"
      ]

      context = %{}

      for transition_text <- transitions do
        element = %TextElement{
          text: transition_text,
          x: 450,
          y: 100
        }

        assert ElementType.transition?(element, 0, [element], context),
               "#{transition_text} should be identified as transition"
      end
    end
  end

  describe "page_number?/4" do
    test "identifies valid page numbers at top margin" do
      element = %TextElement{
        text: "1",
        x: 300,
        y: 50  # Top margin
      }
      
      context = %{}
      
      assert ElementType.page_number?(element, 0, [element], context)
    end

    test "identifies valid page numbers at bottom margin" do
      element = %TextElement{
        text: "12",
        x: 300,
        y: 750  # Bottom margin
      }
      
      context = %{}
      
      assert ElementType.page_number?(element, 0, [element], context)
    end

    test "rejects page number at middle position" do
      element = %TextElement{
        text: "1",
        x: 300,
        y: 400  # Middle of page
      }
      
      context = %{}
      
      refute ElementType.page_number?(element, 0, [element], context)
    end


    test "identifies various page number patterns" do
      page_patterns = [
        "1",
        "12",
        "123",
        "1.",
        "-12-"
      ]
      
      context = %{}
      
      for pattern <- page_patterns do
        element = %TextElement{
          text: pattern,
          x: 300,
          y: 50
        }
        
        assert ElementType.page_number?(element, 0, [element], context),
               "#{pattern} should be identified as page number"
      end
    end
  end

  describe "scene_number?/4" do
    test "identifies valid scene numbers at right margin" do
      element = %TextElement{
        text: "1",
        x: 520,  # Right margin
        y: 200
      }
      
      context = %{}
      
      assert ElementType.scene_number?(element, 0, [element], context)
    end

    test "rejects scene number at wrong position" do
      element = %TextElement{
        text: "1",
        x: 300,  # Center position
        y: 200
      }
      
      context = %{}
      
      refute ElementType.scene_number?(element, 0, [element], context)
    end

    test "accepts scene number regardless of position in group" do
      element1 = %TextElement{text: "Some text", x: 100, y: 200}
      element2 = %TextElement{text: "1", x: 520, y: 210}

      context = %{}

      # Scene numbers can appear anywhere in a group (real-world usage in Juno)
      assert ElementType.scene_number?(element2, 1, [element1, element2], context)
    end

    test "identifies various scene number patterns" do
      scene_patterns = [
        "1",
        "1A",
        "12",
        "12.",
        "A1",
        "1-2"
      ]
      
      context = %{}
      
      for pattern <- scene_patterns do
        element = %TextElement{
          text: pattern,
          x: 520,
          y: 200
        }
        
        assert ElementType.scene_number?(element, 0, [element], context),
               "#{pattern} should be identified as scene number"
      end
    end
  end
end
