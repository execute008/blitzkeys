defmodule BlitzkeysWeb.Presence do
  @moduledoc """
  Provides presence tracking for players in typing game rooms.
  """
  use Phoenix.Presence,
    otp_app: :blitzkeys,
    pubsub_server: Blitzkeys.PubSub
end
