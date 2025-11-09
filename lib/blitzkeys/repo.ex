defmodule Blitzkeys.Repo do
  use Ecto.Repo,
    otp_app: :blitzkeys,
    adapter: Ecto.Adapters.Postgres
end
