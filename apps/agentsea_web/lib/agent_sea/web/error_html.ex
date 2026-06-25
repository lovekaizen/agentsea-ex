defmodule AgentSea.Web.ErrorHTML do
  @moduledoc false

  # Render the plain status message for any error template (e.g. "404.html").
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
