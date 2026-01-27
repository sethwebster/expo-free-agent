defmodule ExpoControllerWeb.CoreComponents do
  @moduledoc """
  Core UI components for the Phoenix application.
  """

  use Phoenix.Component
  import Phoenix.HTML

  @doc """
  Renders flash messages with support for phx-click and phx-disconnected events.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a single flash message.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :kind, :atom, required: true, doc: "the kind of flash message (:info or :error)"

  def flash(assigns) do
    ~H"""
    <%= if Phoenix.Flash.get(@flash, @kind) do %>
      <div
        id={"flash-#{@kind}"}
        phx-click="lv:clear-flash"
        phx-value-key={@kind}
        role="alert"
        class={[
          "fixed top-4 right-4 max-w-sm w-full p-4 rounded-lg shadow-lg cursor-pointer z-50",
          @kind == :info && "bg-blue-50 text-blue-800 border border-blue-200",
          @kind == :error && "bg-red-50 text-red-800 border border-red-200"
        ]}
      >
        <p class="font-semibold"><%= Phoenix.Flash.get(@flash, @kind) %></p>
      </div>
    <% end %>
    """
  end
end
