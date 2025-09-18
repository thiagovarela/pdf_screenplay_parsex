defmodule PdfScreenplayParsex.Errors do
  @moduledoc """
  Comprehensive error types and handling for PDF screenplay parsing.

  This module defines structured error types and provides utilities for
  error handling throughout the parsing pipeline.
  """

  defmodule PDFError do
    @moduledoc """
    Represents errors that occur during PDF processing.
    """
    defexception [:message, :type, :details, :file_info]

    @type t :: %__MODULE__{
      message: String.t(),
      type: atom(),
      details: map() | nil,
      file_info: map() | nil
    }

    @impl true
    def exception(args) when is_list(args) do
      message = Keyword.get(args, :message, "PDF processing failed")
      type = Keyword.get(args, :type, :unknown)
      details = Keyword.get(args, :details, %{})
      file_info = Keyword.get(args, :file_info, %{})

      %__MODULE__{
        message: message,
        type: type,
        details: details,
        file_info: file_info
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, type: :unknown, details: %{}, file_info: %{}}
    end

    @impl true
    def message(%__MODULE__{message: message, type: type, details: details}) do
      base_message = "PDF Error (#{type}): #{message}"

      case details do
        details when map_size(details) > 0 ->
          details_str = details |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
          "#{base_message} | Details: #{details_str}"
        _ ->
          base_message
      end
    end
  end

  defmodule ValidationError do
    @moduledoc """
    Represents errors that occur during input validation.
    """
    defexception [:message, :field, :value, :constraint]

    @type t :: %__MODULE__{
      message: String.t(),
      field: atom() | String.t() | nil,
      value: any(),
      constraint: atom() | String.t() | nil
    }

    @impl true
    def exception(args) when is_list(args) do
      field = Keyword.get(args, :field)
      value = Keyword.get(args, :value)
      constraint = Keyword.get(args, :constraint)

      message = Keyword.get(args, :message) || build_default_message(field, value, constraint)

      %__MODULE__{
        message: message,
        field: field,
        value: value,
        constraint: constraint
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, field: nil, value: nil, constraint: nil}
    end

    @impl true
    def message(%__MODULE__{message: message}), do: message

    defp build_default_message(field, value, constraint) do
      case {field, constraint} do
        {field, constraint} when not is_nil(field) and not is_nil(constraint) ->
          "Validation failed for field '#{field}': #{constraint} (got: #{inspect(value)})"
        {field, _} when not is_nil(field) ->
          "Validation failed for field '#{field}' (got: #{inspect(value)})"
        _ ->
          "Validation failed"
      end
    end
  end

  defmodule PythonExecutionError do
    @moduledoc """
    Represents errors that occur during Python code execution via Pythonx.
    """
    defexception [:message, :python_error, :python_traceback, :code_snippet]

    @type t :: %__MODULE__{
      message: String.t(),
      python_error: String.t() | nil,
      python_traceback: String.t() | nil,
      code_snippet: String.t() | nil
    }

    @impl true
    def exception(args) when is_list(args) do
      python_error = Keyword.get(args, :python_error)
      python_traceback = Keyword.get(args, :python_traceback)
      code_snippet = Keyword.get(args, :code_snippet)

      message = Keyword.get(args, :message) || build_default_message(python_error)

      %__MODULE__{
        message: message,
        python_error: python_error,
        python_traceback: python_traceback,
        code_snippet: code_snippet
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, python_error: nil, python_traceback: nil, code_snippet: nil}
    end

    @impl true
    def message(%__MODULE__{message: message, python_error: python_error}) do
      case python_error do
        nil -> message
        error -> "#{message} | Python error: #{error}"
      end
    end

    defp build_default_message(python_error) do
      case python_error do
        nil -> "Python execution failed"
        error -> "Python execution failed: #{error}"
      end
    end
  end

  defmodule ClassificationError do
    @moduledoc """
    Represents errors that occur during screenplay element classification.
    """
    defexception [:message, :element, :pass, :context]

    @type t :: %__MODULE__{
      message: String.t(),
      element: map() | nil,
      pass: atom() | String.t() | nil,
      context: map() | nil
    }

    @impl true
    def exception(args) when is_list(args) do
      message = Keyword.get(args, :message, "Classification failed")
      element = Keyword.get(args, :element)
      pass = Keyword.get(args, :pass)
      context = Keyword.get(args, :context, %{})

      %__MODULE__{
        message: message,
        element: element,
        pass: pass,
        context: context
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, element: nil, pass: nil, context: %{}}
    end

    @impl true
    def message(%__MODULE__{message: message, pass: pass}) do
      case pass do
        nil -> message
        pass -> "#{message} (during #{pass} pass)"
      end
    end
  end

  defmodule MemoryError do
    @moduledoc """
    Represents errors due to memory constraints during processing.
    """
    defexception [:message, :current_usage, :limit, :operation]

    @type t :: %__MODULE__{
      message: String.t(),
      current_usage: integer() | nil,
      limit: integer() | nil,
      operation: String.t() | nil
    }

    @impl true
    def exception(args) when is_list(args) do
      current_usage = Keyword.get(args, :current_usage)
      limit = Keyword.get(args, :limit)
      operation = Keyword.get(args, :operation)

      message = Keyword.get(args, :message) || build_default_message(current_usage, limit, operation)

      %__MODULE__{
        message: message,
        current_usage: current_usage,
        limit: limit,
        operation: operation
      }
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, current_usage: nil, limit: nil, operation: nil}
    end

    @impl true
    def message(%__MODULE__{message: message}), do: message

    defp build_default_message(current_usage, limit, operation) do
      case {current_usage, limit, operation} do
        {current, limit, op} when not is_nil(current) and not is_nil(limit) and not is_nil(op) ->
          "Memory limit exceeded during #{op}: #{current}MB > #{limit}MB"
        {current, limit, _} when not is_nil(current) and not is_nil(limit) ->
          "Memory limit exceeded: #{current}MB > #{limit}MB"
        {_, _, op} when not is_nil(op) ->
          "Memory constraint error during #{op}"
        _ ->
          "Memory constraint error"
      end
    end
  end

  # Utility functions for error handling

  @doc """
  Wraps a function call with comprehensive error handling.

  ## Parameters

    * `fun` - Function to execute
    * `context` - Context information for error reporting

  ## Returns

  Returns `{:ok, result}` on success or `{:error, exception}` on failure.
  """
  @spec with_error_handling(function(), map()) :: {:ok, any()} | {:error, Exception.t()}
  def with_error_handling(fun, context \\ %{}) do
    try do
      result = fun.()
      {:ok, result}
    rescue
      error in [PDFError, ValidationError, PythonExecutionError, ClassificationError, MemoryError] ->
        {:error, error}

      error in ArgumentError ->
        validation_error = %ValidationError{
          message: "Invalid argument: #{error.message}",
          field: Map.get(context, :field),
          value: Map.get(context, :value),
          constraint: "valid_argument"
        }
        {:error, validation_error}

      error ->
        pdf_error = %PDFError{
          message: "Unexpected error: #{inspect(error)}",
          type: :unexpected,
          details: %{
            error_type: error.__struct__,
            error_message: Exception.message(error),
            context: context
          }
        }
        {:error, pdf_error}
    catch
      :throw, value ->
        pdf_error = %PDFError{
          message: "Caught thrown value: #{inspect(value)}",
          type: :thrown,
          details: %{thrown_value: value, context: context}
        }
        {:error, pdf_error}

      :exit, reason ->
        pdf_error = %PDFError{
          message: "Process exited: #{inspect(reason)}",
          type: :exit,
          details: %{exit_reason: reason, context: context}
        }
        {:error, pdf_error}
    end
  end

  @doc """
  Validates input parameters and returns appropriate errors.

  ## Parameters

    * `value` - Value to validate
    * `validators` - List of validation functions or constraints
    * `field` - Field name for error reporting

  ## Returns

  Returns `:ok` if valid, `{:error, ValidationError.t()}` if invalid.
  """
  @spec validate(any(), list(), atom() | String.t()) :: :ok | {:error, ValidationError.t()}
  def validate(value, validators, field) do
    case find_validation_error(value, validators, field) do
      nil -> :ok
      error -> {:error, error}
    end
  end

  defp find_validation_error(value, validators, field) do
    Enum.find_value(validators, fn validator ->
      case apply_validator(validator, value, field) do
        :ok -> nil
        {:error, error} -> error
      end
    end)
  end

  defp apply_validator({:required}, value, field) do
    if is_nil(value) do
      {:error, %ValidationError{
        message: "#{field} is required",
        field: field,
        value: value,
        constraint: :required
      }}
    else
      :ok
    end
  end

  defp apply_validator({:type, expected_type}, value, field) do
    if type_match?(value, expected_type) do
      :ok
    else
      {:error, %ValidationError{
        message: "#{field} must be of type #{expected_type}",
        field: field,
        value: value,
        constraint: {:type, expected_type}
      }}
    end
  end

  defp apply_validator({:max_size, max_bytes}, value, field) when is_binary(value) do
    if byte_size(value) <= max_bytes do
      :ok
    else
      {:error, %ValidationError{
        message: "#{field} exceeds maximum size of #{max_bytes} bytes",
        field: field,
        value: byte_size(value),
        constraint: {:max_size, max_bytes}
      }}
    end
  end

  defp apply_validator({:min_size, min_bytes}, value, field) when is_binary(value) do
    if byte_size(value) >= min_bytes do
      :ok
    else
      {:error, %ValidationError{
        message: "#{field} is below minimum size of #{min_bytes} bytes",
        field: field,
        value: byte_size(value),
        constraint: {:min_size, min_bytes}
      }}
    end
  end

  defp apply_validator(validator_fun, value, field) when is_function(validator_fun, 1) do
    case validator_fun.(value) do
      true -> :ok
      false -> {:error, %ValidationError{
        message: "#{field} failed validation",
        field: field,
        value: value,
        constraint: :custom
      }}
      {:error, message} -> {:error, %ValidationError{
        message: message,
        field: field,
        value: value,
        constraint: :custom
      }}
    end
  end

  defp type_match?(value, :binary), do: is_binary(value)
  defp type_match?(value, :integer), do: is_integer(value)
  defp type_match?(value, :float), do: is_float(value)
  defp type_match?(value, :number), do: is_number(value)
  defp type_match?(value, :atom), do: is_atom(value)
  defp type_match?(value, :list), do: is_list(value)
  defp type_match?(value, :map), do: is_map(value)
  defp type_match?(value, :boolean), do: is_boolean(value)
  defp type_match?(_value, _type), do: false
end
