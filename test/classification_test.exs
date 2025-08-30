defmodule BrickAndSteelClassificationTest do
  use ExUnit.Case

  test "brick & steel snapshot" do
    # Read the PDF and parse it
    {:ok, pdf_binary} = File.read("test/fixtures/Brick-&-Steel.pdf")

    {:ok, classified_pages} =
      PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)

    # Get the formatted output
    actual_output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(classified_pages)

    # Read expected output from fixture
    {:ok, expected_output} = File.read("test/fixtures/bricksteel.txt")

    # Compare exact match
    assert actual_output == expected_output,
           """
           dump_content output does not match fixture file.

           Expected (from fixture):
           #{expected_output}

           Actual (from dump_content):
           #{actual_output}
           """
  end

  test "12 monkeys snapshot" do
    # Read the PDF and parse it
    {:ok, pdf_binary} = File.read("test/fixtures/12 Monkeys.pdf")

    {:ok, classified_pages} =
      PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)

    # Get the formatted output
    actual_output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(classified_pages)

    # Read expected output from fixture
    {:ok, expected_output} = File.read("test/fixtures/12monkeys.txt")

    # Compare exact match
    assert actual_output == expected_output,
           """
           dump_content output does not match fixture file.

           Expected (from fixture):
           #{expected_output}

           Actual (from dump_content):
           #{actual_output}
           """
  end

  test "juno snapshot" do
    # Read the PDF and parse it
    {:ok, pdf_binary} = File.read("test/fixtures/Juno.pdf")

    {:ok, classified_pages} =
      PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)

    # Get the formatted output
    actual_output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(classified_pages)

    # Read expected output from fixture
    {:ok, expected_output} = File.read("test/fixtures/juno.txt")

    # Compare exact match
    assert actual_output == expected_output,
           """
           dump_content output does not match fixture file.

           Expected (from fixture):
           #{expected_output}

           Actual (from dump_content):
           #{actual_output}
           """
  end

  test "interstellar snapshot" do
    # Read the PDF and parse it
    {:ok, pdf_binary} = File.read("test/fixtures/Interstellar.pdf")

    {:ok, classified_pages} =
      PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)

    # Get the formatted output
    actual_output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(classified_pages)

    # Read expected output from fixture
    {:ok, expected_output} = File.read("test/fixtures/interstellar.txt")

    # Compare exact match
    assert actual_output == expected_output,
           """
           dump_content output does not match fixture file.

           Expected (from fixture):
           #{expected_output}

           Actual (from dump_content):
           #{actual_output}
           """
  end

  test "scriptsample snapshot" do
    # Read the PDF and parse it
    {:ok, pdf_binary} = File.read("test/fixtures/scriptsample.pdf")

    {:ok, classified_pages} =
      PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)

    # Get the formatted output
    actual_output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(classified_pages)

    # Read expected output from fixture
    {:ok, expected_output} = File.read("test/fixtures/scriptsample.txt")

    # Compare exact match
    assert actual_output == expected_output,
           """
           dump_content output does not match fixture file.

           Expected (from fixture):
           #{expected_output}

           Actual (from dump_content):
           #{actual_output}
           """
  end

  test "it snapshot" do
    # Read the PDF and parse it
    {:ok, pdf_binary} = File.read("test/fixtures/IT.pdf")

    {:ok, classified_pages} =
      PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)

    # Get the formatted output
    actual_output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(classified_pages)

    # Read expected output from fixture
    {:ok, expected_output} = File.read("test/fixtures/it.txt")

    # Compare exact match
    assert actual_output == expected_output,
           """
           dump_content output does not match fixture file.

           Expected (from fixture):
           #{expected_output}

           Actual (from dump_content):
           #{actual_output}
           """
  end

  test "alien covenant snapshot" do
    # Read the PDF and parse it
    {:ok, pdf_binary} = File.read("test/fixtures/Alien Covenant.pdf")

    {:ok, classified_pages} =
      PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)

    # Get the formatted output
    actual_output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(classified_pages)

    # Read expected output from fixture
    {:ok, expected_output} = File.read("test/fixtures/alien_covenant.txt")

    # Compare exact match
    assert actual_output == expected_output,
           """
           dump_content output does not match fixture file.

           Expected (from fixture):
           #{expected_output}

           Actual (from dump_content):
           #{actual_output}
           """
  end

  test "interstellar final snapshot" do
    # Read the PDF and parse it
    {:ok, pdf_binary} = File.read("test/fixtures/Interstellar-Final.pdf")

    {:ok, classified_pages} =
      PdfScreenplayParsex.ScreenplayClassifier.classify_screenplay(pdf_binary)

    # Get the formatted output
    actual_output = PdfScreenplayParsex.ScreenplayClassifier.dump_content(classified_pages)

    # Read expected output from fixture
    {:ok, expected_output} = File.read("test/fixtures/interstellar_final.txt")

    # Compare exact match
    assert actual_output == expected_output,
           """
           dump_content output does not match fixture file.

           Expected (from fixture):
           #{expected_output}

           Actual (from dump_content):
           #{actual_output}
           """
  end
end
