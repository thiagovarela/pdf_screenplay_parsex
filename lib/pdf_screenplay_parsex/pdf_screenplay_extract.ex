defmodule PdfScreenplayParsex.PdfScreenplayExtract do
  @moduledoc """
  Handles PDF text extraction using PyMuPDF via the PdfScreenplayServer GenServer.

  This module provides enhanced error handling and delegates all Python operations
  to the PdfScreenplayServer GenServer for thread-safe Python interpreter management.
  """

  alias PdfScreenplayParsex.{Errors, PdfScreenplayServer}

  def extract_text_from_binary(binary) do
    extract_text_with_positions(binary)
  end

  def extract_text_with_positions(binary) do
    Errors.with_error_handling(fn ->
      case PdfScreenplayServer.extract_text_with_positions(binary) do
        {:ok, result} -> result
        {:error, error} -> 
          raise %Errors.PythonExecutionError{
            message: "PDF extraction failed in PdfScreenplayServer",
            python_error: inspect(error)
          }
      end
    end, %{operation: "extract_text_with_positions", binary_size: byte_size(binary)})
  end
end