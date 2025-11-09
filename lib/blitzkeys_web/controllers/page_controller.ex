defmodule BlitzkeysWeb.PageController do
  use BlitzkeysWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
