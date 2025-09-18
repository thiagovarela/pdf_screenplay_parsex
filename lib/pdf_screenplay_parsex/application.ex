defmodule PdfScreenplayParsex.Application do
  @moduledoc """
  The PdfScreenplayParsex Application.

  This module defines the supervision tree for the application,
  ensuring that the Python interpreter is properly managed through
  a GenServer process.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PdfScreenplayParsex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
