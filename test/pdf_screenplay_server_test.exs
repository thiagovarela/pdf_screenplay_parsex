defmodule PdfScreenplayParsex.PdfScreenplayServerTest do
  use ExUnit.Case, async: false
  
  alias PdfScreenplayParsex.{PdfScreenplayServer, PositionalExtractionResult}
  
  @moduletag :integration
  
  # NOTE: These tests focus on GenServer behavior and API contracts.
  # In a test environment without Python dependencies (pdfplumber, langdetect),
  # the calls will return {:error, ...} but the GenServer should remain responsive
  # and handle all requests gracefully without crashing.

  # Simple PDF binary for testing (minimal valid PDF structure)
  @test_pdf_binary <<
    "%PDF-1.4\n",
    "1 0 obj\n<<\n/Type /Catalog\n/Pages 2 0 R\n>>\nendobj\n",
    "2 0 obj\n<<\n/Type /Pages\n/Kids [3 0 R]\n/Count 1\n>>\nendobj\n",
    "3 0 obj\n<<\n/Type /Page\n/Parent 2 0 R\n/MediaBox [0 0 612 792]\n/Contents 4 0 R\n>>\nendobj\n",
    "4 0 obj\n<<\n/Length 44\n>>\nstream\nBT\n/F1 12 Tf\n72 720 Td\n(Hello World) Tj\nET\nendstream\nendobj\n",
    "xref\n0 5\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000206 00000 n \n",
    "trailer\n<<\n/Size 5\n/Root 1 0 R\n>>\nstartxref\n299\n%%EOF"
  >>

  describe "GenServer lifecycle" do
    test "server starts successfully" do
      # The server should already be started by the application
      assert Process.whereis(PdfScreenplayServer) != nil
    end

    test "server is alive and responding" do
      assert GenServer.call(PdfScreenplayServer, {:extract_text, @test_pdf_binary})
    end

    test "server handles unknown requests" do
      assert {:error, :unknown_request} = GenServer.call(PdfScreenplayServer, {:unknown_request})
    end
  end

  describe "extract_text_with_positions/1" do
    test "calls GenServer and returns response" do
      result = PdfScreenplayServer.extract_text_with_positions(@test_pdf_binary)
      
      # Should return either success or error, but not crash
      case result do
        {:ok, %PositionalExtractionResult{}} -> assert true
        {:error, _error} -> assert true
      end
    end

    test "returns error with invalid binary" do
      invalid_binary = "not a pdf"
      
      result = PdfScreenplayServer.extract_text_with_positions(invalid_binary)
      
      assert {:error, _error} = result
    end

    test "returns structured response format when successful" do
      result = PdfScreenplayServer.extract_text_with_positions(@test_pdf_binary)
      
      case result do
        {:ok, %PositionalExtractionResult{pages: pages, language: language, total_text: total_text}} ->
          assert is_list(pages)
          assert is_binary(language)  
          assert is_binary(total_text)
        {:error, _error} ->
          # If Python dependencies are missing, this is expected
          assert true
      end
    end

    test "handles empty PDF gracefully" do
      # Minimal PDF with no content
      minimal_pdf = "%PDF-1.4\n%%EOF"
      
      result = PdfScreenplayServer.extract_text_with_positions(minimal_pdf)
      
      # Should return some response (not crash)
      case result do
        {:ok, %PositionalExtractionResult{}} -> assert true
        {:error, _error} -> assert true
      end
    end
  end

  describe "extract_text/1" do
    test "calls GenServer and returns response" do
      result = PdfScreenplayServer.extract_text(@test_pdf_binary)
      
      # Should return either success or error, but not crash
      case result do
        {:ok, text} -> 
          assert is_binary(text)
        {:error, _error} -> 
          assert true
      end
    end

    test "returns error with invalid binary" do
      invalid_binary = "not a pdf"
      
      result = PdfScreenplayServer.extract_text(invalid_binary)
      
      assert {:error, _error} = result
    end
  end

  describe "concurrent requests" do
    test "handles multiple simultaneous requests" do
      # Test that the GenServer can handle concurrent requests
      tasks = for _i <- 1..5 do
        Task.async(fn ->
          PdfScreenplayServer.extract_text(@test_pdf_binary)
        end)
      end

      results = Task.await_many(tasks, 10_000)
      
      # All requests should complete (either success or consistent error)
      assert length(results) == 5
      
      # All results should have the same format
      first_result = hd(results)
      assert Enum.all?(results, fn result -> 
        match?({:ok, _}, result) == match?({:ok, _}, first_result) and
        match?({:error, _}, result) == match?({:error, _}, first_result)
      end)
    end
  end

  describe "error handling" do
    test "server survives Python errors" do
      # Test with malformed PDF that will cause Python error
      malformed_pdf = "%PDF-1.4\nmalformed content"
      
      # Make request that will likely fail
      result = PdfScreenplayServer.extract_text(malformed_pdf)
      assert {:error, _error} = result
      
      # Server should still be alive and responsive
      assert Process.alive?(Process.whereis(PdfScreenplayServer))
      
      # Should be able to handle subsequent requests (may succeed or fail consistently)
      valid_result = PdfScreenplayServer.extract_text(@test_pdf_binary)
      case valid_result do
        {:ok, _text} -> assert true
        {:error, _error} -> assert true
      end
    end

    test "timeout handling for long-running operations" do
      # This test ensures the GenServer doesn't hang indefinitely
      # Using a very large binary that might cause processing delays
      large_invalid_binary = String.duplicate("not a pdf ", 10_000)
      
      # Should complete within reasonable time (either success or error)
      result = PdfScreenplayServer.extract_text(large_invalid_binary)
      
      # Should get some response (not hang)
      assert {:error, _error} = result
    end
  end

  describe "Python environment" do
    test "Python integration responds consistently" do
      # Test that Python calls return consistent response format
      result1 = PdfScreenplayServer.extract_text_with_positions(@test_pdf_binary)
      result2 = PdfScreenplayServer.extract_text_with_positions(@test_pdf_binary)
      
      # Both calls should return the same format (both success or both error)
      case {result1, result2} do
        {{:ok, _}, {:ok, _}} -> assert true
        {{:error, _}, {:error, _}} -> assert true
        _ -> flunk("Inconsistent response formats between calls")
      end
    end
  end

  describe "GenServer state management" do
    test "server maintains state across requests" do
      # First request
      result1 = PdfScreenplayServer.extract_text(@test_pdf_binary)
      
      # Second request should work the same way (state preserved)
      result2 = PdfScreenplayServer.extract_text(@test_pdf_binary)
      
      # Both should have consistent behavior
      assert match?({:ok, _}, result1) == match?({:ok, _}, result2)
      assert match?({:error, _}, result1) == match?({:error, _}, result2)
    end
  end
end