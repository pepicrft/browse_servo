defmodule BrowseServo.Page do
  @moduledoc """
  High-level page handle.
  """

  alias BrowseServo.Browser

  @enforce_keys [:browser, :id, :title, :url]
  defstruct [:browser, :id, :title, :url]

  @type t :: %__MODULE__{
          browser: pid(),
          id: pos_integer(),
          title: String.t(),
          url: String.t()
        }

  @spec goto(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def goto(%__MODULE__{} = page, url) do
    Browser.goto(page.browser, page, url)
  end

  @spec content(t()) :: {:ok, String.t()} | {:error, term()}
  def content(%__MODULE__{} = page) do
    Browser.content(page.browser, page)
  end

  @spec title(t()) :: {:ok, String.t()} | {:error, term()}
  def title(%__MODULE__{} = page) do
    Browser.title(page.browser, page)
  end

  @spec evaluate(t(), String.t()) :: {:ok, term()} | {:error, term()}
  def evaluate(%__MODULE__{} = page, expression) do
    Browser.evaluate(page.browser, page, expression)
  end

  @spec close(t()) :: :ok | {:error, term()}
  def close(%__MODULE__{} = page) do
    Browser.close_page(page.browser, page)
  end
end
