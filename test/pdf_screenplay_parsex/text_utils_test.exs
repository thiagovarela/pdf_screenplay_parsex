defmodule PdfScreenplayParsex.TextUtilsTest do
  use ExUnit.Case
  doctest PdfScreenplayParsex.TextUtils

  alias PdfScreenplayParsex.TextUtils

  describe "scene_heading?/1" do
    test "returns true for basic INT scene headings" do
      assert TextUtils.scene_heading?("INT. HOUSE - DAY")
      assert TextUtils.scene_heading?("INT HOUSE - NIGHT")
      assert TextUtils.scene_heading?("INT. KITCHEN - MORNING")
      assert TextUtils.scene_heading?("INT. KITCHEN - (CONT'D)")
      assert TextUtils.scene_heading?("INT. KITCHEN - (CONTINUOUS)")
    end

    test "returns true for basic EXT scene headings" do
      assert TextUtils.scene_heading?("EXT. PARK - DAY")
      assert TextUtils.scene_heading?("EXT STREET - NIGHT")
      assert TextUtils.scene_heading?("EXT. BEACH - SUNSET")
    end

    test "returns true for mixed scene headings" do
      assert TextUtils.scene_heading?("INT/EXT. CAR - DAY")
      assert TextUtils.scene_heading?("EXT/INT BUILDING - NIGHT")
    end

    test "returns false for non-scene headings" do
      refute TextUtils.scene_heading?("JOHN")
      refute TextUtils.scene_heading?("Hello world")
      refute TextUtils.scene_heading?("FADE IN:")
      refute TextUtils.scene_heading?("")
    end

    test "handles whitespace variations" do
      assert TextUtils.scene_heading?("EXT.   PARK   -   NIGHT")
    end
  end

  describe "character?/1" do
    test "returns true for basic character names" do
      assert TextUtils.character?("JOHN")
      assert TextUtils.character?("MARY")
      assert TextUtils.character?("DETECTIVE SMITH")
    end

    test "returns true for character names with parentheticals" do
      assert TextUtils.character?("JOHN (O.S.)")
      assert TextUtils.character?("JOHN`S MOM")
      assert TextUtils.character?("MARY  (V.O.)")
      assert TextUtils.character?("MS. MARY (V.O.)")
      assert TextUtils.character?("MR. O'brian")
      assert TextUtils.character?("ROBOT #5")
      assert TextUtils.character?("JOSÉ")
      assert TextUtils.character?("C-3PO")
      assert TextUtils.character?("BJÖRN")
      assert TextUtils.character?("DETECTIVE (CONT'D)")
    end

    test "returns false for lowercase names" do
      refute TextUtils.character?("john")
      refute TextUtils.character?("mary smith")
    end

    test "returns false for empty or invalid input" do
      refute TextUtils.character?("")
      refute TextUtils.character?("123")
      refute TextUtils.character?("(parenthetical only)")
    end
  end

  describe "transition?/1" do
    test "returns true for fade transitions" do
      assert TextUtils.transition?("FADE IN:")
      assert TextUtils.transition?("FADE OUT.")
      assert TextUtils.transition?("fade in:")
      assert TextUtils.transition?("fade out.")
    end

    test "returns true for cut transitions" do
      assert TextUtils.transition?("CUT TO:")
      assert TextUtils.transition?("DISSOLVE TO:")
      assert TextUtils.transition?("MATCH CUT TO:")
      assert TextUtils.transition?("SMASH CUT TO:")
      assert TextUtils.transition?("JUMP CUT TO:")
      assert TextUtils.transition?("CROSS CUT TO:")
    end

    test "returns true for special transitions" do
      assert TextUtils.transition?("INTERCUT:")
      assert TextUtils.transition?("INTERCUT WITH:")
      assert TextUtils.transition?("BURN TO PINK:")
      assert TextUtils.transition?("MONTAGE:")
      assert TextUtils.transition?("END MONTAGE")
      assert TextUtils.transition?("BACK TO:")
      assert TextUtils.transition?("FLASHBACK:")
      assert TextUtils.transition?("END FLASHBACK")
      assert TextUtils.transition?("FREEZE FRAME")
      assert TextUtils.transition?("THE END")
    end

    test "handles case insensitive matching" do
      assert TextUtils.transition?("cut to:")
      assert TextUtils.transition?("Cut To:")
      assert TextUtils.transition?("DISSOLVE TO:")
      assert TextUtils.transition?("dissolve to:")
      assert TextUtils.transition?("the end")
      assert TextUtils.transition?("The End")
    end

    test "returns false for non-transitions" do
      refute TextUtils.transition?("JOHN")
      refute TextUtils.transition?("INT. HOUSE - DAY")
      refute TextUtils.transition?("Hello world")
      refute TextUtils.transition?("CUT TO COMMERCIAL")
      refute TextUtils.transition?("FADE IN SLOWLY")
      refute TextUtils.transition?("")
    end
  end

  describe "subheading?/1" do
    test "returns true for basic subheadings without colon" do
      assert TextUtils.subheading?("LATER")
      assert TextUtils.subheading?("MEANWHILE")
      assert TextUtils.subheading?("NEXT DAY")
      assert TextUtils.subheading?("THAT NIGHT")
      assert TextUtils.subheading?("FIVE MINUTES LATER")
    end

    test "returns true for subheadings with colon" do
      assert TextUtils.subheading?("LATER:")
      assert TextUtils.subheading?("MEANWHILE:")
      assert TextUtils.subheading?("NEXT DAY:")
      assert TextUtils.subheading?("THAT NIGHT:")
      assert TextUtils.subheading?("FIVE MINUTES LATER:")
    end

    test "returns true for single word subheadings" do
      assert TextUtils.subheading?("LATER")
      assert TextUtils.subheading?("MEANWHILE")
      assert TextUtils.subheading?("SUDDENLY")
      assert TextUtils.subheading?("AFTERWARDS")
    end

    test "returns false for mixed case text" do
      refute TextUtils.subheading?("Later")
      refute TextUtils.subheading?("Meanwhile")
      refute TextUtils.subheading?("Next Day")
      refute TextUtils.subheading?("later:")
    end

    test "returns false for scene headings" do
      refute TextUtils.subheading?("INT. HOUSE - DAY")
      refute TextUtils.subheading?("EXT. PARK - NIGHT")
    end

    test "returns false for empty or invalid input" do
      refute TextUtils.subheading?("")
      refute TextUtils.subheading?("123")
      refute TextUtils.subheading?("hello world")
    end
  end
end
